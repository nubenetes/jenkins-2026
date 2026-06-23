[← Previous: 402. Pipelines as Code](./402-PIPELINES_AS_CODE.md) | [🏠 Home](../README.md) | [→ Next: 501. Platform Operations](./501-PLATFORM_OPERATIONS.md)

---

# 403. Tekton (alternative CI engine)

This project ships **two interchangeable CI engines**. Jenkins is the default;
**Tekton** is the alternative, selected by a single feature flag. When Tekton is
chosen the platform installs Tekton Pipelines + Triggers + the official Tekton
Dashboard, exposes the Dashboard on the internet behind **Google IAP** (exactly
like Headlamp), and runs the **same microservices pipeline** ported to Tekton
Tasks/Pipelines under [`tekton/`](../tekton/).

## Selecting the engine

`ci.engine` in [`config/config.yaml`](../config/config.yaml) is the durable
default; `JENKINS2026_CI_ENGINE` is the ephemeral override — the same
durable-default + override pattern as `observability.mode` / `JENKINS2026_OBS_MODE`.

```yaml
# config/config.yaml
ci:
  engine: jenkins      # jenkins (default) | tekton
```

```bash
# one-off run with Tekton instead of Jenkins
JENKINS2026_CI_ENGINE=tekton scripts/up.sh
```

In CI, the **[`Day1.cluster.01-gke`](../.github/workflows/Day1.cluster.01-gke.yml)**
workflow exposes a `ci_engine` choice input (`jenkins` default, or `tekton`)
that flows to `scripts/up.sh` as `JENKINS2026_CI_ENGINE`. The two engines are
mutually exclusive on a given cluster.

`scripts/lib/config.sh` validates the value (`jenkins|tekton`) and exports
`J2026_CI_ENGINE`, which `up.sh`/`down.sh` and the numbered steps branch on:

