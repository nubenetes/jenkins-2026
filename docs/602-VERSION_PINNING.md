[← Previous: 601. DevSecOps](./601-DEVSECOPS.md) | [🏠 Home](../README.md) | [→ Next: 901. Local Development](./901-LOCAL_DEVELOPMENT.md)

---

# 602. Version Pinning & Supply-Chain Reproducibility

Every external dependency this project pulls — Helm charts, container images, CLI
tools, GitHub Actions, Terraform providers — is **pinned to an exact version**, with
**one deliberate exception (ArgoCD)**. The goal: a re-run of `Day1.cluster.01` (or
`scripts/up.sh` locally) deploys the *same* bits every time, so behaviour is
reproducible and a moving upstream tag can never silently break or change the stack.

## Why pin — and the trade-off

| | Pinning to an exact version | Tracking `latest` / a floating tag |
|---|---|---|
| **Reproducibility** | ✅ Same inputs → same result, every run | ❌ The same commit can deploy differently next week |
| **Failure mode** | ✅ Upgrades happen on *your* schedule, reviewed | ❌ Silent breakage mid-run, hard to bisect |
| **Supply chain** | ✅ A moved/retagged image or action can't inject change | ❌ A compromised or moved tag flows straight in |
| **Security patches** | ⚠️ You must bump deliberately (Dependabot helps) | ✅ Picked up automatically |
| **Maintenance** | ⚠️ Periodic bumps + lockfile updates | ✅ Zero effort (until it breaks) |

We accept the maintenance cost for reproducibility and a controlled blast radius.
This isn't theoretical — every floating version here has bitten us at least once:

- **Jenkins chart was `""` (latest)** → it silently moved to 5.9.x, which split
  `authorizationStrategy`/`securityRealm` into their own ConfigMaps and crashed JCasC
  at boot (`Single entry map expected … found multiple entries`). Pinned to `5.9.29`.
  See [401. Jenkins](./401-JENKINS.md).
- **`az` CLI extension (unpinned)** started sending a retired ARM api-version
  (`InvalidApiVersionParameter`) and broke the Azure dashboard publish.
- **`yq` from `releases/latest/download`** could change behaviour between two runs of
  the same workflow.

## The matrix

`Mechanism` = how the pin is enforced. `Source of truth` = where you change it.

| Component | Pinned to | Source of truth | Mechanism |
|---|---|---|---|
| **Jenkins** chart | `5.9.29` | `config/config.yaml` `jenkins.chart.version` | ArgoCD `targetRevision` ([`jenkins-app.yaml`](../argocd/jenkins-app.yaml)) |
| **ArgoCD** *(exception)* | **tracks `3.5.x`** | `config/config.yaml` `argocd.version_constraint` | runtime resolve + daily watcher — see below |
| **OTel operator** chart | `0.117.0` | `config.yaml` `observability.otelOperator.chart.version` | `helm --version` in [`02-otel-operator.sh`](../scripts/02-otel-operator.sh) |
| **OTel collector** chart | `0.159.0` | `config.yaml` `observability.otelCollector.chart.version` | `helm --version` in [`03-observability.sh`](../scripts/03-observability.sh) |
| **grafana/k8s-monitoring** | `4.1.6` | `03-observability.sh` (`--version`) | grafana-cloud mode only |
| **grafana/pdc-agent** | `0.2.0` | `03-observability.sh` (`--version`) | grafana-cloud mode only |
| **Headlamp** chart | `0.43.0` | `config.yaml` `headlamp.chart.version` + [`headlamp-app.yaml`](../argocd/headlamp-app.yaml) | ArgoCD `targetRevision` |
| **kube-prometheus-stack / Loki / Tempo** | `87.0.1 / 7.0.0 / 1.24.4` | [`argocd/observability-oss/values.yaml`](../argocd/observability-oss/values.yaml) | ArgoCD `targetRevision` |
| **CloudNativePG** chart | pinned | [`argocd/platform-postgres/values.yaml`](../argocd/platform-postgres/values.yaml) | ArgoCD `targetRevision` |
| **Argo Rollouts** | `2.37.7` | [`argo-rollouts-app.yaml`](../argocd/argo-rollouts-app.yaml) | ArgoCD `targetRevision` |
| **External Secrets** | `0.12.1` | [`external-secrets-app.yaml`](../argocd/external-secrets-app.yaml) | ArgoCD `targetRevision` |
| **Tekton** pipelines/triggers/dashboard/… | `v1.13.1` / `v0.36.0` / `v0.69.0` / … | `config.yaml` `tekton.versions` + **vendored** [`argocd/tekton/components/`](../argocd/tekton/) | pinned release YAML, applied by `04-tekton.sh` |
| **Tekton task images** | `alpine/git:2.54.0`, `codeql-container:@c6f3f8cb…` | [`tekton/tasks/*.yaml`](../tekton/tasks/) | image tag/digest |
| **`yq`** (CI) | `v4.53.3` | `.github/workflows/*` | release-download URL |
| **GitHub Actions** | full commit SHA (`@<sha> # vX`) | `.github/workflows/*` | SHA pin + [`dependabot.yml`](../.github/dependabot.yml) |
| **Terraform providers** | exact (per lockfile) | `terraform/*/.terraform.lock.hcl` | committed lockfiles + `~> X.0` in `versions.tf` |

