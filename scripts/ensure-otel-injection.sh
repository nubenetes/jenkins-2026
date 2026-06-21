#!/usr/bin/env bash
# Idempotent guard against the OTel auto-instrumentation injection race.
#
# The operator's pod-mutation webhook (mpod.kb.io) has failurePolicy: Ignore by
# design, so a microservices pod admitted before the Instrumentation CR / the
# webhook was serving starts WITHOUT the Java agent and silently emits no
# metrics/traces - the Grafana dashboards then look empty. This script detects
# that and triggers a `kubectl rollout restart` so the operator re-injects the
# agent on the fresh pods.
#
# Safe to run any time: it's a no-op for Deployments that don't exist yet, have
# no ready replicas, or are already injected. Run as a final deploy step
# (scripts/up.sh calls it) and any time the dashboards look empty. See
# docs/observability.md "OTel injection race".
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

ns="${J2026_MICROSERVICES_NS_STABLE}"
restarted=()

log_step "Ensuring OTel Java agent is injected in '${ns}' Deployments"
for deploy in ${J2026_MICROSERVICES_SERVICES}; do
  if ! kubectl -n "${ns}" get deploy "${deploy}" >/dev/null 2>&1; then
    log_info "${deploy}: not deployed yet - skipping"
    continue
  fi
  if [[ "$(kubectl -n "${ns}" get deploy "${deploy}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)" -lt 1 ]]; then
    log_info "${deploy}: no available replicas yet - skipping"
    continue
  fi
  if otel_agent_injected "${ns}" "${deploy}"; then
    log_info "${deploy}: OTel agent injected"
  else
    log_warn "${deploy}: OTel agent NOT injected - rolling restart to trigger injection"
    kubectl -n "${ns}" rollout restart deploy "${deploy}"
    restarted+=("${deploy}")
  fi
done

rc=0
for deploy in "${restarted[@]:-}"; do
  [[ -z "${deploy}" ]] && continue
  kubectl -n "${ns}" rollout status deploy "${deploy}" --timeout=180s || log_warn "${deploy}: rollout status timed out"
  if otel_agent_injected "${ns}" "${deploy}"; then
    log_info "${deploy}: OTel agent injected after restart"
  else
    log_error "${deploy}: still NOT injected after restart - check the operator's mpod.kb.io webhook"
    rc=1
  fi
done

log_info "OTel injection guard done."
exit "${rc}"
