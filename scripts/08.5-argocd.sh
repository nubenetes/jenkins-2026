#!/usr/bin/env bash
# Installs ArgoCD and configures it with Google OIDC.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

export J2026_ARGOCD_NAMESPACE="argocd"
export J2026_ARGOCD_RELEASE="argocd"

log_step "Installing ArgoCD into ${J2026_ARGOCD_NAMESPACE}"
kubectl_apply_namespace "${J2026_ARGOCD_NAMESPACE}"

helm upgrade --install ${J2026_ARGOCD_RELEASE} argo/argo-cd \
  --namespace ${J2026_ARGOCD_NAMESPACE} \
  --set server.extraArgs={--insecure} \
  --wait

# Google OIDC Configuration
# We use Dex for OIDC federation.
log_step "Configuring ArgoCD OIDC (Google login)"

# Note: Dex needs the public URL for the callback.
ARGOCD_HOST="argocd.${J2026_GATEWAY_BASE_DOMAIN}"
ARGOCD_URL="https://${ARGOCD_HOST}"

# Fetch IAP secrets (used for general OIDC as well in this PoC)
CLIENT_ID="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.client_id}' 2>/dev/null | base64 -d || true)"
CLIENT_SECRET="$(kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.client_secret}' 2>/dev/null | base64 -d || true)"

if [[ -n "${CLIENT_ID}" && -n "${CLIENT_SECRET}" ]]; then
  log_info "Wiring Google OIDC for ArgoCD at ${ARGOCD_URL}"
  
  # Update argocd-cm for OIDC
  # Using kubectl patch for idempotency
  kubectl patch configmap argocd-cm -n ${J2026_ARGOCD_NAMESPACE} --type merge -p "
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
"

  # Map authenticated users to admin role (PoC simplification)
  kubectl patch configmap argocd-rbac-cm -n ${J2026_ARGOCD_NAMESPACE} --type merge -p '
data:
  policy.default: role:readonly
  policy.csv: |
    g, authenticated, role:admin
'
else
  log_warn "OIDC credentials not found. ArgoCD will use local admin password."
fi

log_info "ArgoCD installed and configured."
