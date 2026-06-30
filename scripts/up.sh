#!/usr/bin/env bash
# Provisions the entire jenkins-2026 PoC for the configured platform
# (config/config.yaml platform.target, override with JENKINS2026_PLATFORM).
#
# Order:
#   00 check-prereqs    (sequential - tooling, cluster, helm repos)
#   01 namespaces       (sequential - namespaces, secrets, rolebindings)
#   02 otel-operator    (sequential - CRDs needed by 05's Instrumentation CR)
#   08.5-argocd.sh      (sequential - CD engine for GitOps; before 03 so oss
#                        mode can apply the observability-oss app-of-apps)
#   03 observability    (sequential - oss mode deploys via ArgoCD)
#   04 jenkins          (sequential to prevent API pressure)
#   06 seed-pipelines   (sequential - needs 04 ready)
#   07 grafana-dashboards (sequential - needs 03's credentials/configmap)
#   07.5 grafana-alerts  (sequential - provisions contact point + alert rules)
#   08 headlamp         (sequential - cluster management UI)
#   09 gateway          (sequential - public access via GKE Gateway API + IAP)
#
# Each step is idempotent; re-running up.sh after a partial failure is safe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

log_step "jenkins-2026 up - platform=${J2026_PLATFORM} ci-engine=${J2026_CI_ENGINE} observability=${J2026_OBS_MODE}"

"${SCRIPT_DIR}/00-check-prereqs.sh"
# Reclaim any orphaned CSI persistent disks left by a previous incarnation BEFORE
# this cluster provisions its own (they cost money + burn the SSD_TOTAL_GB quota).
# Safe + idempotent: only deletes unattached pvc-* disks not referenced by a live
# PV, and aborts if the cluster is unreachable. Non-fatal. See docs/501.
bash "${SCRIPT_DIR}/sweep-orphaned-pds.sh" || log_warn "Orphan-PD sweep failed (non-fatal) - continuing"
"${SCRIPT_DIR}/01-namespaces.sh"
"${SCRIPT_DIR}/02-otel-operator.sh"

# ArgoCD (the CD engine) is installed BEFORE observability so 03-observability.sh
# (oss mode) can apply the observability-oss app-of-apps — the Application CRD
# must already exist. 08.5-argocd only depends on the jenkins-credentials Secret
# from 01-namespaces, not on observability/jenkins.
log_step "Installing 08.5-argocd (CD Engine)"
"${SCRIPT_DIR}/08.5-argocd.sh"

# Wire up External Secrets (no-op unless secrets.backend=eso). Runs after ESO is
# installed by 08.5 and before the secret consumers (03/04/08/09).
log_step "Syncing External Secrets (08.6, eso mode only)"
"${SCRIPT_DIR}/08.6-eso-sync.sh"

log_step "Installing 03-observability (sequential to prevent API pressure)"
"${SCRIPT_DIR}/03-observability.sh"

# CI engine (config.yaml ci.engine, override with JENKINS2026_CI_ENGINE):
#   jenkins -> 04-jenkins.sh        + 06-seed-pipelines.sh
#   tekton  -> 04-tekton.sh         + 06-tekton-pipelines.sh
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  log_step "Installing 04-tekton (CI engine = tekton)"
  "${SCRIPT_DIR}/04-tekton.sh"
  "${SCRIPT_DIR}/06-tekton-pipelines.sh"
else
  log_step "Installing 04-jenkins (sequential to prevent API pressure)"
  "${SCRIPT_DIR}/04-jenkins.sh"
  "${SCRIPT_DIR}/06-seed-pipelines.sh"
fi

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
  log_step "Waiting for the microservices Deployments to be Available before OTel injection check"
  # Gate on the actual workloads, NOT the ArgoCD app health: microservices-stable
  # reports health=Unknown even when everything is fine, because ArgoCD has no
  # health assessment for the CNPG (Cluster/Pooler) and OTel (Instrumentation) CRs
  # the app owns. Waiting for app="Healthy" therefore always burned the full 10m
  # timeout. `wait --all` errors (and the loop retries) until the Deployments exist.
  timeout 600 bash -c '
    until kubectl -n "'"${J2026_MICROSERVICES_NS_STABLE}"'" wait --for=condition=Available \
            deployment --all --timeout=15s >/dev/null 2>&1; do
      sleep 10
    done
  ' || log_warn "microservices Deployments not Available within 10m — running OTel guard anyway"
fi

# Self-heal the OTel auto-instrumentation injection race. Idempotent: no-op
# when microservices are not deployed or already injected. Non-fatal.
"${SCRIPT_DIR}/ensure-otel-injection.sh" || log_warn "OTel injection guard reported an issue (see above)."

log_info "jenkins-2026 is up. Run scripts/status.sh for endpoints and rollout status."
