#!/usr/bin/env bash
# Installs ArgoCD and configures it with Google OIDC and GitOps projects.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

# Wait (best-effort) for an argocd-server rollout to finish. argocd-server is a GKE
# NEG backend, so `kubectl rollout status` blocks on the load-balancer readiness gate
# (cloud.google.com/load-balancer-neg-ready), which only clears once the LB
# HealthCheckPolicy protocol matches what the pod serves. 09-gateway.sh reconciles
# that policy (HTTP when backend TLS is off, HTTPS when on) - but 09 runs long AFTER
# this script, so at this point the policy can MISMATCH the pod in either direction:
#   - backend TLS active now: pod serves HTTPS, the leftover policy is still HTTP;
#   - backend TLS off now but a PRIOR backend_tls=true run left a stale HTTPS policy:
#     the HTTPS probe fails against this plain-HTTP pod.
# Either way the NEG never goes healthy until 09 flips the policy, so a HARD wait here
# DEADLOCKS the whole Day1 before 09 can heal it (observed: run #176 timed out 5m on
# "1 old replicas are pending termination" after a true->false backend_tls switch).
# The container itself is Ready and the old replica keeps serving, so warn-and-continue:
# 09 makes the new pod NEG-healthy and drains the old one. TLS-active is still skipped
# outright (no point waiting 5m for a guaranteed miss). Mirrors 09-gateway.sh's own
# non-fatal post-HealthCheckPolicy wait. See docs/504 § argocd.
wait_argocd_server_rollout() {
  if [[ "$(j2026_argocd_backend_tls_active)" == "true" ]]; then
    log_info "Backend TLS active - skipping the argocd-server rollout wait (NEG readiness gate clears at 09-gateway.sh)."
    return 0
  fi
  # Delegate to the shared NEG-aware best-effort helper (lib/common.sh) - same wait used
  # by headlamp and the other Gateway-fronted backends, so the mode-switch idempotency
  # logic lives in ONE place. (This TLS-active early-skip stays here because when TLS is
  # ON the HTTP-vs-HTTPS miss is guaranteed until 09, so there is no point waiting 5m.)
  wait_neg_backend_rollout "${J2026_ARGOCD_RELEASE}-server" "${J2026_ARGOCD_NAMESPACE}" "5m"
}

