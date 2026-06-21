#!/usr/bin/env bash
# Imports the community infra dashboards listed in community-dashboards.txt into
# Azure Managed Grafana (managed-azure mode), bound to the Prometheus datasource
# (Azure Monitor managed Prometheus). Node Exporter / kube-state-metrics infra
# views are far more comprehensive maintained-by-the-community dashboards than a
# hand-rolled one - the same ones oss/grafana-cloud get from their bundled
# stacks. The app/CI/k6 + Azure logs/traces dashboards stay custom (no public
# equivalent); only generic k8s infra is delegated to the community.
#
# Used by 02.01-gke-provision.yml (managed-azure) and runnable by hand. Requires
# az (logged in, with Grafana Admin on the instance) + the amg extension.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

az extension add -n amg --only-show-errors >/dev/null 2>&1 || true

read -r grafana rg endpoint < <(az grafana list -o json 2>/dev/null | python3 -c '
import sys, json
g = [x for x in json.load(sys.stdin) if x["name"].startswith("jenkins-2026")]
if g:
    print(g[0]["name"], g[0]["resourceGroup"], g[0]["properties"]["endpoint"])
')
if [[ -z "${grafana:-}" || -z "${endpoint:-}" ]]; then
  echo "No Azure Managed Grafana found - skipping community dashboard import."
  exit 0
fi

prom="$(az grafana data-source list -n "${grafana}" -g "${rg}" \
  --query "[?type=='prometheus'].uid | [0]" -o tsv)"
if [[ -z "${prom:-}" ]]; then
  echo "No Prometheus datasource in ${grafana} - skipping community dashboard import."
  exit 0
fi

# Grafana's import API resolves a dashboard's __inputs (datasource +
# VAR_DATASOURCE constant) properly - far more robust than string-replacing
# datasource placeholders, since community dashboards mix ${DS_PROMETHEUS},
# ${datasource} and $datasource. Auth: an Azure AD token (audience
# ce34e7e5-... is the Azure Managed Grafana first-party app).
token="$(az account get-access-token --resource ce34e7e5-485f-4d76-964f-b3d2b16d1e4f --query accessToken -o tsv)"

echo "Importing community infra dashboards into ${grafana} (prometheus uid=${prom})"
while read -r gid uid name; do
  [[ -z "${gid}" || "${gid}" == \#* ]] && continue
  if ! curl -fsSL "https://grafana.com/api/dashboards/${gid}/revisions/latest/download" -o /tmp/gnet.json; then
    echo "::warning::failed to fetch gnetId ${gid} (${name})"
    continue
  fi
  # Build the import payload: pin our uid, and give every __input the
  # Prometheus datasource uid (datasource inputs + the VAR_DATASOURCE constant).
  python3 - "${prom}" "${uid}" <<'PY'
import json, sys
prom, uid = sys.argv[1], sys.argv[2]
d = json.load(open("/tmp/gnet.json"))
d["uid"] = uid
inputs = []
for i in d.get("__inputs", []):
    e = {"name": i["name"], "type": i["type"], "value": prom}
    if i.get("pluginId"):
        e["pluginId"] = i["pluginId"]
    inputs.append(e)
json.dump({"dashboard": d, "overwrite": True, "inputs": inputs}, open("/tmp/gnet-import.json", "w"))
PY
  if curl -fsS -X POST "${endpoint%/}/api/dashboards/import" \
       -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
       -d @/tmp/gnet-import.json >/dev/null; then
    echo "imported ${name} (gnetId ${gid})"
  else
    echo "::warning::failed to import ${name} (gnetId ${gid})"
  fi
done < "${HERE}/community-dashboards.txt"
