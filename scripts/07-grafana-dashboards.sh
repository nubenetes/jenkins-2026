#!/usr/bin/env bash
# Publishes observability/grafana/dashboards/*.json:
#
#   grafana-cloud - imports them into the "jenkins-2026" folder via the
#     Grafana HTTP API, using GRAFANA_BASE_URL + GRAFANA_API_KEY from the
#     "${J2026_GRAFANA_CLOUD_SECRET}" Secret (see secret.example.yaml).
#
#   oss - no-op: 03-observability.sh already provisioned them via the
#     "jenkins-2026-grafana-dashboards" ConfigMap + kube-prometheus-stack's
#     Grafana sidecar.
#
#   managed - documented stub, same as 03-observability.sh.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

DASHBOARDS_DIR="${J2026_ROOT_DIR}/observability/grafana/dashboards"

case "${J2026_OBS_MODE}" in
  grafana-cloud)
    if ! kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_error "Secret '${J2026_GRAFANA_CLOUD_SECRET}' not found in namespace '${J2026_OBS_NAMESPACE}'."
      exit 1
    fi

    GRAFANA_BASE_URL="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_BASE_URL}' | base64 -d)"
    GRAFANA_API_KEY="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_API_KEY}' | base64 -d)"

    if [[ -z "${GRAFANA_BASE_URL}" || -z "${GRAFANA_API_KEY}" ]]; then
      log_warn "GRAFANA_BASE_URL / GRAFANA_API_KEY not set in '${J2026_GRAFANA_CLOUD_SECRET}' - skipping dashboard import."
      exit 0
    fi

    # Ensure gcx is installed
    if ! command -v gcx &> /dev/null; then
      log_step "Installing gcx CLI"
      # Install to a local bin to avoid sudo
      mkdir -p "${HOME}/.local/bin"
      curl -fsSL https://raw.githubusercontent.com/grafana/gcx/main/scripts/install.sh | BINDIR="${HOME}/.local/bin" sh
      export PATH="${HOME}/.local/bin:${PATH}"
    fi

    log_step "Authenticating gcx with Grafana Cloud"
    # gcx uses GRAFANA_URL and GRAFANA_TOKEN env vars
    export GRAFANA_URL="${GRAFANA_BASE_URL}"
    export GRAFANA_TOKEN="${GRAFANA_API_KEY}"

    for dashboard in "${DASHBOARDS_DIR}"/*.json; do
      name="$(basename "${dashboard}")"
      log_step "Pushing ${name} via gcx"
      
      # Use gcx dashboards push. --folder ensures they go to the right place.
      # gcx handles the "overwrite" and "id: null" logic internally.
      gcx dashboards push "${dashboard}" --folder "jenkins-2026"
    done
    ;;

  oss)
    log_info "observability.mode=oss: dashboards already provisioned via ConfigMap + Grafana sidecar."
    ;;

  managed)
    log_warn "observability.mode=managed is a documented stub (docs/platforms.md) - skipping dashboard import."
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}'."
    exit 1
    ;;
esac
