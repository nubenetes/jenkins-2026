#!/usr/bin/env bash
# Triggers the "seed-jobs" pipeline (defined by jenkins/casc/jcasc-seed-job.yaml,
# which itself runs jenkins/pipelines/seed/seed_jobs.groovy via the Job DSL
# plugin) so the 9 stable Microservices pipelines exist immediately, instead of
# waiting for its H/30 * * * * cron trigger.
#
# Talks to the Jenkins REST API from inside the controller pod via
# `kubectl exec`, so no Ingress/port-forward is required.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

NS="${J2026_JENKINS_NAMESPACE}"
RELEASE="${J2026_JENKINS_RELEASE}"
POD="${RELEASE}-0"

log_step "Waiting for ${POD} to be ready"
kubectl rollout status "statefulset/${RELEASE}" -n "${NS}" --timeout=10m

ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${NS}" -o jsonpath='{.data.admin-password}' | base64 -d)"
AUTH="${J2026_JENKINS_ADMIN_USER}:${ADMIN_PASSWORD}"

jenkins_exec() {
  kubectl exec -n "${NS}" "${POD}" -c jenkins -- "$@"
}

# The crumb is bound to the session cookie that issued it, so the
# crumbIssuer request and the build request must share a cookie jar -
# persisted in the pod's /tmp across these separate `kubectl exec` calls.
#
# `kubectl rollout status` above only guarantees the pod is Ready, not that the
# Jenkins HTTP API is already serving - right after a (re)start curl can get an
# empty reply (exit 52) or a 503 while Jenkins finishes booting/applying JCasC.
# Poll the crumbIssuer until it returns a valid crumb instead of failing hard.
log_step "Fetching CSRF crumb (waiting for the Jenkins HTTP API to serve)"
jenkins_exec rm -f /tmp/seed-cookies.txt
CRUMB=""
DEADLINE=$(( SECONDS + 300 ))
while [[ $SECONDS -lt $DEADLINE ]]; do
  CRUMB_JSON="$(jenkins_exec curl -s --max-time 10 -c /tmp/seed-cookies.txt -u "${AUTH}" \
      'http://localhost:8080/crumbIssuer/api/json' 2>/dev/null || true)"
  CRUMB="$(printf '%s' "${CRUMB_JSON}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["crumb"])' 2>/dev/null || true)"
  [[ -n "${CRUMB}" ]] && break
  sleep 3
done
if [[ -z "${CRUMB}" ]]; then
  log_error "Timed out (5m) waiting for the Jenkins crumbIssuer API to respond"
  exit 1
fi

log_step "Triggering the 'seed-jobs' pipeline"
# -i includes response headers so we can read the Location header for the queue item ID
TRIGGER_RESPONSE="$(jenkins_exec curl -si -b /tmp/seed-cookies.txt -u "${AUTH}" \
  -H "Jenkins-Crumb: ${CRUMB}" -X POST 'http://localhost:8080/job/seed-jobs/build')"
HTTP_STATUS="$(printf '%s' "${TRIGGER_RESPONSE}" | head -1 | tr -d '\r\n' | awk '{print $2}')"
# Location is always .../queue/item/<id>/ regardless of configured Jenkins root URL
QUEUE_ITEM_ID="$(printf '%s' "${TRIGGER_RESPONSE}" | grep -i '^Location:' | tr -d '\r' | grep -oE '[0-9]+/?$' | tr -d '/')"
log_info "HTTP ${HTTP_STATUS} — queue item #${QUEUE_ITEM_ID}"

if [[ -z "${QUEUE_ITEM_ID}" ]]; then
  log_error "Failed to parse queue item from trigger response (HTTP ${HTTP_STATUS})"
  exit 1
fi

log_step "Waiting for seed-jobs build to start"
BUILD_NUM=""
DEADLINE=$(( SECONDS + 120 ))
while [[ $SECONDS -lt $DEADLINE ]]; do
  BUILD_NUM="$(jenkins_exec curl -sg -u "${AUTH}" \
      "http://localhost:8080/queue/item/${QUEUE_ITEM_ID}/api/json" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); exe=d.get("executable"); print(exe["number"] if exe else "")' \
    2>/dev/null || true)"
  [[ -n "${BUILD_NUM}" ]] && break
  sleep 2
done

if [[ -z "${BUILD_NUM}" ]]; then
  log_error "Timed out (2m) waiting for seed-jobs build to start (queue item #${QUEUE_ITEM_ID})"
  exit 1
fi
log_info "seed-jobs build #${BUILD_NUM} started"

log_step "Waiting for seed-jobs build #${BUILD_NUM} to complete"
BUILD_RESULT=""
DEADLINE=$(( SECONDS + 360 ))
while [[ $SECONDS -lt $DEADLINE ]]; do
  BUILD_RESULT="$(jenkins_exec curl -sg -u "${AUTH}" \
      "http://localhost:8080/job/seed-jobs/${BUILD_NUM}/api/json" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("result") or "")' \
    2>/dev/null || true)"
  [[ -n "${BUILD_RESULT}" ]] && break
  sleep 3
done

if [[ "${BUILD_RESULT}" != "SUCCESS" ]]; then
  log_error "seed-jobs build #${BUILD_NUM} ended with: ${BUILD_RESULT:-TIMEOUT}"
  exit 1
fi
log_info "seed-jobs build #${BUILD_NUM} succeeded"

log_step "Verifying Microservices pipeline jobs were created"
expected=0
for svc in ${J2026_MICROSERVICES_SERVICES}; do
  expected=$((expected + 1))
done
# +2: seed-jobs itself + microservices-k6-smoke (matches smoke-test.sh EXPECTED_JOBS)
min_jobs=$((expected + 2))

count="$(jenkins_exec curl -sg -u "${AUTH}" 'http://localhost:8080/api/json?tree=jobs[name]' \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["jobs"]))')"
if [[ "${count}" -lt "${min_jobs}" ]]; then
  log_error "Expected >= ${min_jobs} jobs after seed run, found only ${count}"
  exit 1
fi
log_info "Found ${count} jobs (>= ${min_jobs}: ${expected} Microservices pipelines + seed-jobs + k6-smoke)"

log_info "Seed pipeline triggered. Browse http://localhost:8080/view/microservices/ (after port-forwarding)"
log_info "  kubectl -n ${NS} port-forward svc/${RELEASE} 8080:8080"
