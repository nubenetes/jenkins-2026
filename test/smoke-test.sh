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

  # Dashboard HTTP reachability via its Service. The tekton-pipelines namespace
  # enforces the 'restricted' PodSecurity standard, so the ephemeral curl pod MUST
  # carry a compliant securityContext or admission rejects it (no securityContext ->
  # Forbidden -> no HTTP code -> false FAIL). Hit /readiness (the dashboard's own
  # readiness endpoint, guaranteed 200 when the pod is Ready). Use run->wait->logs
  # rather than 'run -i' (the interactive attach raced a fast-completing pod).
  dash_url="http://${J2026_TEKTON_DASHBOARD_SERVICE}.${TEKTON_NS}.svc.cluster.local:${J2026_TEKTON_DASHBOARD_PORT}/readiness"
  kubectl -n "${TEKTON_NS}" delete pod smoke-tkn-dash --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${TEKTON_NS}" run smoke-tkn-dash --restart=Never --image=curlimages/curl:8.10.1 \
    --overrides='{
      "spec": {
        "securityContext": {"runAsNonRoot": true, "seccompProfile": {"type": "RuntimeDefault"}},
        "containers": [{
          "name": "smoke-tkn-dash",
          "image": "curlimages/curl:8.10.1",
          "command": ["curl","-s","-o","/dev/null","-w","%{http_code}","--max-time","20","'"${dash_url}"'"],
          "securityContext": {
            "allowPrivilegeEscalation": false, "runAsNonRoot": true, "runAsUser": 100,
            "capabilities": {"drop": ["ALL"]}, "seccompProfile": {"type": "RuntimeDefault"}
          }
        }]
      }
    }' >/dev/null 2>&1
  if kubectl -n "${TEKTON_NS}" wait --for=jsonpath='{.status.phase}'=Succeeded \
       pod/smoke-tkn-dash --timeout=90s >/dev/null 2>&1; then
    DASH_CODE="$(kubectl -n "${TEKTON_NS}" logs smoke-tkn-dash 2>/dev/null | tr -dc '0-9')"
  else
    DASH_CODE=""
  fi
  kubectl -n "${TEKTON_NS}" delete pod smoke-tkn-dash --ignore-not-found >/dev/null 2>&1 || true
  if [[ "${DASH_CODE}" == "200" ]]; then
    log_info "PASS - Tekton Dashboard responds (HTTP 200 on /readiness)"
  else
    log_error "FAIL - Tekton Dashboard HTTP check (got '${DASH_CODE:-no-response}')"
    FAIL=1
  fi

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
elif [[ "${J2026_CI_ENGINE}" == "githubactions" ]]; then
  GHA_NS="${J2026_GHA_NAMESPACE}"
  RUNNER_NS="${J2026_GHA_RUNNER_NAMESPACE}"

  log_step "ARC controller"
  # The gha-runner-scale-set-controller Deployment name is release-prefixed; match by
  # the well-known label so the check is release-agnostic.
  ARC_CTRL="$(kubectl get deploy -n "${GHA_NS}" -l app.kubernetes.io/part-of=gha-rs-controller -o name 2>/dev/null | head -n1)"
  if [[ -n "${ARC_CTRL}" ]]; then
    check "ARC controller deployment Available" \
      bash -c "kubectl -n '${GHA_NS}' wait --for=condition=Available '${ARC_CTRL}' --timeout=30s"
  else
    log_error "FAIL - ARC controller (gha-rs-controller) not found in ${GHA_NS}"
    FAIL=1
  fi

  log_step "ARC runner scale set"
  # The CR existing is NOT enough — the controller creates the AutoscalingRunnerSet *before* it
  # registers with GitHub, so a 403 (missing org runner-admin permission on the App/PAT) leaves
  # the CR present but unregistered. The real success signal is the AutoscalingListener pod: the
  # controller only creates it after minting a runner registration token. Check the CR exists AND
  # a listener is Running. (At minRunners=0 there are no runner pods; the per-fork
  # microservices-ci.yml workflows live in the forks, not the cluster.)
  check "AutoscalingRunnerSet ${J2026_GHA_RUNNER_SCALE_SET_NAME} exists" \
    bash -c "kubectl -n '${RUNNER_NS}' get autoscalingrunnerset '${J2026_GHA_RUNNER_SCALE_SET_NAME}'"
  check "ARC AutoscalingListener Running (scale set registered with GitHub)" \
    bash -c "for _ in \$(seq 1 18); do kubectl -n '${GHA_NS}' get pods --field-selector=status.phase=Running -o name 2>/dev/null | grep -q listener && exit 0; sleep 5; done; echo 'no Running AutoscalingListener — the scale set did not register; check the controller logs for a 403 (org runner-admin permission on the GitHub App / PAT)'; exit 1"

elif [[ "${J2026_CI_ENGINE}" == "argoworkflows" ]]; then
  ARGOWF_NS="${J2026_ARGOWF_NAMESPACE}"
  EVENTS_NS="${J2026_ARGOWF_EVENTS_NAMESPACE}"
  RUN_NS="${J2026_ARGOWF_RUN_NAMESPACE}"

  log_step "Argo Workflows control plane"
  for deploy in workflow-controller "${J2026_ARGOWF_SERVER_SERVICE}"; do
    check "${deploy} deployment Available" \
      bash -c "kubectl -n '${ARGOWF_NS}' wait --for=condition=Available deploy/'${deploy}' --timeout=30s"
  done
  # Argo Events v1.9.x ships a single unified controller-manager Deployment.
  check "Argo Events controller-manager Available" \
    bash -c "kubectl -n '${EVENTS_NS}' wait --for=condition=Available deploy/controller-manager --timeout=30s"

  log_step "Argo Workflows pipelines-as-code"
  check "microservices-pipeline WorkflowTemplate exists" \
    bash -c "kubectl -n '${RUN_NS}' get workflowtemplate microservices-pipeline"
  check "argoworkflows-ci ServiceAccount exists" \
    bash -c "kubectl -n '${RUN_NS}' get sa argoworkflows-ci"
  # Trigger wiring (the Argo Events analogue of Tekton's PaC Repository CRs): one github
  # EventSource + one microservices Sensor filter all forks (no per-service CR).
  check "github EventSource exists" \
    bash -c "kubectl -n '${EVENTS_NS}' get eventsource github"
  check "microservices Sensor exists" \
    bash -c "kubectl -n '${EVENTS_NS}' get sensor microservices"

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

  jenkins_url="http://localhost:8080"
  if [[ "${JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED}" == "true" ]]; then
    jenkins_url="http://localhost:8081"
  fi

  check "Jenkins login page responds (HTTP 200)" \
    bash -c "[[ \$(kubectl exec -n '${JENKINS_NS}' '${JENKINS_POD}' -c jenkins -- curl -s -o /dev/null -w '%{http_code}' ${jenkins_url}/login) == 200 ]]"

  log_step "Seed job / pipelines-as-code"
  ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${JENKINS_NS}" -o jsonpath='{.data.admin-password}' | base64 -d)"
  AUTH="${J2026_JENKINS_ADMIN_USER}:${ADMIN_PASSWORD}"

  EXPECTED_JOBS=$(( NUM_SERVICES + 2 )) # 1 stable pipeline/service + seed-jobs + microservices-k6-smoke

  JOB_COUNT="$(jenkins_exec curl -sg -u "${AUTH}" "${jenkins_url}/api/json?tree=jobs[name]" \
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
