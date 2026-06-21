# managed-azure dashboard variants

These `*-azure.json` dashboards are the `observability.mode=managed-azure`
counterparts of [`../dashboards/`](../dashboards). Azure Managed Grafana reads
from **Azure Monitor** datasources (not Prometheus/Loki/Tempo), so the log and
trace panels are rewritten:

| Panel kind | Canonical (oss / grafana-cloud) | managed-azure variant |
|---|---|---|
| Metrics | Prometheus / PromQL | **unchanged** - Azure Monitor managed Prometheus is Prometheus-compatible, so `${DS_PROMETHEUS}` binds to it and the PromQL works as-is |
| Logs | Loki / LogQL | Azure Monitor **Logs** (KQL over Application Insights `AppTraces`) |
| Traces | Tempo / TraceQL | Azure Monitor **Traces** (App Insights requests + dependencies) |

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

## Validate on first integration

The Azure Monitor datasource query JSON (query types, table names like
`AppTraces`, the `azureTraces` trace types) is best-effort and **should be
validated against a real Azure account** - field names may need minor tweaks
depending on your Application Insights ingestion mode (workspace-based vs
classic). See [`docs/observability.md`](../../../docs/observability.md#managed-azure).
