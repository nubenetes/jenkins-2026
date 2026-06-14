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

echo "View XML for 'petclinic-develop':"
jenkins_exec curl -s -u "${AUTH}" 'http://localhost:8080/view/petclinic-develop/config.xml'
