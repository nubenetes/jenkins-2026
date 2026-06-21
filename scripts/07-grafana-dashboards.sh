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
#   managed-aws - publishes the managed-aws dashboard variants to Amazon Managed
#     Grafana (AMG). AMG has no static API key, so a SHORT-LIVED workspace
#     service-account token is minted via the AWS API at publish time (needs AWS
#     credentials). AMG connection params come from env vars, falling back to the
#     in-cluster "${J2026_AWS_MANAGED_SECRET}" Secret - so the dedicated
#     02.04-publish-aws-dashboards.yml workflow can publish with no cluster
#     access (reading them from the persistent terraform state instead).
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
    # (DS_CW_UID / DS_XRAY_UID). AMG auto-provisions one datasource per type
    # enabled on the workspace (Amazon Managed Prometheus, CloudWatch, X-Ray -
    # fully configured with the workspace IAM role, no secrets), so we match
    # those by TYPE and reuse them (creating one only as a fallback), then
    # substitute their real uids and bind ${DS_PROMETHEUS} to AMP before importing.
    for tool in aws jq curl; do
      if ! command -v "${tool}" >/dev/null 2>&1; then
        log_warn "'${tool}' not found - skipping managed-aws dashboard import."
        exit 0
      fi
    done
    # AMG has no static API key, so this path mints a workspace token with the
    # AWS API and therefore needs AWS credentials. up.sh has none in CI (the
    # keyless design only feeds the collector via web identity), so publishing
    # runs as a dedicated, AWS-authenticated workflow that invokes this script
    # (02.04-publish-aws-dashboards.yml). Skip gracefully when unauthenticated
    # rather than failing up.sh.
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      log_warn "No AWS credentials available - skipping managed-aws dashboard import (published by the 02.04 dashboards workflow)."
      exit 0
    fi

    # Source the AMG connection params. Two callers:
    #   up.sh (in-cluster) - read them from the in-cluster J2026_AWS_MANAGED_SECRET
    #     Secret that 02.01 built from the persistent terraform state.
    #   02.04-publish-aws-dashboards.yml (no cluster) - it exports them straight
    #     from that same terraform state, so they're already in the environment.
    # Environment wins (the ':=' only reads the Secret when an env var is unset),
    # so dashboards can be published with no cluster access at all (AMG/AMP are
    # persistent; the GKE cluster is throwaway). Env var names match secret keys.
    if kubectl get secret "${J2026_AWS_MANAGED_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      sread() { kubectl get secret "${J2026_AWS_MANAGED_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath="{.data.$1}" | base64 -d; }
      : "${GRAFANA_BASE_URL:=$(sread GRAFANA_BASE_URL)}"
      : "${AWS_REGION:=$(sread AWS_REGION)}"
      : "${GRAFANA_WORKSPACE_ID:=$(sread GRAFANA_WORKSPACE_ID)}"
      : "${AMP_QUERY_URL:=$(sread AMP_QUERY_URL)}"
    fi
    GRAFANA_BASE_URL="${GRAFANA_BASE_URL:-}"
    AWS_REGION="${AWS_REGION:-}"
    WORKSPACE_ID="${GRAFANA_WORKSPACE_ID:-}"
    AMP_QUERY_URL="${AMP_QUERY_URL:-}"
    if [[ -z "${GRAFANA_BASE_URL}" || -z "${WORKSPACE_ID}" ]]; then
      log_warn "AMG connection params not available (no '${J2026_AWS_MANAGED_SECRET}' Secret and no GRAFANA_BASE_URL/GRAFANA_WORKSPACE_ID in env) - skipping dashboard import."
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

    # AMG creates the XRAY/CLOUDWATCH datasource *entries* (data_sources on the
    # workspace) but does NOT register the X-Ray datasource *plugin* binary, so
    # every trace panel fails with "Plugin not registered" until it's installed.
    # pluginAdminEnabled is on for AMG workspaces, so install it from the catalog
    # (idempotent: skip if already present). CloudWatch/Prometheus are built in.
    ensure_plugin() {
      local id="$1"
      if api GET "/api/plugins/${id}/settings" >/dev/null 2>&1; then return 0; fi
      if api POST "/api/plugins/${id}/install" -d '{}' >/dev/null 2>&1; then
        log_info "Installed Grafana plugin ${id}."
      else
        log_warn "Could not install plugin ${id} - trace panels may stay empty."
      fi
    }
    ensure_plugin "grafana-x-ray-datasource"

    # Match an existing datasource by TYPE (reusing AMG's auto-provisioned one);
    # create it only if the workspace has none of that type. Echoes its uid.
    DS_JSON="$(api GET "/api/datasources" 2>/dev/null || echo '[]')"
    ensure_ds() {
      local type="$1" name="$2" url="$3" jsondata="$4" uid
      uid="$(jq -r --arg t "${type}" 'map(select(.type==$t)) | .[0].uid // empty' <<<"${DS_JSON}")"
      if [[ -z "${uid}" ]]; then
        local body
        body="$(jq -n --arg n "${name}" --arg t "${type}" --arg u "${url}" --argjson j "${jsondata}" \
          '{name:$n,type:$t,access:"proxy",isDefault:false,jsonData:$j} + (if $u=="" then {} else {url:$u} end)')"
        uid="$(api POST "/api/datasources" -d "${body}" 2>/dev/null | jq -r '.datasource.uid // empty' || true)"
      fi
      printf '%s' "${uid}"
    }

    PROM_UID="$(ensure_ds "prometheus" "amazon-managed-prometheus" "${AMP_QUERY_URL}" \
      "$(jq -nc --arg r "${AWS_REGION}" '{httpMethod:"POST",sigV4Auth:true,sigV4AuthType:"default",sigV4Region:$r}')")"
    CW_UID="$(ensure_ds "cloudwatch" "cloudwatch" "" \
      "$(jq -nc --arg r "${AWS_REGION}" '{authType:"default",defaultRegion:$r}')")"
    XRAY_UID="$(ensure_ds "grafana-x-ray-datasource" "x-ray" "" \
      "$(jq -nc --arg r "${AWS_REGION}" '{authType:"default",defaultRegion:$r}')")"
    # Display name for the ${DS_PROMETHEUS} template var - the reused datasource's
    # real name (falls back to the name we'd create above).
    PROM_NAME="$(jq -r 'map(select(.type=="prometheus")) | .[0].name // "amazon-managed-prometheus"' <<<"${DS_JSON}")"
    [[ -n "${PROM_UID}" ]] || log_warn "Amazon Managed Prometheus datasource not resolved - metric panels may be empty."
    [[ -n "${CW_UID}" ]]   || log_warn "CloudWatch datasource not resolved - log panels may be empty."
    [[ -n "${XRAY_UID}" ]] || log_warn "X-Ray datasource not resolved - trace panels may be empty."

    AWS_DASHBOARDS_DIR="${J2026_ROOT_DIR}/observability/grafana/dashboards-aws"
    log_step "Publishing dashboards to Amazon Managed Grafana (${GRAFANA_BASE_URL})"
    # Two sets, both bound to AMP via the same ${DS_PROMETHEUS} substitution:
    #   *-aws.json          - the custom project dashboards (generate.py)
    #   community/*.json     - vendored upstream Kubernetes/node dashboards
    #                          (community/vendor.py); these carry no CloudWatch/
    #                          X-Ray panels, so the DS_CW_UID/DS_XRAY_UID fixups
    #                          below are simply no-ops for them.
    for dashboard in "${AWS_DASHBOARDS_DIR}"/*-aws.json "${AWS_DASHBOARDS_DIR}"/community/*.json; do
      [[ -f "${dashboard}" ]] || continue
      name="$(basename "${dashboard}" .json)"
      payload="$(jq --arg cw "${CW_UID}" --arg xray "${XRAY_UID}" --arg prom "${PROM_UID}" --arg promname "${PROM_NAME}" '
        def fixuid: walk(if type=="object" and .uid=="DS_CW_UID" then .uid=$cw
                         elif type=="object" and .uid=="DS_XRAY_UID" then .uid=$xray
                         else . end);
        (fixuid
         | .templating.list |= map(if .name=="DS_PROMETHEUS"
             then .current={selected:true,text:$promname,value:$prom}
             else . end)
         | .id=null)
        | {dashboard:., folderUid:"", overwrite:true}' "${dashboard}")"
      # Stream the body via stdin (--data-binary @-) rather than passing it as a
      # curl argument: some vendored dashboards (e.g. node-exporter-full, ~500KB)
      # exceed ARG_MAX as a command-line arg and would silently fail to publish.
      if printf '%s' "${payload}" | api POST "/api/dashboards/db" --data-binary @- >/dev/null 2>&1; then
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
