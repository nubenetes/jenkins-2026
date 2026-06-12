#!/usr/bin/env bash
# Triggers the "seed-jobs" pipeline (defined by jenkins/casc/jcasc-seed-job.yaml,
# which itself runs jenkins/pipelines/seed/seed-jobs.groovy via the Job DSL
# plugin) so the 18 PetClinic pipelines (9 services x stable/-develop) exist
# immediately, instead of waiting for its H/30 * * * * cron trigger.
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

log_step "Fetching CSRF crumb"
CRUMB_JSON="$(jenkins_exec curl -s -u "${AUTH}" 'http://localhost:8080/crumbIssuer/api/json')"
CRUMB_HEADER="$(printf '%s' "${CRUMB_JSON}" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"{d[\"crumbRequestField\"]}: {d[\"crumb\"]}")')"

log_step "Triggering the 'seed-jobs' pipeline"
jenkins_exec curl -s -u "${AUTH}" -H "${CRUMB_HEADER}" -X POST 'http://localhost:8080/job/seed-jobs/build' -o /dev/null -w '%{http_code}\n'

log_step "Waiting for seed-jobs to create the PetClinic pipeline jobs"
expected=0
for svc in ${J2026_PETCLINIC_SERVICES}; do
  expected=$((expected + 2))
done

for _ in $(seq 1 30); do
  count="$(jenkins_exec curl -s -u "${AUTH}" 'http://localhost:8080/api/json?tree=jobs[name]' \
    | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["jobs"]))')"
  if [[ "${count}" -ge "$((expected + 1))" ]]; then
    log_info "Found ${count} jobs (>= ${expected} PetClinic pipelines + seed-jobs)."
    break
  fi
  sleep 2
done

log_info "Seed pipeline triggered. Browse http://localhost:8080/view/petclinic/ (after port-forwarding)"
log_info "  kubectl -n ${NS} port-forward svc/${RELEASE} 8080:8080"
