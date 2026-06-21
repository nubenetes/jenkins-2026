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

read -r grafana rg < <(az grafana list \
  --query "[?starts_with(name,'jenkins-2026')].[name,resourceGroup] | [0]" -o tsv)
if [[ -z "${grafana:-}" ]]; then
  echo "No Azure Managed Grafana found - skipping community dashboard import."
  exit 0
fi

prom="$(az grafana data-source list -n "${grafana}" -g "${rg}" \
  --query "[?type=='prometheus'].uid | [0]" -o tsv)"
if [[ -z "${prom:-}" ]]; then
  echo "No Prometheus datasource in ${grafana} - skipping community dashboard import."
  exit 0
fi

echo "Importing community infra dashboards into ${grafana} (prometheus uid=${prom})"
while read -r gid uid name; do
  [[ -z "${gid}" || "${gid}" == \#* ]] && continue
  if ! curl -fsSL "https://grafana.com/api/dashboards/${gid}/revisions/latest/download" -o /tmp/gnet.json; then
    echo "::warning::failed to fetch gnetId ${gid} (${name})"
    continue
  fi
  # Strip the import-only __inputs/__requires and bind the datasource template
  # to the concrete Prometheus datasource, then pin our own uid.
  python3 - "${prom}" "${uid}" <<'PY'
import json, sys
prom, uid = sys.argv[1], sys.argv[2]
d = json.load(open("/tmp/gnet.json"))
d.pop("__inputs", None)
d.pop("__requires", None)
d = json.loads(json.dumps(d).replace("${DS_PROMETHEUS}", prom).replace("${datasource}", prom))
d["uid"] = uid
json.dump(d, open("/tmp/gnet-bound.json", "w"))
PY
  if az grafana dashboard create -n "${grafana}" -g "${rg}" \
       --definition @/tmp/gnet-bound.json --overwrite --only-show-errors >/dev/null; then
    echo "imported ${name} (gnetId ${gid})"
  else
    echo "::warning::failed to publish ${name} (gnetId ${gid})"
  fi
done < "${HERE}/community-dashboards.txt"
