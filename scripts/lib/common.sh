#!/usr/bin/env bash
# Shared logging, prereq-checking and parallel-execution helpers, sourced by
# every script under scripts/. Not meant to be executed directly.

# Resolve the repo root regardless of where this file is sourced from.
J2026_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export J2026_ROOT_DIR

J2026_LOG_DIR="${J2026_ROOT_DIR}/logs"
mkdir -p "${J2026_LOG_DIR}"
export J2026_LOG_DIR

# --- logging --------------------------------------------------------------

if [[ -t 1 ]]; then
  J2026_C_RESET=$'\033[0m'
  J2026_C_INFO=$'\033[36m'
  J2026_C_WARN=$'\033[33m'
  J2026_C_ERROR=$'\033[31m'
  J2026_C_STEP=$'\033[1;35m'
  J2026_C_DEBUG=$'\033[2m'
else
  J2026_C_RESET=""; J2026_C_INFO=""; J2026_C_WARN=""; J2026_C_ERROR=""; J2026_C_STEP=""; J2026_C_DEBUG=""
fi

# Verbosity: info (default) | debug. Set via JENKINS2026_LOG_LEVEL (the GHA workflows'
# log_level dropdown input) or config.yaml logging.level (re-read in config.sh). Only
# 'debug' adds output. There is DELIBERATELY no 'trace'/`set -x` level: bash xtrace
# prints command arguments, which would leak the secret VALUES the provisioning scripts
# pass to `kubectl create secret`/`kubectl patch` (generated admin password, dockerconfig,
# the ArgoCD-minted token, …) into the run log — GitHub only masks registered secrets,
# not script-derived ones. Use the native ACTIONS_STEP_DEBUG for runner-level tracing.
: "${J2026_LOG_LEVEL:=${JENKINS2026_LOG_LEVEL:-info}}"
export J2026_LOG_LEVEL