resolve_argocd_version() {
  local constraint="$1"
  local baseline="$2"
  log_info "Resolving ArgoCD version matching constraint: ${constraint} (baseline: ${baseline})" >&2
  
  # Fetch releases from GitHub API
  local api_url="https://api.github.com/repos/argoproj/argo-cd/releases"
  local releases_json
  releases_json=$(curl -s --connect-timeout 10 --retry 3 "${api_url}")
  
  if [[ -z "${releases_json}" || "$(echo "${releases_json}" | jq 'type' 2>/dev/null)" != '"array"' ]]; then
    log_warn "Failed to query GitHub Releases API or hit rate limit. Falling back to baseline: ${baseline}" >&2
    echo "${baseline}"
    return 0
  fi
  
  # Format constraint into regex (e.g. "3.5.x" -> "^v3\.5\.[0-9]+$")
  local base_prefix=$(echo "${constraint}" | sed 's/\.x$//' | sed 's/\./\\./g')
  local stable_regex="^v${base_prefix}\.[0-9]+$"
  local any_regex="^v${base_prefix}\.[0-9]+(-rc[0-9]+)?$"
  
  # First try: stable releases only
  local latest_stable
  latest_stable=$(echo "${releases_json}" | jq -r --arg prefix "${stable_regex}" '
    map(select(.prerelease == false and .draft == false and (.tag_name | test($prefix))))
    | sort_by(.published_at) | last | .tag_name
  ' 2>/dev/null || echo "")

  if [[ -n "${latest_stable}" && "${latest_stable}" != "null" ]]; then
    log_info "Resolved latest stable version: ${latest_stable}" >&2
    echo "${latest_stable}"
    return 0
  fi

  # Second try: fallback to pre-releases (rc)
  log_info "No stable release found matching ${constraint}. Searching for pre-releases..." >&2
  local latest_rc
  latest_rc=$(echo "${releases_json}" | jq -r --arg prefix "${any_regex}" '
    map(select(.draft == false and (.tag_name | test($prefix))))
    | sort_by(.published_at) | last | .tag_name
  ' 2>/dev/null || echo "")

  if [[ -n "${latest_rc}" && "${latest_rc}" != "null" ]]; then
    log_info "Resolved latest pre-release: ${latest_rc}" >&2
    echo "${latest_rc}"
    return 0
  fi

  log_warn "No versions matching constraint found in releases API. Falling back to baseline: ${baseline}" >&2
  echo "${baseline}"
}

RESOLVED_ARGOCD_VERSION=$(resolve_argocd_version "${J2026_ARGOCD_VERSION_CONSTRAINT}" "${J2026_ARGOCD_VERSION}")

log_step "Installing ArgoCD into ${J2026_ARGOCD_NAMESPACE} (Version: ${RESOLVED_ARGOCD_VERSION})"
kubectl_apply_namespace "${J2026_ARGOCD_NAMESPACE}"

# Helm 3 recovery logic
log_info "Checking ArgoCD Helm release status..."
current_status=$(helm list -n "${J2026_ARGOCD_NAMESPACE}" -f "^${J2026_ARGOCD_RELEASE}$" -o json | yq eval '.[0].status' 2>/dev/null || echo "not-found")

if [[ "${current_status}" == "pending-install" || "${current_status}" == "pending-upgrade" || "${current_status}" == "uninstalling" ]]; then
  log_warn "ArgoCD is stuck in '${current_status}'. Uninstalling to reset state..."
  helm uninstall "${J2026_ARGOCD_RELEASE}" -n "${J2026_ARGOCD_NAMESPACE}" --wait || true
  sleep 2
fi

# 1. Install ArgoCD
log_step "Running Helm upgrade"
# Delete existing patched configmaps to prevent Helm Server-Side Apply / ownership conflict failures on subsequent runs
kubectl delete configmap argocd-cm argocd-rbac-cm -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found=true || true

# Backend TLS (opt-in, docs/504): serve argocd-server over TLS by dropping the
# `--insecure` extraArg from helm/argocd-values.yaml, so the LB re-encrypts the UI
# hop (BackendTLSPolicy in 09-gateway.sh) against the cert-manager argocd-server-tls
# cert 08.7 mints. Gated on j2026_argocd_backend_tls_active (flag AND an engine whose
# deploy caller speaks TLS: jenkins/githubactions), so tekton/argo clusters keep the
# plaintext argocd their `:80 --plaintext` callers need. Empty array = no-op.
argocd_tls_helm_args=()
if [[ "$(j2026_argocd_backend_tls_active)" == "true" ]]; then
  log_info "Backend TLS active (ci.engine=${J2026_CI_ENGINE}) - serving argocd-server over TLS (dropping --insecure)"
  argocd_tls_helm_args=(-f "${J2026_ROOT_DIR}/helm/argocd-values-backend-tls.yaml")
fi

helm upgrade --install "${J2026_ARGOCD_RELEASE}" argo/argo-cd \
  --namespace "${J2026_ARGOCD_NAMESPACE}" \
  --version "${J2026_ARGOCD_CHART_VERSION}" \
  -f "${J2026_ROOT_DIR}/helm/argocd-values.yaml" \
  --set global.image.tag="${RESOLVED_ARGOCD_VERSION}" \
  "${argocd_tls_helm_args[@]}" \
  --timeout 10m

# 2. Configure OIDC/RBAC
log_step "Configuring ArgoCD OIDC/RBAC"
ARGOCD_HOST="argocd.${J2026_GATEWAY_BASE_DOMAIN}"
ARGOCD_URL="https://${ARGOCD_HOST}"

# Fetch the IAP OAuth client (reused for ArgoCD's Google OIDC login). Read it from
# the headlamp namespace - it is always created and always carries the
# gateway-iap-oauth Secret (01-namespaces replicates it into every IAP backend ns),
# unlike the jenkins namespace which only exists when ci.engine=jenkins.
CLIENT_ID="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" -o jsonpath='{.data.client_id}' 2>/dev/null | base64 -d || true)"
CLIENT_SECRET="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" -o jsonpath='{.data.client_secret}' 2>/dev/null | base64 -d || true)"

if [[ -n "${CLIENT_ID}" && -n "${CLIENT_SECRET}" ]]; then
  log_info "Wiring IAP authproxy SSO for ArgoCD at ${ARGOCD_URL}"

  PATCH_FILE=$(mktemp)
  # Dex authproxy connector: ArgoCD trusts the identity Google IAP injects at the edge
  # (the X-Goog-Authenticated-User-Email header), so IAP performs the ONE Google login
  # and ArgoCD runs NO second OAuth flow — single sign-on (docs/501). This replaces the
  # former Google `oidc` connector, whose redirect caused a second login on top of IAP.
  # The header value is prefixed `accounts.google.com:`, so the RBAC bindings below carry
  # that prefix. SECURITY: authproxy trusts the header WITHOUT verifying IAP's signed JWT,
  # so argocd-server must be reachable ONLY behind IAP — the argocd-baseline NetworkPolicy
  # (infrastructure/networkpolicies.yaml) restricts pod :8080 ingress to the GKE LB + CI
  # namespaces so no arbitrary in-cluster pod can forge the header (header-spoof mitigation).
  cat <<EOF > "${PATCH_FILE}"
