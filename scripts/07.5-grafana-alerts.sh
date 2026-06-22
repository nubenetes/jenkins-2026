#!/usr/bin/env bash
# Provisions Grafana alerting: contact point (email), notification policy, and
# alert rules from observability/grafana/alerting/.
#
#   grafana-cloud  - uses GRAFANA_BASE_URL + GRAFANA_API_KEY from the
#                    "${J2026_GRAFANA_CLOUD_SECRET}" Secret (same as 07-grafana-dashboards.sh).
#                    Admin email from GRAFANA_ALERT_EMAIL env var, falling back
#                    to the jenkins-credentials oidc-admin-email Secret key.
#
#   oss            - TODO(obs-mode): OSS Grafana needs SMTP configured in the
#                    kube-prometheus-stack values (grafana.smtp.*) before email
#                    contact points work. Wire this after enabling an SMTP relay.
#
#   managed-azure  - TODO(obs-mode): Azure Managed Grafana supports email via
#                    Action Groups / Azure Monitor alert rules. Provision via
#                    Terraform in terraform/azure-managed-grafana/ or via the
#                    Azure Portal, then adapt this script to use the AMG REST API.
#
#   managed-aws    - TODO(obs-mode): Amazon Managed Grafana supports email via
#                    Amazon SNS. Provision an SNS topic + subscription in
#                    terraform/aws-managed-grafana/ and configure the AMG
#                    contact point to point at the SNS HTTP endpoint.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

ALERTS_DIR="${J2026_ROOT_DIR}/observability/grafana/alerting"

case "${J2026_OBS_MODE}" in
  grafana-cloud)
    if ! kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_error "Secret '${J2026_GRAFANA_CLOUD_SECRET}' not found in namespace '${J2026_OBS_NAMESPACE}'."
      exit 1
    fi

    GRAFANA_BASE_URL="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.GRAFANA_BASE_URL}' | base64 -d)"
    GRAFANA_API_KEY="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" \
      -o jsonpath='{.data.GRAFANA_API_KEY}' | base64 -d)"

    if [[ -z "${GRAFANA_BASE_URL}" || -z "${GRAFANA_API_KEY}" ]]; then
      log_warn "GRAFANA_BASE_URL / GRAFANA_API_KEY not set in '${J2026_GRAFANA_CLOUD_SECRET}' - skipping alert provisioning."
      exit 0
    fi

    # Resolve alert email: env var wins, then fall back to the oidc-admin-email
    # key in jenkins-credentials (same secret used for Jenkins OIDC SSO login).
    ALERT_EMAIL="${GRAFANA_ALERT_EMAIL:-$(kubectl get secret jenkins-credentials \
      -n "${J2026_JENKINS_NAMESPACE}" \
      -o jsonpath='{.data.oidc-admin-email}' 2>/dev/null | base64 -d 2>/dev/null || true)}"
    if [[ -z "${ALERT_EMAIL}" ]]; then
      log_warn "No alert email found (set GRAFANA_ALERT_EMAIL or populate jenkins-credentials oidc-admin-email) — skipping alert provisioning."
      exit 0
    fi
    log_info "Alert notifications will go to: ${ALERT_EMAIL}"

    gcapi() {
      local method="$1" path="$2"; shift 2
      curl -fsS -X "${method}" "${GRAFANA_BASE_URL%/}${path}" \
        -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
        -H "Content-Type: application/json" "$@"
    }

    # --- folder ----------------------------------------------------------------
    log_step "Ensuring alert folder 'jenkins-2026 Alerts'"
    gcapi POST /api/folders \
      -d '{"uid":"jenkins-2026-alerts","title":"jenkins-2026 Alerts"}' \
      -o /dev/null 2>/dev/null || true  # 412 Conflict = already exists, OK

    # --- contact point ---------------------------------------------------------
    log_step "Upserting email contact point"
    sed "s/EMAIL_ADDRESS/${ALERT_EMAIL}/g" "${ALERTS_DIR}/contact-points.json" > /tmp/j2026-cp.json
    EXISTING_CP="$(gcapi GET /api/v1/provisioning/contact-points 2>/dev/null \
      | python3 -c "import json,sys; cps=json.load(sys.stdin); \
          print(next((c['uid'] for c in cps if c['uid']=='jenkins2026-email-cp'),''))" \
      2>/dev/null || true)"
    if [[ -n "${EXISTING_CP}" ]]; then
      gcapi PUT /api/v1/provisioning/contact-points/jenkins2026-email-cp \
        -d @/tmp/j2026-cp.json -o /dev/null
      log_info "Updated contact point jenkins2026-email-cp."
    else
      gcapi POST /api/v1/provisioning/contact-points \
        -d @/tmp/j2026-cp.json -o /dev/null
      log_info "Created contact point jenkins2026-email-cp."
    fi

    # --- notification policy ---------------------------------------------------
    log_step "Applying notification policy (route all → email)"
    gcapi PUT /api/v1/provisioning/policies \
      -d @"${ALERTS_DIR}/notification-policy.json" -o /dev/null
    log_info "Notification policy applied."

    # --- alert rules -----------------------------------------------------------
    log_step "Upserting alert rules"
    for rule_file in "${ALERTS_DIR}/rules"/*.json; do
      RULE_UID="$(python3 -c "import json; print(json.load(open('${rule_file}'))['uid'])")"
      RULE_TITLE="$(python3 -c "import json; print(json.load(open('${rule_file}'))['title'])")"
      HTTP_CODE="$(gcapi GET "/api/v1/provisioning/alert-rules/${RULE_UID}" \
        -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")"
      if [[ "${HTTP_CODE}" == "200" ]]; then
        gcapi PUT "/api/v1/provisioning/alert-rules/${RULE_UID}" \
          -d @"${rule_file}" -o /dev/null
        log_info "Updated alert rule: ${RULE_TITLE}"
      else
        gcapi POST /api/v1/provisioning/alert-rules \
          -d @"${rule_file}" -o /dev/null
        log_info "Created alert rule: ${RULE_TITLE}"
      fi
    done
    ;;

  oss)
    # TODO(obs-mode): OSS Grafana email alerts require SMTP in the
    # kube-prometheus-stack values (grafana.smtp.*). Wire this after
    # configuring an SMTP relay in helm/observability/values-oss.yaml.
    log_warn "observability.mode=oss: Grafana email alerts not yet wired (SMTP relay needed). Skipping."
    ;;

  managed-azure)
    # TODO(obs-mode): Azure Managed Grafana supports email via Action Groups
    # / Azure Monitor alert rules. Provision via Terraform in
    # terraform/azure-managed-grafana/ then adapt this script to use the AMG
    # REST API for contact-point / rule provisioning.
    log_warn "observability.mode=managed-azure: Grafana email alerts not yet wired (Action Groups needed). Skipping."
    ;;

  managed-aws)
    # TODO(obs-mode): Amazon Managed Grafana supports email via Amazon SNS.
    # Provision an SNS topic + subscription in terraform/aws-managed-grafana/
    # and configure the AMG contact point to the SNS HTTP endpoint.
    log_warn "observability.mode=managed-aws: Grafana email alerts not yet wired (SNS topic needed). Skipping."
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}'."
    exit 1
    ;;
esac
