#!/usr/bin/env bash
# Installs ArgoCD and configures it with Google OIDC and GitOps projects.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

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

RESOLVED_3_5_PATCH=$(resolve_argocd_version "${J2026_ARGOCD_VERSION_CONSTRAINT}" "${J2026_ARGOCD_VERSION}")

log_step "Installing ArgoCD into ${J2026_ARGOCD_NAMESPACE} (Version: ${RESOLVED_3_5_PATCH})"
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

helm upgrade --install "${J2026_ARGOCD_RELEASE}" argo/argo-cd \
  --namespace "${J2026_ARGOCD_NAMESPACE}" \
  -f "${J2026_ROOT_DIR}/helm/argocd-values.yaml" \
  --set global.image.tag="${RESOLVED_3_5_PATCH}" \
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
  log_info "Wiring Google OIDC for ArgoCD at ${ARGOCD_URL}"
  
  PATCH_FILE=$(mktemp)
  cat <<EOF > "${PATCH_FILE}"
data:
  url: ${ARGOCD_URL}
  dex.config: |
    connectors:
      - type: oidc
        id: google
        name: Google
        config:
          issuer: https://accounts.google.com
          clientID: ${CLIENT_ID}
          clientSecret: ${CLIENT_SECRET}
          redirectURI: ${ARGOCD_URL}/api/dex/callback
          scopes:
            - openid
            - profile
            - email
          userIDKey: email
          userNameKey: email
EOF
  kubectl patch configmap argocd-cm -n ${J2026_ARGOCD_NAMESPACE} --patch-file "${PATCH_FILE}"
  rm "${PATCH_FILE}"

  PATCH_FILE_RBAC=$(mktemp)
  # scopes MUST include 'email': Google OIDC returns no 'groups' claim, so RBAC
  # subjects are matched against the email claim (the human admin is bound by email
  # below / in the CI-account section). With the default '[groups]' nothing matches
  # and OIDC users fall to policy.default. (policy.csv here is overwritten by the
  # CI-account patch further down; the binding that matters is set there.)
  cat <<EOF > "${PATCH_FILE_RBAC}"
data:
  scopes: '[groups, email]'
  policy.default: role:readonly
  policy.csv: |
    g, authenticated, role:admin
EOF
  if [[ -n "${J2026_JENKINS_OIDC_ADMIN_EMAIL}" ]]; then
    echo "    g, ${J2026_JENKINS_OIDC_ADMIN_EMAIL}, role:admin" >> "${PATCH_FILE_RBAC}"
  fi
  kubectl patch configmap argocd-rbac-cm -n ${J2026_ARGOCD_NAMESPACE} --patch-file "${PATCH_FILE_RBAC}"
  rm "${PATCH_FILE_RBAC}"
  
  # Restart argocd-server and dex to pick up CM changes
  log_info "Restarting ArgoCD components to pick up OIDC config"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-dex-server" -n "${J2026_ARGOCD_NAMESPACE}"
  
  log_info "Waiting for ArgoCD server and dex rollouts to complete to release resource quota..."
  kubectl rollout status deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}" --timeout=5m
  kubectl rollout status deployment "${J2026_ARGOCD_RELEASE}-dex-server" -n "${J2026_ARGOCD_NAMESPACE}" --timeout=5m
else
  log_warn "OIDC credentials not found. ArgoCD will use local admin password."
fi

# 2.5 Configure the CI engine's ArgoCD account (CLI/API access) - the pipeline
# 'Deploy' stage uses this token to `argocd app sync`. Account name follows the
# active CI engine (ci.engine): 'jenkins' or 'tekton'.
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  CI_ARGOCD_ACCOUNT="tekton"
else
  CI_ARGOCD_ACCOUNT="jenkins"
fi
log_step "Configuring '${CI_ARGOCD_ACCOUNT}' account in ArgoCD"
kubectl patch configmap argocd-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p "{\"data\": {\"accounts.${CI_ARGOCD_ACCOUNT}\": \"apiKey\"}}"

