#!/usr/bin/env bash
# =============================================================================
# Post-deploy smoke tests for scripts/up.sh. Runs standalone against any
# cluster up.sh has been run on, or as the last step of test/e2e.sh. Exits
# non-zero if any check fails (after running all of them).
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "${ROOT_DIR}/scripts/lib/config.sh"

FAIL=0

# check <description> <command...> - runs <command...>, logs PASS/FAIL.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    log_info "PASS - ${desc}"
  else
    log_error "FAIL - ${desc}"
    FAIL=1
  fi
}

NUM_SERVICES=$(wc -w <<< "${J2026_MICROSERVICES_SERVICES}")

if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  TEKTON_NS="${J2026_TEKTON_NAMESPACE}"
  PIPELINE_NS="${J2026_TEKTON_PIPELINE_NAMESPACE}"

  log_step "Tekton control plane"
  for deploy in tekton-pipelines-controller tekton-pipelines-webhook "${J2026_TEKTON_DASHBOARD_SERVICE}"; do
    check "${deploy} deployment Available" \
      bash -c "kubectl -n '${TEKTON_NS}' wait --for=condition=Available deploy/'${deploy}' --timeout=10s"
  done

  check "Tekton Dashboard responds (HTTP 200)" \
    bash -c "[[ \$(kubectl -n '${TEKTON_NS}' run smoke-tkn-dash --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- curl -s -o /dev/null -w '%{http_code}' --max-time 30 http://${J2026_TEKTON_DASHBOARD_SERVICE}.${TEKTON_NS}.svc.cluster.local:${J2026_TEKTON_DASHBOARD_PORT}/) == 200 ]]"

  log_step "Tekton pipelines-as-code"
  check "microservices-pipeline Pipeline exists" \
    bash -c "kubectl -n '${PIPELINE_NS}' get pipeline microservices-pipeline"
  # PaC mode (gateway + controller present) drives CI from git: PipelineRuns are
  # created on push/PR, not pre-generated, so assert the PaC wiring (one Repository
  # CR per service, created by ArgoCD) plus a healthy controller. Without a gateway
  # (seed fallback) 06-tekton-pipelines.sh kicks one PipelineRun per service - check
  # those instead.
  if kubectl -n pipelines-as-code get deploy pipelines-as-code-controller >/dev/null 2>&1; then
    check "pipelines-as-code-controller deployment Available" \
      bash -c "kubectl -n pipelines-as-code wait --for=condition=Available deploy/pipelines-as-code-controller --timeout=30s"
    REPO_COUNT="$(kubectl -n "${PIPELINE_NS}" get repository.pipelinesascode.tekton.dev -o name 2>/dev/null | wc -l)"
    if [[ "${REPO_COUNT}" -ge "${NUM_SERVICES}" ]]; then
      log_info "PASS - ${REPO_COUNT} PaC Repository CR(s) found (expected >= ${NUM_SERVICES})"
    else
      log_error "FAIL - only ${REPO_COUNT} PaC Repository CR(s) found (expected >= ${NUM_SERVICES})"
      FAIL=1
    fi
  else
    PR_COUNT="$(kubectl -n "${PIPELINE_NS}" get pipelinerun -o name 2>/dev/null | wc -l)"
    if [[ "${PR_COUNT}" -ge "${NUM_SERVICES}" ]]; then
      log_info "PASS - ${PR_COUNT} PipelineRun(s) found (expected >= ${NUM_SERVICES})"
    else
      log_error "FAIL - only ${PR_COUNT} PipelineRun(s) found (expected >= ${NUM_SERVICES})"
      FAIL=1
    fi
  fi
