#!/usr/bin/env bash
# Grafana Assistant (official grafana-assistant-app) - OPT-IN via
# observability.assistant.enabled / JENKINS2026_OBS_ASSISTANT_ENABLED, default
# false, oss mode ONLY, SaaS-HYBRID.
#
# The plugin itself is installed by the values-oss-assistant.yaml overlay (layered
# by the observability-oss app-of-apps when 03-observability.sh passes
# assistantEnabled=true). This script provides the script-managed COMPANION the
# overlay reads: the `grafana-assistant-credentials` Secret carrying the
# connection to YOUR Grafana Cloud stack, built from the GitHub secrets
#   GRAFANA_CLOUD_ASSISTANT_BACKEND_URL / _INSTANCE_ID / _TOKEN
# (passed as env by the Day1 up.sh step). The plugin's accessToken uses the
# documented "<instanceId>:<rawToken>" form, assembled here.
#
# grafana-cloud / managed-* -> NO-OP: the Assistant is offered only in oss (where
# the in-cluster Grafana needs a connection; the SaaS/managed Grafanas have their
# own). When INACTIVE: symmetric retire of the Secret. Non-fatal: an optional
# feature must never wedge a provision, and Grafana runs fine without it (the
# overlay's env refs are optional=true). Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

GRAFANA_DEPLOYMENT="oss-kube-prometheus-stack-grafana"
CRED_SECRET="grafana-assistant-credentials"
NS="${J2026_GRAFANA_OSS_NAMESPACE}"

retire_assistant() {
  if kubectl get namespace "${NS}" >/dev/null 2>&1; then
    kubectl delete secret "${CRED_SECRET}" -n "${NS}" --ignore-not-found
  fi
}

# --- non-oss modes: retire-and-exit -------------------------------------------
if [[ "${J2026_OBS_MODE}" != "oss" ]]; then
  retire_assistant
  if [[ "${J2026_OBS_ASSISTANT_ENABLED}" == "true" ]]; then
    log_warn "observability.assistant.enabled=true has NO effect in ${J2026_OBS_MODE}: the Grafana Assistant flag is oss-only (the managed/SaaS Grafanas ship their own). See docs/301 § Grafana Assistant."
  else
    log_info "Grafana Assistant: nothing to do in ${J2026_OBS_MODE} (oss-only flag)."
  fi
  exit 0
fi

# --- oss, flag off: retire ----------------------------------------------------
if [[ "${J2026_OBS_ASSISTANT_ENABLED}" != "true" ]]; then
  log_step "Grafana Assistant is off (observability.assistant.enabled=false) - retiring the connection Secret"
  retire_assistant
  log_info "Grafana Assistant is off - nothing more to do."
  exit 0
fi

# ==============================================================================
# ENABLE (oss): the grafana-assistant-credentials Secret (Grafana Cloud connection)
# ==============================================================================
log_step "Grafana Assistant connection (${J2026_OBS_ASSISTANT_PLUGIN_ID} @ ${J2026_OBS_ASSISTANT_PLUGIN_VERSION})"

BACKEND_URL="${GRAFANA_CLOUD_ASSISTANT_BACKEND_URL:-}"
INSTANCE_ID="${GRAFANA_CLOUD_ASSISTANT_INSTANCE_ID:-}"
RAW_TOKEN="${GRAFANA_CLOUD_ASSISTANT_TOKEN:-}"

