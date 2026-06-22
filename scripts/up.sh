#!/usr/bin/env bash
# Provisions the entire jenkins-2026 PoC for the configured platform
# (config/config.yaml platform.target, override with JENKINS2026_PLATFORM).
#
# Order:
#   00 check-prereqs    (sequential - tooling, cluster, helm repos)
#   01 namespaces       (sequential - namespaces, secrets, rolebindings)
#   02 otel-operator    (sequential - CRDs needed by 05's Instrumentation CR)
#   03 observability  \
#   04 jenkins         > parallel - independent of each other
#   06 seed-pipelines   (sequential - needs 04 ready)
#   07 grafana-dashboards (sequential - needs 03's credentials/configmap)
#   07.5 grafana-alerts  (sequential - provisions contact point + alert rules)
#   08 headlamp         (sequential - cluster management UI)
#   08.5-argocd.sh      (sequential - CD engine for GitOps)
#   09 gateway          (sequential - public access via GKE Gateway API + IAP)
#
# Each step is idempotent; re-running up.sh after a partial failure is safe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

log_step "jenkins-2026 up - platform=${J2026_PLATFORM} observability=${J2026_OBS_MODE}"

"${SCRIPT_DIR}/00-check-prereqs.sh"
"${SCRIPT_DIR}/01-namespaces.sh"
"${SCRIPT_DIR}/02-otel-operator.sh"

log_step "Installing 03-observability (sequential to prevent API pressure)"
"${SCRIPT_DIR}/03-observability.sh"

log_step "Installing 08.5-argocd (CD Engine)"
"${SCRIPT_DIR}/08.5-argocd.sh"

log_step "Installing 04-jenkins (sequential to prevent API pressure)"
"${SCRIPT_DIR}/04-jenkins.sh"

"${SCRIPT_DIR}/06-seed-pipelines.sh"
"${SCRIPT_DIR}/07-grafana-dashboards.sh"
"${SCRIPT_DIR}/07.5-grafana-alerts.sh" || log_warn "Grafana alert provisioning reported an issue (see above) — non-fatal"
"${SCRIPT_DIR}/08-headlamp.sh"
"${SCRIPT_DIR}/09-gateway.sh"

# On a re-run the microservices are already up — check OTel injection immediately.
# On a fresh provision ArgoCD deploys them asynchronously after this point, so
# we first wait for microservices-stable to become Healthy (up to 10 min), then
# run the guard. The wait is skipped when the app does not exist yet (first ever
# run before ArgoCD has created the Application).
if kubectl -n argocd get application microservices-stable >/dev/null 2>&1; then
  log_step "Waiting for ArgoCD microservices-stable to be Healthy before OTel injection check"
  timeout 600 bash -c '
    until [[ "$(kubectl -n argocd get application microservices-stable \
                -o jsonpath="{.status.health.status}" 2>/dev/null)" == "Healthy" ]]; do
      sleep 10
    done
  ' || log_warn "microservices-stable not Healthy within 10m — running OTel guard anyway"
fi

# Self-heal the OTel auto-instrumentation injection race. Idempotent: no-op
# when microservices are not deployed or already injected. Non-fatal.
"${SCRIPT_DIR}/ensure-otel-injection.sh" || log_warn "OTel injection guard reported an issue (see above)."

log_info "jenkins-2026 is up. Run scripts/status.sh for endpoints and rollout status."
