# terraform/workload-identity

Standalone **GKE Workload Identity Federation** helper — a keyless-auth reference
module wiring a GitHub Actions OIDC pool + a shared CI/agent GCP service account
to in-cluster Kubernetes ServiceAccounts. It exists as a compact, self-contained
illustration of the zero-trust pattern the rest of the repo uses (no static JSON
keys anywhere). See [`docs/501` § Zero-Trust Security & Workload Identity](../../docs/501-PLATFORM_OPERATIONS.md#3-zero-trust-security--workload-identity)
and [`docs/102`](../../docs/102-GITHUB_ACTIONS_AUTOMATION.md).

## AUXILIARY / MANUAL — not in CI, not the real CI trust

**No workflow applies or destroys this module**, and `scripts/up.sh` does not run
it. It is manual/auxiliary. The **real** GitHub→GCP CI trust — the pool, provider
and service account the whole lifecycle actually authenticates through — lives in
[`terraform/bootstrap`](../bootstrap) (Day0, human-run). Do not confuse the two:

- This module's pool is **`github-actions-pool-2026`** with provider
  `github-actions-provider` and SA **`jenkins-2026-ci-agent`**.
- `terraform/bootstrap`'s pool is **`jenkins-2026-github`** (provider
  `github-actions`) with SA **`jenkins-2026-ci`**.

They are distinct GCP resources. Applying this module during a Day0 does **not**
replace or update the bootstrap trust; running it against the same project simply
creates a second, parallel pool + SA. Treat it as a lab/example — apply it only
if you deliberately want that separate identity, not as part of standing the
platform up.

## Layout & state

- Single file, `workload_identity.tf` (provider block + variables + resources) —
  there is intentionally **no `versions.tf`, `outputs.tf` or backend block**.
- **State is local only** (`terraform.tfstate`, gitignored). No GCS backend, no
  remote-state prefix — reflecting its manual, out-of-band status.

## Inputs

- `project_id` — GCP project.
- `github_repo` — `org/repo` allowed to assume the SA (attribute condition
  `assertion.repository == <github_repo>`).

## What it grants

The `jenkins-2026-ci-agent` SA is bound `roles/secretmanager.secretAccessor` and
is impersonable by (a) the `github_repo` GitHub principal set, (b) the
`jenkins/jenkins-agent` KSA, and (c) the `external-secrets/external-secrets` KSA.
No outputs are exported.

## Run (by hand only)

```bash
cd terraform/workload-identity
terraform init
terraform apply -var project_id=<project> -var github_repo=nubenetes/jenkins-2026
```