| Step | `ci.engine=jenkins` | `ci.engine=tekton` |
|---|---|---|
| Install CI engine (`up.sh`) | `scripts/04-jenkins.sh` | [`scripts/04-tekton.sh`](../scripts/04-tekton.sh) |
| Seed pipelines (`up.sh`) | `scripts/06-seed-pipelines.sh` | [`scripts/06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh) |
| Day2 redeploy | `Day2.redeploy.02-jenkins` | [`Day2.redeploy.03-tekton`](../.github/workflows/Day2.redeploy.03-tekton.yml) |
| Teardown (`down.sh`) | Helm uninstall | engine-agnostic (removes both) |

**The two engines are mutually exclusive.** A clean install only deploys the
selected engine (`up.sh` branches on `ci.engine`, so Jenkins is never installed
in tekton mode). Switching engines on a *running* cluster **decommissions the
other one**: `scripts/04-tekton.sh` retires Jenkins if present (Helm uninstall +
removes the Jenkins gateway route/IAP/health-check), and `scripts/04-jenkins.sh`
retires Tekton if present (control-plane + pipeline namespaces + Tekton gateway
route/IAP). This runs on both `up.sh` and the `Day2.redeploy.*` paths. The
shared microservices are GitOps-managed by ArgoCD, so they survive the switch —
only the CI engine itself (and its public routing) changes.

## What gets installed (GitOps via ArgoCD app-of-apps)

Tekton is **GitOps-managed by ArgoCD**, the same app-of-apps pattern as
[`argocd/observability-oss`](../argocd/observability-oss) and
[`argocd/platform-postgres`](../argocd/platform-postgres).
[`scripts/04-tekton.sh`](../scripts/04-tekton.sh) applies the parent Application
[`argocd/tekton-app.yaml`](../argocd/tekton-app.yaml) (substituting repo/branch,
exactly like the other app-of-apps), which renders four child Applications:

| Child Application | Source | Sync wave | Notes |
|---|---|---|---|
| `tekton-pipelines` | `argocd/tekton/components/pipelines` (vendored `v1.13.1` `release.yaml`) | 0 | the engine + CRDs |
| `tekton-triggers` | `argocd/tekton/components/triggers` (vendored `v0.36.0` release + interceptors) | 1 | API/webhook-driven runs |
| `tekton-dashboard` | `argocd/tekton/components/dashboard` (vendored `v0.69.0` `release-full.yaml`) | 1 | **read-write** GUI; no native auth |
| `tekton-pipeline-as-code` | `tekton/` (Tasks/Pipelines/Triggers/RBAC + the `tekton-ci` SA) | 2 | the ported pipeline; lands in the `tekton-ci` namespace |

The component manifests are **vendored** under `argocd/tekton/components/*/`
(`release*.yaml`) — Tekton now ships these only as GitHub release assets (not on
the GCS bucket), and a `github.com` URL would be misclassified by kustomize as a
git repo, so vendoring is the reliable, auditable choice. Versions are kept in
sync with `ci.tekton.versions` in [`config/config.yaml`](../config/config.yaml). The large Tekton CRDs are
handled the same way as the CNPG operator (`ServerSideApply=true` + `Replace=true`
+ `ServerSideDiff=true`). The credential Secrets are **not** GitOps-managed (they
hold env-sourced secrets) — `01-namespaces.sh` / `08.5-argocd.sh` create them
imperatively; an SA may reference Secrets that don't exist yet, so ordering is
fine. ArgoCD requires `08.5-argocd.sh` to run first (it already does in `up.sh`).

## Tooling: kustomize vs Helm (and why both)

Deploying Tekton through ArgoCD deliberately mixes **Helm** and **kustomize** —
each layer uses the tool that fits it best, rather than forcing one tool
everywhere. The choice per layer:

| Layer | Tool used | Why this tool (and not the other) |
|---|---|---|
| **App-of-apps parent** (`argocd/tekton/`) | **Helm** | The wrapper must *template* `repoURL`/`targetRevision` (and could template versions) down into the child Applications. That per-environment templating is exactly what Helm does cleanly and what the repo already does for `observability-oss`/`platform-postgres`. Kustomize templates this only awkwardly (vars/replacements). |
| **Upstream components** (Pipelines / Triggers / Dashboard) | **kustomize** over the pinned official release YAML | **Tekton has no official Helm chart.** Triggers/Dashboard are pulled as kustomize *remote resources* from the GCS release bucket; **Pipelines is vendored** (`release.yaml` committed in-tree) because v1.7+ is published only as a GitHub release asset (not on the GCS bucket), and a `github.com` URL is misclassified by kustomize as a git repo. Helm here would mean adopting an unofficial community chart — version lag + a third-party trust dependency for a security-sensitive CI engine. |
| **Pipelines-as-code** (`tekton/` Tasks/Pipelines/Triggers/RBAC) | **plain manifests** (ArgoCD directory source) | Static custom resources with no per-environment templating need; neither Helm nor kustomize adds value. Per-run values are supplied as Tekton **params** at `PipelineRun` time, not at apply time. |

### Why not "all Helm"

There is **no official Tekton Helm chart** — upstream ships release YAMLs. Using
a community chart would (a) rarely carry the exact pinned version (e.g.
`v1.13.1`), and (b) insert a third party into the supply chain of the CI engine.
Pinning the official, vendored release manifest is the stronger
posture. (Contrast: `observability-oss` *does* use Helm for its children —
because kube-prometheus-stack/Loki/Tempo *have* well-maintained official charts.)

### Why not "all kustomize"

The app-of-apps parent has to flow `repoURL`/branch into N child Applications per
environment. Helm values do this in one line; kustomize would need clunky
`replacements`/`vars` and diverge from the established `observability-oss` /
`platform-postgres` pattern. So the wrapper stays Helm.

### The one trade-off

Because the component manifests are vendored files (not Helm-templated), the
**versions are pinned by the vendored `argocd/tekton/components/*/release*.yaml`**,
not flowed from `config.yaml`. `ci.tekton.versions` documents the intended
versions; keep the two in sync when bumping (re-download the release file). (An optional future refinement is to turn the
`tekton/` pipelines-as-code into a small Helm chart to inject the observability
namespace and tool-image versions — but the *component* versions would still
live in the kustomizations regardless.)

## Dashboard on the internet, behind Google IAP

The Tekton Dashboard has **no built-in authentication** — it relies on an
upstream auth proxy. This project gates it at the edge with Google IAP, the
identical model used for Headlamp:
[`scripts/09-gateway.sh`](../scripts/09-gateway.sh) emits an `HTTPRoute`
(`tekton.<baseDomain>` → `tekton-dashboard:9097`) and a `GCPBackendPolicy`
(`tekton-iap`) that reuses the existing `gateway-iap-oauth` secret and the
project-level `roles/iap.httpsResourceAccessor` already granted to the admin
emails by `terraform/gke` — so **no new OAuth client and no Terraform change**
are needed. Access is restricted to the same Google accounts as Headlamp/Jenkins.

```
https://tekton.<baseDomain>   →  Google IAP login  →  Tekton Dashboard
```

## The pipeline, ported

The full Jenkins microservices pipeline ([`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy))
is ported to Tekton under [`tekton/`](../tekton/) — one Task per stage, wired
into `microservices-pipeline`. Both engines read the same service registry
([`jenkins/pipelines/seed/services.yaml`](../jenkins/pipelines/seed/services.yaml)).

