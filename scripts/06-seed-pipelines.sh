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
log_step "Fetching CSRF crumb"
jenkins_exec rm -f /tmp/seed-cookies.txt
CRUMB_JSON="$(jenkins_exec curl -s -c /tmp/seed-cookies.txt -u "${AUTH}" 'http://localhost:8080/crumbIssuer/api/json')"
CRUMB="$(printf '%s' "${CRUMB_JSON}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["crumb"])')"

log_step "Triggering the 'seed-jobs' pipeline"
jenkins_exec curl -s -b /tmp/seed-cookies.txt -u "${AUTH}" -H "Jenkins-Crumb: ${CRUMB}" -X POST 'http://localhost:8080/job/seed-jobs/build' -o /dev/null -w '%{http_code}\n'

log_step "Waiting for seed-jobs to create the Microservices pipeline jobs"
expected=0
for svc in ${J2026_MICROSERVICES_SERVICES}; do
  expected=$((expected + 1))
done
# +2: seed-jobs itself + microservices-k6-smoke (matches smoke-test.sh EXPECTED_JOBS)
min_jobs=$((expected + 2))

job_wait_ok=0
for _ in $(seq 1 90); do
  count="$(jenkins_exec curl -sg -u "${AUTH}" 'http://localhost:8080/api/json?tree=jobs[name]' \
    | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["jobs"]))')"
  if [[ "${count}" -ge "${min_jobs}" ]]; then
    log_info "Found ${count} jobs (>= ${min_jobs} expected: ${expected} Microservices pipelines + seed-jobs + k6-smoke)."
    job_wait_ok=1
    break
  fi
  sleep 5
done

if [[ "${job_wait_ok}" -eq 0 ]]; then
  log_error "Timed out waiting for seed-jobs to create ${min_jobs} jobs (last count: ${count})."
  exit 1
fi

log_info "Seed pipeline triggered. Browse http://localhost:8080/view/microservices/ (after port-forwarding)"
log_info "  kubectl -n ${NS} port-forward svc/${RELEASE} 8080:8080"