# The plugin installs regardless (via the overlay); without the connection it just
# sits unconfigured. Warn (don't fail) if the credentials weren't supplied, so an
# operator who flipped the flag before creating the GitHub secrets sees a clear
# message rather than a broken chat.
if [[ -z "${INSTANCE_ID}" || -z "${RAW_TOKEN}" ]]; then
  log_warn "──────────────────────────────────────────────────────────────────────────"
  log_warn "Grafana Assistant: PLUGIN INSTALLED, CONNECTION PENDING (a manual step)."
  log_warn ""
  log_warn "This is EXPECTED and by design in oss mode: the repo does NOT automate the"
  log_warn "Grafana Cloud side. Your observability DATA stays in GKE (Prometheus/Loki/"
  log_warn "Tempo in-cluster) - zero Grafana Cloud data ingestion, zero data cost - and"
  log_warn "ONLY the Grafana Cloud AI *Assistant* is used, which is FREE on the Grafana"
  log_warn "Cloud free tier (3 AI users/mo, 40M tokens/user; token cap = hard limit, no"
  log_warn "charge). See docs/301 § Grafana Assistant."
  log_warn ""
  log_warn "TO FINISH THE CONNECTION - two ways:"
  log_warn "  (A) DURABLE (recommended): set the three GitHub secrets"
  log_warn "      GRAFANA_CLOUD_ASSISTANT_{BACKEND_URL,INSTANCE_ID,TOKEN} from a Grafana"
  log_warn "      Cloud stack (docs/103) and re-run Day1. Survives pod restarts."
  log_warn "  (B) QUICK: open /plugins/grafana-assistant-app and click 'Connect to"
  log_warn "      Grafana Cloud'. But Grafana persistence is OFF here, so this is LOST"
  log_warn "      on the next pod restart (ArgoCD sync / Day1 / eviction)."
  log_warn "──────────────────────────────────────────────────────────────────────────"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### ⚠️ Grafana Assistant — installed, connection PENDING (manual)"
      echo
      echo "The \`grafana-assistant-app\` plugin is installed, but its Grafana Cloud connection is **not configured** (the \`GRAFANA_CLOUD_ASSISTANT_*\` secrets were not set)."
      echo
      echo "**By design in \`oss\`:** your observability **data stays in GKE** (in-cluster, free — zero Grafana Cloud data ingestion) and only the Grafana Cloud AI **Assistant** is used — **free** on the [free tier](https://grafana.com/docs/grafana-cloud/machine-learning/assistant/pricing/) (3 AI users/mo, 40M tokens/user, no card; token cap, no charge)."
      echo
      echo "**To finish:**"
      echo "- **Durable (recommended):** set \`GRAFANA_CLOUD_ASSISTANT_{BACKEND_URL,INSTANCE_ID,TOKEN}\` from a Grafana Cloud stack (docs/103) and re-run Day1."
      echo "- **Quick:** click *Connect to Grafana Cloud* in the plugin UI — but it is lost on the next pod restart (Grafana persistence is off)."
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
  retire_assistant
  exit 0
fi

# accessToken carries the documented "<instanceId>:<rawToken>" value.
ACCESS_TOKEN="${INSTANCE_ID}:${RAW_TOKEN}"

BEFORE_HASH="$(kubectl get secret "${CRED_SECRET}" -n "${NS}" -o jsonpath='{.data}' 2>/dev/null | sha256sum | cut -d' ' -f1 || true)"
kubectl create secret generic "${CRED_SECRET}" -n "${NS}" \
  --from-literal=backendUrl="${BACKEND_URL}" \
  --from-literal=instanceId="${INSTANCE_ID}" \
  --from-literal=accessToken="${ACCESS_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
AFTER_HASH="$(kubectl get secret "${CRED_SECRET}" -n "${NS}" -o jsonpath='{.data}' 2>/dev/null | sha256sum | cut -d' ' -f1 || true)"

# The plugin reads these as GF_ASSISTANT_* env at Grafana startup, so restart when
# the connection changed (same pattern as the LLM app's provisioning restart).
if [[ "${BEFORE_HASH}" != "${AFTER_HASH}" ]] \
   && kubectl get deployment "${GRAFANA_DEPLOYMENT}" -n "${NS}" >/dev/null 2>&1; then
  log_info "Assistant connection changed - restarting Grafana to load it."
  kubectl rollout restart deployment "${GRAFANA_DEPLOYMENT}" -n "${NS}"
fi
log_info "Grafana Assistant wired: ${J2026_OBS_ASSISTANT_PLUGIN_ID} -> Grafana Cloud stack ${INSTANCE_ID} (SaaS-hybrid; prompts processed by Grafana Cloud). Verify the exact GF_ASSISTANT_* mapping on first enable - docs/301."