> The `helm --version` wiring uses `${VAR:+--version=$VAR}` — if the config value were
> ever blanked it falls back to the chart repo's latest (same as before the pin), so
> the pin is additive and can't break the install.

## The ArgoCD exception — deliberate 3.5.x tracking

ArgoCD is intentionally **not** hard-pinned: we track the **`3.5.x`** line to get its
new features *and* its ongoing patches (3.5.0 currently ships only as a release
candidate that is being patched). The trade-off — less deterministic than a pin — is
accepted **for ArgoCD only**. Three mechanisms keep it current, all reading the same
`config/config.yaml` `argocd.version_constraint`:

1. **Day1** (`scripts/08.5-argocd.sh` → `resolve_argocd_version`): at install it queries
   the GitHub Releases API and picks the **latest stable** `3.5.x` (e.g. `v3.5.1`), or
   the **newest rc** while no `3.5.x` GA exists yet. So the moment `v3.5.0` GA ships, a
   fresh Day1 installs it; later `v3.5.x` patches likewise.
2. **Day2** (`Day2.redeploy.01-argocd`): re-runs `08.5-argocd.sh` → same resolution, in
   place, without recreating the cluster.
3. **Automatic, no re-run** ([`argocd-version-patch-watcher.yaml`](../argocd/argocd-version-patch-watcher.yaml)):
   a daily CronJob in the `argocd` namespace resolves the latest `3.5.x` and, if it
   differs from the running `argocd-server` image, **live-patches** every ArgoCD
   Deployment/StatefulSet to the new tag. GA preferred, rc fallback.

The watcher's constraint is **templated from config** by `08.5-argocd.sh` (it
substitutes `__ARGOCD_CONSTRAINT__`), so Day1, Day2 and the watcher can never drift —
change `argocd.version_constraint` in one place and all three follow. To go back to a
hard pin (e.g. once 3.5 stabilises), set the constraint to an exact `3.5.N` line and/or
remove the watcher.

## GitHub Actions: SHA pins + Dependabot

Every `uses:` is pinned to a **full 40-char commit SHA** with a trailing `# vX`
comment (e.g. `actions/checkout@34e1148… # v4`). A moved major-version tag (the usual
`@v4`) can no longer change what runs in CI. [`.github/dependabot.yml`](../.github/dependabot.yml)
runs the `github-actions` ecosystem weekly (grouped into one PR) and bumps the SHA +
the `# vX` comment together — so we keep immutability **and** timely updates without
hand-resolving SHAs.

## Terraform: lockfiles are the pin

`versions.tf` declares `~> X.0` ranges, but the **committed `.terraform.lock.hcl`** in
each module records the *exact* provider versions (and their checksums). `terraform
init` honours the lockfile, so every run uses identical providers. Bump with
`terraform init -upgrade` then commit the updated lockfile.

## How to bump a pin

| Type | How |
|---|---|
| Helm chart in `config.yaml` | edit the `…chart.version`, re-run Day1 (or the matching `Day2.redeploy`) |
| ArgoCD-app chart (`argocd/*`) | edit `targetRevision` / the app-of-apps `values.yaml`, sync |
| Tekton component | bump `config.yaml` `tekton.versions` **and** re-vendor `argocd/tekton/components/*` |
| Tekton task image / `yq` | edit the tag / release URL |
| GitHub Action | let Dependabot PR it (or edit the SHA + `# vX`) |
| Terraform provider | `terraform init -upgrade` + commit `.terraform.lock.hcl` |
| ArgoCD line | edit `argocd.version_constraint` (tracks automatically thereafter) |

## Known residual

`az extension add -n amg / resource-graph` (in the Azure dashboard workflows) is not
version-pinned — Azure CLI extensions auto-update and `--version` pinning is brittle.
Risk is low now that the Azure publish path uses the Grafana **data-plane API** rather
than the fragile `az grafana` ARM subcommands (see [301. Observability](./301-OBSERVABILITY.md)).

---

[← Previous: 601. DevSecOps](./601-DEVSECOPS.md) | [🏠 Home](../README.md) | [→ Next: 901. Local Development](./901-LOCAL_DEVELOPMENT.md)

---

*602. Version Pinning & Supply-Chain Reproducibility — jenkins-2026*
