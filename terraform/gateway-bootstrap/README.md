# terraform/gateway-bootstrap

The **persistent Gateway resources** — the public-endpoint infrastructure that
survives cluster rebuilds so the URLs come back with **no manual DNS**. It
provisions the global static external IP, the Certificate Manager wildcard cert +
DNS authorization + cert map, **and** the wildcard-A and cert-validation-CNAME
records inside the permanent delegated DNS zone (created by
[`terraform/bootstrap`](../bootstrap), referenced by the fixed name
`jenkins-2026-public-zone`). Because the zone (hence the one-time parent-domain
`NS` delegation) lives in the never-destroyed root tier, only the records churn
on a rebuild — the delegation is done once, ever. See
[`docs/501`](../../docs/501-PLATFORM_OPERATIONS.md) and
[`docs/503`](../../docs/503-NETWORKING.md).

## Lifecycle owner

Applied by **`Day0.infra.01-gateway.yml`** and re-reconciled to the current IP on
every **`Day1.cluster.00-all`** run; destroyed by **`Decom.infra.01-gateway.yml`**
(the records drop and are recreated on rebuild; the zone persists). Re-running
`terraform apply` against existing state is a safe no-op. It can also be run
locally with this directory's own local state.

> Note: `scripts/09-gateway.sh` (Day1) does **not** run this module — it only
> references the outputs by their fixed resource names (`jenkins-2026-gateway-ip`,
> `jenkins-2026-cert-map`) via `config/config.yaml` `gateway.staticIPName` /
> `gateway.certMapName`. The IAP OAuth client is a separate, manual Console step.

## State

GCS remote state in the bootstrap state bucket, prefix
**`jenkins-2026/gateway-bootstrap`** (via a `backend_override.tf` the workflows
write) — or local `terraform.tfstate` when run by hand.

## Key inputs

- `project_id` (required — must match `terraform/gke`).
- `base_domain` (default `jenkins2026.nubenetes.com`; wildcard cert covers it and
  `*.<base_domain>`) — must match `config/config.yaml` `gateway.baseDomain` and
  `terraform/bootstrap`.

## Key outputs

- `static_ip_address` / `static_ip_name` (→ `config.yaml` `gateway.staticIPName`),
  `certmap_name` (→ `gateway.certMapName`), and `dns_authorization_record`
  (cert-validation CNAME, now auto-created — exposed for reference/debugging only).
