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
# j2026_active_ci_engine - echoes the ACTIVE CI engine ("jenkins", "tekton",
# "githubactions" or "argoworkflows"), resolved with this precedence:
#   1. An explicit JENKINS2026_CI_ENGINE override (Day1 matrix sets it on every
#      cluster-touching step, so this branch wins during provisioning and avoids
#      any "is the engine deployed yet?" race).
#   2. Detection from the live cluster: each engine's controller workload exists
#      only when that engine is deployed (retire_ci_engine removes the losing
#      engine's apps + namespaces on a switch) — the Jenkins StatefulSet, the
#      Tekton controller, the ARC controller (by label), or the Argo Workflows
#      controller. This is what makes a STANDALONE Day2.publish run correct
#      regardless of config.yaml's ci.engine default (which is just the repo
#      default and may not match what the cluster was deployed with).
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
  # ARC controller Deployment is release-name-prefixed (<release>-gha-rs-controller), so
  # match by the well-known label to stay release-agnostic.
  if [[ -n "$(kubectl get deployment -n "${J2026_GHA_NAMESPACE:-arc-systems}" \
       -l app.kubernetes.io/part-of=gha-rs-controller -o name 2>/dev/null)" ]]; then
    echo "githubactions"
    return
  fi
  if kubectl get deployment workflow-controller -n "${J2026_ARGOWF_NAMESPACE:-argo}" >/dev/null 2>&1; then
    echo "argoworkflows"
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

# --- backend TLS (LB→pod re-encryption) activation ----------------------------
#
# j2026_backend_tls_active - echoes "true" when the OPT-IN backend-TLS feature
# (gateway.backendTls.enabled / JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED,
# resolved into J2026_GATEWAY_BACKEND_TLS_ENABLED by lib/config.sh) is ON *and*
# the cluster actually serves the BackendTLSPolicy CRD (GKE Gateway backend TLS
# is GA 2026-05 on gke-l7-global-external-managed; older clusters lack the
# CRD). EVERY consumer - 08.5-argocd.sh's Headlamp TLS values overlay,
# 08.7-backend-tls.sh's cert-manager/CA/cert install, 09-gateway.sh's
# BackendTLSPolicy + HTTPS HealthCheckPolicy - gates on THIS, never on the raw
# flag: if only some of them acted on a CRD-less cluster, the pod would serve
# TLS the LB still speaks plain HTTP to (or vice versa) → instant 502 at that
# host. Gating all of them on the same probe degrades consistently to plain
# HTTP with a warning instead. The warning goes to stderr because callers
# invoke this in command substitution. See docs/504-BACKEND_TLS.md.
j2026_backend_tls_active() {
  if [[ "${J2026_GATEWAY_BACKEND_TLS_ENABLED:-false}" != "true" ]]; then
    echo "false"
    return
  fi
  if kubectl get crd backendtlspolicies.gateway.networking.k8s.io >/dev/null 2>&1; then
    echo "true"
  else
    log_warn "gateway.backendTls.enabled=true but this cluster does not serve the BackendTLSPolicy CRD (GKE Gateway backend TLS, GA 2026-05) - staying on plain HTTP." >&2
    echo "false"
  fi
}

# Backend TLS for argocd-server (the ArgoCD UI hop) is additionally gated on the
# CI engine. Flipping argocd-server to TLS breaks any deploy caller that still
# talks plain HTTP to it, so only engines whose caller speaks TLS qualify:
#   - jenkins:       vars/microservicesDeploy.groovy uses argocd-server:443 (TLS)
#                    when 04-jenkins.sh sets ARGOCD_SERVER to the :443 form.
#   - githubactions: its caller already uses `--server <host> --insecure` (TLS,
#                    no --plaintext), so it works against a TLS argocd-server.
# tekton + argoworkflows callers still use `:80 --plaintext` (their PaC-triggered
# runs render from static YAML that can't read this Day1 flag), so argocd stays
# plain HTTP for those engines - Headlamp + faro backend TLS still apply. Migrating
# those two callers is the documented next step (docs/504). Echoes true/false.
j2026_argocd_backend_tls_active() {
  [[ "$(j2026_backend_tls_active)" == "true" ]] || { echo "false"; return; }
  case "${J2026_CI_ENGINE}" in
    jenkins | githubactions) echo "true" ;;
    *) echo "false" ;;
  esac
}

