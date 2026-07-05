[← Previous: 902. Troubleshooting](./902-TROUBLESHOOTING.md) | [🏠 Home](../README.md)

---

# 903. Glossary

A single lookup point for the vocabulary that recurs across all 23 guides. The
docs are deliberately dense and reuse the same 25+ acronyms and repo-specific
terms of art everywhere; this page defines each **once** with a one-line
definition and a link to the doc that owns the full explanation — so you can
read any page without reverse-engineering `NEG`, `PaC` or "retire" from context.

New here? Read the three sections top-to-bottom once, then use it as a
reference. Specialists: jump to the term.

- [Lifecycle vocabulary](#lifecycle-vocabulary)
- [Platform acronyms](#platform-acronyms)
- [Repo-specific terms of art](#repo-specific-terms-of-art)

---

## Lifecycle vocabulary

The words for **when** and **how** things run — the `DayN.tier.ZZ-resource`
workflow scheme and the two deployment tiers. Owner: [101. GitHub Actions
Workflows](./101-GITHUB_ACTIONS_WORKFLOWS.md).

| Term | Definition |
| :--- | :--- |
| **Day0** | The one-time, **persistent** bootstrap phase — WIF trust, the Gateway static IP + wildcard cert, the permanent DNS zone, and the observability backends. Created once, kept across cluster rebuilds. See [100](./100-BOOTSTRAP.md), [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |
| **Day1** | Create the **throwaway GKE cluster** + deploy the full stack (`Day1.cluster.01-gke`, the CI equivalent of [`test/e2e.sh`](../test/e2e.sh)). Idempotent: re-running it is how you **apply a change** to a running cluster — not `Decom` + `Day1`. See [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |
| **Day2** | Operations on an **already-running** cluster — redeploy a component, publish dashboards/alerts, run k6 traffic, scale (park) the node pools. The `Day2.*` tiers are independent categories, not an ordered chain. See [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |
| **Decom** | Teardown. Sorts after `Day2` so it always lands last. `Decom.cluster.01-gke` tears down the cluster (to stop charges); persistent Day0 resources survive by design (see [104](./104-REBUILD_SAFETY.md)). |
| **`DayN.tier.ZZ-resource`** | The workflow naming convention: **DayN** = lifecycle phase · **tier** = a controlled-vocabulary word (`infra`, `cluster`, `redeploy`, `publish`, `traffic`, `scale`, `registry`) · **ZZ** = a per-resource id stable across phases (`03` is always Azure) · **-resource** names the target, no verb. Alphabetical sort of the workflow `name:` fields **is** the execution order. See [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |
| **`develop` tier** | The optional, **lean second deployment tier** — a full gateway + services stack in a separate `microservices-develop` namespace, building the app's `develop` branch (true branch-based promotion). OFF by default (`microservices.developTrackEnabled`); roughly doubles the microservices footprint. See [402](./402-PIPELINES_AS_CODE.md). |
| **`stable` tier** | The default, always-on deployment tier in the `microservices` namespace, building the app's `main` branch. The counterpart to the `develop` tier. See [402](./402-PIPELINES_AS_CODE.md). |
| **tier** | The semantic word in the middle of a workflow name that groups workflows within a phase (`infra`, `cluster`, `redeploy`, `publish`, `traffic`, `scale`, `registry`). A readable label, not a number. See [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |
| **Umbrella (`Day1.cluster.00-all`)** | The opt-in "Everything up" workflow that orchestrates the Day1 leaves via `workflow_call`. See [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |
| **Umbrella (`Decom.infra.00-all`)** | The opt-in "Everything" teardown workflow that destroys the cluster **and** every persistent backend at once — never run without explicit intent. See [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |
| **ZZ** | The two-digit per-resource id in a workflow name, stable for the same resource across all phases (`Day0.infra.03` → `Day2.publish.03` → `Decom.infra.03` all address Azure). See [101](./101-GITHUB_ACTIONS_WORKFLOWS.md). |

---

## Platform acronyms

The technology acronyms used across every guide, alphabetical.

| Acronym | Expansion & one-line meaning | Owner |
| :--- | :--- | :--- |
| **app-of-apps** | An ArgoCD **pattern** (not a CRD): a parent `Application` whose source is a Helm chart that renders **hand-authored, heterogeneous** child `Application` manifests (each its own chart/namespace/sync-wave). Distinct from `ApplicationSet`. | [`argocd/README.md`](../argocd/README.md) |
| **AppSet / `ApplicationSet`** | An ArgoCD **CRD** that **generates** many uniform `Application`s from one template + a generator (list, Git dir, cluster list). The repo has exactly one — the microservices AppSet. | [`argocd/README.md`](../argocd/README.md) |
| **ARC** | **Actions Runner Controller** — runs GitHub Actions self-hosted runners as ephemeral pods on the `ci-spot` Spot ComputeClass. Active when `ci.engine=githubactions`. | [404](./404-GITHUB_ACTIONS.md) |
| **CNPG** | **CloudNativePG** — the operator providing HA Postgres (primary + standbys, failover, WAL archiving to the Day0 backups bucket) for the microservices. | [502](./502-MICROSERVICES_GITOPS.md), [201](./201-ARCHITECTURE.md) |
| **ComputeClass** | A GKE Custom ComputeClass (here `ci-spot`) that NAP uses to auto-provision right-sized, Spot-first, scale-to-zero node pools for bursty CI agents (`infrastructure/compute-classes/ci-spot.yaml`). | [501](./501-PLATFORM_OPERATIONS.md) |
| **Dataplane V2** | GKE's Cilium/eBPF data plane (`datapath_provider = ADVANCED_DATAPATH`) — the reason NetworkPolicies actually **enforce**. An immutable cluster field. | [503](./503-NETWORKING.md) |
| **ESO** | **External Secrets Operator** — in `secrets.backend=eso`, syncs GitHub-sourced values from GCP Secret Manager into the cluster over keyless Workload Identity. | [201 § Secrets backend](./201-ARCHITECTURE.md#secrets-backend-imperative--eso) |
| **Faro / RUM** | Grafana **Faro** Real User Monitoring — browser-side (frontend) observability; the Angular SPA beacons to the collector's Faro receiver at `faro.<domain>` (public, no IAP). | [202](./202-MICROSERVICES-APP-ARCHITECTURE.md), [301](./301-OBSERVABILITY.md) |
| **IAP** | **Identity-Aware Proxy** — Google's edge identity check in front of the admin UIs (Jenkins, Headlamp, pgAdmin, Tekton/Argo dashboards) via `GCPBackendPolicy`. The public `microservices` host has no IAP. | [501](./501-PLATFORM_OPERATIONS.md) |
| **JCasC** | **Jenkins Configuration as Code** — YAML (`jenkins/casc/`) that **is** the entire Jenkins config (security, clouds, libraries, credentials), loaded at boot. Nothing is clicked in the UI. | [401](./401-JENKINS.md) |
| **JHipster** | The code generator behind the production-shaped demo app: a Java **gateway** (serving an Angular SPA) + a backend microservice, database-per-service. | [202](./202-MICROSERVICES-APP-ARCHITECTURE.md) |
| **NAP** | **Node Auto-Provisioning** — GKE-native (GA equivalent of Karpenter) that auto-creates/deletes right-sized Spot, scale-to-zero node pools on demand, driven by the `ci-spot` ComputeClass. Single flag: `nodeAutoProvisioning.enabled`. | [501](./501-PLATFORM_OPERATIONS.md) |
| **NEG** | **Network Endpoint Group** — container-native load balancing: the GKE L7 LB sends straight to the pod `targetPort`, not the Service port (a common NetworkPolicy/health-check gotcha). | [503](./503-NETWORKING.md) |
| **OIDC** | **OpenID Connect** — the token type GitHub Actions presents to GCP/Azure/AWS for keyless auth (the trust half of WIF), and the login protocol for the UIs' Google sign-in. | [102](./102-GITHUB_ACTIONS_AUTOMATION.md) |
| **OTel / OTLP** | **OpenTelemetry** — the auto-instrumented traces/metrics/logs pipeline (Operator + Java agent + Collector); **OTLP** is the wire protocol the collectors export over to any of the four Grafana backends. | [301](./301-OBSERVABILITY.md) |
| **PaC** | **Pipelines-as-Code** — Git-push-driven CI (a `git push` on a fork creates the run) via a webhook, rather than creating runs by hand. Used by the Tekton and Argo Workflows engines. | [403](./403-TEKTON.md) |
| **WIF** | **Workload Identity Federation** — keyless GCP auth: every GitHub Actions workflow federates its OIDC token, so **no JSON service-account keys are ever stored**. The root of trust created at Day0. | [102](./102-GITHUB_ACTIONS_AUTOMATION.md), [100](./100-BOOTSTRAP.md) |
| **WireGuard** | GKE inter-node **pod-traffic encryption** (`in_transit_encryption_config`). Like Dataplane V2, an immutable cluster field — changing it recreates the cluster. | [503](./503-NETWORKING.md) |

---

## Repo-specific terms of art

Terms this project coins or uses in a specific way, alphabetical.

| Term | Definition | Owner |
| :--- | :--- | :--- |
| **Bootstrap paradox** | Why the Day0 root (`scripts/bootstrap.sh`) **can't** be a GitHub Actions workflow: CI needs the WIF trust + state bucket that this step creates, so it must be run once by a human with local-then-migrated state. | [100 § Bootstrap paradox](./100-BOOTSTRAP.md#why-it-cant-be-a-github-actions-workflow-the-bootstrap-paradox) |
| **`ci.engine`** | The feature flag selecting one of **four** mutually-exclusive CI engines: `jenkins` (default) · `tekton` · `githubactions` · `argoworkflows`. All share one ~11-stage pipeline contract + the `services.yaml` registry. | [`config/config.yaml`](../config/config.yaml) |
| **Feature-flag pattern** | The repo's config convention: a durable default in `config/config.yaml` + an ephemeral per-run `JENKINS2026_*` env-var override (e.g. `JENKINS2026_CI_ENGINE`). New knobs follow this, never an ad-hoc flag. | [201](./201-ARCHITECTURE.md), [`config/config.yaml`](../config/config.yaml) |
| **`K6SIM_*` contract** | The single, backward-compatible variable contract driving the one k6 script — no params = the original lightweight smoke test; `K6SIM_*` selects profile (smoke/load/stress/soak/spike/breakpoint), VUs, duration, thresholds, and `stable`-vs-`develop` targeting. | [302](./302-K6_LOAD_TESTING.md) |
| **Imperative (push) plane** | Resources applied **by the scripts** (`kubectl`/`helm`/Terraform push) rather than reconciled from Git — e.g. NetworkPolicies and ResourceQuotas that must land before workloads for Dataplane V2 timing. The counterpart to the GitOps plane. | [201 § Imperative vs GitOps](./201-ARCHITECTURE.md#imperative-push-vs-gitops-pull-the-provisioning-split) |
| **GitOps (pull) plane** | Resources **reconciled by ArgoCD** from the gitops-config repo (image tags, app manifests) — CI never runs `kubectl`; it commits a tag and ArgoCD pulls it onto the cluster. | [201 § Imperative vs GitOps](./201-ARCHITECTURE.md#imperative-push-vs-gitops-pull-the-provisioning-split), [502](./502-MICROSERVICES_GITOPS.md) |
| **retire (`retire_ci_engine`)** | The idempotent `lib/common.sh` helper that fully removes a sibling CI engine's ArgoCD apps + namespaces when you switch `ci.engine`, so no orphaned resources leak. "Mode retirement" is the analogous cleanup when switching `observability.mode`. | [`scripts/lib/common.sh`](../scripts/lib/common.sh) |
| **Seed job** | The cron-driven Jenkins job that reads the small `services.yaml` registry and **generates** the per-service pipeline jobs (Job DSL). The Tekton/Argo/GHA engines have their own `runs/` seed equivalent. | [402](./402-PIPELINES_AS_CODE.md) |
| **Self-hosted state** | The Terraform state model: after the first local `apply`, `bootstrap.sh` migrates even the bootstrap module's own state into the GCS bucket it just created — so the steady state is "all remote", including bootstrap. | [100 § State model](./100-BOOTSTRAP.md#the-state-model-self-hosted-in-the-bucket) |
| **Shared library (`vars/`)** | The Groovy shared-library steps in [`vars/`](../vars/) the Jenkins pipeline delegates to (`microservicesBuild`/`Image`/`Deploy`/`SmokeTest`/`K6Smoke`). The Tekton/Argo engines port the same logic to Tasks/WorkflowTemplates. | [402](./402-PIPELINES_AS_CODE.md) |

---

[← Previous: 902. Troubleshooting](./902-TROUBLESHOOTING.md) | [🏠 Home](../README.md)

---

*903. Glossary — jenkins-2026*
