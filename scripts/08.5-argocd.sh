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

# Fetch IAP secrets
CLIENT_ID="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.client_id}' 2>/dev/null | base64 -d || true)"
CLIENT_SECRET="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.client_secret}' 2>/dev/null | base64 -d || true)"

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
  cat <<EOF > "${PATCH_FILE_RBAC}"
data:
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

# 2.5 Configure Jenkins Account for ArgoCD (CLI/API access) - Unconditional
log_step "Configuring Jenkins account in ArgoCD"
kubectl patch configmap argocd-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p '{"data": {"accounts.jenkins": "apiKey"}}'

policy_csv="g, jenkins, role:admin"
if [[ -n "${CLIENT_ID}" && -n "${CLIENT_SECRET}" ]]; then
  policy_csv="g, authenticated, role:admin\n${policy_csv}"
  if [[ -n "${J2026_JENKINS_OIDC_ADMIN_EMAIL}" ]]; then
    policy_csv="${policy_csv}\ng, ${J2026_JENKINS_OIDC_ADMIN_EMAIL}, role:admin"
  fi
fi
kubectl patch configmap argocd-rbac-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p "{\"data\": {\"policy.csv\": \"${policy_csv}\"}}"

# Restart argocd-server to pick up local account and rbac config changes (only if OIDC was disabled, since we restarted above otherwise)
if [[ -z "${CLIENT_ID}" || -z "${CLIENT_SECRET}" ]]; then
  log_info "Restarting ArgoCD server to pick up local account config"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}"
  kubectl rollout status deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}" --timeout=5m
fi

log_info "Generating ArgoCD API token for Jenkins"
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

# Ensure no old token-gen pod exists
kubectl delete pod argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found=true --wait=true || true

# Use a subshell to capture token and ensure RBAC cleanup happens regardless of success/failure
set +e
kubectl run argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --restart=Never \
  --image="quay.io/argoproj/argocd:${RESOLVED_3_5_PATCH}" \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "argocd-token-gen",
        "image": "quay.io/argoproj/argocd:'"${RESOLVED_3_5_PATCH}"'",
        "command": ["bash", "-c", "argocd account generate-token --account jenkins --core"],
        "resources": {
          "requests": {
            "cpu": "50m",
            "memory": "128Mi"
          },
          "limits": {
            "cpu": "100m",
            "memory": "256Mi"
          }
        }
      }]
    }
  }'

# Wait for the pod to succeed (complete its execution)
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --timeout=3m
EXIT_CODE=$?

if [[ ${EXIT_CODE} -eq 0 ]]; then
  RAW_TOKEN=$(kubectl logs argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}")
else
  RAW_TOKEN=""
fi
set -e
kubectl delete pod argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found=true || true
          
# Strip any newlines or trailing whitespace from the token to prevent JSON patch errors
TOKEN=$(echo "${RAW_TOKEN}" | tr -d '\n\r' | xargs)
          
# Cleanup temporary RBAC
kubectl delete clusterrolebinding temp-argocd-admin || true

if [[ ${EXIT_CODE} -eq 0 && -n "${TOKEN}" ]]; then
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

log_step "Configuring CloudNative-PG Operator via ArgoCD"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/cnpg-app.yaml"

log_step "Configuring External Secrets Operator via ArgoCD"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/external-secrets-app.yaml"

log_step "Configuring Headlamp via ArgoCD"
# Inject values into the Headlamp Application manifest
HEADLAMP_APP_FILE=$(mktemp)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g; 
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
    "${J2026_ROOT_DIR}/argocd/headlamp-app.yaml" > "${HEADLAMP_APP_FILE}"
kubectl apply -f "${HEADLAMP_APP_FILE}"
rm "${HEADLAMP_APP_FILE}"

log_step "Configuring pgAdmin via ArgoCD"
# Inject values into the pgAdmin Application manifest
PGADMIN_APP_FILE=$(mktemp)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g; 
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
    "${J2026_ROOT_DIR}/argocd/pgadmin-app.yaml" > "${PGADMIN_APP_FILE}"
kubectl apply -f "${PGADMIN_APP_FILE}"
rm "${PGADMIN_APP_FILE}"


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

log_step "Applying ArgoCD Version Patch Watcher CronJob"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/argocd-version-patch-watcher.yaml" -n "${J2026_ARGOCD_NAMESPACE}"

log_info "ArgoCD installed and GitOps configured."
