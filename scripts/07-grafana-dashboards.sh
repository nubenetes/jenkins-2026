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
      log_warn "Add them (Grafana Cloud -> Administration -> Service accounts) and re-run this script."
      exit 0
    fi

    for dashboard in "${DASHBOARDS_DIR}"/*.json; do
      name="$(basename "${dashboard}")"
      log_step "Importing ${name} into ${GRAFANA_BASE_URL}"
      python3 - "${dashboard}" <<'PYEOF' | curl -sf -X POST "${GRAFANA_BASE_URL}/api/dashboards/db" \
          -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
          -H "Content-Type: application/json" \
          --data-binary @- -o /dev/null -w '  -> HTTP %{http_code}\n'
import json, sys
with open(sys.argv[1]) as f:
    dashboard = json.load(f)
dashboard["id"] = None
print(json.dumps({"dashboard": dashboard, "overwrite": True, "folderTitle": "jenkins-2026"}))
PYEOF
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
