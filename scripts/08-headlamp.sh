#!/usr/bin/env bash
# Installs Headlamp (kubernetes-sigs/headlamp) - a web UI for managing this
# cluster - into ${J2026_HEADLAMP_NAMESPACE}, wired to Google OIDC login via
# the "${J2026_HEADLAMP_CREDENTIALS_SECRET}" Secret (created by
# scripts/01-namespaces.sh), and grants cluster-admin to every email in
# J2026_HEADLAMP_ADMIN_EMAILS via a ClusterRoleBinding. See README.md
# "Headlamp" for the access model, OAuth client setup and caveats. Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

helm_args=(
  upgrade --install "${J2026_HEADLAMP_RELEASE}" "${J2026_HEADLAMP_CHART_NAME}"
  --namespace "${J2026_HEADLAMP_NAMESPACE}"
  --create-namespace
  -f "${J2026_ROOT_DIR}/helm/headlamp/values.yaml"
  --wait --timeout 5m
)

if [[ -n "${J2026_HEADLAMP_CHART_VERSION}" ]]; then
  helm_args+=(--version "${J2026_HEADLAMP_CHART_VERSION}")
fi

log_step "Installing ${J2026_HEADLAMP_RELEASE} (${J2026_HEADLAMP_CHART_NAME}) into ${J2026_HEADLAMP_NAMESPACE}"
helm "${helm_args[@]}"

log_step "Granting cluster-admin to Headlamp admin emails"
if [[ -z "${J2026_HEADLAMP_ADMIN_EMAILS}" ]]; then
  log_info "headlamp.adminEmails / JENKINS2026_HEADLAMP_ADMIN_EMAILS is empty - no ClusterRoleBindings created."
  log_info "See README.md \"Headlamp\" to grant your Google account access."
else
  IFS=',' read -ra admin_emails <<<"${J2026_HEADLAMP_ADMIN_EMAILS}"
  for email in "${admin_emails[@]}"; do
    email="$(echo "${email}" | xargs)" # trim whitespace
    [[ -z "${email}" ]] && continue
    # Sanitize email into a valid resource name (RFC 1123): lowercase,
    # '@'/'.'/'+' -> '-'.
    binding_name="headlamp-admin-$(echo "${email}" | tr '[:upper:]' '[:lower:]' | tr '@.+' '-')"
    log_info "ClusterRoleBinding ${binding_name} -> User ${email} (cluster-admin)"
    kubectl create clusterrolebinding "${binding_name}" \
      --clusterrole=cluster-admin \
      --user="${email}" \
      --dry-run=client -o yaml | kubectl apply -f -
  done
fi

log_info "Headlamp ready. Forward the UI with:"
log_info "  kubectl -n ${J2026_HEADLAMP_NAMESPACE} port-forward svc/${J2026_HEADLAMP_RELEASE} 8080:80"
log_info "Then open http://localhost:8080 and sign in with Google."
