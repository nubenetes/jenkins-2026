#!/usr/bin/env bash
# Publishes observability/grafana/dashboards/*.json:
#
#   grafana-cloud - imports them into the "CI-CD Observability" folder via the
#     Grafana HTTP API, using GRAFANA_BASE_URL + GRAFANA_API_KEY from the
#     "${J2026_GRAFANA_CLOUD_SECRET}" Secret (see secret.example.yaml).
#
#   oss - no-op: 03-observability.sh already provisioned them via the
#     "jenkins-2026-grafana-dashboards" ConfigMap + kube-prometheus-stack's
#     Grafana sidecar.
#
#   managed-azure - no-op here: Azure Managed Grafana has no static API key
#     (Entra-only auth), so this script can't publish. The dashboards are
#     published post azure/login by the dedicated step in Day1.cluster.01-gke.yml
#     (Entra data-plane token, ${appinsights} substitution, az grafana dashboard
#     create into the "CI-CD Observability" folder).
#
#   managed-aws - publishes the managed-aws dashboard variants to Amazon Managed
#     Grafana (AMG). AMG has no static API key, so a SHORT-LIVED workspace
#     service-account token is minted via the AWS API at publish time (needs AWS
#     credentials). AMG connection params come from env vars, falling back to the
#     in-cluster "${J2026_AWS_MANAGED_SECRET}" Secret - so the dedicated
#     Day2.publish.04-aws-grafana.yml workflow can publish with no cluster
#     access (reading them from the persistent terraform state instead).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

DASHBOARDS_DIR="${J2026_ROOT_DIR}/observability/grafana/dashboards"

# Publish only the ACTIVE CI engine's overview dashboard (jenkins XOR tekton) so a
# tekton cluster doesn't show an empty "Jenkins CI" dashboard (and vice-versa). The
# k6 / microservices / postgres dashboards are engine-neutral and always shipped.
# Resolve the engine via the shared helper (explicit override → live-cluster
# detection → config.yaml default) so a standalone Day2.publish run is correct
# even when config.yaml's ci.engine default does not match the deployed cluster.
ACTIVE_CI_ENGINE="$(j2026_active_ci_engine)"
log_info "Active CI engine: ${ACTIVE_CI_ENGINE}"
# One CI overview dashboard per ci.engine; only the ACTIVE engine's is published.
case "${ACTIVE_CI_ENGINE}" in
  tekton)        KEEP_CI_DASHBOARD="tekton-overview" ;;
  githubactions) KEEP_CI_DASHBOARD="github-actions-ci" ;;
  argoworkflows) KEEP_CI_DASHBOARD="argo-workflows-ci" ;;
  *)             KEEP_CI_DASHBOARD="jenkins-overview" ;;
esac
ALL_CI_DASHBOARDS="jenkins-overview tekton-overview github-actions-ci argo-workflows-ci"
# return 0 (skip) when the basename (sans -azure/-aws suffix) is a CI overview for an
# INACTIVE engine.
is_offengine_dashboard() {
  local base="${1%-azure}"; base="${base%-aws}" d
  for d in ${ALL_CI_DASHBOARDS}; do
    [[ "${base}" == "${d}" && "${base}" != "${KEEP_CI_DASHBOARD}" ]] && return 0
  done
  return 1
}

# Echo the uid(s) a CI overview may be published under, for deletion. A dashboard is
# published under whatever uid its canonical JSON carries — NOT necessarily
# "jenkins2026-<basename>" (jenkins-overview was round-tripped through Grafana Cloud
# and now carries a generated uid), and the -azure/-aws variants preserve the
# canonical uid (generate.py), so the canonical file is authoritative for every
# backend. Also echo the legacy "jenkins2026-<basename>" uid when it differs: a
# persistent stack may still hold a copy published under it. $1=dashboard basename.
offengine_uids() {
  local d="$1" canon
  canon="$(jq -r '.uid // empty' "${DASHBOARDS_DIR}/${d}.json" 2>/dev/null || true)"
  [[ -n "${canon}" ]] && printf '%s\n' "${canon}"
  [[ "${canon}" != "jenkins2026-${d}" ]] && printf '%s\n' "jenkins2026-${d}"
  return 0
}

