# terraform/bootstrap

The **root of trust** — Day0 "phase 0", the one-command human-run step every
other tier depends on. It creates the durable, cluster-independent singletons:
the GCS Terraform **state bucket** (holding every other module's remote state),
the GitHub **OIDC / Workload Identity Federation** pool + provider + CI service
account (so all CI authenticates keyless — no JSON keys), the **Postgres backups
bucket** (`<project_id>-jenkins-2026-postgres-backups`, kept for CNPG recovery),
and the **permanent delegated public DNS zone** (`google_dns_managed_zone.public`
for `base_domain`, so its nameservers never change across gateway rebuilds). See
[`docs/100-BOOTSTRAP.md`](../../docs/100-BOOTSTRAP.md).

## Lifecycle owner — HUMAN-RUN, one-time (never in CI)

Applied and destroyed **only** by [`scripts/bootstrap.sh`](../../scripts/bootstrap.sh)
(`up` / `down`), run by hand from a workstation. This is the "bootstrap paradox":
CI can't create the WIF trust + state bucket that CI itself needs, so it can't be
a workflow. `bootstrap.sh down` is the symmetric root teardown (state → local,
`terraform destroy` with `state_bucket_force_destroy=true`, then delete the four
GitHub secrets).

## State — local seed, then migrated to GCS

`terraform apply` first runs with **local state**, then `bootstrap.sh` **migrates
that state into the state bucket** it just created (prefix `jenkins-2026/bootstrap`,
via a gitignored `backend_override.tf`), so even bootstrap is remote-state going
forward — self-hosting, no fragile local `.tfstate` to lose. (The versions.tf
header describes only the pre-migration seed step.)

> **Danger — never blind-`terraform apply` here.** These are named, persistent
> singletons. A re-apply against lost/stale state 409s "already exists" per
> resource and can orphan or duplicate them. Always check the existing (migrated)
> state first; recovery is `terraform import`, not recreate. Do not wire this into
> any workflow.

## Key inputs

- `project_id` (required) — same project `terraform/gke` deploys into.
- `base_domain` (default `jenkins2026.nubenetes.com`) — the delegated DNS zone;
  must match `config/config.yaml` `gateway.baseDomain` and `terraform/gateway-bootstrap`.
- `github_repo`, `ci_service_account_id`, `workload_identity_pool_id`,
  `state_bucket_name`, `state_bucket_force_destroy` (the last set `true` by
  `bootstrap.sh down`).

## Key outputs (become the four GitHub secrets/variables)

- `state_bucket` → `TF_STATE_BUCKET`
- `ci_service_account_email` → `GCP_SERVICE_ACCOUNT`
- `workload_identity_provider` → `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `project_id` → `GCP_PROJECT_ID`
- `dns_zone_name_servers` — the one-time parent-domain `NS` delegation targets
  (never change).
