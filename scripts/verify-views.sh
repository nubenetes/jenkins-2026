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

echo "View details for 'petclinic':"
jenkins_exec curl -s -u "${AUTH}" 'http://localhost:8080/view/petclinic/api/json?tree=jobs[name]' | python3 -m json.tool

echo "------------------------------------------------"
echo "View details for 'petclinic-develop':"
jenkins_exec curl -s -u "${AUTH}" 'http://localhost:8080/view/petclinic-develop/api/json?tree=jobs[name]' | python3 -m json.tool
