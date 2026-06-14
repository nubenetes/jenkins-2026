#!/usr/bin/env bash
set -euo pipefail

NS="observability"
SECRET="grafana-cloud-credentials"

GRAFANA_BASE_URL=$(kubectl get secret "${SECRET}" -n "${NS}" -o jsonpath='{.data.GRAFANA_BASE_URL}' | base64 -d)
GRAFANA_API_KEY=$(kubectl get secret "${SECRET}" -n "${NS}" -o jsonpath='{.data.GRAFANA_API_KEY}' | base64 -d)

if [[ -z "${GRAFANA_BASE_URL}" || -z "${GRAFANA_API_KEY}" ]]; then
  echo "Error: GRAFANA_BASE_URL or GRAFANA_API_KEY not found in secret."
  exit 1
fi

echo "Fetching all datasources from ${GRAFANA_BASE_URL}..."
curl -s -H "Authorization: Bearer ${GRAFANA_API_KEY}" "${GRAFANA_BASE_URL}/api/datasources" | python3 -m json.tool
