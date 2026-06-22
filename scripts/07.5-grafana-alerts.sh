#!/usr/bin/env bash
# Provisions Grafana alerting: contact point (email), notification policy, and
# alert rules from observability/grafana/alerting/.
#
#   grafana-cloud  - uses GRAFANA_BASE_URL + GRAFANA_API_KEY from the
#                    "${J2026_GRAFANA_CLOUD_SECRET}" Secret (same as 07-grafana-dashboards.sh).
#                    Admin email from GRAFANA_ALERT_EMAIL env var, falling back
#                    to the jenkins-credentials oidc-admin-email Secret key.
#
#   oss            - reads admin password from kube-prometheus-stack-grafana Secret,
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
  if [[ -n "${EXISTING_CP}" ]]; then
    gcapi PUT /api/v1/provisioning/contact-points/jenkins2026-email-cp \
      -d @/tmp/j2026-cp.json > /dev/null
    log_info "Updated contact point jenkins2026-email-cp."
  else
    gcapi POST /api/v1/provisioning/contact-points \
      -d @/tmp/j2026-cp.json > /dev/null
    log_info "Created contact point jenkins2026-email-cp."
  fi

  # --- notification policy ---------------------------------------------------
  log_step "Applying notification policy (route all → email)"
  gcapi PUT /api/v1/provisioning/policies \
    -d @"${ALERTS_DIR}/notification-policy.json" > /dev/null
  log_info "Notification policy applied."

  # --- alert rules -----------------------------------------------------------
  log_step "Upserting alert rules"
  for rule_file in "${ALERTS_DIR}/rules"/*.json; do
    RULE_UID="$(python3 -c "import json; print(json.load(open('${rule_file}'))['uid'])")"
    RULE_TITLE="$(python3 -c "import json; print(json.load(open('${rule_file}'))['title'])")"
    HTTP_CODE="$(gcapi_code GET "/api/v1/provisioning/alert-rules/${RULE_UID}")"
    if [[ "${HTTP_CODE}" == "200" ]]; then
      gcapi PUT "/api/v1/provisioning/alert-rules/${RULE_UID}" \
        -d @"${rule_file}" > /dev/null
      log_info "Updated alert rule: ${RULE_TITLE}"
    else
      gcapi POST /api/v1/provisioning/alert-rules \
        -d @"${rule_file}" > /dev/null
      log_info "Created alert rule: ${RULE_TITLE}"
    fi
  done
}

# ---------------------------------------------------------------------------
# resolve_email  — reads GRAFANA_ALERT_EMAIL env var or falls back to
# jenkins-credentials oidc-admin-email Secret. Prints the email to stdout.
# ---------------------------------------------------------------------------
resolve_email() {
  local email="${GRAFANA_ALERT_EMAIL:-$(kubectl get secret jenkins-credentials \
    -n "${J2026_JENKINS_NAMESPACE}" \
    -o jsonpath='{.data.oidc-admin-email}' 2>/dev/null | base64 -d 2>/dev/null || true)}"
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
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
      exit 0
    fi
    log_info "Alert notifications will go to: ${GF_EMAIL}"
    provision_alerts "${GF_BASE_URL}" "${GF_API_KEY}" "${GF_EMAIL}"
    ;;

  oss)
    # Reads admin password from the kube-prometheus-stack-grafana Secret,
    # port-forwards the in-cluster Grafana Service, mints a short-lived API key,
    # then provisions the alerting resources.
    #
    # NOTE: Email delivery also requires SMTP to be configured in the Grafana
    # Helm chart (grafana.ini.smtp.*). The alert rules and contact point are
    # provisioned regardless — without SMTP the rules appear in Grafana but
    # emails won't be sent. Refer to helm/observability/values-oss.yaml for
    # the SMTP configuration hook (to be added in a follow-up).
    GF_ADMIN_PWD="$(kubectl get secret kube-prometheus-stack-grafana \
      -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)"
    if [[ -z "${GF_ADMIN_PWD:-}" ]]; then
      log_error "oss: admin-password not found in kube-prometheus-stack-grafana secret."
      exit 1
    fi

    log_step "Port-forwarding kube-prometheus-stack-grafana → localhost:13000"
    kubectl port-forward -n "${J2026_OBS_NAMESPACE}" \
      svc/kube-prometheus-stack-grafana 13000:80 &
    PF_PID=$!
    trap "kill ${PF_PID} 2>/dev/null || true" EXIT
    sleep 4

    GF_BASE_URL="http://localhost:13000"

    GF_API_KEY="$(curl -sf -u "admin:${GF_ADMIN_PWD}" \
      -X POST "${GF_BASE_URL}/api/auth/keys" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"alerts-prov-$(date +%s)\",\"role\":\"Admin\",\"secondsToLive\":300}" \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])" 2>/dev/null || true)"
    if [[ -z "${GF_API_KEY:-}" ]]; then
      log_error "oss: failed to mint Grafana API key from admin credentials."
      exit 1
    fi

    GF_EMAIL="$(resolve_email)"
    if [[ -z "${GF_EMAIL}" ]]; then
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
      exit 0
    fi
    log_info "Alert notifications will go to: ${GF_EMAIL}"
    provision_alerts "${GF_BASE_URL}" "${GF_API_KEY}" "${GF_EMAIL}"
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
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
      exit 0
    fi
    log_info "Alert notifications will go to: ${GF_EMAIL}"
    provision_alerts "${GF_BASE_URL}" "${GF_API_KEY}" "${GF_EMAIL}"
    ;;

  managed-aws)
    # Amazon Managed Grafana: mint a short-lived workspace service-account token
    # via the AWS CLI (requires AWS credentials, typically via GitHub OIDC).
    GF_BASE_URL="${GRAFANA_BASE_URL:-$(kubectl get secret aws-managed-credentials \
      -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.AWS_AMG_ENDPOINT}' 2>/dev/null | base64 -d || true)}"
    GRAFANA_WORKSPACE_ID="${GRAFANA_WORKSPACE_ID:-$(kubectl get secret aws-managed-credentials \
      -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.AWS_AMG_WORKSPACE_ID}' 2>/dev/null | base64 -d || true)}"

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
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
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
