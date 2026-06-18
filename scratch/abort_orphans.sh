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

echo "Stopping 'gateway' build #8..."
jenkins_exec curl -s -b /tmp/build-cookies.txt -u "${AUTH}" -H "Jenkins-Crumb: ${CRUMB}" -X POST 'http://localhost:8080/job/gateway/8/stop' -o /dev/null -w 'Gateway abort status: %{http_code}\n'

echo "Stopping 'jhipstersamplemicroservice' build #27..."
jenkins_exec curl -s -b /tmp/build-cookies.txt -u "${AUTH}" -H "Jenkins-Crumb: ${CRUMB}" -X POST 'http://localhost:8080/job/jhipstersamplemicroservice/27/stop' -o /dev/null -w 'JHipster Microservice abort status: %{http_code}\n'

echo "Deleting agent pods..."
kubectl delete pod gateway-8-fjst1-5sr9x-mxz0c -n jenkins --grace-period=0 --force || true
kubectl delete pod jhipstersamplemicroservice-27-2p2kv-vzlvl-xhq67 -n jenkins --grace-period=0 --force || true
