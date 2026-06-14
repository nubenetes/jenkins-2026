#!/usr/bin/env bash
set -euo pipefail

NS="jenkins"
RELEASE="jenkins"
POD="${RELEASE}-0"

ADMIN_PASSWORD=$(kubectl get secret jenkins-credentials -n "${NS}" -o jsonpath='{.data.admin-password}' | base64 -d)
AUTH="admin:${ADMIN_PASSWORD}"

jenkins_exec() {
  kubectl exec -n "${NS}" "${POD}" -c jenkins -- "$@"
}

echo "Fetching CSRF crumb..."
jenkins_exec rm -f /tmp/seed-cookies.txt
CRUMB_JSON=$(jenkins_exec curl -s -c /tmp/seed-cookies.txt -u "${AUTH}" 'http://localhost:8080/crumbIssuer/api/json')
CRUMB=$(echo "${CRUMB_JSON}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["crumb"])')

echo "Triggering the 'seed-jobs' pipeline..."
jenkins_exec curl -s -b /tmp/seed-cookies.txt -u "${AUTH}" -H "Jenkins-Crumb: ${CRUMB}" -X POST 'http://localhost:8080/job/seed-jobs/build'