else
  JENKINS_NS="${J2026_JENKINS_NAMESPACE}"
  JENKINS_RELEASE="${J2026_JENKINS_RELEASE}"
  JENKINS_POD="${JENKINS_RELEASE}-0"

  jenkins_exec() {
    kubectl exec -n "${JENKINS_NS}" "${JENKINS_POD}" -c jenkins -- "$@"
  }

  log_step "Jenkins controller"
  check "${JENKINS_POD} pod is Running" \
    bash -c "kubectl -n '${JENKINS_NS}' get pod '${JENKINS_POD}' -o jsonpath='{.status.phase}' | grep -qx Running"

  check "Jenkins login page responds (HTTP 200)" \
    bash -c "[[ \$(kubectl exec -n '${JENKINS_NS}' '${JENKINS_POD}' -c jenkins -- curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login) == 200 ]]"

  log_step "Seed job / pipelines-as-code"
  ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${JENKINS_NS}" -o jsonpath='{.data.admin-password}' | base64 -d)"
  AUTH="${J2026_JENKINS_ADMIN_USER}:${ADMIN_PASSWORD}"

  EXPECTED_JOBS=$(( NUM_SERVICES + 2 )) # 1 stable pipeline/service + seed-jobs + microservices-k6-smoke

  JOB_COUNT="$(jenkins_exec curl -sg -u "${AUTH}" 'http://localhost:8080/api/json?tree=jobs[name]' \
    | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["jobs"]))' 2>/dev/null || echo 0)"

  if [[ "${JOB_COUNT}" -ge "${EXPECTED_JOBS}" ]]; then
    log_info "PASS - ${JOB_COUNT} Jenkins jobs found (expected >= ${EXPECTED_JOBS})"
  else
    log_error "FAIL - only ${JOB_COUNT} Jenkins jobs found (expected >= ${EXPECTED_JOBS})"
    FAIL=1
  fi
fi

log_step "OpenTelemetry"
check "otel-operator pod Running" \
  bash -c "kubectl -n '${J2026_OBS_NAMESPACE}' get pods -l app.kubernetes.io/instance='${J2026_OTEL_OPERATOR_RELEASE}' -o jsonpath='{.items[0].status.phase}' | grep -qx Running"

check "otel-collector-gateway pod Running" \
  bash -c "kubectl -n '${J2026_OBS_NAMESPACE}' get pods -l app.kubernetes.io/instance='${J2026_OTEL_GATEWAY_RELEASE}' -o jsonpath='{.items[0].status.phase}' | grep -qx Running"

check "otel-collector-logs daemonset has ready pods" \
  bash -c "[[ \$(kubectl -n '${J2026_OBS_NAMESPACE}' get daemonset '${J2026_OTEL_LOGS_RELEASE}-agent' -o jsonpath='{.status.numberReady}') -ge 1 ]]"

# Catch the injection race: any running microservices Deployment must have the
# OTel Java agent injected, else it emits no metrics/traces and the dashboards
# look empty. Deferred for Deployments not running yet (images not built, or
# scaled to 0). scripts/ensure-otel-injection.sh remediates; this asserts.
for deploy in ${J2026_MICROSERVICES_SERVICES}; do
  if kubectl -n "${J2026_MICROSERVICES_NS_STABLE}" get deploy "${deploy}" >/dev/null 2>&1 \
     && [[ "$(kubectl -n "${J2026_MICROSERVICES_NS_STABLE}" get deploy "${deploy}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)" -ge 1 ]]; then
    check "${deploy}: OTel Java agent injected" otel_agent_injected "${J2026_MICROSERVICES_NS_STABLE}" "${deploy}"
  else
    log_info "SKIP - ${deploy}: not running yet (agent injection check deferred)"
  fi
done

if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  check "OSS Grafana pod Running" \
    bash -c "kubectl -n '${J2026_GRAFANA_OSS_NAMESPACE}' get pods -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}' | grep -qx Running"
fi

log_step "Microservices (stable)"
for ns in "${J2026_MICROSERVICES_NS_STABLE}"; do
  check "namespace ${ns} has ${NUM_SERVICES} Deployments" \
    bash -c "[[ \$(kubectl -n '${ns}' get deploy -o jsonpath='{range .items[*]}{.metadata.name}{\"\\n\"}{end}' | grep -v 'pooler' | wc -l) -eq ${NUM_SERVICES} ]]"
done

echo
if [[ "${FAIL}" -eq 1 ]]; then
  log_error "Smoke tests FAILED."
  log_info "Note: Microservices pods may show ImagePullBackOff until each service's"
  log_info "Jenkins pipeline has run at least once (see README's 'First run note')."
  log_info "This does not by itself fail the Deployment-count checks above."
  exit 1
fi

log_info "All smoke tests passed."
