# terraform/grafana-cloud-stack

The **`observability.mode=grafana-cloud` backend** — creates the Grafana Cloud
stack that the OTel pipeline sends telemetry to and that dashboards are imported
into. The stack slug is **Terraform-generated** (`<prefix><random-suffix>` →
`https://<slug>.grafana.net`) so a destroy+recreate never collides with Grafana
Cloud's reserved-slug cooldown. This is the grafana-cloud analogue of the
`azure-managed-grafana` / `aws-managed-grafana` bootstrap-tier backends. The
Grafana Cloud org/account (free tier) is created once by hand and never managed
here — only the stack. See [`docs/301`](../../docs/301-OBSERVABILITY.md).

## Lifecycle owner

Applied **one-time** by **`Day0.infra.02-grafana-cloud.yml`**, destroyed by
**`Decom.infra.02-grafana-cloud.yml`** — the persistent bootstrap tier, exactly
like the Azure/AWS backends. Ephemeral (no delete protection). Re-applying is a
no-op; a destroy+recreate mints a fresh slug.

## State

GCS remote state in the bootstrap state bucket, prefix
**`jenkins-2026/grafana-cloud-stack`** (same bucket as `terraform/gke`).

## Key inputs

- `grafana_cloud_api_token` (sensitive) — org-level Access Policy token
  (`GRAFANA_CLOUD_API_TOKEN` GitHub secret), also used by `grafana-cloud-token`.
- `stack_slug_prefix` (default `jenkins2026obs`), `region_slug` (default
  `prod-eu-west-3`).

## Key outputs (read from state, not GitHub secrets)

- `stack_slug` — the generated subdomain. **`Day1.cluster.01-gke` reads it from
  this module's state** (`terraform output -raw stack_slug`) and passes it to
  `terraform/grafana-cloud-token`, which looks the stack up by slug. There is
  deliberately **no** `GRAFANA_CLOUD_STACK_SLUG` secret/variable.
- `stack_id` (OTLP Basic-auth username), `otlp_endpoint`, `grafana_url`,
  `org_slug`, `region_slug`.