data:
  url: ${ARGOCD_URL}
  dex.config: |
    connectors:
      - type: authproxy
        id: iap
        name: Google IAP
        config:
          userHeader: "X-Goog-Authenticated-User-Email"
EOF
  kubectl patch configmap argocd-cm -n ${J2026_ARGOCD_NAMESPACE} --patch-file "${PATCH_FILE}"
  rm "${PATCH_FILE}"

  PATCH_FILE_RBAC=$(mktemp)
  # scopes = '[email]': IAP forwards no 'groups' claim (nor did the old Google OIDC),
  # so RBAC subjects are matched by email only. The IAP authproxy identity is the raw
  # header value, which IAP prefixes with 'accounts.google.com:' — so the human admin
  # binding carries that prefix (below / in the CI-account section). (policy.csv here
  # is overwritten by the CI-account patch further down; the binding that matters is
  # set there.)
  cat <<EOF > "${PATCH_FILE_RBAC}"
data:
  scopes: '[email]'
  policy.default: role:readonly
  policy.csv: |
    g, authenticated, role:admin
EOF
  if [[ -n "${J2026_JENKINS_OIDC_ADMIN_EMAIL}" ]]; then
    echo "    g, accounts.google.com:${J2026_JENKINS_OIDC_ADMIN_EMAIL}, role:admin" >> "${PATCH_FILE_RBAC}"
  fi
  kubectl patch configmap argocd-rbac-cm -n ${J2026_ARGOCD_NAMESPACE} --patch-file "${PATCH_FILE_RBAC}"
  rm "${PATCH_FILE_RBAC}"
  
  # Restart argocd-server and dex to pick up CM changes
  log_info "Restarting ArgoCD components to pick up OIDC config"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-dex-server" -n "${J2026_ARGOCD_NAMESPACE}"
  
  log_info "Waiting for ArgoCD server and dex rollouts to complete to release resource quota..."
  # Backend TLS: the TLS argocd-server pod carries a GKE NEG readiness gate that only
  # clears once 09-gateway.sh flips the LB HealthCheckPolicy to HTTPS (until then the
  # HTTP LB health check 3xx-redirects against the now-TLS pod, so the NEG never goes
  # healthy). `rollout status` blocks on that gate and would DEADLOCK the Day1 here
  # (08.5 runs long before 09). Skip it for argocd-server when TLS is active - its
  # container is Ready; the old replica terminates once 09 makes the NEG healthy.
  wait_argocd_server_rollout
  kubectl rollout status deployment "${J2026_ARGOCD_RELEASE}-dex-server" -n "${J2026_ARGOCD_NAMESPACE}" --timeout=5m
else
  log_warn "OIDC credentials not found. ArgoCD will use local admin password."
fi

# 2.5 Configure the CI engine's ArgoCD account (CLI/API access) - the pipeline
# 'Deploy' stage uses this token to `argocd app sync`. Account name follows the
# active CI engine (ci.engine): 'jenkins', 'tekton' or 'githubactions'.
case "${J2026_CI_ENGINE}" in
  tekton)        CI_ARGOCD_ACCOUNT="tekton" ;;
  githubactions) CI_ARGOCD_ACCOUNT="githubactions" ;;
  argoworkflows) CI_ARGOCD_ACCOUNT="argoworkflows" ;;
  *)             CI_ARGOCD_ACCOUNT="jenkins" ;;
esac
log_step "Configuring '${CI_ARGOCD_ACCOUNT}' account in ArgoCD"
kubectl patch configmap argocd-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p "{\"data\": {\"accounts.${CI_ARGOCD_ACCOUNT}\": \"apiKey\"}}"

# The CI account is a LOCAL argocd apiKey account (not header-derived), so its RBAC
# subject is the bare account name — NO accounts.google.com: prefix (unlike the human).
policy_csv="g, ${CI_ARGOCD_ACCOUNT}, role:admin"
if [[ -n "${CLIENT_ID}" && -n "${CLIENT_SECRET}" ]]; then
  # Grant the human admin by the identity the IAP authproxy connector reports — the
  # IAP header value, which IAP prefixes with 'accounts.google.com:'. Bind the specific
  # admin email (ArgoCD has no built-in "authenticated" group; that subject is a no-op).
  # ⚠️ The prefix is load-bearing: a bare email would silently drop the admin to readonly.
  if [[ -n "${J2026_JENKINS_OIDC_ADMIN_EMAIL}" ]]; then
    policy_csv="g, accounts.google.com:${J2026_JENKINS_OIDC_ADMIN_EMAIL}, role:admin\n${policy_csv}"
  else
    log_warn "JENKINS_OIDC_ADMIN_EMAIL unset - no human will get ArgoCD admin via IAP SSO (only the '${CI_ARGOCD_ACCOUNT}' API account). Set the GitHub secret to your Google login email, else ArgoCD shows an empty app list to SSO users."
  fi
