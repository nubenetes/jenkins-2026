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

log_step "Installing 04-jenkins (sequential to prevent API pressure)"
"${SCRIPT_DIR}/04-jenkins.sh"

log_step "Installing 05-microservices (Initial Helm releases)"
"${SCRIPT_DIR}/05-microservices.sh"

log_step "Installing 08.5-argocd (CD Engine)"
"${SCRIPT_DIR}/08.5-argocd.sh"

"${SCRIPT_DIR}/06-seed-pipelines.sh"
"${SCRIPT_DIR}/07-grafana-dashboards.sh"
"${SCRIPT_DIR}/08-headlamp.sh"
"${SCRIPT_DIR}/09-gateway.sh"

log_info "jenkins-2026 is up. Run scripts/status.sh for endpoints and rollout status."
