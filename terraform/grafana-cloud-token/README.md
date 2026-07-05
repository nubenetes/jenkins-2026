# terraform/grafana-cloud-token

The **ephemeral, per-cluster credentials** for `observability.mode=grafana-cloud`
— the tokens the Day1 workflow puts into the in-cluster `grafana-cloud-credentials`
Secret. It mints (a) an access-policy token scoped to the persistent stack from
[`terraform/grafana-cloud-stack`](../grafana-cloud-stack) (metrics/logs/traces/
profiles `:write`, used as the OTLP gateway's Basic-auth password) and (b) a stack
service-account token (Editor, used by `scripts/07-grafana-dashboards.sh` to push
dashboards over the Grafana HTTP API), plus a PDC network token. It **never
touches the stack itself** — it looks it up by slug via a data source. Same
GCS-remote-state-via-`backend_override.tf` pattern as `terraform/gke`. See
[`docs/301`](../../docs/301-OBSERVABILITY.md).

## Lifecycle owner

Applied by **`Day1.cluster.01-gke.yml`** (after the cluster is provisioned),
destroyed by **`Decom.cluster.01-gke.yml`** (revoking both tokens) — the
per-cluster tier, unlike the stack it draws from (which is Day0/persistent).

## State

GCS remote state in the bootstrap state bucket, prefix
**`jenkins-2026/grafana-cloud-token`** (via `backend_override.tf` written by both
workflows, so the destroy run finds what the apply run created).

## Key inputs

- `grafana_cloud_api_token` (sensitive) — the same org-level token as
  `grafana-cloud-stack` (`GRAFANA_CLOUD_API_TOKEN`).
- `stack_slug` — the generated slug, read from `grafana-cloud-stack`'s state
  output by CI and passed in (no longer a GitHub secret/variable).
- `jenkins_admin_password` (sensitive) — for the datasource configuration.

## Key outputs (→ the `grafana-cloud-credentials` Secret)

- `otlp_endpoint` (`GRAFANA_CLOUD_OTLP_ENDPOINT`), `otlp_auth` (Basic-auth,
  sensitive), `grafana_base_url`, `grafana_api_key` (dashboard-push SA token,
  sensitive), `stack_id`, plus `pdc_token` / `pdc_cluster`.
