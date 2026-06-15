#!/usr/bin/env bash
# Installs ArgoCD and configures it with Google OIDC.
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

# 1. Pre-create the ConfigMaps so ArgoCD starts with the right config
# This is faster than patching a running system.
log_step "Pre-configuring ArgoCD OIDC/RBAC"
ARGOCD_HOST="argocd.${J2026_GATEWAY_BASE_DOMAIN}"
ARGOCD_URL="https://${ARGOCD_HOST}"

# Fetch IAP secrets
CLIENT_ID="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.client_id}' 2>/dev/null | base64 -d || true)"
CLIENT_SECRET="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.client_secret}' 2>/dev/null | base64 -d || true)"

if [[ -n "${CLIENT_ID}" && -n "${CLIENT_SECRET}" ]]; then
  log_info "Wiring Google OIDC for ArgoCD at ${ARGOCD_URL}"
  
  # Create/Update argocd-cm
  PATCH_FILE=$(mktemp)
  cat <<EOF > "${PATCH_FILE}"
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: ${J2026_ARGOCD_NAMESPACE}
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
EOF
  kubectl apply -f "${PATCH_FILE}"
  rm "${PATCH_FILE}"

  # Create/Update argocd-rbac-cm
  PATCH_FILE_RBAC=$(mktemp)
  cat <<EOF > "${PATCH_FILE_RBAC}"
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: ${J2026_ARGOCD_NAMESPACE}
data:
  policy.default: role:readonly
  policy.csv: |
    g, authenticated, role:admin
EOF
  kubectl apply -f "${PATCH_FILE_RBAC}"
  rm "${PATCH_FILE_RBAC}"
else
  log_warn "OIDC credentials not found. ArgoCD will start with default local admin."
fi

# 2. Install ArgoCD WITHOUT --wait to unblock the script
log_step "Running Helm upgrade (background-ish)"
helm upgrade --install "${J2026_ARGOCD_RELEASE}" argo/argo-cd \
  --namespace "${J2026_ARGOCD_NAMESPACE}" \
  --set server.extraArgs="{--insecure}" \
  --timeout 10m

# 3. Use our own faster monitoring for the critical components
log_step "Waiting for ArgoCD Server to be ready"
wait_for_deployment "${J2026_ARGOCD_RELEASE}-server" "${J2026_ARGOCD_NAMESPACE}" "5m"

log_info "ArgoCD installed and configured."

log_info "ArgoCD installed and configured."
