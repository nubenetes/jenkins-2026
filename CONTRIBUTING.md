# Contributing to jenkins-2026

Thanks for your interest in the project. This is a reference Jenkins-on-Kubernetes
PoC with four interchangeable CI engines and four observability backends; a lot of
its behaviour is **enforced by CI, not just documented**. This guide is the short
version of the rules a contribution has to follow — enough to open a PR that will
actually merge. The deep design docs live under [`docs/`](docs/) (indexed from the
[`README.md`](README.md)); this page links them rather than duplicating them.

> **New here?** Skim [`README.md`](README.md) first (the "For newcomers" on-ramp
> and the Document Inventory), then come back for the process. Standing the
> platform up locally is [`docs/901-LOCAL_DEVELOPMENT.md`](docs/901-LOCAL_DEVELOPMENT.md).

---

## 1. Branch model — `main` is reached only through `develop`

This repo runs **strict GitFlow**. `main` is protected and reachable **only via a
pull request whose head branch is exactly `develop`**:

- **Require a pull request before merging** on `main`.
- The **`gitflow-guard`** required status check
  ([`.github/workflows/gitflow-guard.yml`](.github/workflows/gitflow-guard.yml))
  fails any PR into `main` whose head is not `develop` — a `feature/*`, `hotfix/*`
  or fork branch targeting `main` directly is rejected with a "Gitflow violation"
  error.
- **`enforce_admins=true`** — even a maintainer can't push straight to `main` or
  bypass the check.

So every change lands like this:

```
your change  →  branch off develop  →  PR into develop  →  (merge)
                                     →  PR develop → main  →  (promote / release)
```

Do **not** open a PR from a feature branch straight into `main` — CI will reject
it, and the only human-readable explanation lives here and in the workflow's error
message. Branch off `develop`, merge to `develop` first, then a **`develop → main`
promotion PR** carries the change to `main`.

