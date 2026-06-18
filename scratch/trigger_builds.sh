#!/usr/bin/env bash
set -euo pipefail

NS="jenkins"
POD="jenkins-0"
ADMIN_PASSWORD="$(kubectl get secret jenkins-credentials -n jenkins -o jsonpath='{.data.admin-password}' | base64 -d)"
AUTH="admin:${ADMIN_PASSWORD}"

jenkins_exec() {
  kubectl exec -n "${NS}" "${POD}" -c jenkins -- "$@"
}

echo "Fetching CSRF crumb..."
jenkins_exec rm -f /tmp/build-cookies.txt
CRUMB_JSON="$(jenkins_exec curl -s -c /tmp/build-cookies.txt -u "${AUTH}" 'http://localhost:8080/crumbIssuer/api/json')"
CRUMB="$(printf '%s' "${CRUMB_JSON}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["crumb"])')"

echo "Triggering 'gateway' build..."
jenkins_exec curl -s -b /tmp/build-cookies.txt -u "${AUTH}" -H "Jenkins-Crumb: ${CRUMB}" -X POST 'http://localhost:8080/job/gateway/build' -o /dev/null -w 'Gateway build trigger status: %{http_code}\n'

echo "Triggering 'jhipstersamplemicroservice' build..."
jenkins_exec curl -s -b /tmp/build-cookies.txt -u "${AUTH}" -H "Jenkins-Crumb: ${CRUMB}" -X POST 'http://localhost:8080/job/jhipstersamplemicroservice/build' -o /dev/null -w 'JHipster Microservice build trigger status: %{http_code}\n'