fi
kubectl patch configmap argocd-rbac-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p "{\"data\": {\"policy.csv\": \"${policy_csv}\"}}"

# Restart argocd-server to pick up local account and rbac config changes (only if OIDC was disabled, since we restarted above otherwise)
if [[ -z "${CLIENT_ID}" || -z "${CLIENT_SECRET}" ]]; then
  log_info "Restarting ArgoCD server to pick up local account config"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}"
  wait_argocd_server_rollout  # skipped under backend TLS (NEG gate clears at 09) - see note above
fi

log_info "Generating ArgoCD API token for the '${CI_ARGOCD_ACCOUNT}' account"
# Use a temporary ClusterRoleBinding. Use apply or delete/create to avoid "already exists" errors.
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: temp-argocd-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: default
  namespace: ${J2026_ARGOCD_NAMESPACE}
EOF

# Generate the token via a short-lived pod running the argocd CLI in --core mode
# (it talks to the k8s API directly; the temp cluster-admin binding above grants
# the default SA the access it needs). Retried + diagnosed: on a fresh cluster the
# argocd image pull (cold node) or argocd settling can push the pod past the
# per-attempt timeout, and a single silent failure here leaves the CI engine
# without an ArgoCD token (the pipeline 'Deploy' stage then can't `argocd app
# sync`). So retry, and on failure dump the pod's events/logs before deleting it.
set +e
RAW_TOKEN=""
EXIT_CODE=1
for attempt in 1 2 3; do
  kubectl delete pod argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl run argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --restart=Never \
    --image="quay.io/argoproj/argocd:${RESOLVED_ARGOCD_VERSION}" \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "argocd-token-gen",
          "image": "quay.io/argoproj/argocd:'"${RESOLVED_ARGOCD_VERSION}"'",
          "command": ["bash", "-c", "argocd account generate-token --account '"${CI_ARGOCD_ACCOUNT}"' --core"],
          "resources": {
            "requests": { "cpu": "50m", "memory": "128Mi" },
            "limits": { "cpu": "100m", "memory": "256Mi" }
          }
        }]
      }
    }' >/dev/null 2>&1

  if kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/argocd-token-gen \
       -n "${J2026_ARGOCD_NAMESPACE}" --timeout=5m; then
    RAW_TOKEN=$(kubectl logs argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}")
    EXIT_CODE=0
    break
  fi

  # Did not reach Succeeded within the timeout — surface WHY before retrying.
  log_warn "ArgoCD token-gen attempt ${attempt}/3 did not Succeed — diagnostics:"
  kubectl get pod argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" -o wide 2>&1 | sed 's/^/    /' || true
  kubectl describe pod argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" 2>&1 \
    | grep -A15 -iE '^events:' | sed 's/^/    /' || true
  kubectl logs argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" 2>&1 | tail -n 20 | sed 's/^/    /' || true
done
set -e
kubectl delete pod argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found=true || true
          
# Strip any newlines or trailing whitespace from the token to prevent JSON patch errors
TOKEN=$(echo "${RAW_TOKEN}" | tr -d '\n\r' | xargs)
          
# Cleanup temporary RBAC
kubectl delete clusterrolebinding temp-argocd-admin || true

if [[ ${EXIT_CODE} -eq 0 && -n "${TOKEN}" ]]; then
  if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
    # Tekton: store the token where the gitops-deploy Task reads it
    # (ARGOCD_AUTH_TOKEN), in the pipeline-execution namespace.
    log_info "Storing ArgoCD token in 'tekton-argocd' Secret (${J2026_TEKTON_PIPELINE_NAMESPACE})"
    kubectl create secret generic tekton-argocd \
      -n "${J2026_TEKTON_PIPELINE_NAMESPACE}" \
      --from-literal=token="${TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f -
  elif [[ "${J2026_CI_ENGINE}" == "githubactions" ]]; then
    # GitHub Actions / ARC: store the token where the microservices-ci workflow's
    # GitOps-bump step reads it (ARGOCD_AUTH_TOKEN), in the runner namespace — read
    # in-cluster by the runner SA, never a fork secret (the cluster API token must
    # never leave the cluster).
    log_info "Storing ArgoCD token in 'arc-argocd' Secret (${J2026_GHA_RUNNER_NAMESPACE})"
    kubectl create secret generic arc-argocd \
      -n "${J2026_GHA_RUNNER_NAMESPACE}" \
      --from-literal=token="${TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f -
  elif [[ "${J2026_CI_ENGINE}" == "argoworkflows" ]]; then
    # Argo Workflows: store the token where the gitops-deploy WorkflowTemplate step reads
    # it (ARGOCD_AUTH_TOKEN, via secretKeyRef argoworkflows-argocd), in the execution namespace.
    log_info "Storing ArgoCD token in 'argoworkflows-argocd' Secret (${J2026_ARGOWF_RUN_NAMESPACE})"
    kubectl create secret generic argoworkflows-argocd \
      -n "${J2026_ARGOWF_RUN_NAMESPACE}" \
      --from-literal=token="${TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    log_info "Storing ArgoCD token in ${J2026_JENKINS_CREDENTIALS_SECRET}"
    kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
      --type=merge -p "{\"stringData\":{\"argocd-token\":\"${TOKEN}\"}}"

    # Safety fallback check: restart Jenkins pod if it exists and lacks the env variable
    if kubectl get statefulset "${J2026_JENKINS_RELEASE}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
      if kubectl get pod "${J2026_JENKINS_RELEASE}-0" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
        RUNNING_TOKEN=$(kubectl exec "${J2026_JENKINS_RELEASE}-0" -n "${J2026_JENKINS_NAMESPACE}" -c jenkins -- env | grep ARGOCD_AUTH_TOKEN || true)
        if [[ -z "${RUNNING_TOKEN}" ]]; then
          log_warn "Jenkins is running but does not have ARGOCD_AUTH_TOKEN set. Restarting Jenkins pod..."
          kubectl delete pod "${J2026_JENKINS_RELEASE}-0" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found=true
          wait_for_resource "statefulset" "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}" "15m"
        fi
      fi
    fi
  fi