<details>
<summary>Why the companion <code>gitops-config</code> repo is the exact opposite (don't "fix" it)</summary>

The application-deployment repo **`jenkins-2026-gitops-config`** deliberately has
the **opposite** `main` policy: **direct-push** `main` (no require-PR; force-push
still blocked). Every CI engine's *GitOps Update* stage does
`git push origin main` to bump the deployed image tag, and a require-PR rule there
would reject that push (the CI PAT doesn't bypass branch protection) and **wedge
every deploy**. Image-tag bumps are machine-managed, not human-reviewed, so that
repo's `main` must accept the direct push.

The two policies are intentional and must not be reconciled to match. See
[`docs/502-MICROSERVICES_GITOPS.md`](docs/502-MICROSERVICES_GITOPS.md) and the
`gitops-config` repo's README. The app **forks**
(`jhipster-sample-app-gateway` / `-microservice`) carry a third, lighter policy
(force-push/deletion blocked, no require-PR) for the same CI-direct-push reason —
see [`docs/405-GITHUB_ACTIONS.md`](docs/405-GITHUB_ACTIONS.md) § Security.
</details>

---

## 2. The idempotency contract

**Every `scripts/0N-*.sh` step, every Terraform module, and every workflow must be
safe to re-run.** This is not a style preference — it's the platform's change-apply
mechanism:

- [`scripts/up.sh`](scripts/up.sh) re-runs every numbered step in order on each
  provision; [`scripts/down.sh`](scripts/down.sh) tears them down in reverse.
- **Applying a change = re-run, not tear-down-and-rebuild.** The CI `Day1`
  workflow (and `up.sh` locally) converges in place on an existing cluster:
  `terraform apply` no-ops when a resource is already in state, `up.sh` re-applies
  every step, and ArgoCD re-syncs from git. `Decom` is only for stopping charges
  when you're done, never a prerequisite for a change.

Practically, when you add or edit a step:

- Guard `kubectl create` / `helm install` so a second run updates instead of
  erroring (`kubectl apply`, `helm upgrade --install`, `create ... --dry-run |
  apply`, or an explicit "already exists" check).
- Make Terraform converge, not duplicate — a re-`apply` on existing state must be
  a no-op, not a second resource.
- A **rebuild** (`Decom` then `Day1`) must not collide with persistent/external
  state or leave residue that blocks the next rebuild. That whole bug class and
  the mechanisms that neutralise it (random-suffix slugs, `ignore_changes`,
  tombstone-adoption, guarded fresh-provision cleanup, …) are catalogued in
  [`docs/104-REBUILD_SAFETY.md`](docs/104-REBUILD_SAFETY.md); read it before
  adding any resource with a fixed identity outside the cluster.

---

## 3. The feature-flag pattern — never an ad-hoc flag

Every configurable axis follows **one** pattern; add new knobs the same way rather
than inventing a bespoke flag:

- **Durable default** lives in [`config/config.yaml`](config/config.yaml).
- **Ephemeral per-run override** is a `JENKINS2026_*` environment variable read by
  [`scripts/lib/config.sh`](scripts/lib/config.sh) (and exposed as a workflow
  input where it makes sense). It overrides the config file for a single run —
  the CI-matrix override pattern — without editing anything.

Existing examples to copy: `platform.target` / `JENKINS2026_PLATFORM`,
`observability.mode` / `JENKINS2026_OBS_MODE`, `ci.engine` / `JENKINS2026_CI_ENGINE`,
`secrets.backend` / `JENKINS2026_SECRETS_BACKEND`. `config.sh` loads the YAML with
`yq` and exports it as `J2026_*` env vars for the scripts to consume.

---

## 4. Conventions checklist

### Secrets hygiene

- **Never commit secret material.** The following are gitignored — keep them so:
  `observability/otel-collector/secret.yaml`, `**/secret.local.yaml`, `*.env`, all
  `*.tfstate*`, `**/.terraform/`, `terraform/*/terraform.tfvars`, and the
  CI-written `backend_override.tf` files.
- Ship a redacted template instead of a real file — `*.example.yaml` /
  `terraform.tfvars.example`. Extend [`.gitignore`](.gitignore) rather than
  committing a "just this once" example with real values.
- If a workflow starts consuming a **new** GitHub secret or variable, add it to
  the inventory in
  [`docs/103-GITHUB_SECRETS_INVENTORY.md`](docs/103-GITHUB_SECRETS_INVENTORY.md)
  (purpose, sensitivity, source, consuming workflows) in the same PR.

### Shell scripts

- `bash`, with **`set -euo pipefail` at the top of every script** (each
  `scripts/0N-*.sh` sets it, then sources
  [`scripts/lib/common.sh`](scripts/lib/common.sh) and
  [`scripts/lib/config.sh`](scripts/lib/config.sh) for logging + config).
- Use **`yq`** (the Go version) for any YAML manipulation — don't introduce a
  second YAML tool.
- New setup steps go in the numbered sequence and must honour the idempotency
  contract above.

### Terraform

- Run **`terraform fmt -recursive`** and **`terraform validate`** (after
  `terraform init -backend=false` when a module has no backend configured yet)
  before considering a change done.
- CI mirrors this: the **Terraform validate** check
  ([`.github/workflows/terraform-validate.yml`](.github/workflows/terraform-validate.yml))
  runs `fmt -check -recursive` plus `validate` against **every** module on any PR
  that touches `terraform/**` — a formatting or schema error blocks the PR before
  it ever reaches a real, billed cluster.

### Mermaid diagrams (docs)

- Run **[`scripts/verify-mermaid.sh`](scripts/verify-mermaid.sh)** (needs
  `mmdc` — `npm install -g @mermaid-js/mermaid-cli`) before considering a
  diagram change done; pass the touched files as args for a quick check.
- CI mirrors this: the **Mermaid validate** check
  ([`.github/workflows/mermaid-validate.yml`](.github/workflows/mermaid-validate.yml))
  renders **every** ` ```mermaid ` block in the repo on any PR that touches
  `*.md` — a diagram that would silently fail to render on GitHub (the classic:
  a bare `;` in sequenceDiagram note/message text) blocks the PR instead.

> ⚠️ [`terraform/bootstrap`](terraform/bootstrap) is a one-time, human-run module
> with local (then bucket-migrated) state — **never** wire it into CI, and never
> re-`apply` it without inspecting the existing state first (re-creating it orphans
> or duplicates persistent resources). See
> [`docs/100-BOOTSTRAP.md`](docs/100-BOOTSTRAP.md).

---

## 5. Running the checks locally

A PR gets three lightweight, credential-free checks. You can reproduce them
before pushing:

```bash
# Terraform (only if you touched terraform/**)
terraform fmt -recursive terraform/            # format in place (CI checks with -check)
find terraform -type f -name '*.tf' -not -path '*/.terraform/*' -printf '%h\n' \
  | sort -u | while read -r m; do
      terraform -chdir="$m" init -backend=false -input=false >/dev/null \
        && terraform -chdir="$m" validate
    done

# Mermaid diagrams (only if you touched *.md): render-verify every ```mermaid block.
# Needs mermaid-cli: npm install -g @mermaid-js/mermaid-cli
scripts/verify-mermaid.sh                      # or pass specific files as args

# Gitflow: nothing to run — just make sure your promotion PR's head branch is `develop`.
```

Both checks are visible as badges at the top of the [`README.md`](README.md)
("Gitflow Guard" and "Terraform validate"). The full local provisioning +
end-to-end test (`test/e2e.sh`) creates **real, billed GCP resources** and is not
part of the PR gate — only run it deliberately, per
[`docs/901-LOCAL_DEVELOPMENT.md`](docs/901-LOCAL_DEVELOPMENT.md).

---

## 6. Documentation & releases

- Deep docs are numbered `docs/NNN-TITLE.md` with header/footer prev/next
  navigation; a new numbered doc means updating the README Document Inventory (and
  the docs-count badge). The index and per-doc summaries are in the
  [`README.md`](README.md).
- Add a `CHANGELOG.md` bullet under `## [Unreleased]` (in the right group,
  citing the `(#NNN)`) when your PR merges to `develop` — see
  [`RELEASING.md`](RELEASING.md) for the versioning + release-cut convention
  (`Unreleased` → milestone minor → tag + GitHub release, 1:1, via
  [`scripts/cut-release.sh`](scripts/cut-release.sh)). Don't hand-create tags or
  releases; that's the maintainer's `develop → main` cut.

---

By contributing you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
