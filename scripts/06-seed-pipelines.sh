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
# NEG-aware best-effort wait (lib/common.sh): when ci.engine=jenkins the controller is a
# Gateway/NEG backend, so a hard rollout wait deadlocks on a HealthCheckPolicy protocol
# mismatch until 09-gateway.sh reconciles it (backend_tls mode switch). The crumbIssuer
# poll below is the real readiness gate; 09 makes the NEG healthy. See docs/504 § argocd.
wait_neg_backend_rollout "${RELEASE}" "${NS}" "10m" "statefulset"

ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${NS}" -o jsonpath='{.data.admin-password}' | base64 -d)"
AUTH="${J2026_JENKINS_ADMIN_USER}:${ADMIN_PASSWORD}"

# Local REST API base for the in-pod curls below. With backend TLS active
# (docs/504) the controller serves HTTPS on 8080 and plain HTTP on the pod's
# httpsKeyStore.httpPort (8081); these calls run INSIDE the pod (localhost), so
# target the plain-HTTP port to avoid speaking HTTP to the HTTPS listener (which
# returns an empty/garbage reply and hangs the crumb fetch). Plain 8080
# otherwise. JENKINS_FWD_SVC_PORT is the matching plain SERVICE port for the
# port-forward hint at the end (8082 → pod 8081 under TLS; see
# helm/jenkins/values-backend-tls.yaml).
if [[ "$(j2026_backend_tls_active)" == "true" ]]; then
  JENKINS_LOCAL_URL="http://localhost:8081"
  JENKINS_FWD_SVC_PORT=8082
else
  JENKINS_LOCAL_URL="http://localhost:8080"
  JENKINS_FWD_SVC_PORT=8080
fi

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
# The seed build is occasionally flaky: the git checkout streams its output back
# over the agent↔controller JNLP channel, and a freshly-(re)started controller
# still applying JCasC / loading plugins can drop that channel mid-checkout
# ("Could not checkout <sha>" / ClosedChannelException) — the SAME repo+branch
# passes on a calmer run. So (re)trigger the WHOLE build a few times before giving
# up, fetching a fresh crumb each attempt (a controller restart between attempts
# would otherwise leave a stale crumb). A real, persistent error still fails every
# attempt and surfaces. Tune with SEED_MAX_ATTEMPTS.
SEED_MAX_ATTEMPTS="${SEED_MAX_ATTEMPTS:-3}"

# fetch_crumb -> sets CRUMB (+ session cookie jar). Returns 1 if the API never serves.
fetch_crumb() {
  log_step "Fetching CSRF crumb (waiting for the Jenkins HTTP API to serve)"
  jenkins_exec rm -f /tmp/seed-cookies.txt
  CRUMB=""
  local deadline=$(( SECONDS + 300 )) crumb_json
  while [[ $SECONDS -lt $deadline ]]; do
    crumb_json="$(jenkins_exec curl -s --max-time 10 -c /tmp/seed-cookies.txt -u "${AUTH}" \
        "${JENKINS_LOCAL_URL}/crumbIssuer/api/json" 2>/dev/null || true)"
    CRUMB="$(printf '%s' "${crumb_json}" \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["crumb"])' 2>/dev/null || true)"
    [[ -n "${CRUMB}" ]] && break
    sleep 3
  done
  [[ -n "${CRUMB}" ]] || { log_warn "Timed out (5m) waiting for the Jenkins crumbIssuer API"; return 1; }
  return 0
}

# run_seed_build -> POST /build, wait for it to start, then finish. 0 only on SUCCESS.
run_seed_build() {
  log_step "Triggering the 'seed-jobs' pipeline"
  local trig http queue build result deadline
  # -i includes response headers so we can read the Location header for the queue item ID
  trig="$(jenkins_exec curl -si -b /tmp/seed-cookies.txt -u "${AUTH}" \
    -H "Jenkins-Crumb: ${CRUMB}" -X POST "${JENKINS_LOCAL_URL}/job/seed-jobs/build")"
  http="$(printf '%s' "${trig}" | head -1 | tr -d '\r\n' | awk '{print $2}')"
  # Location is always .../queue/item/<id>/ regardless of the configured Jenkins root URL
  queue="$(printf '%s' "${trig}" | grep -i '^Location:' | tr -d '\r' | grep -oE '[0-9]+/?$' | tr -d '/')"
  log_info "HTTP ${http} — queue item #${queue}"
  [[ -n "${queue}" ]] || { log_warn "Failed to parse queue item (HTTP ${http}) — crumb may have expired"; return 1; }

  log_step "Waiting for seed-jobs build to start"
  build=""; deadline=$(( SECONDS + 120 ))
  while [[ $SECONDS -lt $deadline ]]; do
    build="$(jenkins_exec curl -sg -u "${AUTH}" \
        "${JENKINS_LOCAL_URL}/queue/item/${queue}/api/json" \
      | python3 -c 'import sys,json; d=json.load(sys.stdin); exe=d.get("executable"); print(exe["number"] if exe else "")' \
      2>/dev/null || true)"
    [[ -n "${build}" ]] && break
    sleep 2
  done
  [[ -n "${build}" ]] || { log_warn "Timed out (2m) waiting for the build to start (queue #${queue})"; return 1; }
  log_info "seed-jobs build #${build} started"

  log_step "Waiting for seed-jobs build #${build} to complete"
  result=""; deadline=$(( SECONDS + 360 ))
  while [[ $SECONDS -lt $deadline ]]; do
    result="$(jenkins_exec curl -sg -u "${AUTH}" \
        "${JENKINS_LOCAL_URL}/job/seed-jobs/${build}/api/json" \
      | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("result") or "")' \
      2>/dev/null || true)"
    [[ -n "${result}" ]] && break
    sleep 3
  done
  if [[ "${result}" == "SUCCESS" ]]; then
    log_info "seed-jobs build #${build} succeeded"
    return 0
  fi
  log_warn "seed-jobs build #${build} ended with: ${result:-TIMEOUT}"
  return 1
}