policy_csv="g, ${CI_ARGOCD_ACCOUNT}, role:admin"
if [[ -n "${CLIENT_ID}" && -n "${CLIENT_SECRET}" ]]; then
  # Grant the human admin via their Google email claim (scopes include 'email'
  # above). ArgoCD has NO built-in "authenticated" group - that subject is a
  # no-op - so bind the specific admin email instead.
  if [[ -n "${J2026_JENKINS_OIDC_ADMIN_EMAIL}" ]]; then
    policy_csv="g, ${J2026_JENKINS_OIDC_ADMIN_EMAIL}, role:admin\n${policy_csv}"
  else
    log_warn "JENKINS_OIDC_ADMIN_EMAIL unset - no human will get ArgoCD admin via OIDC (only the '${CI_ARGOCD_ACCOUNT}' API account). Set the GitHub secret to your Google login email, else ArgoCD shows an empty app list to SSO users."
  fi
fi
kubectl patch configmap argocd-rbac-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p "{\"data\": {\"policy.csv\": \"${policy_csv}\"}}"

# Restart argocd-server to pick up local account and rbac config changes (only if OIDC was disabled, since we restarted above otherwise)
if [[ -z "${CLIENT_ID}" || -z "${CLIENT_SECRET}" ]]; then
  log_info "Restarting ArgoCD server to pick up local account config"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}"
  kubectl rollout status deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}" --timeout=5m
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
    --image="quay.io/argoproj/argocd:${RESOLVED_3_5_PATCH}" \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "argocd-token-gen",
          "image": "quay.io/argoproj/argocd:'"${RESOLVED_3_5_PATCH}"'",
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
wait_for_deployment "${J2026_ARGOCD_RELEASE}-server" "${J2026_ARGOCD_NAMESPACE}" "5m"

# 4. Configure GitOps Project and AppSet
log_step "Configuring ArgoCD Microservices GitOps Project"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/microservices-project.yaml"

log_step "Configuring platform-postgres app-of-apps (CNPG operator + pgAdmin) via ArgoCD"
# Correlated Postgres platform: the CNPG operator and the pgAdmin UI that
# administers its databases are grouped under one parent Application
# (argocd/platform-postgres). repoUrl/branch are passed down so the pgAdmin
# child's git source tracks the active branch.
PG_APP_FILE=$(mktemp)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
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
kubectl apply -f "${HEADLAMP_APP_FILE}"
rm "${HEADLAMP_APP_FILE}"

# pgAdmin is deployed by the platform-postgres app-of-apps above (grouped with
# the CNPG operator it administers).

log_step "Generating and applying Microservices ApplicationSet"
# Inject values into the AppSet manifest
# Using @ as delimiter for sed to avoid issues with URLs
APPSET_FILE=$(mktemp)
GITOPS_REPO_URL="https://github.com/nubenetes/jenkins-2026-gitops-config.git"
sed "s@{{repoUrl}}@${GITOPS_REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
     s@{{platform}}@${J2026_PLATFORM}@g" \
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

kubectl apply -f "${APPSET_FILE}"
rm "${APPSET_FILE}"

log_step "Applying ArgoCD Version Patch Watcher CronJob (tracking ${J2026_ARGOCD_VERSION_CONSTRAINT})"
# Template the tracked constraint from config so the daily auto-upgrade watcher,
# Day1 and Day2.redeploy.01 all read the SAME source (config.yaml argocd.version_constraint).
sed "s|__ARGOCD_CONSTRAINT__|${J2026_ARGOCD_VERSION_CONSTRAINT}|g" \
  "${J2026_ROOT_DIR}/argocd/argocd-version-patch-watcher.yaml" \
  | kubectl apply -n "${J2026_ARGOCD_NAMESPACE}" -f -

log_info "ArgoCD installed and GitOps configured."