else
  log_error "Failed to generate ArgoCD token (exit code: ${EXIT_CODE})"
  log_info "Raw output: ${RAW_TOKEN}"
fi

# 3. Wait for Server
log_step "Waiting for ArgoCD Server to be ready"
# argocd-server is a GKE NEG backend, so its readiness gate stays open until
# 09-gateway.sh reconciles the LB HealthCheckPolicy protocol to match what the pod
# serves (HTTPS when backend TLS is on, HTTP when off) - and 09 runs long after this.
# The mismatch bites in BOTH directions: TLS-on leaves an HTTP policy vs an HTTPS pod;
# a prior-TLS-on-then-off run leaves a STALE HTTPS policy vs a now-HTTP pod (observed
# live: Day1 #176 deadlocked HERE on a backend_tls true->false switch, AFTER the
# resource-quota wait above was already made non-fatal). Do NOT use wait_for_deployment
# here: besides hard-failing, it SELF-HEALS by RESTARTING argocd-server, and every
# restart RESETS the NEG (new pod, gate back to 0/1), so the rollout can never converge
# and the deployment thrashes across replicasets. Reuse the shared best-effort helper
# (non-fatal, and crucially NO restart): the old replica keeps serving the ArgoCD API
# for the GitOps-project/AppSet applies below, and 09 makes the new pod NEG-healthy and
# drains the old one. It also early-skips outright when backend TLS is active (a
# guaranteed miss until 09). See docs/504 § argocd.
wait_argocd_server_rollout

# 4. Configure GitOps Project and AppSet
log_step "Configuring ArgoCD Microservices GitOps Project"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/microservices-project.yaml"

# Platform-config: the static, engine-aware platform RBAC (Jenkins/Tekton/pgAdmin
# RoleBindings + the OTel-instrumentation ClusterRole) that 01-namespaces.sh /
# 02-otel-operator.sh used to apply imperatively, now GitOps-owned (drift-detected,
# self-healed). ciEngine/developTrackEnabled are passed down so only the active
# engine's RBAC renders. Its consumers (CI pipelines, pgAdmin) run long after this
# syncs, so the move imposes no ordering risk. (NetworkPolicies + quotas stay
# script-applied — they must land before workloads for Dataplane V2 timing.)
log_step "Configuring platform-config (static platform RBAC) via ArgoCD"
PLATFORM_CONFIG_APP_FILE=$(mktemp)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
# {{branchStable}} = the DEPLOY branch (J2026_SELF_REPO_BRANCH), so the stable tier's
# gitops tracks whatever branch you deployed from (main in prod, develop when validating
# develop end-to-end). NOT config.yaml microservices.branches.stable. See that file.
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
     s@{{ciEngine}}@${J2026_CI_ENGINE}@g;
     s@{{developTrackEnabled}}@${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}@g;
     s@{{backstageEnabled}}@${J2026_BACKSTAGE_ENABLED}@g" \
    "${J2026_ROOT_DIR}/argocd/platform-config-app.yaml" > "${PLATFORM_CONFIG_APP_FILE}"
kubectl apply -f "${PLATFORM_CONFIG_APP_FILE}"
rm "${PLATFORM_CONFIG_APP_FILE}"

