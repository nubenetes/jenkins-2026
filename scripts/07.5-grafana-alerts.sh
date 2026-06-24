#!/usr/bin/env bash
# Provisions Grafana alerting: contact point (email), notification policy, and
# alert rules from observability/grafana/alerting/.
#
#   grafana-cloud  - uses GRAFANA_BASE_URL + GRAFANA_API_KEY from the
#                    "${J2026_GRAFANA_CLOUD_SECRET}" Secret (same as 07-grafana-dashboards.sh).
#                    Grafana Cloud requires the contact-point email to be an org
#                    member — use GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD for this.
#
# Alert email resolution (highest → lowest priority, all modes):
#   1. GRAFANA_ALERT_EMAIL_<MODE>  e.g. GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD
#   2. GRAFANA_ALERT_EMAIL         generic fallback
#   3. jenkins-credentials.oidc-admin-email  cluster default
#
#   oss            - reads admin password from oss-kube-prometheus-stack-grafana Secret,
#                    port-forwards the in-cluster Grafana Service, and mints a
#                    short-lived Admin API key. Rules/contact point appear in Grafana
#                    regardless; email delivery also requires SMTP in values-oss.yaml.
#
#   managed-azure  - obtains an Azure AD bearer token via the Azure CLI (requires
#                    prior 'az login' or GitHub OIDC → Azure credentials), then
#                    uses the Azure Managed Grafana REST API.
#
#   managed-aws    - mints a short-lived AMG workspace service-account token via
#                    the AWS CLI (requires AWS credentials / OIDC auth), then uses
#                    the Amazon Managed Grafana REST API.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

ALERTS_DIR="${J2026_ROOT_DIR}/observability/grafana/alerting"