log_info()  { printf '%s[INFO ]%s %s\n'  "${J2026_C_INFO}"  "${J2026_C_RESET}" "$*"; }
log_warn()  { printf '%s[WARN ]%s %s\n'  "${J2026_C_WARN}"  "${J2026_C_RESET}" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n'  "${J2026_C_ERROR}" "${J2026_C_RESET}" "$*" >&2; }
log_step()  { printf '%s[STEP ]%s %s\n'  "${J2026_C_STEP}"  "${J2026_C_RESET}" "$*"; }
# Only emits when J2026_LOG_LEVEL=debug. Goes to stderr so it never pollutes a
# function's stdout "return value" (e.g. helpers that echo a value to be captured).
log_debug() { [[ "${J2026_LOG_LEVEL}" == "debug" ]] && printf '%s[DEBUG]%s %s\n' "${J2026_C_DEBUG}" "${J2026_C_RESET}" "$*" >&2 || true; }

# --- prereqs ----------------------------------------------------------------

# require_cmd <binary> [hint]
require_cmd() {
  local bin="$1" hint="${2:-}"
  if ! command -v "${bin}" >/dev/null 2>&1; then
    log_error "Required command '${bin}' not found in PATH."
    [[ -n "${hint}" ]] && log_error "  -> ${hint}"
    return 1
  fi
}

# --- kubectl/apply helpers ---------------------------------------------------

# kubectl_apply_namespace <name> - idempotent namespace creation.
kubectl_apply_namespace() {
  local ns="$1"
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
}

# helm_uninstall_if_present <release> <namespace> - uninstall a Helm release
# only if it exists. Used by 03-observability.sh to make in-place switches
# between observability.mode=grafana-cloud and =oss clean (retire the releases
# that belong to the mode we're switching away from). Safe to call when the
# release isn't installed.
helm_uninstall_if_present() {
  local release="$1" ns="$2"
  if helm status "${release}" -n "${ns}" >/dev/null 2>&1; then
    log_info "Uninstalling stale release '${release}' from '${ns}' (mode switch)."
    helm uninstall "${release}" -n "${ns}"
  fi
}

# --- parallel step execution -------------------------------------------------
#
# run_bg <name> <cmd...> - runs <cmd...> in the background, streaming stdout
# and stderr to logs/<name>.log, and remembers its PID under <name> for
# wait_bg. Use from orchestrators (up.sh/down.sh) to fan out independent
# steps; use plain `"${J2026_ROOT_DIR}/scripts/0X-....sh"` directly for
# sequential steps.
declare -gA J2026_BG_PIDS=()
declare -gA J2026_BG_LOGS=()

run_bg() {
  local name="$1"; shift
  local log_file="${J2026_LOG_DIR}/${name}.log"
  log_info "-> ${name} (parallel, log: ${log_file#${J2026_ROOT_DIR}/})"
  ( "$@" ) >"${log_file}" 2>&1 &
  J2026_BG_PIDS["${name}"]=$!
  J2026_BG_LOGS["${name}"]="${log_file}"
}

# wait_for_resource <type> <name> <namespace> [timeout]
# Uses kubectl rollout status with a total timeout (security mechanism)
# while showing progress updates. On first timeout, dumps pod diagnostics
# and attempts a rollout restart (self-heal) before giving up.
wait_for_resource() {
  local type="$1" name="$2" ns="$3" timeout="${4:-15m}"
  log_step "Monitoring ${type}/${name} in ${ns} (timeout: ${timeout})..."

  # Wait for the resource to at least exist before monitoring rollout.
  local count=0
  while ! kubectl get "${type}/${name}" -n "${ns}" >/dev/null 2>&1; do
    if [[ $count -ge 60 ]]; then
      log_error "Timeout: ${type}/${name} was never created."
      return 1
    fi
    log_info "  ... waiting for ${type}/${name} to appear..."
    sleep 5
    ((count++))
  done

  if kubectl rollout status "${type}/${name}" -n "${ns}" --timeout="${timeout}"; then
    log_info "OK: ${type}/${name} is ready."
    return 0
  fi

  # First rollout attempt timed out - dump diagnostics then self-heal.
  log_error "Rollout timed out for ${type}/${name} - collecting diagnostics..."
  log_info "--- pod list ---"
  kubectl get pods -n "${ns}" -o wide 2>/dev/null | grep -F "${name}" || true
  log_info "--- pod events (last 20) ---"
  kubectl get events -n "${ns}" --sort-by='.lastTimestamp' 2>/dev/null \
    | grep -F "${name}" | tail -20 || true
  log_info "--- pod logs (tail 40, incl. previous containers) ---"
  local pod
  while IFS= read -r pod; do
    [[ -z "${pod}" ]] && continue
    log_info "  >> ${pod}"
    kubectl logs --previous "${pod}" -n "${ns}" --tail=40 2>/dev/null \
      || kubectl logs "${pod}" -n "${ns}" --tail=40 2>/dev/null \
      || true
  done < <(kubectl get pods -n "${ns}" --no-headers \
    -o custom-columns=':metadata.name' 2>/dev/null | grep -F "${name}")

  log_step "Self-heal: rolling restart of ${type}/${name}..."
  kubectl rollout restart "${type}/${name}" -n "${ns}"
  if kubectl rollout status "${type}/${name}" -n "${ns}" --timeout="${timeout}"; then
    log_info "OK: ${type}/${name} is ready (after self-heal restart)."
    return 0
  fi

  log_error "Rollout failed for ${type}/${name} after self-heal attempt."
  return 1
}

# wait_for_deployment <name> <namespace> [timeout]
wait_for_deployment() {
  wait_for_resource "deployment" "$1" "$2" "${3:-5m}"
}

# wait_bg - waits for every PID registered via run_bg, prints a per-step
# pass/fail summary, and returns non-zero if any step failed.
wait_bg() {
  local failed=0
  local name pid
  for name in "${!J2026_BG_PIDS[@]}"; do
    pid="${J2026_BG_PIDS[${name}]}"
    if wait "${pid}"; then
      log_info "OK   ${name}"
    else
      log_error "FAIL ${name} - see ${J2026_BG_LOGS[${name}]#${J2026_ROOT_DIR}/}"
      failed=1
    fi
  done
  J2026_BG_PIDS=()
  J2026_BG_LOGS=()
  return "${failed}"
}

# --- OTel auto-instrumentation injection ------------------------------------
#
# otel_agent_injected <namespace> <deployment> - returns 0 if the deployment's
# running pods have the OTel Java agent injected by the operator's mutating
# webhook (JAVA_TOOL_OPTIONS carries -javaagent), else 1. Detects the "pod
# admitted before the Instrumentation CR / webhook was ready" race, where the
# app starts uninstrumented and emits no metrics/traces. See
# scripts/ensure-otel-injection.sh and docs/observability.md.
otel_agent_injected() {
  local ns="$1" deploy="$2" pod jto found=1
  for pod in $(kubectl -n "${ns}" get pods -o name 2>/dev/null | grep "^pod/${deploy}-" || true); do
    jto="$(kubectl -n "${ns}" get "${pod}" -o jsonpath='{range .spec.containers[*]}{.env[?(@.name=="JAVA_TOOL_OPTIONS")].value}{"\n"}{end}' 2>/dev/null)"
    if grep -q -- '-javaagent' <<<"${jto}"; then found=0; fi
  done
  return "${found}"
}

# --- active CI engine resolution --------------------------------------------
#
# j2026_active_ci_engine - echoes the ACTIVE CI engine ("jenkins" or "tekton"),
# resolved with this precedence:
#   1. An explicit JENKINS2026_CI_ENGINE override (Day1 matrix sets it on every
#      cluster-touching step, so this branch wins during provisioning and avoids
#      any "is the engine deployed yet?" race).
#   2. Detection from the live cluster: the Jenkins StatefulSet exists only in
#      jenkins mode (04-tekton.sh retires it), and the Tekton controller exists
#      only in tekton mode. This is what makes a STANDALONE Day2.publish run
#      correct regardless of config.yaml's ci.engine default (which is just the
#      repo default and may not match what the cluster was deployed with).
#   3. The config.yaml value (J2026_CI_ENGINE) when no cluster is reachable.
j2026_active_ci_engine() {
  if [[ -n "${JENKINS2026_CI_ENGINE:-}" ]]; then
    echo "${JENKINS2026_CI_ENGINE}"
    return
  fi
  if kubectl get statefulset "${J2026_JENKINS_RELEASE}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    echo "jenkins"
    return
  fi
  if kubectl get deployment tekton-pipelines-controller -n "${J2026_TEKTON_NAMESPACE}" >/dev/null 2>&1; then
    echo "tekton"
    return
  fi
  echo "${J2026_CI_ENGINE}"
}

# --- active secrets backend resolution --------------------------------------
#
# j2026_active_secrets_backend - echoes the ACTIVE secrets backend ("imperative"
# or "eso"), resolved with the SAME precedence as j2026_active_ci_engine:
#   1. An explicit JENKINS2026_SECRETS_BACKEND override (Day1 + the Day2 redeploys
#      that re-run 01-namespaces set it, so it wins during provisioning).
#   2. Detection from the live cluster: the ClusterSecretStore 'gcp-store' is
#      created ONLY in eso mode (scripts/08.6-eso-sync.sh), so its presence means
#      the cluster was provisioned with secrets.backend=eso. This makes a
#      STANDALONE Day2 redeploy (or Decom/down.sh) do the right thing even when
#      the operator forgets to pass secrets_backend (whose default is imperative,
#      which would otherwise diverge from an eso cluster). NOTE: the ESO operator
#      itself is installed in BOTH modes (08.5-argocd.sh), so we key off the
#      gcp-store CR specifically, not the operator's presence.
#   3. The config.yaml value (J2026_SECRETS_BACKEND) when no cluster is reachable.
j2026_active_secrets_backend() {
  if [[ -n "${JENKINS2026_SECRETS_BACKEND:-}" ]]; then
    echo "${JENKINS2026_SECRETS_BACKEND}"
    return
  fi
  if kubectl get clustersecretstore gcp-store >/dev/null 2>&1; then
    echo "eso"
    return
  fi
  echo "${J2026_SECRETS_BACKEND:-imperative}"
}