log_step "Configuring platform-postgres app-of-apps (CNPG operator + pgAdmin) via ArgoCD"
# Correlated Postgres platform: the CNPG operator and the pgAdmin UI that
# administers its databases are grouped under one parent Application
# (argocd/platform-postgres). repoUrl/branch are passed down so the pgAdmin
# child's git source tracks the active branch.
PG_APP_FILE=$(mktemp)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
# backend TLS (docs/504): when active, the pgAdmin child layers its TLS values
# overlay. Gated on j2026_backend_tls_active (flag AND the BackendTLSPolicy CRD),
# so a cluster too old to serve the CRD stays plain HTTP even with the flag on.
PG_BACKEND_TLS="$(j2026_backend_tls_active)"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
     s@{{backendTls}}@${PG_BACKEND_TLS}@g" \
    "${J2026_ROOT_DIR}/argocd/platform-postgres-app.yaml" > "${PG_APP_FILE}"
kubectl apply -f "${PG_APP_FILE}"
rm "${PG_APP_FILE}"

# ArgoCD installs CNPG asynchronously. Wait for the controller to be fully Ready
# AND its webhook caBundle to be injected before continuing — otherwise the first
# Jenkins pipeline run fails with:
#   "x509: certificate signed by unknown authority" on cnpg-webhook-service
# Phase 1: wait for ArgoCD to create the CNPG namespace + deployment (chart sync).
# The Helm chart names the deployment after the chart release — discover it
# rather than hardcoding, since the name can vary by chart version.
log_step "Waiting for CNPG controller deployment to appear (ArgoCD chart sync)"
timeout 300 bash -c '
  until kubectl get deployment -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg \
        --no-headers 2>/dev/null | grep -q .; do
    sleep 5
  done
' || { log_error "CNPG deployment did not appear within 5m — check ArgoCD cnpg-operator app"; exit 1; }

CNPG_DEPLOY=$(kubectl get deployment -n cnpg-system \
  -l app.kubernetes.io/name=cloudnative-pg --no-headers -o custom-columns=NAME:.metadata.name | head -1)
log_info "CNPG deployment name: ${CNPG_DEPLOY}"

# Phase 2: wait for the deployment to be fully ready.
wait_for_deployment "${CNPG_DEPLOY}" "cnpg-system" "5m"

# Phase 3: wait for the controller to self-inject its CA into the webhook configs.
# The cert injection typically happens within 10-30s after the pod becomes Ready,
# but can take longer on slow nodes or after a cold start.
log_step "Waiting for CNPG webhook caBundle to be populated"
_cnpg_self_injected=false
if timeout 180 bash -c '
  until kubectl get mutatingwebhookconfiguration cnpg-mutating-webhook-configuration \
        -o jsonpath="{.webhooks[0].clientConfig.caBundle}" 2>/dev/null \
        | grep -q .; do
    sleep 5
  done
'; then
  _cnpg_self_injected=true
  log_info "CNPG webhook caBundle self-injected by operator."
else
  log_warn "CNPG operator did not self-inject caBundle within 3m — will force-patch from cnpg-ca-secret."
fi

# Phase 4: verify caBundle is correct and patch if needed.
#
# Bug guard: if cnpg-ca-secret does not exist yet when we read it, CA_SECRET_SUBJECT
# would be empty. With an also-empty CABUNDLE_SUBJECT (fresh install) they compare
# equal and the patch is silently skipped — leaving the webhook broken for the first
# pipeline run. Fix: wait explicitly for the secret before any comparison.
log_step "Verifying CNPG webhook caBundle"

timeout 120 bash -c '
  until kubectl get secret cnpg-ca-secret -n cnpg-system >/dev/null 2>&1; do
    sleep 3; echo "Waiting for cnpg-ca-secret..."
  done
' || { log_error "cnpg-ca-secret not created within 2m of operator Ready — check CNPG RBAC"; exit 1; }

CA_BUNDLE=$(kubectl get secret cnpg-ca-secret -n cnpg-system -o jsonpath='{.data.ca\.crt}')
if [[ -z "${CA_BUNDLE}" ]]; then
  log_error "cnpg-ca-secret.ca.crt is empty — CNPG operator init failed"
  exit 1
fi

CA_SUBJECT=$(echo "${CA_BUNDLE}" | base64 -d | openssl x509 -noout -subject 2>/dev/null \
  | sed 's/subject=//' || echo "")

CURRENT_BUNDLE=$(kubectl get mutatingwebhookconfiguration cnpg-mutating-webhook-configuration \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null || echo "")
CURRENT_SUBJECT=""
if [[ -n "${CURRENT_BUNDLE}" ]]; then
  CURRENT_SUBJECT=$(echo "${CURRENT_BUNDLE}" | base64 -d | openssl x509 -noout -subject 2>/dev/null \
    | sed 's/subject=//' || echo "")
fi