# ---------------------------------------------------------------------------
# provision_alerts GRAFANA_BASE_URL GRAFANA_API_KEY ALERT_EMAIL
#
# Idempotent: upserts folder, contact point, notification policy, and all
# alert rules from ${ALERTS_DIR}/rules/*.json via the Grafana provisioning API.
# ---------------------------------------------------------------------------
provision_alerts() {
  local base_url="$1"
  local api_key="$2"
  local alert_email="$3"

  # gcapi METHOD PATH [extra curl args...]
  # On HTTP 4xx/5xx: prints the response body to stderr and returns 1.
  # On success: prints the response body to stdout (callers can pipe or ignore).
  gcapi() {
    local method="$1" path="$2"; shift 2
    local tmp_body http_code
    tmp_body="$(mktemp)"
    http_code="$(curl -sS -X "${method}" "${base_url%/}${path}" \
      -H "Authorization: Bearer ${api_key}" \
      -H "Content-Type: application/json" \
      -o "${tmp_body}" -w "%{http_code}" "$@")"
    if [[ "${http_code}" -ge 400 ]]; then
      log_error "Grafana API ${method} ${path} → HTTP ${http_code}"
      cat "${tmp_body}" >&2
      rm -f "${tmp_body}"
      return 1
    fi
    cat "${tmp_body}"
    rm -f "${tmp_body}"
  }

  # gcapi_code METHOD PATH [extra curl args...] — returns only the HTTP status code.
  gcapi_code() {
    local method="$1" path="$2"; shift 2
    curl -sS -X "${method}" "${base_url%/}${path}" \
      -H "Authorization: Bearer ${api_key}" \
      -H "Content-Type: application/json" \
      -o /dev/null -w "%{http_code}" "$@" 2>/dev/null || echo "000"
  }

  # --- folder ----------------------------------------------------------------
  log_step "Ensuring alert folder 'jenkins-2026 Alerts'"
  # 409 Conflict = already exists → OK; suppress output, keep going.
  gcapi POST /api/folders \
    -d '{"uid":"jenkins-2026-alerts","title":"jenkins-2026 Alerts"}' \
    > /dev/null 2>/dev/null || true

  # --- contact point ---------------------------------------------------------
  log_step "Upserting email contact point"
  sed "s/EMAIL_ADDRESS/${alert_email}/g" "${ALERTS_DIR}/contact-points.json" > /tmp/j2026-cp.json
  EXISTING_CP="$(gcapi GET /api/v1/provisioning/contact-points 2>/dev/null \
    | python3 -c "import json,sys; cps=json.load(sys.stdin); \
        print(next((c['uid'] for c in cps if c['uid']=='jenkins2026-email-cp'),''))" \
    2>/dev/null || true)"
  # Upsert the contact point QUIETLY (own curl, not gcapi): a 400 here is an
  # expected, non-fatal config issue on Grafana Cloud (the email must be an org
  # member), so we handle it with a clean message instead of gcapi's raw
  # 'Error: ... HTTP 400' that looks alarming in CI logs.
  _cp_ok=1
  if [[ -n "${EXISTING_CP}" ]]; then
    _cp_method=PUT; _cp_path="/api/v1/provisioning/contact-points/jenkins2026-email-cp"
  else
    _cp_method=POST; _cp_path="/api/v1/provisioning/contact-points"
  fi
  _cp_body="$(mktemp)"
  _cp_code="$(curl -sS -X "${_cp_method}" "${base_url%/}${_cp_path}" \
    -H "Authorization: Bearer ${api_key}" -H "Content-Type: application/json" \
    -d @/tmp/j2026-cp.json -o "${_cp_body}" -w "%{http_code}" 2>/dev/null || echo 000)"
  if [[ "${_cp_code}" -ge 200 && "${_cp_code}" -lt 300 ]]; then
    log_info "Contact point jenkins2026-email-cp upserted (HTTP ${_cp_code})."
  elif [[ "${_cp_code}" == "400" ]] && grep -q "not members of this organization" "${_cp_body}" 2>/dev/null; then
    _cp_ok=0
    log_warn "Alert email '${alert_email}' is not a member of the Grafana Cloud org —"
    log_warn "skipping the email contact point + notification policy (expected, non-fatal;"
    log_warn "alert rules are still provisioned). Fix: add '${alert_email}' to the org, or set"
    log_warn "GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD to an org-member address (see docs/103 §3)."
  else
    _cp_ok=0
    log_warn "Contact point upsert returned HTTP ${_cp_code} — skipping email contact point +"
    log_warn "notification policy (non-fatal; alert rules still provisioned). Response:"
    sed 's/^/    /' "${_cp_body}" >&2 2>/dev/null || true
  fi
  rm -f "${_cp_body}"

  # --- notification policy ---------------------------------------------------
  if [[ "${_cp_ok}" -eq 1 ]]; then
    log_step "Applying notification policy (route all → email)"
    gcapi PUT /api/v1/provisioning/policies \
      -d @"${ALERTS_DIR}/notification-policy.json" > /dev/null
    log_info "Notification policy applied."
  fi

  # --- resolve the target Grafana's Prometheus datasource UID ----------------
  # The rule JSONs ship with datasourceUid "grafanacloud-prom" (the grafana-cloud
  # default). In every other mode the Prometheus datasource has a different UID
  # (oss = "prometheus"; managed-azure/aws use AMG-assigned UIDs), so uploading
  # the rules verbatim would point them at a non-existent datasource and they'd
  # fail to evaluate ("datasource not found"). Discover the UID from the target
  # Grafana (prefer the default Prometheus datasource) and substitute it below.
  local prom_ds_uid
  prom_ds_uid="$(gcapi GET /api/datasources 2>/dev/null | python3 -c "
import json,sys
try:
    dss=json.load(sys.stdin)
except Exception:
    dss=[]
proms=[d for d in dss if d.get('type')=='prometheus']
default=[d for d in proms if d.get('isDefault')]
print((default or proms or [{}])[0].get('uid',''))
" 2>/dev/null || true)"
  if [[ -z "${prom_ds_uid}" ]]; then
    log_warn "Could not resolve a Prometheus datasource UID from Grafana — uploading alert rules unchanged (they may not evaluate if the datasource UID differs)."
    prom_ds_uid="grafanacloud-prom"
  else
    log_info "Alert rules will target Prometheus datasource UID '${prom_ds_uid}'."
  fi

  # --- alert rules -----------------------------------------------------------
  log_step "Upserting alert rules"
  for rule_file in "${ALERTS_DIR}/rules"/*.json; do
    RULE_UID="$(python3 -c "import json; print(json.load(open('${rule_file}'))['uid'])")"
    RULE_TITLE="$(python3 -c "import json; print(json.load(open('${rule_file}'))['title'])")"
    # Rewrite the shipped grafanacloud-prom datasourceUid to the target's UID.
    RULE_TMP="$(mktemp)"
    sed "s/\"datasourceUid\": *\"grafanacloud-prom\"/\"datasourceUid\": \"${prom_ds_uid}\"/g" \
      "${rule_file}" > "${RULE_TMP}"
    HTTP_CODE="$(gcapi_code GET "/api/v1/provisioning/alert-rules/${RULE_UID}")"
    if [[ "${HTTP_CODE}" == "200" ]]; then
      gcapi PUT "/api/v1/provisioning/alert-rules/${RULE_UID}" \
        -d @"${RULE_TMP}" > /dev/null
      log_info "Updated alert rule: ${RULE_TITLE}"
    else
      gcapi POST /api/v1/provisioning/alert-rules \
        -d @"${RULE_TMP}" > /dev/null
      log_info "Created alert rule: ${RULE_TITLE}"
    fi
    rm -f "${RULE_TMP}"
  done
}

# ---------------------------------------------------------------------------
# resolve_email  — precedence (highest → lowest):
#   1. GRAFANA_ALERT_EMAIL_<MODE>  e.g. GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD
#   2. GRAFANA_ALERT_EMAIL         generic override
#   3. jenkins-credentials.oidc-admin-email  cluster default
# ---------------------------------------------------------------------------
resolve_email() {
  local mode_var="GRAFANA_ALERT_EMAIL_$(echo "${J2026_OBS_MODE}" | tr '[:lower:]-' '[:upper:]_')"
  local email="${!mode_var:-${GRAFANA_ALERT_EMAIL:-$(kubectl get secret jenkins-credentials \
    -n "${J2026_JENKINS_NAMESPACE}" \
    -o jsonpath='{.data.oidc-admin-email}' 2>/dev/null | base64 -d 2>/dev/null || true)}}"
  echo "${email}"
}

case "${J2026_OBS_MODE}" in
  grafana-cloud)
    if ! kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_error "Secret '${J2026_GRAFANA_CLOUD_SECRET}' not found in namespace '${J2026_OBS_NAMESPACE}'."
      exit 1
    fi

    GF_BASE_URL="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.GRAFANA_BASE_URL}' | base64 -d)"
    GF_API_KEY="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.GRAFANA_API_KEY}' | base64 -d)"

    if [[ -z "${GF_BASE_URL}" || -z "${GF_API_KEY}" ]]; then
      log_warn "GRAFANA_BASE_URL / GRAFANA_API_KEY not set in '${J2026_GRAFANA_CLOUD_SECRET}' - skipping alert provisioning."
      exit 0
    fi

    GF_EMAIL="$(resolve_email)"
    if [[ -z "${GF_EMAIL}" ]]; then
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL_$(echo "${J2026_OBS_MODE}" | tr '[:lower:]-' '[:upper:]_'), GRAFANA_ALERT_EMAIL, or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
      exit 0
    fi
    log_info "Alert notifications will go to: ${GF_EMAIL}"
    provision_alerts "${GF_BASE_URL}" "${GF_API_KEY}" "${GF_EMAIL}"
    ;;

  oss)
    # In-cluster Grafana runs with an ephemeral DB (persistence.enabled: false in
    # observability/grafana/values-oss.yaml — a bound PVC's volumeName is
    # immutable and breaks apply/Replace). API-provisioned alerting would be lost
    # on every Grafana pod restart (ArgoCD Replace sync, node eviction, ...), so
    # provision DECLARATIVELY: write a Grafana file-provisioning document into a
    # ConfigMap labelled grafana_alert=1, which the kube-prometheus-stack alerts
    # sidecar (grafana.sidecar.alerts) mounts into provisioning/alerting/ on every
    # boot. No port-forward / API token needed (unlike cloud/azure/aws).
    #
    # NOTE: email delivery still requires SMTP in grafana.ini.smtp.* (follow-up).
    GF_EMAIL="$(resolve_email)"
    if [[ -z "${GF_EMAIL}" ]]; then
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL_$(echo "${J2026_OBS_MODE}" | tr '[:lower:]-' '[:upper:]_'), GRAFANA_ALERT_EMAIL, or populate jenkins-credentials oidc-admin-email) — provisioning rules + policy without a contact point."
    else
      log_info "Alert notifications will go to: ${GF_EMAIL}"
    fi

    # Build the file-provisioning document (JSON is a valid YAML subset, which
    # Grafana's provisioning loader accepts). Rewrite the shipped grafanacloud-prom
    # datasourceUid to the OSS Prometheus datasource UID ("prometheus", set in
    # values-oss.yaml additionalDataSources). When no email is resolved, only the
    # rule groups are emitted (no contact point / policy).
    ALERTING_DOC="$(python3 - "${ALERTS_DIR}" "prometheus" "${GF_EMAIL}" <<'PY'
import json, sys, glob, os
alerts_dir, prom_uid, email = sys.argv[1], sys.argv[2], sys.argv[3]
rules = []
for f in sorted(glob.glob(os.path.join(alerts_dir, "rules", "*.json"))):
    r = json.load(open(f))
    for d in r.get("data", []):
        if d.get("datasourceUid") == "grafanacloud-prom":
            d["datasourceUid"] = prom_uid
    rules.append({
        "uid": r["uid"], "title": r["title"], "condition": r["condition"],
        "for": r.get("for", "0s"), "noDataState": r.get("noDataState", "NoData"),
        "execErrState": r.get("execErrState", "Error"),
        "labels": r.get("labels", {}), "annotations": r.get("annotations", {}),
        "data": r["data"],
    })
doc = {"apiVersion": 1, "groups": [{
    "orgId": 1, "name": "jenkins-2026", "folder": "jenkins-2026 Alerts",
    "interval": "1m", "rules": rules}]}
if email:
    doc["contactPoints"] = [{"orgId": 1, "name": "jenkins-2026-email", "receivers": [
        {"uid": "jenkins2026-email-cp", "type": "email",
         "settings": {"addresses": email}, "disableResolveMessage": False}]}]
    doc["policies"] = [{"orgId": 1, "receiver": "jenkins-2026-email",
                        "group_by": ["alertname", "namespace"], "group_wait": "30s",
                        "group_interval": "5m", "repeat_interval": "4h"}]
print(json.dumps(doc, indent=2))
PY
)"
    if [[ -z "${ALERTING_DOC}" ]]; then
      log_error "oss: failed to build the alerting provisioning document."
      exit 1
    fi

    log_step "Applying declarative alerting ConfigMap (grafana_alert sidecar)"
    kubectl create configmap jenkins-2026-grafana-alerting \
      -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
      --from-literal=jenkins-2026-alerting.yaml="${ALERTING_DOC}" \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl label configmap jenkins-2026-grafana-alerting \
      -n "${J2026_GRAFANA_OSS_NAMESPACE}" grafana_alert=1 --overwrite
    log_info "OSS alerting provisioned declaratively (survives Grafana restarts)."
    ;;

  managed-azure)
    # Azure Managed Grafana accepts Azure AD bearer tokens scoped to the AMG
    # resource (https://grafana.azure.com/). Requires prior 'az login' or an
    # active GitHub OIDC → Azure federated credential.
    GF_BASE_URL="${GRAFANA_BASE_URL:-$(kubectl get secret azure-monitor-credentials \
      -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.AZURE_GRAFANA_ENDPOINT}' 2>/dev/null | base64 -d || true)}"
    if [[ -z "${GF_BASE_URL:-}" ]]; then
      log_error "managed-azure: GRAFANA_BASE_URL not found (set env var or check azure-monitor-credentials secret)."
      exit 1
    fi

    GF_API_KEY="$(az account get-access-token \
      --resource "https://grafana.azure.com/" \
      --query "accessToken" -o tsv 2>/dev/null || true)"
    if [[ -z "${GF_API_KEY:-}" ]]; then
      log_error "managed-azure: failed to get Azure AD token (is 'az login' done / are Azure OIDC credentials valid?)"
      exit 1
    fi

    GF_EMAIL="$(resolve_email)"
    if [[ -z "${GF_EMAIL}" ]]; then
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL_$(echo "${J2026_OBS_MODE}" | tr '[:lower:]-' '[:upper:]_'), GRAFANA_ALERT_EMAIL, or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
      exit 0
    fi
    log_info "Alert notifications will go to: ${GF_EMAIL}"
    provision_alerts "${GF_BASE_URL}" "${GF_API_KEY}" "${GF_EMAIL}"
    ;;

  managed-aws)
    # Amazon Managed Grafana: mint a short-lived workspace service-account token
    # via the AWS CLI (requires AWS credentials, typically via GitHub OIDC).
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      log_warn "No AWS credentials available - skipping managed-aws alert provisioning."
      exit 0
    fi

    GF_BASE_URL="${GRAFANA_BASE_URL:-$(kubectl get secret aws-managed-credentials \
      -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.GRAFANA_BASE_URL}' 2>/dev/null | base64 -d || true)}"
    GRAFANA_WORKSPACE_ID="${GRAFANA_WORKSPACE_ID:-$(kubectl get secret aws-managed-credentials \
      -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.GRAFANA_WORKSPACE_ID}' 2>/dev/null | base64 -d || true)}"

    if [[ -z "${GF_BASE_URL:-}" || -z "${GRAFANA_WORKSPACE_ID:-}" ]]; then
      log_error "managed-aws: GRAFANA_BASE_URL / GRAFANA_WORKSPACE_ID not found (set env vars or check aws-managed-credentials secret)."
      exit 1
    fi

    GF_API_KEY="$(aws grafana create-workspace-api-key \
      --key-role ADMIN \
      --key-name "jenkins-2026-alerts-$(date +%s)" \
      --seconds-to-live 300 \
      --workspace-id "${GRAFANA_WORKSPACE_ID}" \
      --output json 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])" || true)"
    if [[ -z "${GF_API_KEY:-}" ]]; then
      log_error "managed-aws: failed to mint AMG service-account token (check AWS credentials and workspace ID)."
      exit 1
    fi

    GF_EMAIL="$(resolve_email)"
    if [[ -z "${GF_EMAIL}" ]]; then
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL_$(echo "${J2026_OBS_MODE}" | tr '[:lower:]-' '[:upper:]_'), GRAFANA_ALERT_EMAIL, or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
      exit 0
    fi
    log_info "Alert notifications will go to: ${GF_EMAIL}"
    provision_alerts "${GF_BASE_URL}" "${GF_API_KEY}" "${GF_EMAIL}"
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}'."
    exit 1
    ;;
esac
