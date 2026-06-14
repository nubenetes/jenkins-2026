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

    log_step "Configuring gcx CLI context"
    gcx config set contexts.default.grafana.server "${GRAFANA_BASE_URL}"
    gcx config set contexts.default.grafana.token "${GRAFANA_API_KEY}"
    gcx config use-context default

    FOLDER_UID="jenkins-2026"

    log_step "Ensuring Grafana folder '${FOLDER_UID}' exists"
    # Attempt to create the folder. If it exists, the API returns an error which we ignore.
    gcx api /api/folders -d "{\"title\":\"${FOLDER_UID}\", \"uid\":\"${FOLDER_UID}\"}" > /dev/null 2>&1 || true

    for dashboard in "${DASHBOARDS_DIR}"/*.json; do
      name="$(basename "${dashboard}")"
      log_step "Pushing ${name} via gcx api"
      
      # Use jq to wrap the raw dashboard JSON into the format expected by /api/dashboards/db
      # ({"dashboard": ..., "folderUid": "...", "overwrite": true})
      jq -n --slurpfile db "${dashboard}" \
        "{dashboard: \$db[0], folderUid: \"${FOLDER_UID}\", overwrite: true}" | \
        gcx api /api/dashboards/db -d @- > /dev/null
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