if [[ -z "${CURRENT_BUNDLE}" || "${CURRENT_SUBJECT}" != "${CA_SUBJECT}" ]]; then
  if [[ -z "${CURRENT_BUNDLE}" ]]; then
    log_warn "caBundle is empty — force-injecting CA cert from cnpg-ca-secret"
  else
    log_warn "caBundle has wrong cert ('${CURRENT_SUBJECT}' vs '${CA_SUBJECT}') — patching"
  fi
  # Use op:add — works whether the field is absent, empty, or has the wrong value.
  MUTATING_N=$(kubectl get mutatingwebhookconfiguration cnpg-mutating-webhook-configuration \
    -o json | jq '.webhooks | length')
  VALIDATING_N=$(kubectl get validatingwebhookconfiguration cnpg-validating-webhook-configuration \
    -o json | jq '.webhooks | length')
  MUTATING_PATCH=$(python3 -c "
import json
n, ca = int('${MUTATING_N}'), '${CA_BUNDLE}'
print(json.dumps([{'op':'add','path':f'/webhooks/{i}/clientConfig/caBundle','value':ca} for i in range(n)]))")
  VALIDATING_PATCH=$(python3 -c "
import json
n, ca = int('${VALIDATING_N}'), '${CA_BUNDLE}'
print(json.dumps([{'op':'add','path':f'/webhooks/{i}/clientConfig/caBundle','value':ca} for i in range(n)]))")
  kubectl patch mutatingwebhookconfiguration cnpg-mutating-webhook-configuration \
    --type=json -p="${MUTATING_PATCH}"
  kubectl patch validatingwebhookconfiguration cnpg-validating-webhook-configuration \
    --type=json -p="${VALIDATING_PATCH}"
  log_info "CNPG webhook caBundle patched on all webhook configs."
else
  log_info "caBundle already contains the correct CA cert."
fi
log_info "CNPG webhook ready."

log_step "Configuring External Secrets Operator via ArgoCD"
# Substitute the Workload Identity GSA email the ESO controller KSA impersonates
# to read Secret Manager (secrets.backend=eso). The GSA + WI binding are created
# by terraform/gke (google_service_account.eso, account_id eso-secret-reader).
# Templated unconditionally — harmless in imperative mode (ESO installed, unused).
ESO_APP_FILE=$(mktemp)
ESO_GSA_EMAIL="eso-secret-reader@$(gcloud config get-value project 2>/dev/null).iam.gserviceaccount.com"
# NOTE: '#' delimiter, not '@' — the GSA email contains '@'.
sed "s#{{esoGsaEmail}}#${ESO_GSA_EMAIL}#g" \
    "${J2026_ROOT_DIR}/argocd/external-secrets-app.yaml" > "${ESO_APP_FILE}"
kubectl apply -f "${ESO_APP_FILE}"
rm "${ESO_APP_FILE}"

# Argo Rollouts (progressive delivery) + the Gateway API plugin RBAC. The
# controller/CRDs/plugin are GitOps-managed by the argo-rollouts Application
# (public Helm chart, no repo placeholders); the extra ClusterRole lets the
# Gateway API plugin patch HTTPRoute weights for canary traffic shifting.
log_step "Configuring Argo Rollouts via ArgoCD"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/argo-rollouts-app.yaml"
kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/argo-rollouts-gatewayapi-rbac.yaml"

log_step "Configuring Headlamp via ArgoCD"
# Inject values into the Headlamp Application manifest
HEADLAMP_APP_FILE=$(mktemp)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
    "${J2026_ROOT_DIR}/argocd/headlamp-app.yaml" > "${HEADLAMP_APP_FILE}"
# Backend TLS (gateway.backendTls.enabled, docs/504): layer the TLS overlay on
# top of the base values file so headlamp-server terminates TLS itself on 4466
# with the cert-manager-minted headlamp-tls Secret (08.7-backend-tls.sh) and
# its kubelet probes flip to HTTPS - the backend half of the BackendTLSPolicy
# 09-gateway.sh attaches. Gated on j2026_backend_tls_active (flag AND the
# BackendTLSPolicy CRD), never the raw flag, so the pod is never flipped to a
# TLS the LB can't speak. Idempotent flag-off convergence for free: the app
# file is re-rendered from the template every run, so disabling the flag
# re-applies it WITHOUT the overlay and ArgoCD self-heals Headlamp back to
# plain HTTP (same regenerate-then-apply pattern as the microservices AppSet
# develop generator below).
if [[ "$(j2026_backend_tls_active)" == "true" ]]; then
  log_info "Backend TLS active - adding the Headlamp TLS values overlay to the headlamp app"
  yq eval -i \
    '(.spec.sources[] | select(.chart == "headlamp") | .helm.valueFiles) += ["$values/helm/headlamp/values-backend-tls.yaml"]' \
    "${HEADLAMP_APP_FILE}"
fi
kubectl apply -f "${HEADLAMP_APP_FILE}"
rm "${HEADLAMP_APP_FILE}"

# pgAdmin is deployed by the platform-postgres app-of-apps above (grouped with
# the CNPG operator it administers).

log_step "Generating and applying Microservices ApplicationSet"
# Inject values into the AppSet manifest
# Using @ as delimiter for sed to avoid issues with URLs
APPSET_FILE=$(mktemp)
GITOPS_REPO_URL="https://github.com/nubenetes/jenkins-2026-gitops-config.git"
# Postgres backups: override the chart's placeholder gcpProject/gcpServiceAccount/
# gcsBackupBucket defaults with the real project so the CNPG serviceAccountTemplate
# annotates each postgres KSA with an EXISTING GSA (terraform/gke pg_backups) and
# barman archives WAL to the project-scoped bucket. PROJECT_ID like the ESO block.
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
sed "s@{{repoUrl}}@${GITOPS_REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
     s@{{platform}}@${J2026_PLATFORM}@g;
     s@{{gcpProject}}@${PROJECT_ID}@g;
     s@{{gcpServiceAccount}}@jenkins-2026-pg-backups@g;
     s@{{backendTlsEnabled}}@$(j2026_backend_tls_active)@g;
     s@{{gcsBackupBucket}}@${PROJECT_ID}-jenkins-2026-postgres-backups@g" \
    "${J2026_ROOT_DIR}/argocd/microservices-appset.yaml" > "${APPSET_FILE}"

# Optional 'develop' tier (off by default - see microservices.developTrackEnabled
# in config/config.yaml). When enabled, append a second list-generator element so
# ArgoCD creates a 'microservices-develop' Application deploying to its own
# namespace from values-develop.yaml on the gitops 'develop' branch. Idempotent:
# the appset file is regenerated from the template on every run.
if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
  log_info "Develop track enabled - adding 'develop' generator element to the Microservices ApplicationSet"
  DEV_NS="${J2026_MICROSERVICES_DEVELOP_NAMESPACE}" \
  DEV_BRANCH="${J2026_SELF_REPO_DEV_BRANCH}" \
  yq eval -i '.spec.generators[0].list.elements += [{
    "env": "develop",
    "namespace": strenv(DEV_NS),
    "valuesFile": "values-develop.yaml",
    "branch": strenv(DEV_BRANCH)
  }]' "${APPSET_FILE}"
