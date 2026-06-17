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

    log_step "Authenticating with gcx CLI"
    # gcx login --yes performs non-interactive login, discovering the stack ID and namespace
    gcx login --yes default --server "${GRAFANA_BASE_URL}" --token "${GRAFANA_API_KEY}" --allow-server-override

    RESOURCES_DIR="${J2026_ROOT_DIR}/gcx_test"
    FOLDER_UID="jenkins-2026"

    log_step "Preparing dashboard manifests in ${RESOURCES_DIR}/dashboards"
    mkdir -p "${RESOURCES_DIR}/dashboards"

    for dashboard in "${DASHBOARDS_DIR}"/*.json; do
      name="$(basename "${dashboard}" .json)"
      uid="$(jq -r '.uid' "${dashboard}")"
      
      # Wrap dashboard JSON into a gcx-compatible resource manifest
      # We use .uid for metadata.name and ensure folderUID is set in spec
      # We also add the grafana.app/folder annotation which gcx uses for display
      jq -n --slurpfile db "${dashboard}" \
        --arg folderUID "${FOLDER_UID}" \
        --arg uid "${uid}" \
        '{
          apiVersion: "dashboard.grafana.app/v1",
          kind: "Dashboard",
          metadata: {
            name: $uid,
            annotations: {
              "grafana.app/folder": $folderUID
            }
          },
          spec: ($db[0] + {folderUID: $folderUID})
        }' > "${RESOURCES_DIR}/dashboards/${name}.json"
    done

    log_step "Pushing resources via gcx resources push"
    # This will push both the folder (from gcx_test/folders) and the dashboards
    # We use --include-managed to ensure we can update folders/dashboards even if they were 
    # previously managed by other tools (or gcx api calls).
    gcx resources push -p "${RESOURCES_DIR}" --on-error abort --include-managed

    log_step "Configuring Grafana Kubernetes Monitoring app data sources"
    GRAFANA_STACK_ID="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_STACK_ID}' | base64 -d)"
    if [[ -n "${GRAFANA_STACK_ID}" ]]; then
      gcx api /api/plugins/grafana-k8s-app/settings -X POST -d "{
        \"enabled\": true,
        \"jsonData\": {
          \"grafana_instance_id\": ${GRAFANA_STACK_ID},
          \"grafanacom_endpoint\": \"https://grafana.com/api\",
          \"integrations_endpoint\": \"https://integrations-api-eu-west-2.grafana.net\",
          \"prometheus\": {
            \"uid\": \"grafanacloud-prom\"
          },
          \"loki\": {
            \"uid\": \"grafanacloud-logs\"
          },
          \"tempo\": {
            \"uid\": \"grafanacloud-traces\"
          }
        }
      }" >/dev/null || log_warn "Failed to configure Kubernetes Monitoring app settings automatically."
    else
      log_warn "GRAFANA_STACK_ID not found - skipping auto-configuration of Kubernetes app settings."
    fi
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
