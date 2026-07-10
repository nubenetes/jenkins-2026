[← Previous: 601. DevSecOps](./601-DEVSECOPS.md) | [🏠 Home](../README.md) | [→ Next: 901. Local Development](./901-LOCAL_DEVELOPMENT.md)

---

# 602. Version Pinning & Supply-Chain Reproducibility

Every external dependency this project pulls — Helm charts, container images, CLI
tools, GitHub Actions, Terraform providers — is **pinned to an exact version**, with
**one deliberate exception (ArgoCD)** and a short list of known residuals (see
[Known residuals](#known-residuals)). The goal: a re-run of `Day1.cluster.01` (or
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

We accept the maintenance cost for **reproducibility and a controlled blast radius**.
This isn't theoretical — **every floating version here has bitten us at least once**:

- **Jenkins chart was `""` (latest)** → it silently moved to 5.9.x, which split
  `authorizationStrategy`/`securityRealm` into their own ConfigMaps and crashed JCasC
  at boot (`Single entry map expected … found multiple entries`). Pinned (originally
  `5.9.29`, now `5.9.32` — see the matrix). See [401. Jenkins](./401-JENKINS.md).
- **`az` CLI extension (unpinned)** started sending a retired ARM api-version
  (`InvalidApiVersionParameter`) and broke the Azure dashboard publish.
- **`yq` from `releases/latest/download`** could change behaviour between two runs of
  the same workflow.

## The matrix

`Mechanism` = how the pin is enforced. `Source of truth` = where you change it.

| Component | Pinned to | Source of truth | Mechanism |
|---|---|---|---|
| **Jenkins** chart | `5.9.32` | `config/config.yaml` `jenkins.chart.version` | ArgoCD `targetRevision` ([`jenkins-app.yaml`](../argocd/jenkins-app.yaml)) |
| **Jenkins plugins** (full set, exact) | per [`helm/jenkins/values-common.yaml`](../helm/jenkins/values-common.yaml) `controller.installPlugins` | same file | `jenkins-plugin-cli`-resolved against `controller.image.tag`; **bump deliberately** — incl. for security advisories (see below) |
| **ArgoCD** *(policy)* | **latest stable `3.4.x`** + chart `9.5.22` | `config/config.yaml` `argocd.version_constraint` + `chartVersion` | runtime resolve + daily watcher — see below |
| **OTel operator** chart | `0.117.0` | `config.yaml` `observability.otelOperator.chart.version` | `helm --version` in [`02-otel-operator.sh`](../scripts/02-otel-operator.sh) |
| **OTel collector** chart | `0.159.0` | `config.yaml` `observability.otelCollector.chart.version` | `helm --version` in [`03-observability.sh`](../scripts/03-observability.sh) |
| **grafana/k8s-monitoring** | `4.2.0` | `03-observability.sh` (`--version`) | grafana-cloud mode only |
| **grafana/pdc-agent** | `0.2.0` | `03-observability.sh` (`--version`) | grafana-cloud mode only |
| **Headlamp** chart | `0.43.0` | `config.yaml` `headlamp.chart.version` + [`headlamp-app.yaml`](../argocd/headlamp-app.yaml) | ArgoCD `targetRevision` |
| **kube-prometheus-stack / Loki / Tempo** | `87.0.1 / 7.0.0 / 1.24.4` | [`argocd/observability-oss/values.yaml`](../argocd/observability-oss/values.yaml) | ArgoCD `targetRevision` |
| **CloudNativePG** chart (operator) | `0.29.0` *(= operator `v1.30.0`; chart version lags the operator)* | [`argocd/platform-postgres/values.yaml`](../argocd/platform-postgres/values.yaml) | ArgoCD `targetRevision` |
| **PostgreSQL** (CNPG database image) | `18.3-system-trixie` | gitops `helm/microservices` `spec.imageName` (`global.postgresImage`) | image tag |
| **Argo Rollouts** | `2.37.7` | [`argo-rollouts-app.yaml`](../argocd/argo-rollouts-app.yaml) | ArgoCD `targetRevision` |
| **External Secrets** | `0.12.1` | [`external-secrets-app.yaml`](../argocd/external-secrets-app.yaml) | ArgoCD `targetRevision` |
| **Tekton** pipelines/triggers/dashboard/… | `v1.13.1` / `v0.36.0` / `v0.69.0` / … | `config.yaml` `tekton.versions` + **vendored** [`argocd/tekton/components/`](../argocd/tekton/) | pinned release YAML, applied by `04-tekton.sh` |
| **ARC** (`gha-runner-scale-set-controller` + `gha-runner-scale-set` OCI charts — **must match**) | `0.12.1` | [`argocd/githubactions/values.yaml`](../argocd/githubactions/values.yaml) `versions.arc` (reference copy in `config.yaml` `githubactions.versions.arc` — keep in sync) | ArgoCD `targetRevision` on both OCI Helm child apps (templates in [`argocd/githubactions/`](../argocd/githubactions/), applied via [`argocd/githubactions-app.yaml`](../argocd/githubactions-app.yaml) by `04-githubactions.sh` when `ci.engine=githubactions`) |
| **Argo Workflows + Argo Events** (vendored release YAMLs — **bump both together**) | `v3.7.16` (workflows) / `v1.9.4` (events) | `config.yaml` `argoworkflows.versions.{workflows,events}` + **vendored** [`argocd/argoworkflows/components/`](../argocd/argoworkflows/) | pinned release YAML, applied by `04-argoworkflows.sh` when `ci.engine=argoworkflows`. Stays on the **3.7.x** line: Argo Workflows 4.0 ships full-schema CRDs (the `Workflow` CRD alone is ~2.6 MB) that exceed GKE's ~1.5 MB etcd object limit — revisit when 4.1.x ships the CRD-size fix |
| **CI agent images** (shared across three engines — Jenkins pod templates · Tekton tasks · Argo Workflows; the **ARC engine builds runner-native** instead: `actions/setup-java` Temurin 21 for JDK parity, `docker run` semgrep/trivy, CodeQL via `github/codeql-action` — see [404. GitHub Actions](./404-GITHUB_ACTIONS.md) and Known residuals) | maven `3.9.9`, node `20-bookworm`, docker `26-dind`, alpine/k8s `1.31.3`, semgrep `1.79.0`, trivy `0.52.2`, k6 `2.0.0`, `alpine/git:2.54.0`, `codeql-container@c6f3f8cb…` | [`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy) · [`tekton/tasks/*.yaml`](../tekton/tasks/) · [`argoworkflows/`](../argoworkflows/) | image tag/digest (the three engines share the same git + codeql pins) |
| **`yq`** (CI) | `v4.53.3` | `.github/workflows/*` | release-download URL |
| **GitHub Actions** | full commit SHA (`@<sha> # vX`) | `.github/workflows/*` | SHA pin + [`dependabot.yml`](../.github/dependabot.yml) |
| **Terraform providers** | exact (per lockfile) | `terraform/*/.terraform.lock.hcl` | committed lockfiles + `~> X.0` in `versions.tf` |

> The `helm --version` wiring uses `${VAR:+--version=$VAR}` — if the config value were
> ever blanked it falls back to the chart repo's latest (same as before the pin), so
> the pin is additive and can't break the install.

## The ArgoCD version policy — pinned to stable 3.4.x

ArgoCD is **not** hard-pinned to a single patch like the rest of the stack; it **tracks
the latest stable `3.4.x`** (the newest *GA* patch of the 3.4 line, picked up
automatically). It is **deliberately NOT on the 3.5 line**: `3.5.0` has **no GA yet**
(only release candidates), and **`v3.5.0-rc1` shipped multiple controller bugs** that
broke this stack:

- the Lua health-check sandbox lacked the `string` library → a `string.find` in our CNPG
  `Cluster` health check raised a **`ComparisonError`**, leaving `microservices-stable`
  stuck `Unknown` (see [902](./902-TROUBLESHOOTING.md));
- completed Helm-**hook** Jobs weren't recognised under **k8s 1.35** Job conditions → the
  kube-prometheus-stack admission-webhook hooks never "completed" and **wedged every sync**;
- sync operations themselves wedged in `Running`.

So we run the **stable 3.4 line** until 3.5 is GA. The old `version_constraint: "3.5.x"`
auto-resolved to the **rc** precisely because 3.5 has no GA (the resolver falls back to
rc when no GA matches); `"3.4.x"` only ever resolves to a **GA**, so we get stable
patches automatically and **never an rc**.

Two version knobs, both under `config/config.yaml` `argocd`:
- **`version_constraint: "3.4.x"`** — the **image** (binary) tracks the latest 3.4.x GA.
- **`chartVersion: "9.5.22"`** — the **argo-cd Helm chart** is pinned to the 3.4.x line
  (chart `9.5.x` ships ArgoCD `3.4.x`; `9.6+`/`10.x` ship `3.5.x`/`3.6.x`). Pinned so the
  chart's bundled CRDs/RBAC/templates match the pinned binary — otherwise
  `08.5-argocd.sh` installs the *latest* chart, pairing 3.5/3.6 CRDs with a 3.4 binary.

Three mechanisms keep the **image** current within 3.4.x, all reading the same constraint:

1. **Day1** (`scripts/08.5-argocd.sh` → `resolve_argocd_version`): queries the GitHub
   Releases API and picks the **latest stable** `3.4.x` (e.g. `v3.4.4`).
2. **Day2** (`Day2.redeploy.01-argocd`): re-runs `08.5-argocd.sh` → same resolution, in place.
3. **Automatic, no re-run** ([`argocd-version-patch-watcher.yaml`](../argocd/argocd-version-patch-watcher.yaml)):
   a daily CronJob resolves the latest `3.4.x` and live-patches the ArgoCD workloads if the
   running image differs. The constraint is **templated from config** by `08.5-argocd.sh`
   (`__ARGOCD_CONSTRAINT__`), so Day1, Day2 and the watcher never drift.

> **⚠️ Moving to 3.5.x (ONLY when `3.5.0` is GA — do NOT move while 3.5 is still rc):**
> bump all three knobs **together** (chart + binary must move together):
>
> - `argocd.version_constraint` → `"3.5.x"`
> - `argocd.version` → the GA tag
> - `argocd.chartVersion` → the matching `9.6+`/`10.x` chart
>
> Then **re-verify the features that were disabled to dodge the rc1 bugs**:
>
> - the kube-prometheus-stack `admissionWebhooks` (re-enabled in
>   `observability/grafana/values-oss.yaml`) sync cleanly;
> - the CNPG `Cluster` health check still computes.

## GitHub Actions: SHA pins + Dependabot

Every `uses:` is pinned to a **full 40-char commit SHA** with a trailing `# vX`
comment (e.g. `actions/checkout@9c091bb2… # v7.0.0`). A moved major-version tag (the usual
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
| Jenkins plugin | edit its version in `values-common.yaml` `controller.installPlugins`, re-run `Day2.redeploy.02-jenkins`. *Manage Jenkins → Plugins → Updates* surfaces available updates **and security advisories** — pinned plugins don't self-update, so apply advisory fixes here (bump interdependent security plugins together). A wholesale refresh = re-run the `jenkins-plugin-cli` recipe in the `installPlugins` comment against `controller.image.tag` |
| ArgoCD-app chart (`argocd/*`) | edit `targetRevision` / the app-of-apps `values.yaml`, sync |
| Tekton component | bump `config.yaml` `tekton.versions` **and** re-vendor `argocd/tekton/components/*` |
| Argo Workflows / Argo Events | bump `config.yaml` `argoworkflows.versions.{workflows,events}` **and** re-vendor `argocd/argoworkflows/components/{workflows,events}/release.yaml` (bump both together) |
| Tekton task image / `yq` | edit the tag / release URL |
| GitHub Action | let Dependabot PR it (or edit the SHA + `# vX`) |
| Terraform provider | `terraform init -upgrade` + commit `.terraform.lock.hcl` |
| ArgoCD line | edit `argocd.version_constraint` (tracks automatically thereafter) |

## Known residuals

- **`az extension add -n amg / resource-graph`** (in the Azure dashboard workflows) is **not
  version-pinned** — Azure CLI extensions auto-update and `--version` pinning is brittle.
  Risk is low now that the Azure publish path uses the Grafana **data-plane API** rather
  than the fragile `az grafana` ARM subcommands (see [301. Observability](./301-OBSERVABILITY.md)).
- The **fork-rendered ARC workflow**
  ([`jenkins/pipelines/seed/microservices-ci.yml.tmpl`](../jenkins/pipelines/seed/microservices-ci.yml.tmpl))
  tag-pins its `uses:` actions (`@v4`/`@v3`, not SHAs — this repo's Dependabot never sees the
  rendered copies living in the app forks) and runs the **untagged** `aquasec/trivy` image
  for the IaC + image scans. (Its semgrep image *is* pinned — `semgrep/semgrep:1.79.0`.)

---

[← Previous: 601. DevSecOps](./601-DEVSECOPS.md) | [🏠 Home](../README.md) | [→ Next: 901. Local Development](./901-LOCAL_DEVELOPMENT.md)

---

*602. Version Pinning & Supply-Chain Reproducibility — jenkins-2026*
