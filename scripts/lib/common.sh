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
else
  J2026_C_RESET=""; J2026_C_INFO=""; J2026_C_WARN=""; J2026_C_ERROR=""; J2026_C_STEP=""
fi

log_info()  { printf '%s[INFO ]%s %s\n'  "${J2026_C_INFO}"  "${J2026_C_RESET}" "$*"; }
log_warn()  { printf '%s[WARN ]%s %s\n'  "${J2026_C_WARN}"  "${J2026_C_RESET}" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n'  "${J2026_C_ERROR}" "${J2026_C_RESET}" "$*" >&2; }
log_step()  { printf '%s[STEP ]%s %s\n'  "${J2026_C_STEP}"  "${J2026_C_RESET}" "$*"; }

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
