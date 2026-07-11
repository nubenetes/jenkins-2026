# jenkins-2026

[![Release](https://img.shields.io/github/v/release/nubenetes/jenkins-2026?sort=semver&display_name=tag&logo=github&label=release&color=2ea44f)](https://github.com/nubenetes/jenkins-2026/releases/latest)
[![Gitflow Guard](https://github.com/nubenetes/jenkins-2026/actions/workflows/gitflow-guard.yml/badge.svg?branch=main)](https://github.com/nubenetes/jenkins-2026/actions/workflows/gitflow-guard.yml)
[![Terraform validate](https://github.com/nubenetes/jenkins-2026/actions/workflows/terraform-validate.yml/badge.svg?branch=main)](https://github.com/nubenetes/jenkins-2026/actions/workflows/terraform-validate.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[![Last commit](https://img.shields.io/github/last-commit/nubenetes/jenkins-2026?logo=git&logoColor=white)](https://github.com/nubenetes/jenkins-2026/commits/main)
[![Commit activity](https://img.shields.io/github/commit-activity/m/nubenetes/jenkins-2026?logo=github)](https://github.com/nubenetes/jenkins-2026/pulse)
![Top language](https://img.shields.io/github/languages/top/nubenetes/jenkins-2026?logo=gnubash&logoColor=white)
![Code size](https://img.shields.io/github/languages/code-size/nubenetes/jenkins-2026)
[![Docs](https://img.shields.io/badge/docs-26%20guides-blue?logo=readthedocs&logoColor=white)](docs/)
[![Changelog](https://img.shields.io/badge/changelog-Keep%20a%20Changelog-E05735?logo=keepachangelog&logoColor=white)](CHANGELOG.md) [![Google Drive Media](https://img.shields.io/badge/Google%20Drive-Media%20%26%20Resources-4285F4?logo=googledrive&logoColor=white)](https://drive.google.com/drive/folders/15JQNRSIW8mxaIjQ2AVyua-jzLNjDsZ10?usp=sharing)

<!-- STACK-BADGES:START -->
**Stack** — everything the platform wires together (feature-flagged axes marked):

**Cloud & platform**  
![Google Cloud](https://img.shields.io/badge/Google%20Cloud-4285F4?style=flat-square&logo=googlecloud&logoColor=white) ![GKE Kubernetes](https://img.shields.io/badge/GKE%20Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white) ![Dataplane V2 Cilium](https://img.shields.io/badge/Dataplane%20V2%20Cilium-F8C517?style=flat-square&logo=cilium&logoColor=white) ![WireGuard](https://img.shields.io/badge/WireGuard-88171A?style=flat-square&logo=wireguard&logoColor=white) ![Gateway API](https://img.shields.io/badge/Gateway%20API-326CE5?style=flat-square&logo=kubernetes&logoColor=white) ![Google IAP](https://img.shields.io/badge/Google%20IAP-4285F4?style=flat-square&logo=googlecloud&logoColor=white) ![Spot Autoprovisioning](https://img.shields.io/badge/Spot%20Autoprovisioning-1A73E8?style=flat-square&logo=googlecloud&logoColor=white)

**CI engine** — `ci.engine`, one of four  
![Jenkins](https://img.shields.io/badge/Jenkins-D24939?style=flat-square&logo=jenkins&logoColor=white) ![Tekton](https://img.shields.io/badge/Tekton-FD495C?style=flat-square&logo=tekton&logoColor=white) ![GitHub Actions ARC](https://img.shields.io/badge/GitHub%20Actions%20ARC-2088FF?style=flat-square&logo=githubactions&logoColor=white) ![Argo Workflows](https://img.shields.io/badge/Argo%20Workflows-EF7B4D?style=flat-square&logo=argo&logoColor=white)

**GitOps & delivery**  
![Argo CD](https://img.shields.io/badge/Argo%20CD-EF7B4D?style=flat-square&logo=argo&logoColor=white) ![Argo Rollouts](https://img.shields.io/badge/Argo%20Rollouts-EF7B4D?style=flat-square&logo=argo&logoColor=white) ![Argo Events](https://img.shields.io/badge/Argo%20Events-EF7B4D?style=flat-square&logo=argo&logoColor=white) ![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat-square&logo=helm&logoColor=white) ![Kustomize](https://img.shields.io/badge/Kustomize-326CE5?style=flat-square&logo=kubernetes&logoColor=white)

**Observability** — `observability.mode`, one of four + OpenTelemetry  
![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-425CC7?style=flat-square&logo=opentelemetry&logoColor=white) ![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white) ![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white) ![Loki](https://img.shields.io/badge/Loki-F46800?style=flat-square&logo=grafana&logoColor=white) ![Tempo](https://img.shields.io/badge/Tempo-F46800?style=flat-square&logo=grafana&logoColor=white) ![Grafana Cloud](https://img.shields.io/badge/Grafana%20Cloud-F46800?style=flat-square&logo=grafana&logoColor=white) ![Azure Monitor](https://img.shields.io/badge/Azure%20Monitor-0078D4?style=flat-square&logo=microsoftazure&logoColor=white) ![Amazon Managed Grafana](https://img.shields.io/badge/Amazon%20Managed%20Grafana-FF9900?style=flat-square&logo=amazonwebservices&logoColor=white) ![Grafana Faro RUM](https://img.shields.io/badge/Grafana%20Faro%20RUM-F46800?style=flat-square&logo=grafana&logoColor=white)

**Data**  
![CloudNativePG](https://img.shields.io/badge/CloudNativePG-336791?style=flat-square&logo=postgresql&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white) ![pgAdmin](https://img.shields.io/badge/pgAdmin-326690?style=flat-square&logo=postgresql&logoColor=white) ![pgBouncer](https://img.shields.io/badge/pgBouncer-1F3B4D?style=flat-square)

**Secrets & PKI** — `secrets.backend` · opt-in backend TLS  
![External Secrets Operator](https://img.shields.io/badge/External%20Secrets%20Operator-5B4EE9?style=flat-square) ![GCP Secret Manager](https://img.shields.io/badge/GCP%20Secret%20Manager-4285F4?style=flat-square&logo=googlecloud&logoColor=white) ![cert-manager](https://img.shields.io/badge/cert--manager-2E4B8F?style=flat-square) ![Backend TLS opt-in](https://img.shields.io/badge/Backend%20TLS-opt--in-64748B?style=flat-square)

**IaC & tooling**  
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white) ![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white) ![yq](https://img.shields.io/badge/yq-4B5563?style=flat-square) ![GitHub Container Registry](https://img.shields.io/badge/GitHub%20Container%20Registry-181717?style=flat-square&logo=github&logoColor=white)

**App & build**  
![JHipster](https://img.shields.io/badge/JHipster-3E8ACC?style=flat-square&logo=jhipster&logoColor=white) ![Spring Boot](https://img.shields.io/badge/Spring%20Boot-6DB33F?style=flat-square&logo=springboot&logoColor=white) ![Angular](https://img.shields.io/badge/Angular-DD0031?style=flat-square&logo=angular&logoColor=white) ![Java](https://img.shields.io/badge/Java-ED8B00?style=flat-square&logo=openjdk&logoColor=white) ![Maven](https://img.shields.io/badge/Maven-C71A36?style=flat-square&logo=apachemaven&logoColor=white) ![Jib](https://img.shields.io/badge/Jib-4285F4?style=flat-square&logo=google&logoColor=white) ![Kaniko](https://img.shields.io/badge/Kaniko-FC6D26?style=flat-square)

**Test & DevSecOps**  
![k6](https://img.shields.io/badge/k6-7D64FF?style=flat-square&logo=k6&logoColor=white) ![Semgrep](https://img.shields.io/badge/Semgrep-1E90FF?style=flat-square&logo=semgrep&logoColor=white) ![CodeQL](https://img.shields.io/badge/CodeQL-2088FF?style=flat-square&logo=github&logoColor=white) ![Trivy](https://img.shields.io/badge/Trivy-1904DA?style=flat-square&logo=trivy&logoColor=white)

<!-- STACK-BADGES:END -->

> **Two-repo GitOps setup.** This is the **infra repo** (cluster bootstrap, the CI engine — **Jenkins** / **Tekton** / **GitHub Actions** / **Argo Workflows**, one selected by `ci.engine` — plus ArgoCD & observability). Image tags and ArgoCD manifests live in the companion **[`nubenetes/jenkins-2026-gitops-config`](https://github.com/nubenetes/jenkins-2026-gitops-config)** repo.

**At a glance.** A self-contained, **two-repo GitOps** proof-of-concept platform that stands up a complete **build → scan → ship → observe → load-test** pipeline on **Google Kubernetes Engine**, configured **entirely as code** — *nothing is clicked in a UI* — and provisioned/torn down on demand from **GitHub Actions**. It takes the JHipster microservices reference app from a `git push` all the way to a running, fully-observed, traffic-tested deployment, and can do the whole round trip (create the cluster, deploy everything, exercise it, destroy it) in one lifecycle.

**What it chains together, end to end:**

- **CI engine — build, scan & containerize.** One of **four** mutually-exclusive engines selected by `ci.engine`: **Jenkins** by default (Helm chart + **JCasC** + a Job-DSL seed + a Groovy shared library), **Tekton**, **GitHub Actions (ARC)**, or **Argo Workflows** — all defined as code and sharing one ~11-stage pipeline contract (+ the shared [`resources/patch-app-source.sh`](resources/patch-app-source.sh) build-time patch + the [`services.yaml`](jenkins/pipelines/seed/services.yaml) registry). Pipelines compile, test, build images (Jib/Spring-Boot/Kaniko) and push to the registry. See [401](./docs/401-JENKINS.md) · [402](./docs/402-PIPELINES_AS_CODE.md) · [404](./docs/404-TEKTON.md) · [405](./docs/405-GITHUB_ACTIONS.md) · [406](./docs/406-ARGO_WORKFLOWS.md).
- **GitOps CD — ship without `kubectl`.** CI never touches the cluster directly; it commits a new image tag to the **gitops-config** repo, and **ArgoCD** reconciles it onto the cluster (single `Application`s + app-of-apps, with **Argo Rollouts** for sidecar-free canary/blue-green). See [501](./docs/501-PLATFORM_OPERATIONS.md) · [502](./docs/502-MICROSERVICES_GITOPS.md).
- **Observability — see everything, correlated.** End-to-end **OpenTelemetry** (auto-instrumented traces, metrics, logs) flowing into **any of four Grafana backends** — **Grafana Cloud**, in-cluster **OSS** (Prometheus/Loki/Tempo), **Azure Managed Grafana**, or **Amazon Managed Grafana** — all selectable by one flag. See [301](./docs/301-OBSERVABILITY.md).
- **Load & traffic testing — close the loop.** A first-class, parametrizable **k6 engine** drives real traffic and feeds the same dashboards (detailed in the next paragraph). See [302](./docs/302-K6_LOAD_TESTING.md).
- **Security (DevSecOps) — shift left.** **Semgrep** + **CodeQL** SAST, **Trivy** image/IaC scanning, and SARIF surfaced in the CI UI, gating the pipeline. See [601](./docs/601-DEVSECOPS.md).
- **Platform & networking — production-shaped.** GKE on **Dataplane V2** (real NetworkPolicy enforcement) + **WireGuard** inter-node encryption, a **GKE Gateway API** ingress with **Identity-Aware Proxy**, **CloudNativePG** for HA Postgres, and **Headlamp** for cluster ops. See [503](./docs/503-NETWORKING.md) · [501](./docs/501-PLATFORM_OPERATIONS.md).

**How it runs:**

- **Keyless by default.** Every GitHub Actions workflow authenticates to GCP via **Workload Identity Federation** — *no JSON service-account keys are ever stored*.
- **A clean Day0 → Day1 → Day2 → Decom lifecycle.** Persistent bootstrap (**Day0**), cluster up (**Day1**), running-cluster ops (**Day2**), teardown (**Decom**) — every workflow **idempotent and safe to re-run**. See [101](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md).
- **Tuned by a handful of feature flags** (sensible defaults, powerful opt-ins): the **CI engine** (one of four — Jenkins / Tekton / GitHub Actions (ARC) / Argo Workflows), the **observability backend** (the four above), the **secrets backend** (imperative `kubectl` or **GCP Secret Manager + External Secrets Operator**), an optional **lean `develop` tier**, and **public access** (Gateway + IAP). All live in [`config/config.yaml`](./config/config.yaml) with per-run `JENKINS2026_*` overrides.

**Closing the loop — load & traffic testing.** The platform doesn't just deploy and observe; it **drives traffic** through a first-class, fully parametrizable **[k6 engine](./docs/302-K6_LOAD_TESTING.md)** — so the dashboards always have something real to show, and the app is exercised, not just shipped.

**What the k6 engine gives you:**

- **One script, one contract.** A single [`jenkins/pipelines/k6/microservices-smoke.js`](jenkins/pipelines/k6/microservices-smoke.js) driven by **one `K6SIM_*` variable contract** — backward-compatible, so *no parameters* = the original lightweight smoke test.
- **Six workload profiles.** From a 12-iteration **smoke** test to real **load · stress · soak · spike · breakpoint** runs, each a sensible preset shape you can still fine-tune (VUs, duration, ramping stages, arrival rate, thresholds).
- **Committed presets, pick-from-a-menu.** Whole named configs live as **YAML files in git** ([`presets/`](./jenkins/pipelines/k6/presets/)) and are **selectable from a dropdown**; any field you type by hand overrides the preset (**manual > preset > default**).
- **The same test from all four runners.** **Jenkins**, **Tekton**, **GitHub Actions** and **Argo Workflows** run the identical script and contract, against **both the `stable` and `develop` tiers**.
- **One Grafana, layered analysis.** Every run exports OTLP into the **same Grafana** (correlated with the app's own telemetry) and prints a **basic→expert result analysis** inline (latency percentiles, throughput, threshold pass/fail + verdict).

<details>
<summary>🧠 Mental model — the whole platform in one map</summary>

```mermaid
mindmap
  root((jenkins-2026))
    (CI Engine)
      [Jenkins default]
      [Tekton]
      [GitHub Actions ARC]
      [Argo Workflows]
    (GitOps CD)
      [ArgoCD always]
      [app-of-apps]
    (Workloads)
      [JHipster microservices]
      [CloudNativePG]
      [develop tier optional]
    (Observability)
      [OpenTelemetry]
      [four Grafana backends]
      [AI assistant opt-in · oss]
    (Load Testing)
      [k6 traffic engine]
      [profiles + presets]
      [all four CI engines]
    (Platform)
      [GKE Dataplane V2]
      [WireGuard + IAP]
      [keyless WIF]
    (Lifecycle)
      [Day0 bootstrap]
      [Day1 cluster]
      [Day2 ops]
      [Decom teardown]
```

</details>

<details>
<summary>🟢 For newcomers — the platform in plain terms (+ a high-level map)</summary>

Think of it as a **build-and-ship factory for apps, described entirely in code**:

- A **CI engine** (one of four — Jenkins by default, Tekton, GitHub Actions/ARC, or Argo Workflows) builds, scans, and packages the demo microservices.
- **ArgoCD** (GitOps) deploys them — the CI never runs `kubectl`; it just commits a new image tag that ArgoCD reconciles onto the cluster.
- **OpenTelemetry** ships traces/metrics/logs to one of four Grafana backends, all correlated.
- **k6** generates traffic — from a tiny smoke test to full load/stress/soak runs — using **ready-made configs (presets) you pick from a menu**, so the dashboards always have something real to show.
- **GitHub Actions** drives everything and logs into Google Cloud **with no stored key** (Workload Identity), provisioning/tearing down the cluster on demand (Day0 → Day1 → Day2 → Decom).
- A few **feature flags** pick the CI engine, the observability backend, the secrets backend, an optional **lean `develop`** environment, and public access — defaults are sane, options are opt-in.

**High-level design** — the platform at a glance:

```mermaid
flowchart LR
  dev([You / git push]) --> gha["GitHub Actions<br/>keyless WIF → GCP"]
  gha --> prov[provision GKE + full stack]
  prov --> K
  subgraph K["GKE cluster"]
    ci["CI engine (pick one)<br/>Jenkins · Tekton · GHA/ARC · Argo Workflows"] --> argo["ArgoCD · GitOps CD"]
    argo --> apps["JHipster microservices<br/>+ CloudNativePG"]
    apps --> otel["OpenTelemetry"]
  end
  ci -. "push image tag" .-> gops[("gitops-config repo")]
  gops --> argo
  otel --> graf[("Grafana: Cloud · OSS · Azure · AWS")]
  classDef pick fill:#eef,stroke:#66c;
  class ci,graf pick;
```

</details>

<details>
<summary>🔴 For specialists — In depth: feature flags, components &amp; lifecycle (the full technical breakdown)</summary>

<details>
<summary>🔬 Low-level design — planes &amp; components (dashed = optional / off by default)</summary>

```mermaid
flowchart TB
  subgraph CP["Control / GitOps plane"]
    argo["ArgoCD<br/>app-of-apps + ApplicationSet"]
    eso["External Secrets ↔ GCP Secret Manager<br/>optional · secrets.backend=eso"]:::opt
  end
  subgraph CI["CI plane — pick one (ci.engine)"]
    jen["Jenkins<br/>JCasC + seed job + shared lib · WebSocket agents"]
    tek["Tekton<br/>Pipelines/Triggers/Dashboard + PaC + Chains"]
    gha["GitHub Actions/ARC<br/>ephemeral Spot runners · no in-cluster UI"]
    awf["Argo Workflows<br/>WorkflowTemplate + Events · IAP UI"]
  end
  subgraph DATA["Microservices + data plane"]
    gw[gateway] --> msapp[jhipster microservice]
    cnpg[("CNPG HA Postgres<br/>3 instances + poolers + WAL backups")]
    msd["microservices-develop<br/>optional · lean: 1 instance, no backups"]:::opt
  end
  subgraph OBS["Observability plane — pick one (observability.mode)"]
    op["OTel operator<br/>auto-instrument"] --> col["OTel collector"]
    col --> back[("Grafana: Cloud · OSS · Azure · AWS")]
    back -. "AI assistant" .-> llmp["grafana-llm-app + LiteLLM → Vertex AI<br/>optional · observability.llm.enabled · oss only"]:::opt
  end
  sec["Zero-trust: Dataplane V2 netpols + WireGuard · Google IAP · keyless WIF/OIDC"]

  CI -->|"build → scan → image → commit tag"| CP
  CP -->|"sync"| DATA
  DATA -->|"OTLP traces/metrics/logs"| OBS
  sec -.-> CI & DATA & OBS
  classDef opt fill:#eef,stroke:#66c,stroke-dasharray: 4 3;
```

</details>

#### Feature flags

Durable default in [`config/config.yaml`](config/config.yaml); per-run override via a `JENKINS2026_*` env var (local) or a GitHub Actions input (CI):

| Capability | Flag | Default | Optional |
|---|---|---|---|
| **CI engine** | `ci.engine` | **`jenkins`** — official Helm chart + JCasC + Job-DSL seed | **`tekton`** — Tekton Pipelines / Triggers / Dashboard (IAP-protected) + **Pipelines-as-Code**, the same pipeline ported to [`tekton/`](tekton/) ([404](docs/404-TEKTON.md)) · **`githubactions`** — GitHub Actions self-hosted runners via **ARC** (Actions Runner Controller): ephemeral **Spot** runners on the `ci-spot` NAP ComputeClass, native GitHub webhooks, **no** in-cluster UI/route (runs in GitHub's Actions tab) ([405](docs/405-GITHUB_ACTIONS.md)) · **`argoworkflows`** — Argo Workflows + Argo Events: the pipeline ported to [`argoworkflows/`](argoworkflows/) as a WorkflowTemplate, an **IAP-protected Argo Workflows Server UI** (`argo.<domain>`, like the Tekton Dashboard) plus a public, HMAC-protected **Argo Events webhook receiver** (`argo-events.<domain>`) ([406](docs/406-ARGO_WORKFLOWS.md)). The four engines are mutually exclusive; switching retires the others. |
| **CI seed runs** | `<engine>.seedRuns` | **`true`** for `tekton` / `githubactions` / `argoworkflows` — `Day1` seeds **one run per service** (Tekton `PipelineRun`s from [`tekton/runs/`](tekton/runs/) · a dispatched workflow run per fork · one Argo `Workflow` per service) so the engine's **UI/history is pre-populated** from the first provision, at the cost of one build per service per Day1 | **`false`** — rely solely on the git-push trigger (no seed builds). Not applicable to `jenkins` (its Job-DSL seed job always generates the jobs; builds start on demand). Per-run overrides `JENKINS2026_{TEKTON,GITHUBACTIONS,ARGOWORKFLOWS}_SEED_RUNS`. |
| **CI build-pod placement** | `<engine>.runNodePool` | **`static`** for `jenkins` / `tekton` / `argoworkflows` — the long-lived `jenkins-2026-pool` (robust, no NAP/Spot/quota dependency); **`githubactions` ships `ci-spot`** (single-job ARC runners are ideal Spot workloads) | **`ci-spot`** — the NAP **Spot** ComputeClass (elastic, cheaper; needs `nodeAutoProvisioning` + `SSD_TOTAL_GB` headroom). **Per engine** by pod-scheduling shape: single-pod engines (**Jenkins**, **GitHub Actions/ARC**) are good Spot fits (a preemption just re-runs one idempotent build); shared-workspace engines (**Tekton**, **Argo Workflows**) pin a whole run to one node, so keep them `static`. Per-run overrides `JENKINS2026_{JENKINS,TEKTON,GITHUBACTIONS,ARGOWORKFLOWS}_RUN_NODE_POOL` + a `run_node_pool` input on the four `Day2.redeploy` workflows. See [docs/501](docs/501-PLATFORM_OPERATIONS.md#the-engines-on-spot-ci-spot--why-the-placement-flag-is-per-engine). |
| **Observability backend** | `observability.mode` | **`grafana-cloud`** *(the GitHub Actions `Day1` input defaults to **`oss`**)* | **`oss`** (in-cluster Grafana / Loki / Tempo / kube-prometheus) · **`managed-azure`** · **`managed-aws`** — exactly one active per cluster; a rerun deterministically switches. The two **managed** backends need a one-time backend setup ([docs/102 § One-time Setup](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#one-time-setup-bootstrapping)) before Day1. |
| **Secrets backend** | `secrets.backend` | **`imperative`** — `kubectl create secret` from GitHub secrets | **`eso`** — push values to **GCP Secret Manager** + sync via the **External Secrets Operator** over Workload Identity (keyless, versioned, audited). |
| **AI assistant (Grafana LLM app)** | `observability.llm.enabled` | **`false`** | **`true`** — the official **`grafana-llm-app`** plugin (Grafana's AI features), backed by **Vertex AI Gemini** through an in-cluster **LiteLLM** proxy over keyless **Workload Identity** — no API keys, no new public surface (ClusterIP-internal). **`oss` mode only**: `grafana-cloud`'s assistant is native, and the managed Grafanas have **no keyless path** (deliberate decision — see [docs/301 § Grafana LLM app](docs/301-OBSERVABILITY.md#grafana-llm-app-ai-assistant--opt-in-keyless-oss-only)). Per-run override `JENKINS2026_OBS_LLM_ENABLED`. |
| **Develop tier** | `microservices.developTrackEnabled` | **`false`** | **`true`** — an optional **lean, non-HA** second deploy tier (`microservices-develop`: CNPG single instance, single pooler, no backups), engine-neutral, into the same observability stack. |
| **Public access** | `gateway.baseDomain` | **set** → one global **GKE Gateway** + Google **IAP** + a wildcard cert front every UI | **`""`** to disable (reach services via `kubectl port-forward`). |
| **Grafana Cloud tier** | `observability.grafanaCloudTier` | **`free`** | **`paid`** — a profile that sets the volume-control defaults so the free tier fits its limits. `free` → `leanMetrics` on + `logMinSeverity=warn`; `paid` → full metrics + ship all logs. Per-run override `JENKINS2026_GRAFANA_CLOUD_TIER`; GHA `grafana_cloud_tier` dropdown. Only meaningful in grafana-cloud mode. |
| **Lean metrics** | `observability.leanMetrics` | **`auto`** | `true`/`false` — `auto` derives from `grafanaCloudTier` (free→on, paid→off). When on (grafana-cloud), drops the k8s-monitoring **cluster infra metrics** (cadvisor/kube-state/node-exporter) the custom dashboards don't use, to stay under the **free-tier 15k active-series** cap. Force with a literal value or `JENKINS2026_OBS_LEAN_METRICS`. |
| **Log verbosity** | `logging.level` | **`info`** | **`debug`** — additionally emit `[DEBUG]` script lines (`log_debug`) and `TF_LOG=DEBUG` for the Terraform steps. Per-run override `JENKINS2026_LOG_LEVEL`; the GitHub Actions workflows expose it as a `log_level` dropdown. No `trace`/`set -x` level by design (would leak script-derived secrets); use `ACTIONS_STEP_DEBUG` for runner tracing. |
| **Grafana log severity** | `observability.logMinSeverity` | **`auto`** | `trace` (keep all) · `debug` · `info` · `warn` · `error` — minimum severity shipped to the backend, applied as a `filter` in the `otel-collector-logs` DaemonSet (parses level→severity), trimming **every** Grafana logs panel (microservices + platform) in all modes. `auto` derives from `grafanaCloudTier` (free→`warn`, paid→`trace`; non-cloud→`info`). Plain-text lines (no level token) are never dropped. Per-run override `JENKINS2026_LOG_MIN_SEVERITY`; GHA `log_min_severity` dropdown. See [docs/301 § Log Levels](docs/301-OBSERVABILITY.md#log-levels). |
| **Node Auto-Provisioning (Spot CI nodes)** | `nodeAutoProvisioning.enabled` | **`true`** — GKE **NAP** + the Custom **ComputeClass** (`ci-spot`) provisions **Spot, scale-to-zero** CI-agent nodes on demand | **`false`** — CI builds run on the static pool only. Per-run override `JENKINS2026_NODE_AUTOPROVISIONING_ENABLED`; pairs with the per-engine `runNodePool` placement flag above. |
| **Deploy branch (self-repo)** | `jenkins.selfRepoBranch` | **`main`** — the branch of **this repo** the platform deploys from (shared library · seed job · the Tekton/GHA/Argo pipeline definitions); in CI it **auto-tracks the dispatched branch** (`GITHUB_REF_NAME`), so a `Day1` from `develop` validates develop's library/seed before the promotion PR | Per-run override `JENKINS2026_SELF_REPO_BRANCH`. |

**Always on (no flag):** **ArgoCD** (the GitOps CD engine) · **CloudNativePG** HA Postgres + **pgAdmin** · **Headlamp** (cluster UI) · the **OpenTelemetry** operator + collector · **Argo Rollouts** (sidecar-free canary / blue-green via the Gateway API) · **Dataplane V2** (Cilium/eBPF) **enforced NetworkPolicies** + **WireGuard** inter-node pod encryption · **DevSecOps** scanning in every build · and **pinned versions** throughout.

#### What's inside, by area

- **CI engines (pick one of four — `ci.engine`).** *Jenkins* (default): the official Helm chart, configured 100% via **JCasC** + a Job-DSL **seed job** that generates one pipeline per microservice from a `services.yaml` registry; a global **shared library** ([`vars/`](vars/)) runs each build in an ephemeral multi-container agent pod that connects back over **WebSocket**. *Tekton*: Pipelines/Triggers, the IAP-protected **Dashboard**, **Pipelines-as-Code** (git-push-driven), and **Chains** (SLSA provenance) — the same pipeline ported to [`tekton/`](tekton/). *GitHub Actions (ARC)*: ephemeral Spot self-hosted runners via Actions Runner Controller, native GitHub webhooks, **no** in-cluster UI. *Argo Workflows*: the pipeline as a WorkflowTemplate + Argo Events, an IAP-protected Argo Server UI plus an HMAC webhook receiver. The four are **mutually exclusive** — each `scripts/04-<engine>.sh` retires the other three (via the shared `retire_ci_engine` helper in `scripts/lib/common.sh`: deletes their ArgoCD apps + children + namespaces + clears stuck GKE NEG finalizers). All four converge at the deploy boundary (ArgoCD), so the rest of the platform is engine-neutral.
- **The pipeline (all four engines).** ~11 stages: checkout → **Semgrep** SAST → **CodeQL** → **Trivy** IaC → build & test (Maven/npm) → build & push image (Jib / Spring-Boot build-image / Kaniko) → **Trivy** image scan → **GitOps deploy** (`yq` the image tag → push to the gitops repo → `argocd app sync` → OTel self-heal) → smoke test → **k6**. All four engines share the same contract + the [`resources/patch-app-source.sh`](resources/patch-app-source.sh) build-time patch + the [`services.yaml`](jenkins/pipelines/seed/services.yaml) registry. Findings upload as SARIF to GitHub Code Scanning (non-blocking).
- **GitOps CD (always — ArgoCD).** App-of-apps + an `ApplicationSet` render the microservices Helm chart; the CNPG operator, External Secrets, Headlamp, Argo Rollouts, and the active CI engine (Jenkins / Tekton / GitHub Actions-ARC / Argo Workflows) are all ArgoCD `Application`s. CI never `kubectl apply`s apps — it commits an image tag and ArgoCD reconciles.
- **Data (always — CloudNativePG).** Per-service HA Postgres (3 instances + PgBouncer poolers + WAL/base backups to GCS via Workload Identity), administered through **pgAdmin** (IAP, zero-password `.pgpass`). The optional *develop* tier runs a **lean** single-instance, no-backup variant.
- **Observability (pick one backend — `observability.mode`).** The OTel **operator** auto-instruments the JVM apps; an OTel **collector** fans traces/metrics/logs out to **Grafana Cloud**, an in-cluster **OSS** stack (Prometheus/Loki/Tempo/Grafana), **Azure** Managed Grafana, or **Amazon** Managed Grafana — correlated by `trace_id`, with dashboards + alert rules provisioned per mode. CI runs (whichever engine) emit spans too, and each active engine gets its own CI-overview dashboard (jenkins-overview · tekton-overview · github-actions-ci · argo-workflows-ci).
- **Security & zero-trust.** Keyless **WIF/OIDC** everywhere (no JSON keys); **Dataplane V2** (Cilium/eBPF) **enforced** NetworkPolicies + **WireGuard** inter-node encryption; **Google IAP** fronts every admin UI; in-build **DevSecOps** scanning (Semgrep · CodeQL · Trivy · warnings-ng; Tekton adds **Chains**/SLSA); optional **ESO** + GCP Secret Manager.
- **Lifecycle & ops.** A one-time, human-run **bootstrap** ([`scripts/bootstrap.sh`](scripts/bootstrap.sh)) creates the root of trust (WIF + Terraform-state bucket + permanent DNS zone). Then **GitHub Actions** drive **Day0** (persistent infra: Gateway IP/cert, the chosen Grafana backend) → **Day1** (cluster + full stack) → **Day2** (redeploy / publish / traffic ops) → **Decom** (teardown), each behind a required-reviewer environment gate. Every workflow is **idempotent** — re-run to apply a change; you never Decom to converge.

**Two-repo split:** this **infra repo** owns the cluster + CI engine + platform; the companion **[`gitops-config`](https://github.com/nubenetes/jenkins-2026-gitops-config)** repo owns the deployed microservices' image tags + Helm manifests — CI pushes image-tag bumps there, ArgoCD syncs them.

</details>

---

## Table of Contents

**[README — jenkins-2026](#jenkins-2026)**
- [1. Document Inventory](#1-document-inventory)
- [2. Quick Start](#2-quick-start)
- [3. Architecture Overview](#3-architecture-overview)
  - [3.1. Technical Infographics Catalog](#31-technical-infographics-catalog)
  - [3.2. Project Media & External Resources](#32-project-media--external-resources)
- [4. GitHub Actions Workflows](#4-github-actions-workflows)
- [5. Prerequisites](#5-prerequisites)

---

**[100 · Bootstrap — the Root of Trust](./docs/100-BOOTSTRAP.md)**
- [Why it can't be a GitHub Actions workflow (the bootstrap paradox)](./docs/100-BOOTSTRAP.md#why-it-cant-be-a-github-actions-workflow-the-bootstrap-paradox)
- [Create the root: `bootstrap.sh up`](./docs/100-BOOTSTRAP.md#create-the-root-bootstrapsh-up) · [Destroy: `bootstrap.sh down`](./docs/100-BOOTSTRAP.md#destroy-the-root-bootstrapsh-down)
- [The state model (self-hosted in the bucket)](./docs/100-BOOTSTRAP.md#the-state-model-self-hosted-in-the-bucket)

**[101 · GitHub Actions Workflows](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md)**
- [Naming convention: `DayN.tier.ZZ-resource`](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#naming-convention-dayntierzz-resource)
  - [Resource identifier (ZZ): stable across all phases](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#resource-identifier-zz-stable-across-all-phases)
- [Full workflow matrix](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#full-workflow-matrix)
- [Lifecycle diagram](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#lifecycle-diagram)
- [Day-0 / Day-1 / Day-2 operations](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#day-0--day-1--day-2-operations)
  - [Day × workflow matrix](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#day--workflow-matrix)
- [Complete workflow inventory — matrix table](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#complete-workflow-inventory--matrix-table)
- [Day2 ordering: tiers are categories, not stages](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#day2-ordering-tiers-are-categories-not-stages)
- [Are workflows auto-chained? Why not?](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#are-workflows-auto-chained-why-not)
- [Reading the `Day1.cluster.01` run graph: jobs vs in-job branches](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#reading-the-day1cluster01-run-graph-jobs-vs-in-job-branches)
- [Idempotency: every workflow is safe to re-run](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#idempotency-every-workflow-is-safe-to-re-run)

**[102 · GitHub Actions Automation](./docs/102-GITHUB_ACTIONS_AUTOMATION.md)**
- [Bootstrapping Architecture: Persistent vs. Short-Lived Resources](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#bootstrapping-architecture-persistent-vs-short-lived-resources)
- [Workflow Architecture & Lifecycle Diagram](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#workflow-architecture--lifecycle-diagram)
  - [Detailed Workflow Reference and Lifecycle Management](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#detailed-workflow-reference-and-lifecycle-management)
- [Version Pinning and the `git_ref` Parameter](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#version-pinning-and-the-git_ref-parameter)
  - [The `git_ref` Parameter](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#the-git_ref-parameter)
  - [Form Fields Reference (Day1.cluster.01 GKE Provision)](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#form-fields-reference-day1cluster01-gke-provision)
  - [The Danger of Divergent References](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#the-danger-of-divergent-references)
- [Environment Protection and Manual Approvals](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#environment-protection-and-manual-approvals)
  - [Setting up Environment Rules](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#setting-up-environment-rules)
- [One-time Setup (Bootstrapping)](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#one-time-setup-bootstrapping)
- [Running the GKE Workflows](./docs/102-GITHUB_ACTIONS_AUTOMATION.md#running-the-gke-workflows)

---

**[103 · GitHub Secrets Inventory](./docs/103-GITHUB_SECRETS_INVENTORY.md)**
- [GCP / Core Infrastructure](./docs/103-GITHUB_SECRETS_INVENTORY.md#1-gcp--core-infrastructure)
- [Grafana Cloud](./docs/103-GITHUB_SECRETS_INVENTORY.md#2-grafana-cloud)
- [Grafana Alert Email (per-mode)](./docs/103-GITHUB_SECRETS_INVENTORY.md#3-grafana-alert-email)
- [Azure Managed Grafana](./docs/103-GITHUB_SECRETS_INVENTORY.md#4-azure-managed-grafana-managed-azure-mode)
- [AWS Managed Grafana](./docs/103-GITHUB_SECRETS_INVENTORY.md#5-aws-managed-grafana-managed-aws-mode)
- [Jenkins OIDC / Google Sign-In](./docs/103-GITHUB_SECRETS_INVENTORY.md#6-jenkins-oidc--google-sign-in)
- [Headlamp & IAP](./docs/103-GITHUB_SECRETS_INVENTORY.md#7-headlamp--identity-aware-proxy)
- [Private Registry & Git](./docs/103-GITHUB_SECRETS_INVENTORY.md#8-private-registry--git)
- [Tekton CI engine](./docs/103-GITHUB_SECRETS_INVENTORY.md#9-tekton-ci-engine-ciengine-tekton) — `TEKTON_GITHUB_WEBHOOK_SECRET` / `PAC_WEBHOOK_SECRET` (optional webhook HMACs)
- [GitHub Actions / ARC CI engine](./docs/103-GITHUB_SECRETS_INVENTORY.md#95-github-actions--arc-ci-engine-ciengine-githubactions) — `ARC_GITHUB_APP_ID` / `ARC_GITHUB_APP_INSTALLATION_ID` / `ARC_GITHUB_APP_PRIVATE_KEY` (or `GIT_TOKEN` PAT fallback)
- [Argo Workflows CI engine](./docs/103-GITHUB_SECRETS_INVENTORY.md#96-argo-workflows-ci-engine-ciengine-argoworkflows) — `ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET` (optional Argo Events webhook HMAC; `PAC_WEBHOOK_SECRET` fallback)
- [Grafana Cloud k6 (optional)](./docs/103-GITHUB_SECRETS_INVENTORY.md#10-grafana-cloud-k6-the-k6-app--optional)
- [Summary table](./docs/103-GITHUB_SECRETS_INVENTORY.md#summary-table)

---

**[104 · Rebuild-Safety (`Decom` + `Day1`)](./docs/104-REBUILD_SAFETY.md)**
- [Why it matters — the lifecycle & persistence tiers](./docs/104-REBUILD_SAFETY.md#1-why-this-matters--the-lifecycle)
- [The bug class: collision vs residue (+ the Postgres exemplar)](./docs/104-REBUILD_SAFETY.md#2-the-bug-class--two-failure-modes)
- [Rebuild-safety design patterns (the toolbox)](./docs/104-REBUILD_SAFETY.md#3-the-rebuild-safety-design-patterns-the-toolbox)
- [**The rebuild-safety matrix (safe-by-design)**](./docs/104-REBUILD_SAFETY.md#4-the-rebuild-safety-matrix-safe-by-design) — state/buckets · GKE · DNS/gateway · identity/secrets · obs backends · teardown residue · registry/GitOps/CI
- [The 7 closed gaps (#487–#489)](./docs/104-REBUILD_SAFETY.md#5-the-gaps-that-were-closed)
- [Live-verification checklist](./docs/104-REBUILD_SAFETY.md#6-live-verification-checklist) · [Adding a new persistent resource](./docs/104-REBUILD_SAFETY.md#7-adding-a-new-persistent-or-external-resource--the-checklist)

---

**[201 · Architecture](./docs/201-ARCHITECTURE.md)**
- [Overview](./docs/201-ARCHITECTURE.md#overview)
- [System Architecture](./docs/201-ARCHITECTURE.md#system-architecture)
- [Component Diagram](./docs/201-ARCHITECTURE.md#component-diagram)
- [Microservices & Database Architecture](./docs/201-ARCHITECTURE.md#microservices--database-architecture)
  - [Database Injection & Secrets](./docs/201-ARCHITECTURE.md#database-injection--secrets)
  - [CI/CD Flow (GitOps)](./docs/201-ARCHITECTURE.md#cicd-flow-gitops)
- [Repository Layout](./docs/201-ARCHITECTURE.md#repository-layout)
- [Imperative (push) vs GitOps (pull): the provisioning split](./docs/201-ARCHITECTURE.md#imperative-push-vs-gitops-pull-the-provisioning-split)
- [Namespaces & in-cluster Secrets](./docs/201-ARCHITECTURE.md#namespaces--in-cluster-secrets)
- [GKE Cluster Topology & Sizing](./docs/201-ARCHITECTURE.md#gke-cluster-topology--sizing)
  - [Sizing Rationale](./docs/201-ARCHITECTURE.md#sizing-rationale)
  - [FinOps & Cost Analysis](./docs/201-ARCHITECTURE.md#finops--cost-analysis)

---

**[202 · Microservices App Architecture](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md)**
- [Understanding the app (newcomers → specialists)](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md#understanding-the-app-newcomers--specialists)
- [Components](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md#components)
- [Java vs Angular — where each runs](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md#java-vs-angular--where-each-actually-runs)
- [How a request flows](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md#how-a-request-flows)
- [Frontend observability — Angular RUM with Grafana Faro](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md#frontend-observability--angular-rum-with-grafana-faro-implemented)
- [Why JHipster (why this demo app)](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md#why-jhipster-why-this-demo-app)

---

**[301 · Observability](./docs/301-OBSERVABILITY.md)**
- [Key Features](./docs/301-OBSERVABILITY.md#key-features)
- [Grafana Cloud Observability apps — status & recommendation](./docs/301-OBSERVABILITY.md#grafana-cloud-observability-apps--status--recommendation)
- [OTel Components](./docs/301-OBSERVABILITY.md#otel-components)
  - [OpenTelemetry Operator](./docs/301-OBSERVABILITY.md#opentelemetry-operator)
  - [Java Auto-Instrumentation](./docs/301-OBSERVABILITY.md#java-auto-instrumentation)
  - [Angular RUM](./docs/301-OBSERVABILITY.md#angular-rum)
  - [OTel Collector](./docs/301-OBSERVABILITY.md#otel-collector)
  - [Jenkins Plugin](./docs/301-OBSERVABILITY.md#jenkins-plugin)
- [Telemetry Architecture and Signal Flow](./docs/301-OBSERVABILITY.md#telemetry-architecture-and-signal-flow)
- [Signal Correlation: Metrics, Traces, and Logs](./docs/301-OBSERVABILITY.md#signal-correlation-metrics-traces-and-logs)
- [Structured Logging Deep Dive](./docs/301-OBSERVABILITY.md#structured-logging-deep-dive)
  - [Log Levels](./docs/301-OBSERVABILITY.md#log-levels)
- [OTel Injection Race](./docs/301-OBSERVABILITY.md#otel-injection-race)
- [Observability Dashboards](./docs/301-OBSERVABILITY.md#observability-dashboards)
- [k6 Observability Smoke Test](./docs/301-OBSERVABILITY.md#k6-observability-smoke-test)
- [Grafana OSS In-Cluster Mode](./docs/301-OBSERVABILITY.md#grafana-oss-in-cluster-mode)
- [Observability Modes](./docs/301-OBSERVABILITY.md#observability-modes)
  - [Logging in to Amazon Managed Grafana (managed-aws)](./docs/301-OBSERVABILITY.md#logging-in-to-amazon-managed-grafana-managed-aws)
- Runbook: [Log Correlation Validation](./docs/runbooks/log-correlation-validation.md)
- Runbook: [NAP → Spot CI nodes](./docs/runbooks/nap-spot-provisioning.md)

---

**[302 · k6 Traffic, Load & Observability Testing](./docs/302-K6_LOAD_TESTING.md)**
- [Understanding k6 here (newcomers → specialists)](./docs/302-K6_LOAD_TESTING.md#understanding-k6-here-newcomers--specialists)
- [The parameter contract (`K6SIM_*`)](./docs/302-K6_LOAD_TESTING.md#the-parameter-contract-k6sim_)
- [Workload profiles](./docs/302-K6_LOAD_TESTING.md#workload-profiles)
- [Config presets (committed test configs) + inventory matrix & per-preset diagrams](./docs/302-K6_LOAD_TESTING.md#config-presets-committed-test-configs)
- [Running it — the four engines](./docs/302-K6_LOAD_TESTING.md#running-it--the-four-engines) ([Jenkins](./docs/302-K6_LOAD_TESTING.md#jenkins) · [Tekton](./docs/302-K6_LOAD_TESTING.md#tekton) · [GitHub Actions](./docs/302-K6_LOAD_TESTING.md#github-actions) · [Argo Workflows](./docs/302-K6_LOAD_TESTING.md#argo-workflows))
- [Tutorials (basic & advanced)](./docs/302-K6_LOAD_TESTING.md#tutorials)
- [Reading the results — basic & expert](./docs/302-K6_LOAD_TESTING.md#reading-the-results--basic--expert)
- [stable vs develop — compatibility matrix](./docs/302-K6_LOAD_TESTING.md#stable-vs-develop--compatibility-matrix)
- [Troubleshooting](./docs/302-K6_LOAD_TESTING.md#troubleshooting)

**[303 · JVM Tuning & Runtime Strategy](./docs/303-JVM-TUNING.md)**
- [Understanding JVM tuning here (newcomers → specialists)](./docs/303-JVM-TUNING.md#understanding-jvm-tuning-here-newcomers--specialists)
- [The tuning we applied](./docs/303-JVM-TUNING.md#the-tuning-we-applied) ([per-environment values](./docs/303-JVM-TUNING.md#per-environment-values))
- [GC algorithm options](./docs/303-JVM-TUNING.md#gc-algorithm-options)
- [Runtime / startup options](./docs/303-JVM-TUNING.md#runtime--startup-options-the-big-picture)
- [OpenTelemetry instrumentation modes](./docs/303-JVM-TUNING.md#opentelemetry-instrumentation-modes)
- [Why CRaC is the chosen advanced direction](./docs/303-JVM-TUNING.md#why-crac-is-the-chosen-advanced-direction)
- [Analyzing JVM performance in Grafana](./docs/303-JVM-TUNING.md#analyzing-jvm-performance-in-grafana)

---

**[401 · Jenkins](./docs/401-JENKINS.md)**
- [Accessing the UI & Admin Password](./docs/401-JENKINS.md#accessing-the-ui--admin-password)
- [Google Login (OpenID Connect)](./docs/401-JENKINS.md#google-login-openid-connect)
- [Plugins & JCasC Fragments](./docs/401-JENKINS.md#plugins--jcasc-fragments)
- [Global Shared Library](./docs/401-JENKINS.md#global-shared-library)
- [GitOps: Jenkins as an ArgoCD Application](./docs/401-JENKINS.md#gitops-jenkins-as-an-argocd-application)

**[402 · Pipelines as Code](./docs/402-PIPELINES_AS_CODE.md)**
- [The Seed Job](./docs/402-PIPELINES_AS_CODE.md#the-seed-job)
- [Pipeline Branch & Environment Mapping](./docs/402-PIPELINES_AS_CODE.md#pipeline-branch--environment-mapping)
  - [Why the GitOps Repo Uses Only the `main` Branch](./docs/402-PIPELINES_AS_CODE.md#why-the-gitops-repo-uses-only-the-main-branch)
  - [Optional `develop` Tier (Feature Flag, Off by Default)](./docs/402-PIPELINES_AS_CODE.md#optional-develop-tier-feature-flag-off-by-default)
- [High-level architecture](./docs/402-PIPELINES_AS_CODE.md#high-level-architecture)
- [Detailed Pipeline Execution Stages](./docs/402-PIPELINES_AS_CODE.md#detailed-pipeline-execution-stages)
  - [1. Microservices Build & Deploy Pipeline](./docs/402-PIPELINES_AS_CODE.md#1-microservices-build--deploy-pipeline)
  - [2. k6 Integration Smoke Test Pipeline](./docs/402-PIPELINES_AS_CODE.md#2-k6-integration-smoke-test-pipeline)
- [Pipeline Container Security](./docs/402-PIPELINES_AS_CODE.md#pipeline-container-security)
- [Pipeline Reliability Fixes](./docs/402-PIPELINES_AS_CODE.md#pipeline-reliability-fixes-v0107v01016)

**[403 · Declarative vs Scripted (Jenkins authoring)](./docs/403-DECLARATIVE_VS_SCRIPTED.md)**
- [Understanding the two dialects (newcomers → specialists)](./docs/403-DECLARATIVE_VS_SCRIPTED.md#understanding-the-two-dialects-newcomers--specialists)
- [The two dialects in sixty seconds](./docs/403-DECLARATIVE_VS_SCRIPTED.md#1-the-two-dialects-in-sixty-seconds)
- [What each dialect actually is](./docs/403-DECLARATIVE_VS_SCRIPTED.md#2-what-each-dialect-actually-is)
- [The comparison matrix](./docs/403-DECLARATIVE_VS_SCRIPTED.md#4-the-comparison-matrix)
- [When Jenkins recommends which](./docs/403-DECLARATIVE_VS_SCRIPTED.md#6-when-jenkins-officially-recommends-which)
- [This repo's three-layer hybrid](./docs/403-DECLARATIVE_VS_SCRIPTED.md#7-this-repos-architecture-the-three-layer-hybrid)
- [Counterexamples (all-one-way)](./docs/403-DECLARATIVE_VS_SCRIPTED.md#9-counterexamples-what-breaks-if-you-go-all-one-way)
- [Recognising Declarative vs Scripted at a glance](./docs/403-DECLARATIVE_VS_SCRIPTED.md#12-recognising-declarative-vs-scripted-at-a-glance)
- [Job DSL & seed jobs — advanced tutorial](./docs/403-DECLARATIVE_VS_SCRIPTED.md#13-job-dsl-and-seed-jobs-an-advanced-tutorial)
- [The Scripted-god-library anti-pattern](./docs/403-DECLARATIVE_VS_SCRIPTED.md#14-the-common-anti-pattern-a-scripted-god-library-with-thin-jenkinsfiles)

**[404 · Tekton (alternative CI engine)](./docs/404-TEKTON.md)**
- [Selecting the engine (`ci.engine`)](./docs/404-TEKTON.md#selecting-the-engine)
- [What gets installed (GitOps via ArgoCD app-of-apps)](./docs/404-TEKTON.md#what-gets-installed-gitops-via-argocd-app-of-apps)
- [Tooling: kustomize vs Helm (and why both)](./docs/404-TEKTON.md#tooling-kustomize-vs-helm-and-why-both)
- [Dashboard on the internet, behind Google IAP](./docs/404-TEKTON.md#dashboard-on-the-internet-behind-google-iap)
- [The pipeline, ported](./docs/404-TEKTON.md#the-pipeline-ported)
- [Pipelines-as-Code (PaC): Git-driven CI](./docs/404-TEKTON.md#pipelines-as-code-pac-git-driven-ci)

**[405 · GitHub Actions / ARC (third CI engine)](./docs/405-GITHUB_ACTIONS.md)**
- [Where do I see the pipelines? (no in-cluster UI)](./docs/405-GITHUB_ACTIONS.md#-where-do-i-see-the-pipelines-there-is-no-in-cluster-ui)
- [Triggering a build — the branch-based tier model (stable vs develop)](./docs/405-GITHUB_ACTIONS.md#triggering-a-build--the-branch-based-tier-model-stable-vs-develop)
- [Security: why no `pull_request` trigger + branch protection](./docs/405-GITHUB_ACTIONS.md#security-why-no-pull_request-trigger--branch-protection)
- [Selecting the engine (`ci.engine`)](./docs/405-GITHUB_ACTIONS.md#selecting-the-engine)
- [What gets installed (GitOps via ArgoCD app-of-apps)](./docs/405-GITHUB_ACTIONS.md#what-gets-installed-gitops-via-argocd-app-of-apps)
- [The pipeline, rendered into each fork](./docs/405-GITHUB_ACTIONS.md#the-pipeline-rendered-into-each-fork)

**[406 · Argo Workflows (fourth CI engine)](./docs/406-ARGO_WORKFLOWS.md)**
- [High-level architecture](./docs/406-ARGO_WORKFLOWS.md#high-level-architecture)
- [Selecting the engine (`ci.engine`)](./docs/406-ARGO_WORKFLOWS.md#selecting-the-engine)
- [What gets installed (GitOps via ArgoCD app-of-apps)](./docs/406-ARGO_WORKFLOWS.md#what-gets-installed-gitops-via-argocd-app-of-apps)
- [Server UI on the internet, behind Google IAP](./docs/406-ARGO_WORKFLOWS.md#server-ui-on-the-internet-behind-google-iap)
- [The pipeline, ported](./docs/406-ARGO_WORKFLOWS.md#the-pipeline-ported)
- [Triggers (Argo Events)](./docs/406-ARGO_WORKFLOWS.md#triggers-argo-events)

---

**[501 · Platform Operations](./docs/501-PLATFORM_OPERATIONS.md)**
- [ArgoCD Inventory (GitOps)](./docs/501-PLATFORM_OPERATIONS.md#argocd-inventory-gitops)
  - [Projects & Applications](./docs/501-PLATFORM_OPERATIONS.md#projects--applications)
  - [Security & Integration](./docs/501-PLATFORM_OPERATIONS.md#security--integration)
- [Telemetry Verification & Simulation](./docs/501-PLATFORM_OPERATIONS.md#telemetry-verification--simulation)
  - [1. Continuous Traffic Simulation (GitHub Actions)](./docs/501-PLATFORM_OPERATIONS.md#1-continuous-traffic-simulation-github-actions)
  - [2. On-Demand Smoke Test (Jenkins)](./docs/501-PLATFORM_OPERATIONS.md#2-on-demand-smoke-test-jenkins)
  - [3. How to Verify Correlation in Grafana](./docs/501-PLATFORM_OPERATIONS.md#3-how-to-verify-correlation-in-grafana)
- [Platform QA, Chaos & Compliance Validation](./docs/501-PLATFORM_OPERATIONS.md#platform-qa-chaos--compliance-validation)
  - [1. Automated Compliance Validation Gate](./docs/501-PLATFORM_OPERATIONS.md#1-automated-compliance-validation-gate)
  - [2. Platform Verification & Stress-Test Playbooks](./docs/501-PLATFORM_OPERATIONS.md#2-platform-verification--stress-test-playbooks)
- [Golden Path IDP Modernizations (Node Auto-Provisioning & modern scheduling)](./docs/501-PLATFORM_OPERATIONS.md#golden-path-idp-modernizations-node-auto-provisioning--modern-scheduling)
  - [1. Modern Scheduling Compliance](./docs/501-PLATFORM_OPERATIONS.md#1-modern-scheduling-compliance)
  - [2. Elastic Node Auto-Provisioning (Spot ComputeClass)](./docs/501-PLATFORM_OPERATIONS.md#2-elastic-node-auto-provisioning-spot-computeclass)
  - [3. Zero-Trust Security & Workload Identity](./docs/501-PLATFORM_OPERATIONS.md#3-zero-trust-security--workload-identity)
  - [4. GitOps Separation of Concerns](./docs/501-PLATFORM_OPERATIONS.md#4-gitops-separation-of-concerns)
  - [5. Build Performance & High Availability Caching](./docs/501-PLATFORM_OPERATIONS.md#5-build-performance--high-availability-caching)
  - [6. Progressive Delivery (Argo Rollouts + Gateway API)](./docs/501-PLATFORM_OPERATIONS.md#6-progressive-delivery-argo-rollouts--gateway-api)
- [Headlamp (Cluster Management UI)](./docs/501-PLATFORM_OPERATIONS.md#headlamp-cluster-management-ui)
  - [One-time Setup: Google OAuth Client](./docs/501-PLATFORM_OPERATIONS.md#one-time-setup-google-oauth-client)
  - [Adding Your Identity](./docs/501-PLATFORM_OPERATIONS.md#adding-your-identity)
  - [Accessing the UI](./docs/501-PLATFORM_OPERATIONS.md#accessing-the-ui)
- [Public Access (GKE Gateway API + IAP)](./docs/501-PLATFORM_OPERATIONS.md#public-access-gke-gateway-api--iap)
  - [Authentication & Authorization Matrix](./docs/501-PLATFORM_OPERATIONS.md#authentication--authorization-matrix)
  - [One-time Setup](./docs/501-PLATFORM_OPERATIONS.md#one-time-setup)
  - [Troubleshooting: Load Balancer Propagation Delay](./docs/501-PLATFORM_OPERATIONS.md#troubleshooting-load-balancer-propagation-delay)
- [Pausing & resuming the cluster (cost saving)](./docs/501-PLATFORM_OPERATIONS.md#pausing--resuming-the-cluster-cost-saving)

**[502 · Microservices GitOps](./docs/502-MICROSERVICES_GITOPS.md)**
- [GitOps Design Decision: Helm vs. Kustomize](./docs/502-MICROSERVICES_GITOPS.md#gitops-design-decision-helm-vs-kustomize)
  - [Overview](./docs/502-MICROSERVICES_GITOPS.md#overview)
  - [Side-by-Side Comparison](./docs/502-MICROSERVICES_GITOPS.md#side-by-side-comparison)
  - [Technical Rationale & Mechanics](./docs/502-MICROSERVICES_GITOPS.md#technical-rationale--mechanics)
- [Design Decision: Resource Lifecycle & Decommission Orchestration](./docs/502-MICROSERVICES_GITOPS.md#design-decision-resource-lifecycle--decommission-orchestration)
  - [The Problem: Asynchronous Background Deletion](./docs/502-MICROSERVICES_GITOPS.md#the-problem-asynchronous-background-deletion)
  - [Side-by-Side Comparison of Solutions](./docs/502-MICROSERVICES_GITOPS.md#side-by-side-comparison-of-solutions)
- [pgAdmin & Database Administration](./docs/502-MICROSERVICES_GITOPS.md#pgadmin--database-administration)
  - [SRE Break-Glass CLI (Connecting as Superuser)](./docs/502-MICROSERVICES_GITOPS.md#sre-break-glass-cli-connecting-as-superuser)

---

**[503 · Networking](./docs/503-NETWORKING.md)**
- [Understanding the network (newcomers → specialists)](./docs/503-NETWORKING.md#understanding-the-network-newcomers--specialists)
- [Landing zone & topology — single-VPC, *not* hub-spoke (rationale + growth path)](./docs/503-NETWORKING.md#landing-zone--topology-pattern--single-vpc-not-hub-spoke)
- [VPC & subnet topology + IP address plan](./docs/503-NETWORKING.md#vpc--subnet-topology)
- [North-south: ingress (Gateway + IAP + NEG)](./docs/503-NETWORKING.md#north-south-how-traffic-gets-in-ingress) · [egress (no Cloud NAT)](./docs/503-NETWORKING.md#north-south-how-traffic-gets-out-egress)
- [East-west: pod & service networking (VPC-native · Dataplane V2 · WireGuard)](./docs/503-NETWORKING.md#east-west-pod--service-networking)
- [Segmentation: NetworkPolicies inside GKE](./docs/503-NETWORKING.md#segmentation-networkpolicies-inside-gke)

---

**[504 · Backend TLS (LB→pod re-encryption)](./docs/504-BACKEND_TLS.md)**
- [Why (and why opt-in)](./docs/504-BACKEND_TLS.md#why-and-why-opt-in) · [The flag](./docs/504-BACKEND_TLS.md#the-flag)
- [How it works](./docs/504-BACKEND_TLS.md#how-it-works) · [The GKE mechanics](./docs/504-BACKEND_TLS.md#the-gke-mechanics-what-the-policies-actually-do)
- [Stage 1: why Headlamp](./docs/504-BACKEND_TLS.md#stage-1-why-headlamp) · [Stage 5: the doubly-conditional one (OSS Grafana)](./docs/504-BACKEND_TLS.md#stage-5-the-doubly-conditional-one-oss-grafana) · [Converting the next backend](./docs/504-BACKEND_TLS.md#converting-the-next-backend-roadmap--checklist)
- [Does `secrets.backend=eso` change anything?](./docs/504-BACKEND_TLS.md#does-secretsbackendeso-change-anything) · [**Why not a service mesh?**](./docs/504-BACKEND_TLS.md#why-not-a-service-mesh) (Istio / Cloud Service Mesh comparison)
- [Lifecycle](./docs/504-BACKEND_TLS.md#lifecycle) · [Verifying it](./docs/504-BACKEND_TLS.md#verifying-it)

---

**[505 · Backstage (developer portal / IDP)](./docs/505-BACKSTAGE.md)**
- [Understanding Backstage (newcomers → specialists)](./docs/505-BACKSTAGE.md#understanding-backstage-newcomers--specialists) · [High-level architecture](./docs/505-BACKSTAGE.md#high-level-architecture)
- [Enabling it (the feature flag)](./docs/505-BACKSTAGE.md#enabling-it-the-feature-flag) · [What gets installed (app-of-apps)](./docs/505-BACKSTAGE.md#what-gets-installed-gitops-via-argocd-app-of-apps)
- [The portal behind Google IAP](./docs/505-BACKSTAGE.md#the-portal-on-the-internet-behind-google-iap) · [The app image (compile-time plugins, runtime engine)](./docs/505-BACKSTAGE.md#the-app-image-compile-time-plugins-runtime-engine)
- [The catalog](./docs/505-BACKSTAGE.md#the-catalog) · [**CI-engine integration (the four tabs)**](./docs/505-BACKSTAGE.md#ci-engine-integration-the-four-tabs) · [GitOps & Kubernetes views](./docs/505-BACKSTAGE.md#gitops--kubernetes-views-engine-independent)
- [TechDocs](./docs/505-BACKSTAGE.md#techdocs) · [Credentials & RBAC](./docs/505-BACKSTAGE.md#credentials--rbac) · [Backend TLS (stage 10)](./docs/505-BACKSTAGE.md#backend-tls-stage-10)
- [Day-2 operations](./docs/505-BACKSTAGE.md#day-2-operations) · [Troubleshooting](./docs/505-BACKSTAGE.md#troubleshooting) · [Teardown](./docs/505-BACKSTAGE.md#teardown) · [Roadmap](./docs/505-BACKSTAGE.md#roadmap)

---

**[601 · DevSecOps](./docs/601-DEVSECOPS.md)**
- [Pipeline Lifecycle](./docs/601-DEVSECOPS.md#pipeline-lifecycle)
- [Integrated Security Tools](./docs/601-DEVSECOPS.md#integrated-security-tools)
  - [1. Semgrep (Lightweight SAST / Custom Rules)](./docs/601-DEVSECOPS.md#1-semgrep-lightweight-sast--custom-rules)
  - [2. CodeQL (Deep SAST / Semantic Analysis)](./docs/601-DEVSECOPS.md#2-codeql-deep-sast--semantic-analysis)
  - [3. Trivy (Vulnerability and Misconfiguration Scanning)](./docs/601-DEVSECOPS.md#3-trivy-vulnerability-and-misconfiguration-scanning)
  - [4. Jenkins `warnings-ng` Plugin Integration (SARIF Visualizer)](./docs/601-DEVSECOPS.md#4-jenkins-warnings-ng-plugin-integration-sarif-visualizer)

---

**[602 · Version Pinning](./docs/602-VERSION_PINNING.md)**
- [Why pin — and the trade-off](./docs/602-VERSION_PINNING.md#why-pin--and-the-trade-off)
- [The matrix](./docs/602-VERSION_PINNING.md#the-matrix)
- [The ArgoCD version policy — pinned to stable 3.4.x](./docs/602-VERSION_PINNING.md#the-argocd-version-policy--pinned-to-stable-34x)
- [GitHub Actions: SHA pins + Dependabot](./docs/602-VERSION_PINNING.md#github-actions-sha-pins--dependabot)
- [How to bump a pin](./docs/602-VERSION_PINNING.md#how-to-bump-a-pin)

---

**[901 · Local Development](./docs/901-LOCAL_DEVELOPMENT.md)**
- [Prerequisites](./docs/901-LOCAL_DEVELOPMENT.md#prerequisites)
- [Quick Start](./docs/901-LOCAL_DEVELOPMENT.md#quick-start)
- [Step-by-Step Deployment Guide](./docs/901-LOCAL_DEVELOPMENT.md#step-by-step-deployment-guide-for-other-people)
  - [Step 1: Fork and Clone the Repositories](./docs/901-LOCAL_DEVELOPMENT.md#step-1-fork-and-clone-the-repositories)
  - [Step 2: Configure Repository Targets](./docs/901-LOCAL_DEVELOPMENT.md#step-2-configure-repository-targets)
  - [Step 3: Bootstrap — Root of Trust + Public DNS Zone](./docs/901-LOCAL_DEVELOPMENT.md#step-3-bootstrap--root-of-trust--public-dns-zone)
  - [Step 4: Configure GKE / OAuth Credentials (Optional)](./docs/901-LOCAL_DEVELOPMENT.md#step-4-configure-gke--oauth-credentials-optional)
  - [Step 5: Add Remaining GitHub Repository Secrets](./docs/901-LOCAL_DEVELOPMENT.md#step-5-add-remaining-github-repository-secrets)
  - [Step 6: (Optional) Set Up Grafana Cloud Stack](./docs/901-LOCAL_DEVELOPMENT.md#step-6-optional-set-up-grafana-cloud-stack)
  - [Step 7: Deploy the Stack](./docs/901-LOCAL_DEVELOPMENT.md#step-7-deploy-the-stack)
  - [Step 8: Run Pipelines & Verify](./docs/901-LOCAL_DEVELOPMENT.md#step-8-run-pipelines--verify)
- [Automated End-to-End Test](./docs/901-LOCAL_DEVELOPMENT.md#automated-end-to-end-test-provisioning--decommissioning)
  - [Running It](./docs/901-LOCAL_DEVELOPMENT.md#running-it)
  - [Prerequisites for e2e](./docs/901-LOCAL_DEVELOPMENT.md#prerequisites-for-e2e)
  - [Resource Quotas & QoS (Cost Control)](./docs/901-LOCAL_DEVELOPMENT.md#resource-quotas--qos-cost-control)
  - [Terraform Version & Stacks](./docs/901-LOCAL_DEVELOPMENT.md#terraform-version--stacks)

**[902 · Troubleshooting](./docs/902-TROUBLESHOOTING.md)**
- [Common Issues](./docs/902-TROUBLESHOOTING.md#common-issues)
- [ArgoCD OIDC Issues](./docs/902-TROUBLESHOOTING.md#argocd-oidc-issues)
- [Terraform & CI Issues](./docs/902-TROUBLESHOOTING.md#terraform--ci-issues)
- [Jenkins & GitOps Push Issues](./docs/902-TROUBLESHOOTING.md#jenkins--gitops-push-issues)

---

**[903 · Glossary](./docs/903-GLOSSARY.md)**
- [Lifecycle vocabulary](./docs/903-GLOSSARY.md#lifecycle-vocabulary)
- [Platform acronyms](./docs/903-GLOSSARY.md#platform-acronyms)
- [Repo-specific terms of art](./docs/903-GLOSSARY.md#repo-specific-terms-of-art)

---

**[docs/ — documentation index & reading map](./docs/README.md)** — the docs/ folder README with the numbering taxonomy, role-based reading paths, and authoring conventions.

**[Runbooks](./docs/runbooks/)**
- [Log Correlation Validation](./docs/runbooks/log-correlation-validation.md) — step-by-step procedure to validate logs ↔ metrics ↔ traces correlation end-to-end (enable DEBUG logging, restart pods, generate traffic, verify in Grafana)
  - [Background](./docs/runbooks/log-correlation-validation.md#background)
  - [0. Context](./docs/runbooks/log-correlation-validation.md#0-context)
  - [1. Land the change — sync ArgoCD](./docs/runbooks/log-correlation-validation.md#1-land-the-change--sync-argocd)
  - [2. Verify the ConfigMap carries the DEBUG logger](./docs/runbooks/log-correlation-validation.md#2-verify-the-configmap-carries-the-debug-logger)
  - [3. Restart pods so they re-read the ConfigMap](./docs/runbooks/log-correlation-validation.md#3-️-restart-pods-so-they-re-read-the-configmap)
  - [4. Generate traffic](./docs/runbooks/log-correlation-validation.md#4-generate-traffic)
  - [5. Pod-level proof: DEBUG lines carry `trace_id`](./docs/runbooks/log-correlation-validation.md#5-pod-level-proof-debug-lines-carry-trace_id)
  - [6. Grafana — prove both correlation directions](./docs/runbooks/log-correlation-validation.md#6-grafana--prove-both-correlation-directions)
  - [Rollback](./docs/runbooks/log-correlation-validation.md#rollback)
  - [Gotchas](./docs/runbooks/log-correlation-validation.md#gotchas-why-panels-can-look-empty-without-anything-being-broken)
- [NAP → Spot CI nodes](./docs/runbooks/nap-spot-provisioning.md) — live validation that GKE Node Auto-Provisioning + the `ci-spot` ComputeClass bring up Spot, scale-to-zero nodes for CI build agents, and how to read the `SSD_TOTAL_GB` quota ceiling that actually bounds it
  - [Background — what should happen](./docs/runbooks/nap-spot-provisioning.md#background--what-should-happen)
  - [0. Get cluster access (the gotchas)](./docs/runbooks/nap-spot-provisioning.md#0-get-cluster-access-the-gotchas-in-order)
  - [1. Confirm the flag reached Jenkins (no build needed)](./docs/runbooks/nap-spot-provisioning.md#1-confirm-the-flag-reached-jenkins-no-build-needed)
  - [2. Trigger a build and watch the agent + node](./docs/runbooks/nap-spot-provisioning.md#2-trigger-a-build-and-watch-the-agent--node)
  - [3. The real ceiling: `SSD_TOTAL_GB` quota](./docs/runbooks/nap-spot-provisioning.md#3-the-real-ceiling-ssd_total_gb-quota-the-part-everyone-trips-on)
  - [4. Cold-start caveat (first build on a fresh Spot node)](./docs/runbooks/nap-spot-provisioning.md#4-cold-start-caveat--the-first-build-on-a-fresh-spot-node-is-slow)
  - [Troubleshooting — agent stuck Pending](./docs/runbooks/nap-spot-provisioning.md#troubleshooting--agent-stuck-pending)
- [CNPG Restore from Backup](./docs/runbooks/cnpg-restore-from-backup.md) — recover a microservices Postgres database from the barman GCS backups (base backup + WAL / point-in-time recovery): when to restore vs when a rebuild is *meant* to start empty, the concrete CNPG `bootstrap.recovery` manifest, PITR target selection, and the `Expected empty archive` cutover gotcha
  - [Background — what is backed up, and where](./docs/runbooks/cnpg-restore-from-backup.md#background--what-is-backed-up-and-where)
  - [0. Get cluster access](./docs/runbooks/cnpg-restore-from-backup.md#0-get-cluster-access-the-windowssdk-gotchas)
  - [1. Decide: do you actually want to restore? (When NOT to)](./docs/runbooks/cnpg-restore-from-backup.md#1-decide-do-you-actually-want-to-restore-when-not-to)
  - [2. Confirm the backups exist and are usable](./docs/runbooks/cnpg-restore-from-backup.md#2-confirm-the-backups-youre-about-to-restore-from-exist-and-are-usable)
  - [3. Restore — CNPG `bootstrap.recovery` from the object store](./docs/runbooks/cnpg-restore-from-backup.md#3-restore--cnpg-bootstraprecovery-from-the-object-store)
  - [4. Choosing the PITR target](./docs/runbooks/cnpg-restore-from-backup.md#4-choosing-the-pitr-target)
  - [5. Cut over and re-enable GitOps](./docs/runbooks/cnpg-restore-from-backup.md#5-cut-over-and-re-enable-gitops)
  - [6. Verify the restore](./docs/runbooks/cnpg-restore-from-backup.md#6-verify-the-restore)
  - [6b. The serverName / system-id gotcha (Expected empty archive)](./docs/runbooks/cnpg-restore-from-backup.md#6b-the-servername--system-id-gotcha-expected-empty-archive)
  - [Troubleshooting](./docs/runbooks/cnpg-restore-from-backup.md#troubleshooting)


## 1. Document Inventory

| Code | Category | Document | Description |
| :--- | :--- | :--- | :--- |
| **100** | Bootstrap | [Bootstrap — the Root of Trust](./docs/100-BOOTSTRAP.md) | The **Day0 "phase 0"** root of trust: the one-command, human-run `scripts/bootstrap.sh up`/`down` that creates/destroys the **WIF trust + GCS state bucket + CI service account + permanent DNS zone**, the **bootstrap paradox** (why it can't be a workflow), and the **self-hosted-state** model |
| **101** | CI/CD Workflows | [GitHub Actions Workflows](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md) | `DayN.tier.ZZ-resource` **naming scheme**, **lifecycle phases**, the per-`ZZ` lifecycle matrix, **full workflow matrix** with clickable GitHub Actions links, lifecycle **Mermaid diagram**, complete numbered inventory (incl. the opt-in **`Decom.infra.00-all` teardown umbrella**) |
| **102** | CI/CD Workflows | [GitHub Actions Automation](./docs/102-GITHUB_ACTIONS_AUTOMATION.md) | **WIF setup**, GitHub secrets reference, **bootstrapping architecture** (**persistent vs. short-lived** resources), `git_ref` parameter, **environment protection / manual approvals** |
| **103** | CI/CD Workflows | [GitHub Secrets & Variables Inventory](./docs/103-GITHUB_SECRETS_INVENTORY.md) | **Every GitHub Actions secret and repository variable** used across the workflows — purpose, **required vs. optional**, source, which subsystem; incl. the **keyless WIF/OIDC** identifiers and the `AWS_REGION` repo variable |
| **104** | CI/CD Workflows | [Rebuild-Safety (`Decom` + `Day1`)](./docs/104-REBUILD_SAFETY.md) | Why **destroy → recreate** must always converge: the **collision vs residue** bug class (+ the Postgres WAL exemplar), the **rebuild-safety design patterns** toolbox, the **safe-by-design matrix** (state/buckets · GKE · DNS/gateway · identity/secrets · obs backends · teardown residue · registry/GitOps/CI), the closed gaps, and the **live-verification checklist** |
| **201** | Architecture | [Architecture](./docs/201-ARCHITECTURE.md) | **System architecture** + component diagram, **microservices & database architecture (CNPG)**, **CI/CD flow**, the **imperative (push) vs GitOps (pull)** provisioning inventory, **namespaces & in-cluster secrets**, configuration ([`config/config.yaml`](config/config.yaml)), repository layout, **GKE cluster topology**, **FinOps** & cost analysis |
| **202** | Architecture | [Microservices App Architecture](./docs/202-MICROSERVICES-APP-ARCHITECTURE.md) | The **demo application** — and **why JHipster** (a production-shaped demo, not a toy) + **why the repos are forks**: the JHipster **gateway (Java, not Angular)** + the **Angular SPA** it serves + the backend microservice, **request flow**, **database-per-service**, and the **implemented Angular-RUM frontend observability** (Grafana Faro) |
| **301** | Observability | [Observability](./docs/301-OBSERVABILITY.md) | **OTel components** (Operator, Java agent, Angular RUM, Collector), telemetry architecture, **signal correlation** (metrics↔traces↔logs), structured logging, dashboards, **alert rules**, k6 smoke test, **all four observability modes** |
| **302** | Observability | [k6 Traffic, Load & Observability Testing](./docs/302-K6_LOAD_TESTING.md) | The **parametrizable k6 engine**: the unified **`K6SIM_*` contract**, **profiles** (smoke/load/stress/soak/spike/breakpoint), **committed config presets** (dropdown-selectable) with an **inventory matrix + per-preset diagrams**, the same script run from **Jenkins/Tekton/GitHub Actions/Argo Workflows**, **`stable`-vs-`develop`** targeting, **basic & advanced tutorials**, and the **layered (basic→expert) result analysis** |
| **303** | Performance | [JVM Tuning & Runtime Strategy](./docs/303-JVM-TUNING.md) | JVM tuning for the Java microservices: the **container-default trap** (SerialGC + 25% heap) and the **G1/heap fix**, **GC-algorithm + runtime-option matrices** (HotSpot+G1 · AOT cache · **CRaC** · GraalVM Native · OpenJ9), **OTel instrumentation modes** (agent vs Spring starter vs eBPF), why **CRaC** is the chosen advanced direction, and how to read the **JVM-internals dashboard** |
| **401** | Jenkins | [Jenkins](./docs/401-JENKINS.md) | Accessing the UI & **admin password**, **Google OIDC** login, **plugins & JCasC** fragments, global **shared library**, **MCP server** |
| **402** | Jenkins | [Pipelines as Code](./docs/402-PIPELINES_AS_CODE.md) | **Seed job**, **branch & environment mapping** (incl. the optional lean **`develop` tier** + its stable-vs-develop rationale), **pipeline execution stages** (Semgrep/CodeQL/Trivy/Build/Deploy/Smoke), **container security**, reliability fixes |
| **403** | Jenkins | [Declarative vs Scripted](./docs/403-DECLARATIVE_VS_SCRIPTED.md) | **Declarative-vs-Scripted tutorial + the repo's three-layer hybrid**: the two Groovy dialects (**two syntaxes over the same CPS engine — neither built on the other**), the **comparison matrix** + full advantages/disadvantages, **when Jenkins recommends which**, how the repo splits **Job DSL seed (generation) → Declarative pipeline shells → Scripted `vars/` steps**, the **per-file classification map**, **counterexamples** (what breaks all-scripted / all-declarative), and **mermaid diagrams** |
| **404** | Tekton | [Tekton](./docs/404-TEKTON.md) | **Alternative CI engine** (`ci.engine` flag) — Tekton **Pipelines/Triggers/Dashboard** + **Pipelines-as-Code**, IAP-protected Dashboard, the microservices pipeline ported to [`tekton/`](tekton/), **credentials & observability parity** |
| **405** | GitHub Actions / ARC | [GitHub Actions / ARC](./docs/405-GITHUB_ACTIONS.md) | **Third CI engine** (`ci.engine=githubactions`) — GitHub Actions self-hosted runners via **ARC** (Actions Runner Controller): ephemeral **Spot** runners on the `ci-spot` NAP ComputeClass, native **GitHub webhooks** (GitHub App), **no** in-cluster UI/Gateway route, the `argocd/githubactions` app-of-apps, same `services.yaml`/GHCR/GitOps/OTel contract |
| **406** | Argo Workflows | [Argo Workflows](./docs/406-ARGO_WORKFLOWS.md) | **Fourth CI engine** (`ci.engine=argoworkflows`) — **Argo Workflows + Argo Events** (argoproj): the pipeline as a WorkflowTemplate, an **IAP-protected Argo Workflows Server UI** (`argo.<domain>`) **plus** a public, HMAC-protected **Argo Events webhook receiver** (`argo-events.<domain>`), the `argocd/argoworkflows` app-of-apps (controller+server / Events+EventBus / pipeline-as-code, **vendored** release YAMLs), same `services.yaml`/GHCR/GitOps/OTel contract |
| **501** | Platform | [Platform Operations](./docs/501-PLATFORM_OPERATIONS.md) | **ArgoCD inventory**, telemetry simulation, **platform QA & chaos** scenarios, **Golden Path IDP** modernizations (**Node Auto-Provisioning** + modern scheduling), **Headlamp** cluster UI, **GKE Gateway API + IAP** public access, **Argo Rollouts** progressive delivery |
| **502** | Microservices | [Microservices GitOps](./docs/502-MICROSERVICES_GITOPS.md) | **Helm vs. Kustomize** design decision, **resource lifecycle & decommission** orchestration (**NEG synchronization barrier**), **parameterized CNPG HA** (stable vs lean develop), **pgAdmin** & database administration |
| **503** | Networking | [Networking](./docs/503-NETWORKING.md) | Network architecture, **landing zone & topology** (single-VPC, *not* hub-spoke — with rationale + growth path), VPC/subnet + pod/service **CIDR plan**, north-south **ingress** (Gateway + IAP + container-native NEG) & **egress** (no Cloud NAT, the four observability backends), east-west (VPC-native + **Dataplane V2** + **WireGuard**), **NetworkPolicy segmentation** inside GKE, defense-in-depth |
| **504** | Platform ops | [Backend TLS (LB→pod re-encryption)](./docs/504-BACKEND_TLS.md) | The **opt-in** `gateway.backendTls.enabled` hardening — **cert-manager** in-cluster CA + per-backend TLS + Gateway API **`BackendTLSPolicy`** so the LB validates the backend cert; the **GKE mechanics**, the staged per-backend rollout, why it's **not** a service mesh (Istio / Cloud Service Mesh comparison), and why ESO doesn't touch it |
| **505** | Platform ops | [Backstage (developer portal / IDP)](./docs/505-BACKSTAGE.md) | **Backstage v1.52.1** (official Helm chart 2.8.2 + a **custom app image**) as the platform's developer portal: software **catalog** of the microservices + platform, **engine-aware CI/CD tabs** (one image ships the Jenkins/GitHub Actions/Tekton plugins; the active `ci.engine` is picked at **runtime**), **ArgoCD + Kubernetes** views, **TechDocs** rendering these very docs, behind **Google IAP** with in-app **JWT-verified** `gcpIap` sign-in (no second login), CNPG-backed, **backend TLS stage 10**, and the one-time `Day2.publish.06` image bootstrap |
| **601** | Security | [DevSecOps](./docs/601-DEVSECOPS.md) | **Semgrep** SAST, **CodeQL** deep SAST, **Trivy** IaC + image scanning, **`warnings-ng`** plugin SARIF dashboards in Jenkins |
| **602** | Security | [Version Pinning](./docs/602-VERSION_PINNING.md) | **Version-pinning policy + matrix** (charts, images, `yq`, GitHub Actions SHAs, Terraform lockfiles), pros/cons, the deliberate **ArgoCD 3.4.x auto-tracking exception** (off the buggy 3.5.0-rc), how to bump a pin |
| **901** | Reference | [Local Development](./docs/901-LOCAL_DEVELOPMENT.md) | **Prerequisites**, **quick start**, step-by-step deployment guide, automated **e2e test** ([`test/e2e.sh`](test/e2e.sh)), **resource quotas & QoS**, Terraform version |
| **902** | Reference | [Troubleshooting](./docs/902-TROUBLESHOOTING.md) | **Common issues**, ArgoCD OIDC, Terraform & CI, **Jenkins & GitOps push authentication failures** |
| **903** | Reference | [Glossary](./docs/903-GLOSSARY.md) | Single-lookup **glossary** of the vocabulary recurring across every guide: **lifecycle** (Day0/Day1/Day2/Decom, `DayN.tier.ZZ`, tier, ZZ, the two teardown umbrellas, `stable`/`develop` tiers), **platform acronyms** (WIF · OIDC · IAP · NEG · NAP · ComputeClass · ARC · PaC · JCasC · ESO · CNPG · Dataplane V2 · app-of-apps · AppSet · JHipster · OTel/OTLP), and **repo terms of art** (seed job, shared library `vars/`, `retire_ci_engine`, imperative-vs-GitOps planes, self-hosted state, the bootstrap paradox, the `K6SIM_*` contract) — each one line + a link to its owning doc |

> **New here?** [`docs/README.md`](./docs/README.md) is a reading map over this table — the numbering scheme, role-based reading paths (newcomer / operator / SRE / platform engineer / security reviewer), the runbooks, and the doc-authoring conventions.

---

## 2. Quick Start

```bash
# 0. (once, before anything else) Bootstrap the GCP root of trust — WIF trust, GCS
#    state bucket, CI service account, permanent DNS zone, and the 4 GitHub repo
#    secrets. See docs/100-BOOTSTRAP.md.
./scripts/bootstrap.sh up

# 1. Review/edit config/config.yaml — observability.mode (grafana-cloud|oss|managed-azure|managed-aws),
#    ci.engine (jenkins|tekton|githubactions|argoworkflows), secrets.backend (imperative|eso).
#    Default: grafana-cloud + jenkins + imperative. (CI matrix overrides: JENKINS2026_* env vars.)

# 2. (grafana-cloud mode only) create the OTLP credentials secret:
cp observability/otel-collector/secret.example.yaml observability/otel-collector/secret.yaml
#    edit secret.yaml (Grafana Cloud OTLP endpoint + base64(instanceID:apiKey)), then:
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f observability/otel-collector/secret.yaml

# 2b. (managed-azure / managed-aws mode) the observability backend is a persistent,
#     CI-provisioned resource — do its ONE-TIME setup BEFORE Day1: create the cloud
#     bootstrap identity, set the publish credential (AZURE_PUBLISH_CLIENT_ID /
#     AWS_DASHBOARD_PUBLISH_ROLE_ARN), and run Day0.infra.03 (Azure) / Day0.infra.04 (AWS).
#     Full step-by-step: docs/102 § "One-time Setup" (steps 6-7) + docs/103. Skipping it
#     makes Day1's azure/aws login fail ("client-id / role not supplied").

# 3. (optional) registry/git creds consumed by scripts/01-namespaces.sh
#    (needed if MICROSERVICES_REGISTRY packages are private — the GHCR default):
export REGISTRY_USERNAME=<github-username> REGISTRY_PASSWORD=<ghcr-token>
export GIT_USERNAME=<github-username>      GIT_TOKEN=<github-token>

# 4. provision everything:
./scripts/up.sh

# 5. check status / get port-forward commands:
./scripts/status.sh

# tear down (namespaces kept by default; see scripts/down.sh):
./scripts/down.sh
```

See [901. Local Development](./docs/901-LOCAL_DEVELOPMENT.md) for the full step-by-step guide.

---

## 3. Architecture Overview

Several pluggable choices (the [feature-flag table](#jenkins-2026) above), all deterministic & idempotent — the two big ones are the **CI engine** (`ci.engine`: one of four — **Jenkins** default / **Tekton** / **GitHub Actions (ARC)** / **Argo Workflows**, all sharing one ~11-stage contract) and the **observability backend** (`observability.mode`: one of oss / grafana-cloud / managed-azure / managed-aws), plus the opt-in **secrets backend** (`secrets.backend=eso` → GCP Secret Manager) and the optional **lean `develop` tier**. ArgoCD is always the CD/GitOps engine.

<details>
<summary>🏛️ Architecture overview — pluggable CI engine + observability backend</summary>

```mermaid
---
config:
  layout: elk
  flowchart:
    nodeSpacing: 25
    rankSpacing: 45
---
flowchart TB
      subgraph EXT["External (github.com · browser · registry)"]
        direction TB
        users(["users · browser SPA (public)"]):::ext
        ghaIac(["gha-iac · GitHub Actions IaC driver<br/>OIDC→WIF · NOT a CI engine"]):::ext
        forks(["app forks · gateway + msvc<br/>(source · CI checkout & webhooks)"]):::ext
        gitops(["gitops-repo · direct-push main"]):::ext
        ghcr(["ghcr.io/nubenetes · images"]):::ext
      end
      subgraph L0["L0 · Day0 root-of-trust (human-run · NEVER torn down)"]
        direction TB
        BOOT["BOOT · terraform/bootstrap<br/>state local→GCS"]:::prov
        WIF["WIF · OIDC→WIP · repo-scoped"]:::prov
        CISA["CI SA jenkins-2026-ci<br/>container/net/dns/secret/cert admin"]:::prov
        STATE[("GCS state bucket<br/>versioned · per-module prefixes")]:::prov
        DNSZONE["DNS zone jenkins-2026-public-zone<br/>one-time parent NS delegation"]:::prov
        PGBK[("postgres-backups bucket<br/>← CNPG WAL archive (L4)")]:::prov
      end
      subgraph L1["L1 · Provisioning / IaC (one bucket · prefixes)"]
        direction TB
        GWB["gateway-bootstrap (PERSISTENT)<br/>static IP · wildcard cert · A/CNAME"]:::iac
        GKETF["terraform/gke (throwaway)<br/>Dataplane V2 + WireGuard · immutable"]:::iac
        OBSTF["obs-backend modules (ephemeral)<br/>gcloud · azure · aws"]:::iac
      end
      subgraph L2["L2 · GCP edge"]
        direction TB
        DNS["Cloud DNS wildcard → IP"]:::edge
        LB["L7 LB · wildcard TLS · edge-terminated"]:::edge
        IAPN["Identity-Aware Proxy<br/>admin allowlist"]:::edge
        GW["Gateway (ns platform-ingress)<br/>HTTPRoutes · GCPBackendPolicy"]:::edge
      end

      subgraph CP["L3 · Control plane (GKE)"]
        direction TB
        ACD["ArgoCD 3.4.x (always the CD engine)<br/>1 AppSet · app-of-apps · single apps"]:::ctrl
        subgraph CIENG["CIENG · pick EXACTLY ONE (ci.engine)"]
          direction TB
          CONTRACT["shared ~11-stage contract<br/>patch-app-source.sh · services.yaml"]:::contract
            JEN["JEN · jenkins (default *)<br/>chart · JCasC · IAP UI"]:::eng1
            TEK["TEK · tekton<br/>CRDs · IAP Dash · PaC"]:::eng2
            GHAARC["GHA-ARC · GitHub Actions/ARC<br/>ephemeral · ci-spot · NO in-cluster UI"]:::eng3
            ARGOWF["ARGOWF · argoworkflows<br/>WF v3.7.16 + Events · IAP UI"]:::eng4
        end
        OPS["OPS · Operators<br/>ESO · OTel · CNPG · Argo Rollouts"]:::ctrl
        PUIS["PUIS · platform web UIs (IAP)<br/>Headlamp · pgAdmin · Backstage · Grafana (oss)"]:::ctrl
        PUSH["PUSH · imperative lane (0N-*.sh)<br/>creds · NetPol · Quotas"]:::push
      end
      subgraph DP["L4 · Data / runtime plane (ns microservices)"]
        direction TB
        GWAPP["gateway :8080<br/>serves Angular SPA · MySQL→PG patch"]:::data
        MSVC["jhipstersamplemicroservice :8081"]:::data
        POOL["PgBouncer Poolers (session)"]:::data
        PG[("CNPG per svc · 3-replica HA")]:::data
        DEVTIER["develop tier (optional · off)<br/>ns -develop · 1-click · non-HA"]:::dev
      end
      subgraph NODES["Node substrate"]
        direction TB
        STATICP["static pool (e2-standard-8 · 2–4)"]:::node
        NAP["NAP → ci-spot ComputeClass<br/>Spot · scale-to-zero"]:::node
        QUOTA["SSD_TOTAL_GB=500 ceiling"]:::node
      end

      subgraph OBSP["L5 · Observability pipeline"]
        direction TB
        SRCS["sources (4): Java agent · CI · k6 · Faro RUM"]:::obs
        COLG["otel-collector-gateway (Deploy)<br/>OTLP + faro · span/service connectors"]:::obs
        COLL["otel-collector-logs (DaemonSet)"]:::obs
      end
      subgraph BK["BK · pick EXACTLY ONE (observability.mode)"]
        direction TB
          OSS["OSS in-cluster<br/>Prom·Loki·Tempo·Grafana"]:::bk1
          GCLOUD["grafana-cloud<br/>Mimir/Tempo/Loki · Alloy"]:::bk2
          AZ["managed-azure<br/>azuremonitor · Entra SP (oauth2client)"]:::bk3
          AWS["managed-aws<br/>xray+cloudwatch · keyless OIDC"]:::bk4
          LLMAI["Grafana LLM app (opt-in · off)<br/>LiteLLM → Vertex Gemini · WIF keyless"]:::dev
      end
      subgraph AEDGE["Public CI webhooks (HMAC · NO IAP)"]
        direction TB
        ARGOEV["Argo Events · argo-events.&lt;dom&gt;<br/>Sensor → 1 Workflow/push"]:::eng4
        PACWH["Tekton PaC EventListener · pac.&lt;dom&gt;"]:::eng2
      end
      SM["GCP Secret Manager (secrets.backend=eso)<br/>ClusterSecretStore · keyless WIF"]:::sm


    ghaIac -->|"OIDC"| WIF
    WIF -->|"impersonate (keyless)"| CISA
    BOOT --> WIF & CISA & STATE & DNSZONE & PGBK
    CISA -->|"terraform apply"| GWB & GKETF & OBSTF
    GWB -->|"static IP + cert"| GW
    GWB -. "records" .-> DNSZONE
    GKETF -->|"creates cluster"| ACD
    GKETF -. "obs outputs → Secrets" .-> OBSTF
    DNSZONE --> DNS

    users --> DNS --> LB --> IAPN --> GW
    GW -->|"IAP UI: jenkins·tekton·argo"| JEN & TEK & ARGOWF
    GW -->|"IAP UI: headlamp·pgadmin·grafana"| PUIS
    GW -->|"open: microservices·faro·argocd"| GWAPP & SRCS & ACD
    GW -->|"HMAC public"| ARGOEV & PACWH
    forks -. "push webhooks" .-> PACWH & ARGOEV

    CISA -->|"up.sh 00→09"| ACD
    ACD -->|"installs / syncs"| CONTRACT & OPS & GWAPP
    PUSH -. "companions" .-> CONTRACT & GWAPP
    OPS -. "OTel inject · ESO/CNPG WIF" .-> GWAPP
    CONTRACT --- JEN & TEK & GHAARC & ARGOWF
    TEK -. "webhook" .-> PACWH
    ARGOWF -. "webhook" .-> ARGOEV

    forks -->|"checkout source"| CONTRACT
    CONTRACT -->|"build & push"| ghcr
    CONTRACT -. "image-tag bump" .-> gitops
    gitops -->|"ArgoCD source"| ACD
    DEVTIER -. "1-click" .- CONTRACT

    GWAPP -->|"/services/**"| MSVC
    GWAPP --> POOL
    MSVC --> POOL
    POOL --> PG
    CONTRACT -. "agents land on" .-> NAP
    ACD -. "platform on" .-> STATICP
    NAP -. "competes" .-> QUOTA

    GWAPP -->|"OTLP (agent)"| SRCS
    CONTRACT -->|OTLP| SRCS
    SRCS --> COLG
    GWAPP -. "stdout" .-> COLL
    COLG -->|"exactly ONE active"| OSS & GCLOUD & AZ & AWS
    COLL --> OSS & GCLOUD & AZ & AWS
    OSS -. "AI assistant (llm.enabled · oss only)" .-> LLMAI

    PUSH -. "seed values (eso)" .-> SM
    OPS -->|"ESO · keyless WIF"| SM


    classDef ext fill:#fde3f1,stroke:#c0398a,color:#000;
    classDef prov fill:#fdeccb,stroke:#c98a12,color:#000;
    classDef iac fill:#fbe0c3,stroke:#c26a1a,color:#000;
    classDef edge fill:#d9f0ff,stroke:#1f7ab0,color:#000;
    classDef ctrl fill:#e3e6ff,stroke:#4a55c0,color:#000;
    classDef data fill:#d9f7e3,stroke:#249050,color:#000;
    classDef dev fill:#f0f4d8,stroke:#8a9a3a,color:#000;
    classDef node fill:#eef0f2,stroke:#7a7f88,color:#000;
    classDef push fill:#ffe0e0,stroke:#c05050,color:#000;
    classDef obs fill:#ece0ff,stroke:#7a52c0,color:#000;
    classDef contract fill:#fff2cc,stroke:#c9a227,color:#000;
    classDef sm fill:#d9f2f2,stroke:#2b8a8a,color:#000;
    classDef eng1 fill:#dcefe6,stroke:#2f9e6f,color:#000;
    classDef eng2 fill:#dce8f7,stroke:#3a6fb0,color:#000;
    classDef eng3 fill:#f7e6dc,stroke:#c07030,color:#000;
    classDef eng4 fill:#efdcf7,stroke:#9040b0,color:#000;
    classDef bk1 fill:#d6f5ec,stroke:#1f9e86,color:#000;
    classDef bk2 fill:#fce7d6,stroke:#d07a2a,color:#000;
    classDef bk3 fill:#d9e8fb,stroke:#2a6fd0,color:#000;
    classDef bk4 fill:#fdf0d0,stroke:#c99a1a,color:#000;

    style EXT fill:#fef2f8,stroke:#c0398a,color:#000;
    style L0 fill:#fff8ec,stroke:#c98a12,color:#000;
    style L1 fill:#fdf3ea,stroke:#c26a1a,color:#000;
    style L2 fill:#eef8ff,stroke:#1f7ab0,color:#000;
    style CP fill:#f0f1fc,stroke:#4a55c0,color:#000;
    style CIENG fill:#fffdf2,stroke:#c9a227,color:#000;
    style DP fill:#e9fbf0,stroke:#249050,color:#000;
    style NODES fill:#f4f6f8,stroke:#7a7f88,color:#000;
    style AEDGE fill:#fdeee4,stroke:#c07030,color:#000;
    style OBSP fill:#f3ecff,stroke:#7a52c0,color:#000;
    style BK fill:#f0fbf7,stroke:#1f9e86,color:#000;
```

</details>

**How to read it — top-down, by layer:**

- **L0 · Day0 root-of-trust** — human-run, *never* torn down: WIF/OIDC keyless trust · the GCS Terraform-state bucket · the permanent DNS zone · the Postgres-backups bucket (the CNPG WAL archive).
- **L1 · Provisioning / IaC** — Terraform (one state bucket, per-module prefixes).
- **L2 · GCP edge** — DNS → L7 LB → **IAP** → Gateway.
- **L3 · Control plane** —
  - **ArgoCD** — always the CD/GitOps engine.
  - the **chosen CI engine** — 1 of 4 (Jenkins · Tekton · GitHub Actions/ARC · Argo Workflows); see *Pluggable choices* below.
  - **operators** — External Secrets · OTel · CNPG · Argo Rollouts.
  - the IAP-protected **platform web UIs** — Headlamp · pgAdmin · Backstage (the developer portal, [505](./docs/505-BACKSTAGE.md)) · Grafana (oss mode).
  - the imperative **push** lane ArgoCD doesn't own.
- **L4 · Data / runtime plane** — the JHipster gateway + microservice + CloudNative-PG, on the static-vs-NAP node substrate.
- **L5 · Observability pipeline** — the OpenTelemetry collectors.
- **L6 · Backend store** — the one active backend.

**Colours:**

- **Fill colour = component *type*.** Each node & subgraph is tinted by type — external · Day0 root-of-trust · L1 IaC · edge · control plane · data/runtime · develop tier · node substrate · imperative-push · observability · shared CI contract · Secret Manager. Every subgraph carries its own tint, so no two containers share one colour (the old diagram's flaw).
  - The **four CI engines** each get a distinct hue, grouped in the pick-ONE `CIENG` box.
  - The **four observability backends** each get a distinct hue, grouped in the pick-ONE `BK` box.

**Pluggable choices** — each deterministic & idempotent, exactly **one value per cluster**, set in `config/config.yaml` (or the `Day1.cluster.01` inputs) and switched on a re-run. (**ArgoCD is always the CD/GitOps engine** — not pluggable.)

1. **CI engine** (`ci.engine`) — **one of four**, mutually exclusive (switching retires the other three via the shared `retire_ci_engine` helper); all four share the same **~11-stage contract** + the shared **`resources/patch-app-source.sh`** + the `services.yaml` registry:
   - **Jenkins** *(default)* — in-cluster UI behind IAP.
   - **Tekton** — in-cluster Dashboard behind IAP.
   - **GitHub Actions (ARC)** — **no in-cluster UI** (github.com is the UI); triggers **branch-based** on a push to the fork's `main` / `develop`.
   - **Argo Workflows** — in-cluster Argo Server UI behind IAP.
2. **Observability backend** (`observability.mode`) — **one of four**: `oss` (in-cluster) · `grafana-cloud` · `managed-azure` · `managed-aws`. The three external ones are decoupled, persistent, **keyless** (WIF/OIDC) Day0 resources.
3. **Secrets backend** (`secrets.backend`) — `imperative` *(default)*, or `eso` → pushed to **GCP Secret Manager** + synced by the **External Secrets Operator** (keyless WIF).
4. **Lean `develop` tier** (`microservices.developTrackEnabled`, **off by default**) — a non-HA `microservices-develop` namespace alongside `stable`, folded into **L4**, sharing the same observability stack.

For the full component diagram, microservices database architecture (CloudNative-PG HA), and CI/CD flow see [201. Architecture](./docs/201-ARCHITECTURE.md). For the Grafana Cloud Observability apps (App Observability, Synthetic Monitoring, Profiles — grafana-cloud only) see [301. Observability](./docs/301-OBSERVABILITY.md#grafana-cloud-observability-apps--status--recommendation).

### 3.1. Technical Infographics Catalog

To help visualize the system architecture, landing zones, workflows, and CI engine comparisons, a comprehensive catalog of 36 technical infographics is organized below. The infographics are categorized by system domain and folded by default. Click on any category to expand it and explore the files, key components, and detailed architectural descriptions.

For a full standalone catalog with visual previews, see the [Technical Infographics README](./docs/infographics/README.md).

<details>
<summary>📂 000: Platform Overview (2 Infographics)</summary>

- **[001]** - **[End to End Golden Path Platform and Developer Workflow Overview](./docs/infographics/001_End_to_End_Golden_Path_Platform_and_Developer_Workflow_Overview.png)**
  - *Key Technologies*: IDP, Day 0/Day 1, Dev Workflow
  - *Description*: High-level overview of the end-to-end developer journey within the Internal Developer Platform (IDP). Details the separation between Day 0 (core infrastructure bootstrap) and Day 1 (application deployment) workflows.
- **[002]** - **[High Level Design and Multi Repository Platform Architecture](./docs/infographics/002_High_Level_Design_and_Multi_Repository_Platform_Architecture.png)**
  - *Key Technologies*: Git Multi-Repo, Terraform, Jenkins
  - *Description*: Illustrates the multi-repository structure decoupling the platform infrastructure configuration (in the Jenkins-2026 repository) from individual application source code repositories, using remote GCS buckets for state storage.

</details>

<details>
<summary>📂 100: Landing Zone (6 Infographics)</summary>

- **[101]** - **[GCP Keyless Landing Zone and WIF Federation](./docs/infographics/101_GCP_Keyless_Landing_Zone_and_WIF_Federation.png)**
  - *Key Technologies*: GCP, GitHub Actions, OIDC, WIF
  - *Description*: Documents the keyless authentication workflow using Google Workload Identity Federation (WIF). Replaces persistent JSON service account keys with short-lived OAuth2 access tokens exchanged via GitHub OIDC.
- **[102]** - **[GKE Golden Path JHipster Microservice Architecture](./docs/infographics/102_GKE_Golden_Path_JHipster_Microservice_Architecture.png)**
  - *Key Technologies*: GKE, JHipster, Dataplane V2, eBPF
  - *Description*: Maps the internal microservice design deployed within the GKE Golden-Path. Focuses on default-deny network postures enforced by GKE Dataplane V2 and inter-service container communication.
- **[103]** - **[Argo Workflows and Argo Events on GKE](./docs/infographics/103_Argo_Workflows_and_Argo_Events_on_GKE.png)**
  - *Key Technologies*: Argo Events, Argo Workflows, GKE
  - *Description*: Represents the event-driven CI/CD control plane on GKE. Details the Argo Events webhook listener architecture, GKE Gateway API ingress routing, and the 10-stage execution pipeline contract.
- **[104]** - **[GKE Zero Trust Ingress North South Traffic Lifecycle with BackendTLS](./docs/infographics/104_GKE_Zero_Trust_Ingress_North_South_Traffic_Lifecycle_with_BackendTLS.png)**
  - *Key Technologies*: BackendTLSPolicy, Gateway API, Google IAP
  - *Description*: Traces the zero-trust lifecycle of North-South ingress traffic. Details SSL termination at the global L7 Load Balancer, Google IAP context-aware authorization, HTTPRoute definition, BackendTLSPolicy enforcement, and direct NEG routing to pods with 100% continuous transit encryption.
- **[105]** - **[GKE Golden Path High Availability PostgreSQL with CloudNativePG](./docs/infographics/105_GKE_Golden_Path_High_Availability_PostgreSQL_with_CloudNativePG.png)**
  - *Key Technologies*: PostgreSQL, CloudNativePG, PgBouncer
  - *Description*: Illustrates the database clustering setup using CloudNativePG on GKE. Explains high-availability replication across multiple zones, read/write splitting, and pgBouncer pooled connection proxying.
- **[106]** - **[GKE Backend TLS Zero Trust Edge to Pod Journey](./docs/infographics/106_GKE_Backend_TLS_Zero_Trust_Edge_to_Pod_Journey.png)**
  - *Key Technologies*: BackendTLSPolicy, Gateway API, IAP, Cilium eBPF, WireGuard
  - *Description*: Maps the GKE Backend TLS Zero-Trust Edge-to-Pod packet journey. Visualizes the four phases from public edge ingress (L7 Load Balancer) and identity verification (IAP) to GKE Gateway API routing and secondary TLS handshakes directly with target pods (Jenkins, Spring Cloud Gateway, Headlamp UI) without sidecar proxies.

</details>

<details>
<summary>📂 200: Node Provisioning (3 Infographics)</summary>

- **[201]** - **[GKE Cluster Topology and Karpenter Native Node Auto Provisioning](./docs/infographics/201_GKE_Cluster_Topology_and_Karpenter_Native_Node_Auto_Provisioning.png)**
  - *Key Technologies*: GKE NAP, Karpenter-native, quotas
  - *Description*: Details GKE node auto-provisioning (NAP) behaving similarly to Karpenter. Explains quota ceilings, hard technical limits for SSD/disks, and the lifecycle of pending pods triggering dynamic node spin-up.
- **[202]** - **[GitHub Actions on GKE ARC and Spot Runners](./docs/infographics/202_GitHub_Actions_on_GKE_ARC_and_Spot_Runners.png)**
  - *Key Technologies*: GitHub ARC, Spot Instances, WIF
  - *Description*: Analyzes GitHub Actions Runner Controller (ARC) deployments on GKE. Shows how ephemeral runners are scheduled dynamically on cost-effective GCP Spot VMs, with WIF providing secure identity mappings.
- **[203]** - **[Jenkins 2026 GitHub Actions Workflow Catalog Map](./docs/infographics/203_Jenkins_2026_GitHub_Actions_Workflow_Catalog_Map.png)**
  - *Key Technologies*: GitHub Actions, Git Workflows, GKE
  - *Description*: Provides a comprehensive directory of the 29 GitHub Actions workflows managing the GKE Golden-Path platform, detailing naming patterns, push/PR triggers, and operational dependencies.

</details>

<details>
<summary>📂 300: Dataplane Security (5 Infographics)</summary>

- **[301]** - **[GKE Dataplane V2 eBPF Zero Trust Isolation Matrix](./docs/infographics/301_GKE_Dataplane_V2_eBPF_Zero_Trust_Isolation_Matrix.png)**
  - *Key Technologies*: Dataplane V2, eBPF, NetworkPolicies
  - *Description*: Maps the default-deny matrix for the microservices namespace. Explains how Cilium/eBPF enforces network isolation at the kernel level, blocking all non-whitelisted cross-pod interactions.
- **[302]** - **[GKE Dataplane V2 Zero Trust Networking Architecture](./docs/infographics/302_GKE_Dataplane_V2_Zero_Trust_Networking_Architecture.png)**
  - *Key Technologies*: Linux Kernel, Cilium, BPF filters
  - *Description*: Explains the low-level network packet flow inside the Linux Kernel using eBPF JIT-compiled programs, TC (Traffic Control) network hooks, and secure socket redirections bypass.
- **[303]** - **[JHipster Gateway Architecture and Observability Map](./docs/infographics/303_JHipster_Gateway_Architecture_and_Observability_Map.png)**
  - *Key Technologies*: JHipster Gateway, Webpack, Faro
  - *Description*: Details the Gateway layer of the application, contrasting dev (Webpack reload) vs prod profiles, route proxying to downstream microservices, and OpenTelemetry instrumentation hooks.
- **[304]** - **[GKE Golden Path IDP Runtime Traffic and Data Integration](./docs/infographics/304_GKE_Golden_Path_IDP_Runtime_Traffic_and_Data_Integration.png)**
  - *Key Technologies*: Ingress Routing, Egress Policies, IDP
  - *Description*: Represents an expert guide for handling data integration and security. Covers ingress-to-pod mappings, egress whitelist policies, and OTel collector ingestion paths for tracing.
- **[305]** - **[GKE Platform Networking Blueprint Zero Trust North South Ingress](./docs/infographics/305_GKE_Platform_Networking_Blueprint_Zero_Trust_North_South_Ingress.png)**
  - *Key Technologies*: GKE Gateway API, Google IAP, BackendTLSPolicy, NEGs
  - *Description*: Outlines the zero-trust landing zone network blueprint for GKE North-South ingress. Focuses on edge TLS termination, Google IAP user authorization, and secondary handshakes to container-native NEGs with certificates from GKE-managed CAs.

</details>

<details>
<summary>📂 400: Secrets & DevSecOps (2 Infographics)</summary>

- **[401]** - **[Zero Trust Keyless Secrets Lifecycle via ESO and WIF](./docs/infographics/401_Zero_Trust_Keyless_Secrets_Lifecycle_via_ESO_and_WIF.png)**
  - *Key Technologies*: Secret Manager, ESO, GKE Secrets
  - *Description*: Outlines the keyless replication of secrets from Google Secret Manager to Kubernetes Secrets using the External Secrets Operator (ESO) and GCP Workload Identity.
- **[402]** - **[DevSecOps Multilayer Scanning and SARIF Flow](./docs/infographics/402_DevSecOps_Multilayer_Scanning_and_SARIF_Flow.png)**
  - *Key Technologies*: Semgrep, CodeQL, Trivy, SARIF
  - *Description*: Displays the pluggable 4-layer security scanning pipeline (lightweight SAST, deep SAST, dependency check, and container scan) consolidating vulnerabilities into standard SARIF files.

</details>

<details>
<summary>📂 500: CI Engines (2 Infographics)</summary>

- **[501]** - **[Jenkins 2026 Automated CI Engine Architecture](./docs/infographics/501_Jenkins_2026_Automated_CI_Engine_Architecture.png)**
  - *Key Technologies*: Jenkins, JCasC, Helm, GKE Agents
  - *Description*: Details the fully GitOps-managed Jenkins engine. Features declarative Configuration-as-Code (JCasC), Helm-managed state, and dynamic on-demand agent scaling on GKE.
- **[502]** - **[Tekton CI Engine Architecture with Pipelines as Code and SLSA](./docs/infographics/502_Tekton_CI_Engine_Architecture_with_Pipelines_as_Code_and_SLSA.png)**
  - *Key Technologies*: Tekton, SLSA, Pipelines-as-Code
  - *Description*: Showcases the cloud-native Tekton CI model. Describes event-based triggers, Git pipelines-as-code controllers, and SLSA provenance attestation generators for builds.

</details>

<details>
<summary>📂 600: Deployment & GitOps (4 Infographics)</summary>

- **[601]** - **[Two Repo GitOps State Machine with ArgoCD and CI Workflow](./docs/infographics/601_Two_Repo_GitOps_State_Machine_with_ArgoCD_and_CI_Workflow.png)**
  - *Key Technologies*: GitOps, ArgoCD Sync, Multi-Engine CI
  - *Description*: Maps the two-repo GitOps decoupling. Explains how CI processes push container tags to the app repository, and how ArgoCD reconciles the cluster to match the Git state.
- **[602]** - **[Terraform IaC Idempotency and Day 1 State Flow](./docs/infographics/602_Terraform_IaC_Idempotency_and_Day_1_State_Flow.png)**
  - *Key Technologies*: Terraform, State Locking, GCS
  - *Description*: Traces the execution flow of Terraform infrastructure code. Illustrates safe state locking in GCP GCS buckets and the transition from Day 0 setup to Day 1 updates.
- **[603]** - **[Sidecar Free Progressive Delivery with Argo Rollouts and GKE Gateway API](./docs/infographics/603_Sidecar_Free_Progressive_Delivery_with_Argo_Rollouts_and_GKE_Gateway_API.png)**
  - *Key Technologies*: Argo Rollouts, GKE Gateway, Canary
  - *Description*: Illustrates a progressive delivery architecture. Argo Rollouts manages canary traffic splitting directly through GKE Gateway routing, bypassing the need for sidecar-heavy service meshes like Istio.
- **[604]** - **[Sidecar Free Zero Trust BackendTLS and GitOps Workflow](./docs/infographics/604_Sidecar_Free_Zero_Trust_BackendTLS_and_GitOps_Workflow.png)**
  - *Key Technologies*: ArgoCD, GKE Gateway, BackendTLSPolicy, GKE CA
  - *Description*: Maps the GitOps reconciliation flow of zero-trust components in GKE. Details how ArgoCD syncs Gateway and BackendTLSPolicy manifests, terminating TLS at target microservices by validating pod certificates against GKE-managed CAs.

</details>

<details>
<summary>📂 700: Tool Comparisons (6 Infographics)</summary>

- **[701]** - **[Advanced CI Architecture Jenkins vs Tekton on GKE](./docs/infographics/701_Advanced_CI_Architecture_Jenkins_vs_Tekton_on_GKE.png)**
  - *Key Technologies*: Jenkins, Tekton, GKE scheduler
  - *Description*: Compares structural architecture of Jenkins vs Tekton. Focuses on persistent master controllers vs serverless CRD-driven pods, and the impact on resource scheduling.
- **[702]** - **[Spot Instance Resiliency Jenkins vs GitHub Actions ARC](./docs/infographics/702_Spot_Instance_Resiliency_Jenkins_vs_GitHub_Actions_ARC.png)**
  - *Key Technologies*: Spot Nodes, Evictions, ARC, Jenkins
  - *Description*: Benchmarks Spot instance node evictions. Compares Jenkins master-agent connection drops with GitHub Actions ARC runner rescheduling and recovery metrics.
- **[703]** - **[CI Battle Jenkins Groovy vs Argo Workflows DAG and UI Strategy](./docs/infographics/703_CI_Battle_Jenkins_Groovy_vs_Argo_Workflows_DAG_and_UI_Strategy.png)**
  - *Key Technologies*: Groovy script, YAML DAG, Jenkins, Argo
  - *Description*: Compares the imperative scripting style of Jenkins Groovy pipelines against the declarative YAML DAG model of Argo Workflows on GKE. Details the Jenkins UI strategy, explicitly replacing deprecated Blue Ocean with Classic UI and warnings-ng.
- **[704]** - **[CI Grand Master Battlecard 4 Way GKE Matrix](./docs/infographics/704_CI_Grand_Master_Battlecard_4_Way_GKE_Matrix.png)**
  - *Key Technologies*: CI Matrix, Jenkins, Tekton, Argo, GHA
  - *Description*: Provides a 4-way architectural comparison battlecard evaluating the performance, scaling latency, and storage overhead of Jenkins, Tekton, Argo, and GHA.
- **[705]** - **[Jenkins Dominance Pluggable CI 4 Way Matrix and Classic UI Transition](./docs/infographics/705_Jenkins_Dominance_Pluggable_CI_4_Way_Matrix_and_Classic_UI_Transition.png)**
  - *Key Technologies*: Jenkins, CI Matrix, GKE
  - *Description*: Features the Pluggable CI 4-Way comprehensive matrix, detailing resource footprint and scheduling, and noting the deprecation/replacement of Blue Ocean with Classic UI + warnings-ng.
- **[706]** - **[Why Jenkins Wins Battlecard and UI Security Strategy](./docs/infographics/706_Why_Jenkins_Wins_Battlecard_and_UI_Security_Strategy.png)**
  - *Key Technologies*: Jenkins, DevSecOps, Pluggable CI
  - *Description*: Explains the technical benefits of Jenkins in a pluggable CI platform, detailing usability, native security integrations, and the UI security strategy mitigating deprecated Blue Ocean CVE risks.

</details>

<details>
<summary>📂 800: Observability (4 Infographics)</summary>

- **[801]** - **[Grafana OSS Self Hosted OTel Signal Flow](./docs/infographics/801_Grafana_OSS_Self_Hosted_OTel_Signal_Flow.png)**
  - *Key Technologies*: Grafana OSS, OTel Collector, Faro
  - *Description*: Illustrates the self-hosted observability signal flow. Shows how Java/JVM apps send logs, metrics, and traces to OpenTelemetry collectors, which correlate data for Grafana.
- **[802]** - **[Optimized OTel Data Flow and Grafana Cloud Free Tier](./docs/infographics/802_Optimized_OTel_Data_Flow_and_Grafana_Cloud_Free_Tier.png)**
  - *Key Technologies*: OTel Gateway, Grafana Cloud, Free Tier
  - *Description*: Guides developers on configuring custom metric filtering, span dropping, and lean telemetry rules in the OTel Gateway to fit within Grafana Cloud free tier quotas.
- **[803]** - **[JVM Tuning and Hotspot Runtime Strategy](./docs/infographics/803_JVM_Tuning_and_Hotspot_Runtime_Strategy.png)**
  - *Key Technologies*: JVM Tuning, Hotspot GC, Limits
  - *Description*: Resolves the "container-default trap" (where JVM limits default to 25% heap). Optimizes memory allocations and Garbage Collector flags (G1GC) for Docker containers.
- **[804]** - **[End to End Frontend Observability RUM with Grafana Faro and OTel](./docs/infographics/804_End_to_End_Frontend_Observability_RUM_with_Grafana_Faro_and_OTel.png)**
  - *Key Technologies*: Grafana Faro, RUM, Trace Propagation
  - *Description*: Traces client-side Real User Monitoring (RUM) beacon propagation. Demonstrates traceparent header injection from the browser into backend APIs using OpenTelemetry.

</details>

<details>
<summary>📂 900: Load & Lifecycle (2 Infographics)</summary>

- **[901]** - **[k6 Traffic Simulation Unified Workload Profiles](./docs/infographics/901_k6_Traffic_Simulation_Unified_Workload_Profiles.png)**
  - *Key Technologies*: k6, Traffic Simulation, Load Tests
  - *Description*: Explains the k6 workload profile setup, including environment variable injection (`k6sim_*`) and automated load test scenarios mimicking user concurrency peaks.
- **[902]** - **[GKE Golden Path IDP Platform Lifecycle and Rebuild Safety Matrix](./docs/infographics/902_GKE_Golden_Path_IDP_Platform_Lifecycle_and_Rebuild_Safety_Matrix.png)**
  - *Key Technologies*: Platform Lifecycle, Backups, Recovery
  - *Description*: Outlines the platform rebuild-safety matrix, defining backup strategies, disaster recovery runbooks, and recovery point objectives (RPO) for cluster states.

</details>

### 3.2. Project Media & External Resources

To keep this Git repository lightweight, fast to clone, and responsive, all heavy multimedia assets and demonstration walkthroughs are housed in a dedicated external library:

> [!IMPORTANT]
> ### 📁 Platform Media & Resources Library (Google Drive)
>
> All high-resolution drawings, vector diagrams, and video walkthroughs are available in the public shared folder:
>
> 🔗 **[Access the Google Drive Shared Folder](https://drive.google.com/drive/folders/15JQNRSIW8mxaIjQ2AVyua-jzLNjDsZ10?usp=sharing)**
>
> **What you will find inside:**
> *   **🎬 Video Walkthroughs** — Live screen recordings of the `bootstrap.sh` execution, Karpenter autoscaling demos, and Jenkins/Tekton CI pipeline rollouts.
> *   **📊 High-Resolution Diagrams** — Raw architecture mockups, zero-trust network blueprint vectors, and GKE landing zone charts.
> *   **📝 Presentation Sheets** — Interactive slideshows and architectural design sheets explaining the 4-way CI engine comparison.

---

## 4. GitHub Actions Workflows

All **29 lifecycle workflows** live in [`.github/workflows/`](.github/workflows/) following the `DayN.tier.ZZ-resource` naming convention (the two repo-hygiene checks — [`gitflow-guard.yml`](.github/workflows/gitflow-guard.yml), [`terraform-validate.yml`](.github/workflows/terraform-validate.yml) — sit outside the scheme) — **alphabetical sort order = correct execution order** for the **Create** (`Day0`→`Day1`) and **Decom** phases. Within **Day2** the tiers (`redeploy`/`publish`/`traffic`/`registry`/`scale`) are independent **categories**, not an ordered sequence — each workflow is idempotent and dispatched on its own ([why](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md#day2-ordering-tiers-are-categories-not-stages)). See [101. GitHub Actions Workflows](./docs/101-GITHUB_ACTIONS_WORKFLOWS.md) for the full inventory with clickable GitHub Actions links.

| Phase | tier | Resource | Workflow |
|---|---|---|---|
| `Day0` Create | `infra` (persistent) | Gateway, Grafana Cloud, Azure, AWS | [Day0.infra.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.01-gateway.yml) · [Day0.infra.02](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.02-grafana-cloud.yml) · [Day0.infra.03](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.03-azure-grafana.yml) · [Day0.infra.04](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.04-aws-grafana.yml) |
| `Day1` Create | `cluster.00` (umbrella, opt-in) | **Everything up** — one-click from-scratch: Gateway bootstrap + cluster + full stack | [Day1.cluster.00-all](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.00-all.yml) |
| `Day1` Create | `cluster` | GKE cluster + full stack | [Day1.cluster.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.01-gke.yml) |
| `Day2` Update | `redeploy` | ArgoCD, Jenkins, Tekton, Headlamp, Gateway, GitHub Actions, Argo Workflows | [Day2.redeploy.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.01-argocd.yml) · [Day2.redeploy.02](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.02-jenkins.yml) · [Day2.redeploy.03](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.03-tekton.yml) · [Day2.redeploy.04](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.04-headlamp.yml) · [Day2.redeploy.05](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.05-gateway.yml) · [Day2.redeploy.06](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.06-githubactions.yml) · [Day2.redeploy.07](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.07-argoworkflows.yml) |
| `Day2` Update | `publish` | OSS / Grafana Cloud / Azure / AWS dashboards, Grafana alerts | [Day2.publish.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.01-oss-grafana.yml) · [Day2.publish.02](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.02-grafana-cloud.yml) · [Day2.publish.03](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.03-azure-grafana.yml) · [Day2.publish.04](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.04-aws-grafana.yml) · [Day2.publish.05](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.05-alerts.yml) |
| `Day2` Update | `traffic` | k6 traffic · synthetic RUM (Faro beacons) | [Day2.traffic.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.01-k6.yml) · [Day2.traffic.02](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.02-rum.yml) |
| `Day2` Update | `registry` | Prune old microservices image versions from ghcr (immutable per-build tags) | [Day2.registry.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.registry.01-image-retention.yml) |
| `Day2` Update | `scale` | Pause / resume node pools (park at ~zero cost) | [Day2.scale.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.01-pause.yml) · [Day2.scale.02](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.02-resume.yml) |
| `Decom` Destroy | `cluster` (first) | GKE cluster (destroy first) | [Decom.cluster.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.cluster.01-gke.yml) |
| `Decom` Destroy | `infra` (last) | Gateway, Grafana Cloud, Azure, AWS (destroy last) | [Decom.infra.01](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.01-gateway.yml) · [Decom.infra.02](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.02-grafana-cloud.yml) · [Decom.infra.03](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.03-azure-grafana.yml) · [Decom.infra.04](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.04-aws-grafana.yml) |
| `Decom` Destroy | `infra.00` (umbrella, opt-in) | **Everything** — cluster + all persistent backends in one dispatch (type `destroy`) | [Decom.infra.00-all](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.00-all.yml) |

> **Applying changes = re-run, not Decom.** `Day1.cluster.01` is **idempotent**:
> re-run it on an already-provisioned cluster and it converges in place
> (`terraform apply` no-ops when the cluster is already in state; `up.sh`
> re-applies every step; ArgoCD re-syncs from git). You do **not** need to
> decommission to pick up a change. For a CI-engine-only change, the lighter
> `Day2.redeploy.02-jenkins` / `Day2.redeploy.03-tekton` redeploys also converge
> in place (`.03-tekton` also re-runs `01-namespaces` + `08.6-eso-sync` + `09-gateway`;
> `.02-jenkins` re-applies only the Jenkins chart + seed jobs — use
> `Day2.redeploy.05-gateway` to re-apply the gateway routes). `Decom.cluster.01`
> is only for tearing the cluster down when you're done, to stop charges.

---

## 5. Prerequisites

- An existing GKE Kubernetes cluster (`kubectl` context pointing at it).
- `kubectl`, `helm` (v3), [`yq`](https://github.com/mikefarah/yq) (Go version), `git`, `bash`.
- A container registry you can push to (default: `ghcr.io/nubenetes/jenkins-2026-microservices`).
- (default mode) A [Grafana Cloud](https://grafana.com/products/cloud/) stack (free tier) for its OTLP gateway endpoint + API key.

See [901. Local Development](./docs/901-LOCAL_DEVELOPMENT.md) for the complete prerequisites and step-by-step deployment guide.

---

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for the current changelog + the milestone
[release index](CHANGELOG.md#release-index) (older history in
[`CHANGELOG-ARCHIVE.md`](CHANGELOG-ARCHIVE.md)), and [`RELEASING.md`](RELEASING.md)
for the versioning + release-cut convention (`Unreleased` → milestone minor →
tag + GitHub release, 1:1, via [`scripts/cut-release.sh`](scripts/cut-release.sh)).

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contribution workflow — the
strict `develop → main` GitFlow (enforced by the `gitflow-guard` required
check), the idempotency contract, the `config.yaml` + `JENKINS2026_*`
feature-flag pattern, secrets hygiene, the Terraform `fmt`/`validate` gate, and
how to run the PR checks locally.

---

## License

[MIT](LICENSE) © 2026 Nubenetes
