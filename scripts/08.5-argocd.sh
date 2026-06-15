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
  --set server.extraArgs="{--insecure}" \
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
  kubectl patch configmap argocd-rbac-cm -n ${J2026_ARGOCD_NAMESPACE} --patch-file "${PATCH_FILE_RBAC}"
  rm "${PATCH_FILE_RBAC}"
  
  # Restart argocd-server and dex to pick up CM changes
  log_info "Restarting ArgoCD components to pick up OIDC config"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-server" -n "${J2026_ARGOCD_NAMESPACE}"
  kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-dex-server" -n "${J2026_ARGOCD_NAMESPACE}"
  
  # 2.5 Configure Jenkins Account for ArgoCD (CLI/API access)
  log_step "Configuring Jenkins account in ArgoCD"
  kubectl patch configmap argocd-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p '{"data": {"accounts.jenkins": "apiKey"}}'
  kubectl patch configmap argocd-rbac-cm -n "${J2026_ARGOCD_NAMESPACE}" --type merge -p '{"data": {"policy.csv": "g, authenticated, role:admin\ng, jenkins, role:admin"}}'
  
  log_info "Generating ArgoCD API token for Jenkins"
  # Since we don't have the CLI locally yet, we use a throwaway pod to generate the token
  # and store it in the jenkins-credentials secret
  ARGOCD_ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n "${J2026_ARGOCD_NAMESPACE}" -o jsonpath="{.data.password}" | base64 -d)
  
  TOKEN=$(kubectl run argocd-token-gen -n "${J2026_ARGOCD_NAMESPACE}" --rm -i --restart=Never \
    --image=quay.io/argoproj/argocd:v2.11.0 -- \
    bash -c "argocd login localhost:8080 --username admin --password '${ARGOCD_ADMIN_PASSWORD}' --insecure --core && \
            argocd account generate-token --account jenkins --core")
            
  if [[ -n "${TOKEN}" ]]; then
    log_info "Storing ArgoCD token in ${J2026_JENKINS_CREDENTIALS_SECRET}"
    kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
      --type=merge -p "{\"stringData\":{\"argocd-token\":\"${TOKEN}\"}}"
  else
    log_error "Failed to generate ArgoCD token"
  fi
else
  log_warn "OIDC credentials not found. ArgoCD will use local admin password."
fi

# 3. Wait for Server
log_step "Waiting for ArgoCD Server to be ready"
wait_for_deployment "${J2026_ARGOCD_RELEASE}-server" "${J2026_ARGOCD_NAMESPACE}" "5m"

# 4. Configure GitOps Project and AppSet
log_step "Configuring ArgoCD PetClinic GitOps Project"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/petclinic-project.yaml"

log_step "Generating and applying PetClinic ApplicationSet"
# Inject values into the AppSet manifest
# Using @ as delimiter for sed to avoid issues with URLs
APPSET_FILE=$(mktemp)
# Ensure J2026_SELF_REPO_URL is set (fallback to default if empty)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g; 
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g; 
     s@{{branchDevelop}}@${J2026_SELF_REPO_DEV_BRANCH}@g; 
     s@{{platform}}@${J2026_PLATFORM}@g" \
    "${J2026_ROOT_DIR}/argocd/petclinic-appset.yaml" > "${APPSET_FILE}"

kubectl apply -f "${APPSET_FILE}"
rm "${APPSET_FILE}"

log_info "ArgoCD installed and GitOps configured."
