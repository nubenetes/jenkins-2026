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
#   managed-azure - publishes them to Azure Managed Grafana via its Grafana
#     HTTP API (GRAFANA_BASE_URL + GRAFANA_API_KEY from the
#     "${J2026_AZURE_MONITOR_SECRET}" Secret). Metric panels are portable;
#     trace/log panels need Azure-specific rework (follow-up).
#
#   managed-aws - documented stub.
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

  managed-azure)
    # Publish dashboards to Azure Managed Grafana via its Grafana HTTP API
    # (GRAFANA_BASE_URL + GRAFANA_API_KEY in the azure-monitor-credentials
    # Secret). NOTE: the metric panels are portable (Azure Monitor managed
    # Prometheus is PromQL-compatible - just pick that datasource), but the
    # trace (App Insights) and log (Log Analytics) panels need Azure-specific
    # rework and won't render against Tempo/Loki queries. Tracked as a
    # follow-up - see docs/observability.md "managed-azure".
    if ! kubectl get secret "${J2026_AZURE_MONITOR_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_warn "Secret '${J2026_AZURE_MONITOR_SECRET}' not found - skipping dashboard import."
      exit 0
    fi
    GRAFANA_BASE_URL="$(kubectl get secret "${J2026_AZURE_MONITOR_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_BASE_URL}' | base64 -d)"
    GRAFANA_API_KEY="$(kubectl get secret "${J2026_AZURE_MONITOR_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_API_KEY}' | base64 -d)"
    if [[ -z "${GRAFANA_BASE_URL}" || -z "${GRAFANA_API_KEY}" ]]; then
      log_warn "GRAFANA_BASE_URL / GRAFANA_API_KEY not set in '${J2026_AZURE_MONITOR_SECRET}' - skipping dashboard import."
      exit 0
    fi

    # Azure Managed Grafana reads from Azure Monitor datasources, so publish the
    # managed-azure dashboard variants (metric panels unchanged; log/trace
    # panels rewritten to Azure Monitor Logs/Traces). Generated from the
    # canonical dashboards by observability/grafana/dashboards-azure/generate.py.
    AZURE_DASHBOARDS_DIR="${J2026_ROOT_DIR}/observability/grafana/dashboards-azure"
    log_step "Publishing dashboards to Azure Managed Grafana (${GRAFANA_BASE_URL})"
    for dashboard in "${AZURE_DASHBOARDS_DIR}"/*-azure.json; do
      name="$(basename "${dashboard}" .json)"
      # Wrap into the /api/dashboards/db request body and overwrite by uid.
      payload="$(jq -n --slurpfile db "${dashboard}" \
        '{dashboard: ($db[0] + {id: null}), folderUid: "", overwrite: true}')"
      if curl -fsS -X POST "${GRAFANA_BASE_URL%/}/api/dashboards/db" \
          -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
          -H "Content-Type: application/json" \
          -d "${payload}" >/dev/null; then
        log_info "Published ${name}."
      else
        log_warn "Failed to publish ${name} (metric panels may still need an Azure Monitor datasource)."
      fi
    done
    ;;

  managed-aws)
    # Publish the managed-aws dashboard variants to Amazon Managed Grafana (AMG).
    # Unlike grafana-cloud / managed-azure, AMG has NO static API key (it
    # authenticates users via IAM Identity Center), so we mint a SHORT-LIVED
    # workspace service-account token with the AWS API at publish time - nothing
    # is stored, matching the rest of the keyless AWS design.
    #
    # AMG reads from AWS datasources, so generate.py rewrote the log/trace panels
    # (Loki -> CloudWatch Logs, Tempo -> X-Ray) with placeholder datasource uids
    # (DS_CW_UID / DS_XRAY_UID). We ensure the three AWS datasources exist
    # (Amazon Managed Prometheus, CloudWatch, X-Ray - all authenticated by the
    # workspace IAM role, no secrets), then substitute their real uids and bind
    # ${DS_PROMETHEUS} to AMP before importing.
    if ! kubectl get secret "${J2026_AWS_MANAGED_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_warn "Secret '${J2026_AWS_MANAGED_SECRET}' not found - skipping dashboard import."
      exit 0
    fi
    for tool in aws jq curl; do
      if ! command -v "${tool}" >/dev/null 2>&1; then
        log_warn "'${tool}' not found - skipping managed-aws dashboard import."
        exit 0
      fi
    done

    sread() { kubectl get secret "${J2026_AWS_MANAGED_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath="{.data.$1}" | base64 -d; }
    GRAFANA_BASE_URL="$(sread GRAFANA_BASE_URL)"
    AWS_REGION="$(sread AWS_REGION)"
    WORKSPACE_ID="$(sread GRAFANA_WORKSPACE_ID)"
    AMP_QUERY_URL="$(sread AMP_QUERY_URL)"
    if [[ -z "${GRAFANA_BASE_URL}" || -z "${WORKSPACE_ID}" ]]; then
      log_warn "GRAFANA_BASE_URL / GRAFANA_WORKSPACE_ID not set in '${J2026_AWS_MANAGED_SECRET}' - skipping dashboard import."
      exit 0
    fi
    export AWS_REGION AWS_DEFAULT_REGION="${AWS_REGION}"

    # --- mint a short-lived AMG service-account token (keyless) --------------
    SA_NAME="jenkins-2026-dashboard-publisher"
    SA_ID="$(aws grafana list-workspace-service-accounts --workspace-id "${WORKSPACE_ID}" \
      --query "serviceAccounts[?name=='${SA_NAME}'].id | [0]" --output text 2>/dev/null || true)"
    if [[ -z "${SA_ID}" || "${SA_ID}" == "None" ]]; then
      SA_ID="$(aws grafana create-workspace-service-account --workspace-id "${WORKSPACE_ID}" \
        --name "${SA_NAME}" --grafana-role ADMIN --query 'id' --output text)"
    fi
    TOKEN_JSON="$(aws grafana create-workspace-service-account-token --workspace-id "${WORKSPACE_ID}" \
      --service-account-id "${SA_ID}" --name "publish-$(date +%s)" --seconds-to-live 900 --output json)"
    GRAFANA_API_KEY="$(jq -r '.serviceAccountToken.key' <<<"${TOKEN_JSON}")"
    TOKEN_ID="$(jq -r '.serviceAccountToken.id' <<<"${TOKEN_JSON}")"
    cleanup_token() {
      aws grafana delete-workspace-service-account-token --workspace-id "${WORKSPACE_ID}" \
        --service-account-id "${SA_ID}" --token-id "${TOKEN_ID}" >/dev/null 2>&1 || true
    }
    trap cleanup_token EXIT

    api() { local m="$1" p="$2"; shift 2; curl -fsS -X "${m}" "${GRAFANA_BASE_URL%/}${p}" \
      -H "Authorization: Bearer ${GRAFANA_API_KEY}" -H "Content-Type: application/json" "$@"; }

    # Idempotent get-or-create of an AWS datasource; echoes its uid.
    ensure_ds() {
      local name="$1" type="$2" url="$3" jsondata="$4" uid
      uid="$(api GET "/api/datasources/name/${name}" 2>/dev/null | jq -r '.uid // empty' || true)"
      if [[ -z "${uid}" ]]; then
        local body
        body="$(jq -n --arg n "${name}" --arg t "${type}" --arg u "${url}" --argjson j "${jsondata}" \
          '{name:$n,type:$t,access:"proxy",isDefault:false,jsonData:$j} + (if $u=="" then {} else {url:$u} end)')"
        uid="$(api POST "/api/datasources" -d "${body}" 2>/dev/null | jq -r '.datasource.uid // empty' || true)"
      fi
      printf '%s' "${uid}"
    }

    PROM_UID="$(ensure_ds "amazon-managed-prometheus" "prometheus" "${AMP_QUERY_URL}" \
      "$(jq -nc --arg r "${AWS_REGION}" '{httpMethod:"POST",sigV4Auth:true,sigV4AuthType:"default",sigV4Region:$r}')")"
    CW_UID="$(ensure_ds "cloudwatch" "cloudwatch" "" \
      "$(jq -nc --arg r "${AWS_REGION}" '{authType:"default",defaultRegion:$r}')")"
    XRAY_UID="$(ensure_ds "x-ray" "grafana-x-ray-datasource" "" \
      "$(jq -nc --arg r "${AWS_REGION}" '{authType:"default",defaultRegion:$r}')")"
    [[ -n "${PROM_UID}" ]] || log_warn "Amazon Managed Prometheus datasource not resolved - metric panels may be empty."
    [[ -n "${CW_UID}" ]]   || log_warn "CloudWatch datasource not resolved - log panels may be empty."
    [[ -n "${XRAY_UID}" ]] || log_warn "X-Ray datasource not resolved - trace panels may be empty."

    AWS_DASHBOARDS_DIR="${J2026_ROOT_DIR}/observability/grafana/dashboards-aws"
    log_step "Publishing dashboards to Amazon Managed Grafana (${GRAFANA_BASE_URL})"
    for dashboard in "${AWS_DASHBOARDS_DIR}"/*-aws.json; do
      name="$(basename "${dashboard}" .json)"
      payload="$(jq --arg cw "${CW_UID}" --arg xray "${XRAY_UID}" --arg prom "${PROM_UID}" '
        def fixuid: walk(if type=="object" and .uid=="DS_CW_UID" then .uid=$cw
                         elif type=="object" and .uid=="DS_XRAY_UID" then .uid=$xray
                         else . end);
        (fixuid
         | .templating.list |= map(if .name=="DS_PROMETHEUS"
             then .current={selected:true,text:"amazon-managed-prometheus",value:$prom}
             else . end)
         | .id=null)
        | {dashboard:., folderUid:"", overwrite:true}' "${dashboard}")"
      if api POST "/api/dashboards/db" -d "${payload}" >/dev/null 2>&1; then
        log_info "Published ${name}."
      else
        log_warn "Failed to publish ${name}."
      fi
    done
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}'."
    exit 1
    ;;
esac
