# terraform/azure-managed-grafana

The **`observability.mode=managed-azure` backend** — Azure Managed Grafana, an
Azure Monitor workspace + DCE/DCR (managed Prometheus), Application Insights +
Log Analytics, and the Entra service principal the in-cluster OTel collector
authenticates with. Ingestion resources sit in `spaincentral` (next to the GKE
cluster in `europe-southwest1`); AMG itself goes to `francecentral` (AMG isn't
available in `spaincentral`) and queries cross-region. Same persistent-bootstrap
role as `grafana-cloud-stack`. See [`docs/301`](../../docs/301-OBSERVABILITY.md).

## Lifecycle owner

Applied **one-time** by **`Day0.infra.03-azure-grafana.yml`** (GitHub-OIDC → Azure
auth, no stored client secret), destroyed by **`Decom.infra.03-azure-grafana.yml`**.
Safe to re-run. **`Day1.cluster.01-gke` does NOT apply it** — it reads the outputs
straight from the GCS state (`terraform output`) to build the in-cluster
`azure-monitor-credentials` Secret, so those backend credentials never become
GitHub secrets.

## State

GCS remote state in the bootstrap state bucket, prefix
**`jenkins-2026/azure-managed-grafana`** (same bucket as `terraform/gke`).

## Key inputs

- `subscription_id`, `tenant_id` (required). Only identifiers
  (`AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID`/
  `AZURE_GRAFANA_ADMIN_OBJECT_IDS`) are GitHub secrets.
- `resource_group_name`, `location` (default `spaincentral`), `grafana_location`
  (default `francecentral`), `name_prefix`, `grafana_admin_object_ids` (Entra
  object IDs granted Grafana Admin).

## Key outputs (read by Day1 → `azure-monitor-credentials` Secret)

- `azure_monitor_connection_string` (App Insights → traces+logs, sensitive),
  `azure_monitor_prometheus_endpoint` (remote-write URL with the required
  `api-version`), `azure_tenant_id`, `azure_client_id`, `azure_client_secret`
  (sensitive), `grafana_endpoint` (→ `GRAFANA_BASE_URL`), `grafana_name`,
  `resource_group_name`, `grafana_identity_principal_id`.