fi

# --- Rebuild-safe WAL archive (fresh initdb into a persistent barman bucket) ----
# Every Day1 bootstraps the CNPG clusters via `initdb` (a fresh cluster, new
# system id) whose barman path is FIXED (gs://<bucket>/<service>), but the backups
# bucket is persistent (terraform/bootstrap, survives Decom). If a PRIOR
# incarnation's WALs still sit there, CNPG's `barman-cloud-check-wal-archive`
# fails with "Expected empty archive" and WAL archiving + backups break for good.
# So on a FRESH provision only — checked right before the ApplicationSet that
# creates the clusters, so no live CNPG Cluster exists yet — clear the stale
# archive. A re-run against an already-provisioned cluster is skipped, so a
# running cluster's backups are never touched. (All-or-nothing: the tiers are
# always provisioned together.) See docs/902 "WAL archiving fails after a rebuild".
BACKUPS_BUCKET="${PROJECT_ID}-jenkins-2026-postgres-backups"
if kubectl get clusters.postgresql.cnpg.io -A -o name 2>/dev/null | grep -q .; then
  log_info "CNPG cluster(s) already present - leaving gs://${BACKUPS_BUCKET} untouched (protects a running cluster's WAL archive/backups)."
elif gsutil ls "gs://${BACKUPS_BUCKET}/**" >/dev/null 2>&1; then
  log_step "Fresh provision: clearing stale WAL archive in gs://${BACKUPS_BUCKET} (persistent bucket holds a prior incarnation's WALs) so barman-cloud-check-wal-archive passes"
  gsutil -m rm -r "gs://${BACKUPS_BUCKET}/**" >/dev/null 2>&1 \
    || log_warn "Could not clear gs://${BACKUPS_BUCKET} (the CI SA needs storage.objectAdmin on it) - new-cluster WAL archiving may stay broken until the bucket is emptied by hand."
fi

kubectl apply -f "${APPSET_FILE}"
rm "${APPSET_FILE}"

log_step "Applying ArgoCD Version Patch Watcher CronJob (tracking ${J2026_ARGOCD_VERSION_CONSTRAINT})"
# Template the tracked constraint from config so the daily auto-upgrade watcher,
# Day1 and Day2.redeploy.01 all read the SAME source (config.yaml argocd.version_constraint).
sed "s|__ARGOCD_CONSTRAINT__|${J2026_ARGOCD_VERSION_CONSTRAINT}|g" \
  "${J2026_ROOT_DIR}/argocd/argocd-version-patch-watcher.yaml" \
  | kubectl apply -n "${J2026_ARGOCD_NAMESPACE}" -f -

log_info "ArgoCD installed and GitOps configured."