# --- CI-engine retirement (mutual exclusivity) -------------------------------
# The four CI engines (jenkins · tekton · githubactions · argoworkflows) are
# mutually exclusive, so selecting one must FULLY retire the other three. Each
# alternative engine is an ArgoCD *app-of-apps*: a parent Application renders
# several CHILD Applications (with different names) into a few namespaces
# (control-plane + a CI-run ns). A naive "delete the parent app" is NOT enough:
#   - the parent's cascade-prune is unreliable — child apps can be left orphaned
#     (observed: argoworkflows-controller with no deletionTimestamp);
#   - a GKE **NEG finalizer** (networking.gke.io/neg-finalizer) on a UI Service's
#     ServiceNetworkEndpointGroup stalls namespace termination, which stalls the
#     parent app's cascade → deadlock (namespace stuck Terminating, apps OutOfSync).
# retire_ci_engine deletes EVERY app the engine owns, clears stuck NEG finalizers,
# then deletes EVERY namespace it owns (incl. the CI-run ns). Idempotent /
# best-effort. Keep these lists in sync with argocd/<engine>/templates/.
_j2026_engine_apps() {
  case "$1" in
    jenkins)       echo "jenkins" ;;
    tekton)        echo "tekton tekton-pipelines tekton-triggers tekton-dashboard tekton-chains tekton-pruner tekton-pac tekton-pipeline-as-code" ;;
    githubactions) echo "githubactions arc-controller arc-runner-scale-set" ;;
    argoworkflows) echo "argoworkflows argoworkflows-controller argoworkflows-pipeline-as-code argo-events" ;;
  esac
}
_j2026_engine_namespaces() {
  case "$1" in
    jenkins)       echo "${J2026_JENKINS_NAMESPACE:-jenkins}" ;;
    tekton)        echo "${J2026_TEKTON_NAMESPACE:-tekton-pipelines} ${J2026_TEKTON_PIPELINE_NAMESPACE:-tekton-ci} tekton-chains pipelines-as-code" ;;
    githubactions) echo "${J2026_GHA_NAMESPACE:-arc-systems} ${J2026_GHA_RUNNER_NAMESPACE:-arc-runners}" ;;
    argoworkflows) echo "${J2026_ARGOWF_NAMESPACE:-argo} ${J2026_ARGOWF_EVENTS_NAMESPACE:-argo-events} ${J2026_ARGOWF_RUN_NAMESPACE:-argo-ci}" ;;
  esac
}

# _j2026_strip_stuck_argocd_apps <argocd-ns> <app...> — after ArgoCD Applications are issued
# for deletion, poll (~90s) and strip resources-finalizer.argocd.argoproj.io on any still stuck
# Terminating (its cascade-prune stalled — the app-of-apps deadlock) so the CR actually clears.
# Best-effort/idempotent. The caller MUST prune the app's workloads by other means first
# (namespace deletion, or _j2026_force_prune_by_instance for shared-namespace workloads), else
# stripping the finalizer orphans them.
_j2026_strip_stuck_argocd_apps() {
  local acd="$1"; shift
  local app left i=0
  while [ "$i" -lt 18 ]; do
    left=""
    for app in "$@"; do kubectl get application "$app" -n "$acd" >/dev/null 2>&1 && left="${left} ${app}"; done
    [ -z "${left# }" ] && return 0
    i=$((i + 1)); sleep 5
  done
  for app in ${left}; do
    log_warn "  ArgoCD app '${app}' stuck Terminating (resources-finalizer cascade stalled) — stripping finalizer"
    kubectl patch application "$app" -n "$acd" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  done
}