| Jenkins stage | Tekton Task | Notable difference |
|---|---|---|
| Checkout (+ gateway patch) / infra | `fetch-source` | — |
| Semgrep SAST + SARIF upload | `semgrep-scan` | — |
| CodeQL Analysis + SARIF upload | `codeql-analyze` | — |
| Trivy IaC scan | `trivy-iac` | — |
| Build & Test | `maven-build-test` | — |
| Build & Push image | `build-push-image` | **daemonless**: Jib (java) / Kaniko (angular) — no privileged DinD |
| Trivy image scan | `trivy-image` | — |
| Deploy (GitOps + ArgoCD + OTel self-heal) | `gitops-deploy` | ported verbatim |
| Smoke test | `smoke-test` | — |
| Integration k6 | `k6-smoke` (+ standalone `microservices-k6-smoke` Pipeline) | — |

[`scripts/06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh) is the
seed-job analogue: it applies the Tasks/Pipelines/Triggers and generates one
`PipelineRun` per service per environment (stable always; develop when
`JENKINS2026_DEVELOP_TRACK_ENABLED=true`), kicking them asynchronously.

### Credentials & RBAC

Created by [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) /
[`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) in the `tekton-ci`
namespace, from the same `REGISTRY_*` / `GIT_*` env the Jenkins path consumes:

- `tekton-registry` — ghcr.io dockerconfigjson (Jib/Kaniko/Trivy via `DOCKER_CONFIG`)
- `tekton-git` — git basic-auth, annotated `tekton.dev/git-0` (clone/push) + read as env for SARIF upload
- `tekton-argocd` — ArgoCD API token (account `tekton`, provisioned by `08.5-argocd.sh`)
- `tekton-github-webhook-secret` — optional GitHub HMAC token for the EventListener

## Triggers

`tekton/triggers/` installs an `EventListener` + `TriggerTemplate` +
`TriggerBinding` (GitHub HMAC interceptor) so runs can be kicked via API/webhook.
The upstream JHipster app repos aren't owned by this project, so push webhooks
can't be wired to them — the **primary trigger is the seed script**; the
EventListener is for parity and manual/CI re-runs.

## Observability

The `k6-smoke` Task carries `OTEL_SERVICE_NAME=tekton-pipeline-k6-smoke` —
mirroring the Jenkins `jenkins-pipeline-*` convention so that pipeline telemetry
lands in Tempo/Loki/Prometheus alongside everything else. See
[301. Observability](./301-OBSERVABILITY.md).

> **Follow-up:** Tekton *controller* OpenTelemetry tracing (PipelineRun/TaskRun
> spans) is not wired yet — the vendored `release.yaml` ships a `config-tracing`
> ConfigMap that could be patched (in the pipelines kustomization) to point at
> the in-cluster collector.

---

[← Previous: 402. Pipelines as Code](./402-PIPELINES_AS_CODE.md) | [🏠 Home](../README.md) | [→ Next: 501. Platform Operations](./501-PLATFORM_OPERATIONS.md)

---

*403. Tekton — jenkins-2026*