seed_ok=false
for attempt in $(seq 1 "${SEED_MAX_ATTEMPTS}"); do
  log_step "seed-jobs: attempt ${attempt}/${SEED_MAX_ATTEMPTS}"
  if fetch_crumb && run_seed_build; then seed_ok=true; break; fi
  if [[ "${attempt}" -lt "${SEED_MAX_ATTEMPTS}" ]]; then
    log_warn "seed-jobs attempt ${attempt} failed (flaky agent/controller channel) — retrying in 10s…"
    sleep 10
  fi
done
if [[ "${seed_ok}" != "true" ]]; then
  log_error "seed-jobs failed after ${SEED_MAX_ATTEMPTS} attempts — check the build console in Jenkins (job/seed-jobs)."
  exit 1
fi

log_step "Verifying Microservices pipeline jobs were created"
expected=0
for svc in ${J2026_MICROSERVICES_SERVICES}; do
  expected=$((expected + 1))
done
# +2: seed-jobs itself + microservices-k6-smoke (matches smoke-test.sh EXPECTED_JOBS)
min_jobs=$((expected + 2))

# 2>/dev/null on the exec: a failed exec makes kubectl echo the request URL,
# which URL-encodes `-u admin:<password>` — don't leak the admin password to the log.
count="$(jenkins_exec curl -sg -u "${AUTH}" "${JENKINS_LOCAL_URL}/api/json?tree=jobs[name]" 2>/dev/null \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["jobs"]))' 2>/dev/null || echo 0)"
if [[ "${count}" -lt "${min_jobs}" ]]; then
  log_error "Expected >= ${min_jobs} jobs after seed run, found only ${count}"
  exit 1
fi
log_info "Found ${count} jobs (>= ${min_jobs}: ${expected} Microservices pipelines + seed-jobs + k6-smoke)"

# Opt-in-by-default (jenkins.seedBuilds / JENKINS2026_JENKINS_SEED_BUILDS): kick ONE build
# per microservices job so the Jenkins CI/CD tab (Backstage + the Jenkins UI) is
# pre-populated on a fresh cluster — parity with tekton.seedRuns / githubactions.seedRuns.
# Without at least one build the Backstage Jenkins plugin's re-build button crashes on a
# null lastBuild ("Cannot read properties of null (reading 'number')"). The app itself
# deploys via GitOps regardless; this exercises the pipeline + fills the build history.
# FIRE-AND-FORGET: we trigger each build and confirm it queued (HTTP 201) but do NOT wait
# for it to finish (that would add ~20-30 min per service to Day1). microservices-k6-smoke
# self-gates on service readiness (docs/302), so triggering it alongside the app builds is
# safe. Re-fetch a fresh crumb: the one from the seed build above may have aged out.
if [[ "${J2026_JENKINS_SEED_BUILDS}" == "true" ]]; then
  log_step "jenkins.seedBuilds=true — triggering an initial build per microservices job (fire-and-forget)"
  if fetch_crumb; then
    jobs_to_trigger=""
    for job in ${J2026_MICROSERVICES_SERVICES}; do
      jobs_to_trigger="${jobs_to_trigger} ${job}"
      if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
        jobs_to_trigger="${jobs_to_trigger} ${job}-develop"
      fi
    done
    jobs_to_trigger="${jobs_to_trigger} microservices-k6-smoke"
    if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
      jobs_to_trigger="${jobs_to_trigger} microservices-k6-smoke-develop"
    fi

    for job in ${jobs_to_trigger}; do
      # 2>/dev/null on the exec (not the inner curl): a failed exec echoes the request URL,
      # which URL-encodes `-u admin:<password>` — never leak the admin password to the log.
      code="$(jenkins_exec curl -s -o /dev/null -w '%{http_code}' -b /tmp/seed-cookies.txt \
        -u "${AUTH}" -H "Jenkins-Crumb: ${CRUMB}" -X POST "${JENKINS_LOCAL_URL}/job/${job}/build" \
        2>/dev/null || echo "exec-fail")"
      if [[ "${code}" == "201" ]]; then
        log_info "  queued initial build: ${job}"
      else
        log_warn "  could not queue ${job} (HTTP ${code}) — trigger it manually (Build Now) if the tab stays empty"
      fi
    done
  else
    log_warn "jenkins.seedBuilds: could not fetch a crumb — skipping initial builds (trigger manually via Build Now)"
  fi
fi

log_info "Seed pipeline triggered. Browse ${JENKINS_LOCAL_URL}/view/microservices/ (after port-forwarding)"
log_info "  kubectl -n ${NS} port-forward svc/${RELEASE} ${JENKINS_LOCAL_URL##*:}:${JENKINS_FWD_SVC_PORT}"