# _j2026_force_prune_by_instance <ns> <helm-instance...> — force-delete every namespaced +
# cluster-scoped resource labelled app.kubernetes.io/instance=<helm-instance>. For workloads in a
# SHARED namespace (so the ns can't just be deleted) when ArgoCD cascade-prune stalled.
# ⚠️ Prunes ONLY by the INSTANCE label — NEVER app.kubernetes.io/name — because managed-azure/aws
# run their OWN standalone kube-state-metrics + prometheus-node-exporter that SHARE the chart NAME
# label (they carry instance=kube-state-metrics / =prometheus-node-exporter); the instance label is
# unique per Helm release, so this cannot touch the managed-mode exporters.
_j2026_force_prune_by_instance() {
  local ns="$1"; shift
  local inst lbl
  for inst in "$@"; do
    lbl="app.kubernetes.io/instance=${inst}"
    kubectl delete prometheus,alertmanager,servicemonitor,podmonitor,prometheusrule -n "$ns" -l "$lbl" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete all,cm,secret,sa,role,rolebinding,pvc -n "$ns" -l "$lbl" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete clusterrole,clusterrolebinding,mutatingwebhookconfiguration,validatingwebhookconfiguration -l "$lbl" --ignore-not-found >/dev/null 2>&1 || true
  done
}

# retire_ci_engine <engine> — fully remove a sibling CI engine. Idempotent.
retire_ci_engine() {
  local eng="$1" acd="${J2026_ARGOCD_NAMESPACE:-argocd}" app ns neg
  local apps namespaces present=0 a n
  apps="$(_j2026_engine_apps "$eng")"; namespaces="$(_j2026_engine_namespaces "$eng")"
  [[ -n "${apps}" ]] || { log_warn "retire_ci_engine: unknown engine '${eng}'"; return 0; }
  for a in ${apps};       do kubectl get application "$a" -n "$acd" >/dev/null 2>&1 && { present=1; break; }; done
  for n in ${namespaces}; do [[ $present -eq 1 ]] && break; kubectl get namespace "$n" >/dev/null 2>&1 && present=1; done
  [[ $present -eq 1 ]] || return 0
  log_step "Retiring CI engine '${eng}' (apps + namespaces + stuck NEG finalizers)"
  # 1. delete ALL its ArgoCD Applications (parent app-of-apps + every child)
  for app in ${apps}; do
    kubectl delete application "$app" -n "$acd" --ignore-not-found --wait=false 2>/dev/null || true
  done
  # 2. per namespace: clear stuck finalizers that would deadlock ns termination (GKE NEG,
  #    and Argo Events CRs), then delete the namespace so its routes / services / NEGs /
  #    quotas go with it.
  for ns in ${namespaces}; do
    kubectl get namespace "$ns" >/dev/null 2>&1 || continue
    for neg in $(kubectl get svcneg -n "$ns" -o name 2>/dev/null || true); do
      kubectl patch "$neg" -n "$ns" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null \
        && log_info "  cleared stuck NEG finalizer on ${ns}/${neg}" || true
    done
    # Argo Events (argoworkflows engine): strip finalizers on sensor/eventsource/eventbus CRs.
    # Their unified controller-manager is deleted alongside this namespace, so the finalizers
    # would deadlock ns termination — and the eventbus-controller finalizer even REFUSES to
    # complete while an EventSource is still connected ("can not delete an EventBus with N
    # EventSources connected"), a live-observed 30h stuck-Terminating on an engine switch.
    # No-op for engines whose CRDs aren't installed (the `get` errors → continue).
    for _res in sensor eventsource eventbus; do
      kubectl get "$_res" -n "$ns" >/dev/null 2>&1 || continue
      for _obj in $(kubectl get "$_res" -n "$ns" -o name 2>/dev/null || true); do
        kubectl patch "$_obj" -n "$ns" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null \
          && log_info "  cleared finalizer on ${ns}/${_obj}" || true
      done
    done
    kubectl delete namespace "$ns" --ignore-not-found --wait=false 2>/dev/null || true
  done
  # 3. Any Application still Terminating on the resources-finalizer (cascade-prune stalled) —
  #    strip it so the CR clears. The engine's workloads live in the namespaces deleted above,
  #    so no separate force-prune is needed here (unlike the shared-ns OSS stack).
  _j2026_strip_stuck_argocd_apps "$acd" ${apps}
}
