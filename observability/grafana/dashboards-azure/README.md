# managed-azure dashboards

Two kinds, by design:

- **Custom** (`*-azure.json`, this dir): the project-specific views - Jenkins
  CI, per-microservice RED, the k6 smoke test, and the Azure logs/traces panels.
  No public dashboard knows about these (the OTel `service_name`/
  `deployment_environment` labels, `ci_pipeline_run_*` metrics, App Insights
  classic schema), so they're hand-maintained here.
- **Built-in infra** (nothing in this repo): generic Kubernetes/node infra is
  served by **Azure Managed Grafana's own built-in dashboards** (Compute
  Resources / Kubelet / Node Exporter / USE Method), auto-provisioned from the
  Azure Monitor workspace integration - the Azure-native, maintained equivalent
  of what `oss` (kube-prometheus-stack) and `grafana-cloud` (k8s-monitoring app)
  ship. The collector just feeds them: it scrapes cadvisor + kubelet +
  node-exporter + kube-state-metrics (with a `cluster` label) and remote-writes
  to Azure Monitor managed Prometheus - see
  [`values-managed-azure.yaml`](../../otel-collector/values-managed-azure.yaml).

The custom `*-azure.json` variants are the `observability.mode=managed-azure`
counterparts of [`../dashboards/`](../dashboards). Azure Managed Grafana reads
from **Azure Monitor** datasources (not Prometheus/Loki/Tempo), so the log and
trace panels are rewritten:

| Panel kind | Canonical (oss / grafana-cloud) | managed-azure variant |
|---|---|---|
| Metrics | Prometheus / PromQL | **unchanged** - Azure Monitor managed Prometheus is Prometheus-compatible, so `${DS_PROMETHEUS}` binds to it and the PromQL works as-is |
| Logs | Loki / LogQL | Azure Monitor **Logs** (KQL `traces` - App Insights classic schema) |
| Traces | Tempo / TraceQL | Azure Monitor **Logs** (KQL `union requests, dependencies`) |

**Generated, not hand-edited.** Regenerate after changing the canonical
dashboards:

```bash
python3 observability/grafana/dashboards-azure/generate.py
```

[`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh)
publishes these to Azure Managed Grafana via its HTTP API when
`observability.mode=managed-azure`.

## Account-agnostic & secure by design

- **No subscription / resource / tenant IDs** are baked into the JSON. The
  Application Insights resource is chosen at runtime via the `${appinsights}`
  template variable - an **Azure Resource Graph** query
  (`resources | where type =~ 'microsoft.insights/components'`) that lists
  whatever the datasource's managed identity can see.
- **No secrets** in the dashboards: the Azure Monitor datasource authenticates
  with Azure Managed Grafana's managed identity.

## Schema note

The log/trace panels query the **App Insights resource** via the Azure Monitor
datasource, so they use the **classic** App Insights schema (`traces`,
`requests`, `dependencies`, with `operation_Id` / `cloud_RoleName` / `timestamp`)
- **not** the workspace `App*` schema (`AppTraces`/...), which only resolves when
you query the Log Analytics workspace resource. These queries were verified
through Grafana's own query engine against the live data. See
[`docs/observability.md`](../../../docs/observability.md#managed-azure).
