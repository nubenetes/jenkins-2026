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

echo "Seed-jobs last build console output:"
jenkins_exec curl -s -u "${AUTH}" 'http://localhost:8080/job/seed-jobs/lastBuild/consoleText' | tail -n 50
