#!/usr/bin/env bash
# Installs ArgoCD and configures it with Google OIDC and GitOps projects.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

log_step "Installing ArgoCD into ${J2026_ARGOCD_NAMESPACE}"
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
helm upgrade --install "${J2026_ARGOCD_RELEASE}" argo/argo-cd \
  --namespace "${J2026_ARGOCD_NAMESPACE}" \
  -f "${J2026_ROOT_DIR}/helm/argocd-values.yaml" \
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
      - type: google
        id: google
        name: Google
        config:
          clientID: ${CLIENT_ID}
          clientSecret: ${CLIENT_SECRET}
          redirectURI: ${ARGOCD_URL}/api/dex/callback
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
  
  # 2.5 Configure Jenkins Account for ArgoCD (CLI/API access)
  log_step "Configuring Jenkins account in ArgoCD"
  kubectl patch configmap argocd-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p '{"data": {"accounts.jenkins": "apiKey"}}'
  policy_csv="g, authenticated, role:admin\ng, jenkins, role:admin"
  if [[ -n "${J2026_JENKINS_OIDC_ADMIN_EMAIL}" ]]; then
    policy_csv="${policy_csv}\ng, ${J2026_JENKINS_OIDC_ADMIN_EMAIL}, role:admin"
  fi
  kubectl patch configmap argocd-rbac-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p "{\"data\": {\"policy.csv\": \"${policy_csv}\"}}"
  
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
    --image=quay.io/argoproj/argocd:v2.11.0 -- \
    bash -c "argocd account generate-token --account jenkins --core"
  
  # Wait for the pod to succeed (complete its execution)
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --timeout=30s
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
  else
    log_error "Failed to generate ArgoCD token (exit code: ${EXIT_CODE})"
    log_debug "Raw output: ${RAW_TOKEN}"
  fi
else
  log_warn "OIDC credentials not found. ArgoCD will use local admin password."
fi

# 3. Wait for Server
log_step "Waiting for ArgoCD Server to be ready"
wait_for_deployment "${J2026_ARGOCD_RELEASE}-server" "${J2026_ARGOCD_NAMESPACE}" "5m"

# 4. Configure GitOps Project and AppSet
log_step "Configuring ArgoCD Microservices GitOps Project"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/microservices-project.yaml"

log_step "Configuring Postgres Operator via ArgoCD"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/pgo-app.yaml"

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
     s@{{branchDevelop}}@${J2026_SELF_REPO_DEV_BRANCH}@g; 
     s@{{platform}}@${J2026_PLATFORM}@g" \
    "${J2026_ROOT_DIR}/argocd/microservices-appset.yaml" > "${APPSET_FILE}"

kubectl apply -f "${APPSET_FILE}"
rm "${APPSET_FILE}"

log_info "ArgoCD installed and GitOps configured."