# Delete the INACTIVE engines' overview dashboards by UID via the legacy HTTP API
# (Bearer auth). Skipping the off-engine dashboard at publish time is not enough on
# a PERSISTENT stack (Grafana Cloud / Azure Managed Grafana): gcx push and
# POST /api/dashboards/db only upsert, so a stale off-engine overview survives an
# engine switch. Idempotent: no-op when absent. $1=base URL, $2=API key.
# (managed-aws does the equivalent with its short-lived SA token.)
delete_offengine_dashboard() {
  local base="${1%/}" key="$2" d off_uid
  for d in ${ALL_CI_DASHBOARDS}; do
    [[ "${d}" == "${KEEP_CI_DASHBOARD}" ]] && continue
    for off_uid in $(offengine_uids "${d}"); do
      if curl -fsS "${base}/api/dashboards/uid/${off_uid}" -H "Authorization: Bearer ${key}" >/dev/null 2>&1; then
        if curl -fsS -X DELETE "${base}/api/dashboards/uid/${off_uid}" -H "Authorization: Bearer ${key}" >/dev/null 2>&1; then
          log_info "Deleted off-engine dashboard ${d} (uid ${off_uid}, ci.engine=${ACTIVE_CI_ENGINE})."
        else
          log_warn "Could not delete off-engine dashboard ${d} (uid ${off_uid})."
        fi
      fi
    done
  done
}

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

    # This branch talks to Grafana Cloud purely over the Grafana HTTP API with the
    # static GRAFANA_API_KEY - no gcx CLI dependency. (gcx's k8s-style resource layer
    # proved unreliable here; see the publish loop below.)
    FOLDER_UID="jenkins-2026"
    api() { curl -fsS -X "$1" "${GRAFANA_BASE_URL%/}$2" \
      -H "Authorization: Bearer ${GRAFANA_API_KEY}" -H "Content-Type: application/json" "${@:3}"; }

    # Ensure the shared "CI-CD Observability" folder (uid jenkins-2026), and keep its
    # title even if a persistent stack still had the old "jenkins-2026" title. Idempotent.
    api POST /api/folders -d "{\"uid\":\"${FOLDER_UID}\",\"title\":\"CI-CD Observability\"}" >/dev/null 2>&1 || true
    api PUT "/api/folders/${FOLDER_UID}" -d '{"title":"CI-CD Observability","overwrite":true}' >/dev/null 2>&1 || true

    log_step "Publishing dashboards via the Grafana HTTP API (POST /api/dashboards/db)"
    # Use the legacy import endpoint (idempotent upsert by uid, overwrite:true) rather
    # than `gcx resources push`. gcx pushes through Grafana's newer k8s-style resource
    # layer, whose async create/delete + optimistic concurrency intermittently fail on
    # Grafana Cloud with "409 AlreadyExists" / "409 object has been modified", and can
    # desync the legacy vs k8s storage. /api/dashboards/db is a reliable, idempotent
    # upsert - the same path the managed-aws branch uses. Datasource uids are rewritten
    # to the Grafana Cloud built-ins; id is nulled so the import keys purely on uid.
    for dashboard in "${DASHBOARDS_DIR}"/*.json; do
      name="$(basename "${dashboard}" .json)"
      if is_offengine_dashboard "${name}"; then log_info "Skipping ${name} (ci.engine=${ACTIVE_CI_ENGINE})"; continue; fi
      payload="$(jq --arg folderUID "${FOLDER_UID}" '
        (walk(if type=="object" and .uid=="loki"  then .uid="grafanacloud-logs"
              elif type=="object" and .uid=="tempo" then .uid="grafanacloud-traces"
              else . end) | .id=null)
        | {dashboard:., folderUid:$folderUID, overwrite:true}' "${dashboard}")"
      # Stream via stdin (--data-binary @-): large dashboards can exceed ARG_MAX.
      if printf '%s' "${payload}" | api POST /api/dashboards/db --data-binary @- >/dev/null 2>&1; then
        log_info "Published ${name}."
      else
        log_warn "Failed to publish ${name}."
      fi
    done

    log_step "Configuring Grafana Kubernetes Monitoring app data sources"
    GRAFANA_STACK_ID="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_STACK_ID}' | base64 -d)"
    if [[ -n "${GRAFANA_STACK_ID}" ]]; then
      api POST /api/plugins/grafana-k8s-app/settings -d "{
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
    delete_offengine_dashboard "${GRAFANA_BASE_URL}" "${GRAFANA_API_KEY}"
    ;;

  oss)
    log_info "observability.mode=oss: dashboards already provisioned via ConfigMap + Grafana sidecar."
    ;;

  managed-azure)
    # No-op here: Azure Managed Grafana has NO static API key (it authenticates
    # via Entra ID), so the azure-monitor-credentials Secret carries no
    # GRAFANA_API_KEY for this script to use. Publishing instead runs in the
    # dedicated "Publish dashboards to Azure Managed Grafana" step of
    # Day1.cluster.01-gke.yml, which (post azure/login) mints an Entra
    # data-plane token (AMG audience 6f2d169c-08f3-4a4c-a982-bcaf2d038c45),
    # substitutes the ${appinsights} placeholder via `az graph query`, and
    # imports the dashboards-azure/*-azure.json variants into the "CI-CD
    # Observability" folder via the Grafana data-plane API. up.sh's runner
    # is not yet logged into Azure when it reaches this step, mirroring how
    # 07.5-grafana-alerts.sh is re-run post-login for the same reason.
    log_info "observability.mode=managed-azure: dashboards published post-azure/login by Day1.cluster.01-gke.yml (AMG has no static API key)."
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
    # (Day2.publish.04-aws-grafana.yml). Skip gracefully when unauthenticated
    # rather than failing up.sh.
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      log_warn "No AWS credentials available - skipping managed-aws dashboard import (published by the 02.04 dashboards workflow)."
      exit 0
    fi

    # Source the AMG connection params. Two callers:
    #   up.sh (in-cluster) - read them from the in-cluster J2026_AWS_MANAGED_SECRET
    #     Secret that 02.01 built from the persistent terraform state.
    #   Day2.publish.04-aws-grafana.yml (no cluster) - it exports them straight
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
      local type="$1" name="$2" url="$3" jsondata="$4" uid existing
      existing="$(jq -c --arg t "${type}" 'map(select(.type==$t)) | .[0] // empty' <<<"${DS_JSON}")"
      uid="$(jq -r '.uid // empty' <<<"${existing}")"
      if [[ -z "${uid}" ]]; then
        local body
        body="$(jq -n --arg n "${name}" --arg t "${type}" --arg u "${url}" --argjson j "${jsondata}" \
          '{name:$n,type:$t,access:"proxy",isDefault:false,jsonData:$j} + (if $u=="" then {} else {url:$u} end)')"
        uid="$(api POST "/api/datasources" -d "${body}" 2>/dev/null | jq -r '.datasource.uid // empty' || true)"
      else
        # AMG auto-provisions datasource ENTRIES with minimal jsonData - notably the
        # Prometheus one ships without timeInterval, so Grafana assumes a 15s scrape
        # and $__rate_interval collapses to ~60s. The microservices' OTel metrics are
        # pushed every 60s, so rate() over that window sees a single sample and every
        # rate-based panel renders empty. Merge our desired jsonData into the existing
        # entry (PUT is idempotent) so the scrape hint sticks across re-provisions.
        printf '%s' "$(jq --argjson j "${jsondata}" '.jsonData = ((.jsonData // {}) + $j)' <<<"${existing}")" \
          | api PUT "/api/datasources/uid/${uid}" --data-binary @- >/dev/null 2>&1 || true
      fi
      printf '%s' "${uid}"
    }

    PROM_UID="$(ensure_ds "prometheus" "amazon-managed-prometheus" "${AMP_QUERY_URL}" \
      "$(jq -nc --arg r "${AWS_REGION}" '{httpMethod:"POST",sigV4Auth:true,sigV4AuthType:"default",sigV4Region:$r,timeInterval:"60s"}')")"
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
    # Shared "CI-CD Observability" folder (uid jenkins-2026) so dashboards land in
    # the same single folder as the alert rules (07.5), not the root — consistent
    # with grafana-cloud/oss. Idempotent.
    api POST /api/folders -d '{"uid":"jenkins-2026","title":"CI-CD Observability"}' >/dev/null 2>&1 || true
    api PUT /api/folders/jenkins-2026 -d '{"title":"CI-CD Observability","overwrite":true}' >/dev/null 2>&1 || true
    # Two sets, both bound to AMP via the same ${DS_PROMETHEUS} substitution:
    #   *-aws.json          - the custom project dashboards (generate.py)
    #   community/*.json     - vendored upstream Kubernetes/node dashboards
    #                          (community/vendor.py); these carry no CloudWatch/
    #                          X-Ray panels, so the DS_CW_UID/DS_XRAY_UID fixups
    #                          below are simply no-ops for them.
    for dashboard in "${AWS_DASHBOARDS_DIR}"/*-aws.json "${AWS_DASHBOARDS_DIR}"/community/*.json; do
      [[ -f "${dashboard}" ]] || continue
      name="$(basename "${dashboard}" .json)"
      if is_offengine_dashboard "${name}"; then log_info "Skipping ${name} (ci.engine=${ACTIVE_CI_ENGINE})"; continue; fi
      payload="$(jq --arg cw "${CW_UID}" --arg xray "${XRAY_UID}" --arg prom "${PROM_UID}" --arg promname "${PROM_NAME}" '
        def fixuid: walk(if type=="object" and .uid=="DS_CW_UID" then .uid=$cw
                         elif type=="object" and .uid=="DS_XRAY_UID" then .uid=$xray
                         else . end);
        (fixuid
         | .templating.list |= map(if .name=="DS_PROMETHEUS"
             then .current={selected:true,text:$promname,value:$prom}
             else . end)
         | .id=null)
        | {dashboard:., folderUid:"jenkins-2026", overwrite:true}' "${dashboard}")"
      # Stream the body via stdin (--data-binary @-) rather than passing it as a
      # curl argument: some vendored dashboards (e.g. node-exporter-full, ~500KB)
      # exceed ARG_MAX as a command-line arg and would silently fail to publish.
      if printf '%s' "${payload}" | api POST "/api/dashboards/db" --data-binary @- >/dev/null 2>&1; then
        log_info "Published ${name}."
      else
        log_warn "Failed to publish ${name}."
      fi
    done
    # Delete the INACTIVE engines' CI overviews so stale dashboards don't persist
    # across engine switches (all four CI engines are mutually exclusive). Mirrors the
    # delete_offengine_dashboard() helper, but via this branch's AMG `api` wrapper.
    # (The -aws variants preserve the canonical uid, so offengine_uids applies here.)
    for d in ${ALL_CI_DASHBOARDS}; do
      [[ "${d}" == "${KEEP_CI_DASHBOARD}" ]] && continue
      for delete_uid in $(offengine_uids "${d}"); do
        if api GET "/api/dashboards/uid/${delete_uid}" >/dev/null 2>&1; then
          if api DELETE "/api/dashboards/uid/${delete_uid}" >/dev/null 2>&1; then
            log_info "Deleted off-engine dashboard ${d} (uid ${delete_uid})."
          else
            log_warn "Could not delete off-engine dashboard ${d} (uid ${delete_uid})."
          fi
        fi
      done
    done
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}'."
    exit 1
    ;;
esac
