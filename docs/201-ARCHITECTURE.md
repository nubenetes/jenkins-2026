[← Previous: 103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md) | [🏠 Home](../README.md) | [→ Next: 301. Observability](./301-OBSERVABILITY.md)

---

# 201. Architecture

## Overview

`jenkins-2026` deploys a self-contained CI/CD + observability proof-of-concept on top of an **existing** GKE cluster:

- **Jenkins** (jenkinsci/helm-charts), configured entirely via Configuration-as-Code (JCasC) — no manual clicking required.
- **Pipelines as code**: a Job DSL "seed job" generates stable Jenkins Pipeline jobs (`gateway`, `jhipstersamplemicroservice`, `microservices-k6-smoke`) targeting the `microservices` namespace.
- **Spring Microservices + Angular UI**, deployed by those pipelines via a single parameterized Helm chart.
- **OpenTelemetry** end to end: Jenkins, the Java services (OTel Operator auto-instrumentation), and the Angular UI (RUM snippet) all export traces/metrics/logs to an in-cluster OTel Collector, forwarding to **Grafana Cloud** (default) or an in-cluster OSS stack.
- **ArgoCD (GitOps)**: The entire Microservices stack is managed declaratively by ArgoCD, integrated with Google OIDC for SSO.
- **CloudNative-PG (CNPG)**: HA **PostgreSQL 18.3** clusters (3 instances: 1 primary + 2 replicas; the image is **pinned** via the chart's `spec.imageName`) provisioned via CNPG CRDs, with PgBouncer connection pooling. *(The chart + `Cluster`/`Pooler` CRs live in the [gitops-config repo](https://github.com/nubenetes/jenkins-2026-gitops-config), not this one.)*

> **Two-repo GitOps setup.** This is the **infra repo** (cluster bootstrap, Jenkins, ArgoCD, observability). Image tags and ArgoCD manifests live in the companion **[`nubenetes/jenkins-2026-gitops-config`](https://github.com/nubenetes/jenkins-2026-gitops-config)** repo.

## System Architecture

<details>
<summary>🔍 Click to expand System Architecture Diagram</summary>

Two pluggable choices, both deterministic & idempotent: the **CI engine** (`ci.engine`: Jenkins **xor** Tekton) and the **observability backend** (`observability.mode`: one of oss / grafana-cloud / managed-azure / managed-aws). ArgoCD is always the CD/GitOps engine. This is the same overview as [README § 3](../README.md#3-architecture-overview); the [Component Diagram](#component-diagram) below drills into the Jenkins/microservices/observability internals.

```mermaid
flowchart TB
    users([Users / GitHub webhooks]):::ext

    subgraph GH["GitHub"]
      R1["nubenetes/jenkins-2026<br/>IaC · scripts · pipelines · JCasC / tekton"]
      R2["nubenetes/jenkins-2026-gitops-config<br/>microservices + CNPG manifests"]
    end

    subgraph EDGE["GCP edge"]
      IAP["Gateway API + Google IAP<br/>DNS · OAuth"]
    end

    subgraph GKE["GKE cluster — Dataplane V2 (Cilium/eBPF NetworkPolicies) + WireGuard"]
      ACD["ArgoCD<br/>CD / GitOps engine"]
      subgraph CI["CI engine — pick ONE (ci.engine)"]
        JEN["Jenkins<br/>Helm + JCasC + Job-DSL seed"]
        TEK["Tekton<br/>Pipelines/Triggers/Dashboard + PaC"]
      end
      subgraph PLAT["Platform add-ons"]
        HL["Headlamp"]
        PGA["pgAdmin"]
        ROLL["Argo Rollouts<br/>canary / blue-green"]
        ESO["External Secrets"]
        CNPGOP["CNPG operator"]
      end
      subgraph MS["Microservices (gateway + jhipstersample)"]
        APP["Spring Boot apps<br/>OTel auto-instrumented"]
        PG[("CNPG Postgres HA<br/>3 replicas + PgBouncer poolers")]
      end
      subgraph OBS["In-cluster observability"]
        OP["OTel Operator"]
        COL["OTel Collector<br/>reconfigured per mode"]
        OSST["OSS stack: Prometheus · Loki<br/>Tempo · Grafana (mode=oss)"]
      end
    end

    subgraph BK["External observability backends — pick ONE (observability.mode), Day0 Terraform"]
      GCLOUD["Grafana Cloud<br/>grafana-cloud"]
      AZ["Azure Managed Grafana<br/>+ Monitor / App Insights — managed-azure"]
      AWSG["Amazon Managed Grafana<br/>+ AMP / X-Ray / CloudWatch — managed-aws"]
    end

    users --> IAP
    R1 -->|"terraform + scripts/up.sh"| GKE
    R1 -->|"shared library / pipeline defs"| CI
    IAP -->|IAP-protected| JEN & TEK & ACD & HL & PGA
    IAP -->|"open (no IAP)"| APP
    ACD -->|"installs / syncs"| CI & PLAT & MS
    R2 -->|"ArgoCD source"| ACD
    CI -->|"build → push image → commit gitops"| R2
    CI -->|"argocd app sync"| ACD
    APP --> PG
    APP -->|OTLP| COL
    CI -->|OTLP| COL
    OP -.->|injects agent| APP
    SM["GCP Secret Manager<br/>secrets.backend=eso"]:::pick
    SM -.->|"keyless WIF sync"| ESO
    COL -->|mode=oss| OSST
    COL -->|mode=grafana-cloud| GCLOUD
    COL -->|mode=managed-azure| AZ
    COL -->|mode=managed-aws| AWSG

    classDef ext fill:#fde,stroke:#c39;
    classDef pick fill:#eef,stroke:#66c;
    class JEN,TEK,GCLOUD,AZ,AWSG,OSST pick;
```

</details>

## Component Diagram

```mermaid
flowchart TD
    repo["github.com/nubenetes/jenkins-2026<br/>JCasC, Jenkinsfile, shared library,<br/>Helm charts, seed/services.yaml"]

    subgraph jenkins_ns["namespace: jenkins"]
        jenkins["Jenkins controller (jenkinsci/helm-charts + JCasC)<br/>- security, global shared library, OTel exporter, seed jobs<br/>- seed jobs (Job DSL) generate stable pipeline jobs at the root:<br/>  (gateway, jhipstersamplemicroservice, microservices-k6-smoke)<br/>- each run uses a Kubernetes pod agent<br/>  (maven / node / docker:dind / helm+kubectl / k6 containers)"]
    end

    repo -->|"global pipeline library +<br/>seed job (checkout scm)"| jenkins

    subgraph microservices_ns["namespace: microservices (stable, tracks main)"]
        microservices["gateway (Spring Boot + Angular UI),<br/>jhipstersamplemicroservice (Spring Boot backend)"]
    end

    jenkins -->|"helm upgrade --install<br/>(per-service image tag)"| microservices

    subgraph observability_ns["namespace: observability"]
        otel["OpenTelemetry Operator (CRDs: Instrumentation,<br/>OpenTelemetryCollector) - Java auto-instrumentation<br/>otel-collector-gateway (Deployment, OTLP receiver)<br/>otel-collector-logs (DaemonSet, filelog receiver)"]
        k8s_mon["k8s-monitoring (Grafana Alloy Operator & StatefulSet)<br/>- Scrapes cluster metrics (kube-state-metrics)<br/>- Scrapes host metrics (node-exporter)<br/>- Collects cluster events"]
    end

    jenkins -->|OTLP| otel
    microservices -->|"OTLP (traces / metrics / logs)"| otel

    gke["GKE Cluster Infrastructure<br/>(Nodes, Kubelet, Events)"] --> k8s_mon

    grafana_cloud["Grafana Cloud<br/>OTLP gateway -> Mimir, Loki, Tempo + Grafana"]
    oss["In-cluster: kube-prometheus-stack<br/>(Prometheus + Grafana) + Loki + Tempo"]

    otel -->|"observability.mode:<br/>grafana-cloud"| grafana_cloud
    otel -->|"observability.mode:<br/>oss"| oss
    k8s_mon -->|"OTLP/HTTP"| grafana_cloud
```

## Microservices & Database Architecture

The modernized JHipster system is built on a containerized, cloud-native microservices architecture using **Spring Boot 3.x**, **Angular**, and **Java 21**. It consists of two primary services, each with its own dedicated database tier managed by the **CloudNative-PG (CNPG) Operator**:

1. **`gateway`**: Serves as the single entry point for all client requests. Hosts the Angular frontend and handles routing, JWT-based security, and rate-limiting.
2. **`jhipstersamplemicroservice`**: Backend microservice containing business logic and REST endpoints.

<details>
<summary>🔍 Click to expand Architecture & Data Flow Diagram</summary>

```mermaid
graph TD
    subgraph "Client Tier"
        Browser["Browser<br/>(Angular UI)"]
    end

    subgraph "API Gateway (Namespace: microservices)"
        GW["gateway<br/>(Spring Boot / Angular UI)<br/>Port 8080"]
    end

    subgraph "Microservices Tier"
        S_Ms["jhipstersamplemicroservice<br/>(Spring Boot)<br/>Port 8081"]
    end

    subgraph "Connection Pooling (PgBouncer Poolers)"
        Pool_GW["postgres-gateway-pooler<br/>(Service: Port 5432)"]
        Pool_Ms["postgres-jhipstersamplemicroservice-pooler<br/>(Service: Port 5432)"]
    end

    subgraph "Database Tier (CloudNative-PG 3-Instance Clusters)"
        subgraph "postgres-gateway Cluster"
            DB_GW_P[("Primary (gateway-1)")]
            DB_GW_R1[("Standby (gateway-2)")]
            DB_GW_R2[("Standby (gateway-3)")]
        end
        subgraph "postgres-jhipstersamplemicroservice Cluster"
            DB_Ms_P[("Primary (ms-1)")]
            DB_Ms_R1[("Standby (ms-2)")]
            DB_Ms_R2[("Standby (ms-3)")]
        end
    end

    subgraph "Telemetry (Observability Namespace)"
        OTEL_Collector["OpenTelemetry Collector<br/>Gateway"]
    end

    Browser -->|"HTTPS (Port 443)"| GW
    GW -->|"REST / JWT (Port 8081)"| S_Ms
    GW -->|"JDBC (Port 5432)"| Pool_GW
    S_Ms -->|"JDBC (Port 5432)"| Pool_Ms
    Pool_GW -->|Primary Read/Write| DB_GW_P
    Pool_Ms -->|Primary Read/Write| DB_Ms_P
    DB_GW_P -->|Replication| DB_GW_R1
    DB_GW_P -->|Replication| DB_GW_R2
    DB_Ms_P -->|Replication| DB_Ms_R1
    DB_Ms_P -->|Replication| DB_Ms_R2
    GW -.->|"OTLP/gRPC (Port 4317)"| OTEL_Collector
    S_Ms -.->|"OTLP/gRPC (Port 4317)"| OTEL_Collector
```

</details>

### Database Injection & Secrets

The CloudNative-PG Operator automatically provisions a basic-auth secret `postgres-{{ $name }}-app` for each cluster containing `username` and `password`. The Helm chart maps these to Spring environment variables:

- `SPRING_DATASOURCE_URL` → JDBC URL targeting PgBouncer
- `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD`
- `SPRING_R2DBC_URL` → R2DBC URL for reactive microservices

### CI/CD Flow (GitOps)

<details>
<summary>🔍 Click to expand CI/CD Flow (GitOps) Diagram</summary>

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH_Infra as GitHub (Infra Repo)
    participant J as Jenkins (CI)
    participant GH_GitOps as GitHub (GitOps Config Repo)
    participant ACD as ArgoCD (CD)
    participant K8s as Kubernetes (GKE)
    participant Obs as Observability (Grafana)

    Dev->>GH_Infra: Push Code / Change
    J->>J: Build & Test
    J->>J: Push Image to GHCR
    J->>GH_GitOps: Update values-stable.yaml (yq)
    J->>ACD: argocd app sync --wait (CLI)
    Note over ACD,K8s: Reconcile Git -> Cluster
    ACD->>K8s: Apply Manifests
    K8s-->>ACD: Health Check (Ready)
    ACD-->>J: Sync OK / Healthy
    J->>K8s: Run Smoke Tests (curl)
    K8s->>Obs: OTLP Telemetry
    Obs-->>Dev: Dashboard Update
```

</details>

**Progressive delivery**: the platform installs **Argo Rollouts** + the Gateway API traffic-router plugin (GitOps via `argocd/argo-rollouts-app.yaml`), so the microservices can roll out as weighted **canaries** by shifting the GKE Gateway HTTPRoute backend weights — sidecar-free, no service mesh. See [`docs/501` § Progressive Delivery](501-PLATFORM_OPERATIONS.md).

Single source of truth, loaded by every script via [`scripts/lib/config.sh`](../scripts/lib/config.sh) (`yq` → `J2026_*` env vars). Feature flags:

| Key | Default | Override | Meaning |
|---|---|---|---|
| `observability.mode` | `grafana-cloud` | edit `config.yaml` | `grafana-cloud`\|`oss`\|`managed-azure`\|`managed-aws` — where traces/metrics/logs go |
| `ci.engine` | `jenkins` | `JENKINS2026_CI_ENGINE` | `jenkins`\|`tekton` — which CI engine runs the pipelines-as-code (Jenkins default, or Tekton). See [403. Tekton](./403-TEKTON.md) |
| `microservices.developTrackEnabled` | `false` | `JENKINS2026_DEVELOP_TRACK_ENABLED` | Optional second microservices tier (`microservices-develop` namespace, GitOps `develop` branch) |

Other notable sections: `jenkins.*` (chart coordinates, namespace, this repo's own URL/branch), `observability.*` (operator/collector chart coordinates, release names, Secret name), `microservices.*` (namespaces, git org/repos/branches, target registry, list of 2 services seeded into Jenkins).

### CI engine: Jenkins or Tekton

The `ci.engine` flag (`jenkins` default, override `JENKINS2026_CI_ENGINE`) selects which CI engine runs the pipelines-as-code — same durable-default/ephemeral-override pattern as `observability.mode`. When `tekton`, [`scripts/04-tekton.sh`](../scripts/04-tekton.sh) and [`scripts/06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh) take the place of [`scripts/04-jenkins.sh`](../scripts/04-jenkins.sh) / [`scripts/06-seed-pipelines.sh`](../scripts/06-seed-pipelines.sh): the first applies the **`argocd/tekton` app-of-apps** (so ArgoCD installs Pipelines/Triggers/Dashboard + the pipelines-as-code — the same GitOps pattern as `observability-oss`/`platform-postgres`, unlike Jenkins which is `helm install`-ed directly), the second waits for the sync and generates one PipelineRun per service. The pipelines-as-code lives under the top-level `tekton/` dir (Tasks/Pipelines/Triggers/RBAC — a port of the Jenkins shared library). See [403. Tekton](./403-TEKTON.md) for the deep-dive.

## Repository Layout

```
config/config.yaml          single source of truth (feature flags above)
helm/jenkins/                jenkinsci/helm-charts values + values-gke.yaml overlay
helm/headlamp/               kubernetes-sigs/headlamp values (cluster management UI)
helm/pgadmin/                pgAdmin values (CNPG admin UI)
helm/argocd-values.yaml      ArgoCD install values
jenkins/casc/                JCasC: security, OTel exporter, seed job
jenkins/pipelines/           seed/ (seed job: Job DSL + Jenkinsfile.seed + services.yaml) + k6/ (smoke script)
vars/                        Jenkins global shared library (must be at repo root; Microservices pipeline lives here)
tekton/                      Tekton pipelines-as-code (ci.engine=tekton): Tasks/Pipelines/Triggers/RBAC + port of the Jenkins shared library (vars/)
observability/               OTel Operator/Collector + Grafana/Loki/Tempo/Prometheus values + dashboards
argocd/                      ArgoCD Applications/ApplicationSets + app-of-apps (platform-postgres, observability-oss, tekton) + argo-rollouts-app.yaml
infrastructure/              engine-neutral platform manifests applied by 01-namespaces / 08.5-argocd: NetworkPolicies (default/-jenkins/-tekton), Gateway, Karpenter, scheduling, Argo Rollouts Gateway-API RBAC, secrets
scripts/                     00-09 numbered steps + up.sh / down.sh / status.sh
terraform/gke/               throwaway GKE cluster for test/e2e.sh
terraform/bootstrap/         one-time setup for GitHub Actions automation (state bucket + WIF + permanent public DNS zone)
terraform/gateway-bootstrap/ one-time setup for public access (static IP + managed certificate + DNS records in the zone)
scripts/08.5-argocd.sh       ArgoCD installation and OIDC configuration
test/                        e2e.sh (provision → up.sh → smoke-test.sh → down.sh → destroy)
.github/workflows/           DayN.tier.ZZ-resource.yml — see 101. GitHub Actions Workflows
docs/                        numbered docs (this file and siblings)
```

## Namespaces & in-cluster Secrets

> In-cluster Kubernetes `Secret`s, **not** the GitHub Actions secrets — those are
> the *source* values and are inventoried separately in
> [103. GitHub Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md). This section
> is about how, once inside the cluster, secrets are laid out across namespaces and
> why.

### Design principles

1. **A Secret lives in the namespace of the component that consumes it.** There is
   no central "secrets" namespace — `ghcr-credentials` lives where the pods that
   pull images run (`microservices`), the Headlamp OIDC secret lives in `headlamp`,
   the Tekton pipeline credentials live in `tekton-ci`, and so on. Locality keeps
   RBAC tight (a component can only read its own namespace) and makes teardown clean.
2. **The CI engine is mutually exclusive and engine-gated.** Either Jenkins **or**
   Tekton is deployed, never both (`ci.engine`). The `jenkins` namespace and its
   `jenkins-credentials` bundle are created **only** when `ci.engine=jenkins`; the
   `tekton-*` namespaces and their credentials **only** when `ci.engine=tekton`.
3. **The public ingress is engine-neutral.** The GKE Gateway and the per-app
   HTTPRoutes live in the always-present **`platform-ingress`** namespace, so the
   single public entry point never depends on which CI engine is running. (This was
   not always so — see [The `platform-ingress` decoupling](#the-platform-ingress-decoupling) below.)
4. **One exception is replicated by necessity:** the IAP OAuth client
   (`gateway-iap-oauth`) is copied into *every* IAP-protected backend namespace,
   because GKE requires it co-located with the backend Service — see
   [Why the IAP secret is replicated](#why-the-gateway-iap-oauth-secret-is-replicated).

### Namespace inventory

| Namespace | When created | Runs / holds |
|---|---|---|
| `platform-ingress` | always | the GKE **Gateway** object (engine-neutral public ingress) |
| `observability` | always | OTel Operator + Collector; OSS Grafana/Loki/Tempo/Prometheus (oss mode) |
| `headlamp` | always | Headlamp UI + its OIDC secret + an IAP secret copy |
| `pgadmin` / `platform-postgres` | always | pgAdmin + CNPG operator + an IAP secret copy |
| `argocd` | always | ArgoCD (GitOps control plane) |
| `microservices` (+ `microservices-develop`) | always | the JHipster workloads + `ghcr-credentials` |
| `jenkins` | **only `ci.engine=jenkins`** | Jenkins controller + agents + `jenkins-credentials` + an IAP secret copy |
| `tekton-pipelines` | **only `ci.engine=tekton`** | Tekton Pipelines/Triggers/Dashboard control plane + an IAP secret copy |
| `tekton-ci` | **only `ci.engine=tekton`** | PipelineRuns + their credentials (`tekton-registry`/`tekton-git`/`k6-cloud`) |
| `pipelines-as-code` | **only `ci.engine=tekton`** | PaC controller + `pac-webhook` |

### In-cluster Secret inventory (the matrix)

| Secret | Namespace(s) | Contents | Shared / replicated? | Created by | Consumed by |
|---|---|---|---|---|---|
| **`jenkins-credentials`** | `jenkins` *(jenkins-mode)* | admin-password · registry user/pass · git user/token · oidc-client-id/secret · **oidc-admin-email** · microservices URLs · k6-cloud token/project | No — Jenkins config bundle | `01-namespaces.sh` | Jenkins controller (JCasC) |
| **`gateway-iap-oauth`** | `headlamp`, `pgadmin` (+ `grafana-oss` / `tekton-pipelines` / `jenkins` per mode) | IAP OAuth `client_id` / `client_secret` | **YES — replicated** (GKE constraint) | `01-namespaces.sh` | each ns's `GCPBackendPolicy` (IAP); `08.5` reads it (**from `headlamp`**) for ArgoCD's Google OIDC |
| `headlamp-credentials` | `headlamp` | OIDC client id/secret (+ issuer/scopes/callback) | No | `01-namespaces.sh` | Headlamp deployment |
| `tekton-registry` | `tekton-ci` *(tekton-mode)* | `dockerconfigjson` (ghcr.io push/pull, Jib auth) | No | `01-namespaces.sh` | PipelineRuns (build-push-image) |
| `tekton-git` | `tekton-ci` *(tekton-mode)* | git basic-auth, annotated for `github.com` | No | `01-namespaces.sh` | clone / gitops-deploy tasks |
| `tekton-github-webhook-secret` · `pac-webhook` | `tekton-ci` · `pipelines-as-code` *(tekton-mode)* | webhook HMAC token | No | `01-namespaces.sh` | Triggers EventListener / PaC |
| `k6-cloud` | `tekton-ci` *(tekton-mode; same keys also in `jenkins-credentials`)* | `K6_CLOUD_TOKEN` / `K6_CLOUD_PROJECT_ID` | No | `01-namespaces.sh` | k6 tasks (`--out cloud`, the k6-app) |
| `ghcr-credentials` | `microservices` (+ `-develop`) | `dockerconfigjson` imagePullSecret | No | `01-namespaces.sh` | microservices pods (image pull) |
| `grafana-jenkins-ds` | `grafana-oss` *(oss + jenkins-mode)* | `apiToken` (mirror of Jenkins admin password) | No | `03-observability.sh` *(gated to jenkins-mode)* | Grafana → Jenkins datasource |
| `grafana-cloud-credentials` / `azure-monitor-credentials` / `aws-managed-credentials` | `observability` | backend endpoint + token/SP/role per `observability.mode` | No | Day1 workflow / scripts | otel-collector exporter |

### Diagram 1 — Namespace & Secret topology

Each app's Secret sits in that app's namespace; the only cross-namespace **reads**
are the two that the IAP design forces (ArgoCD pulling the OAuth client) and that
the IAP backend policies need (the replicated client). `jenkins` is dashed — it
exists only in jenkins-mode (replace it mentally with the `tekton-*` namespaces in
tekton-mode).

```mermaid
graph TD
    subgraph PI["platform-ingress (always)"]
        GW["GKE Gateway<br/>(+ HTTPRoutes attach cross-ns)"]
    end
    subgraph HL["headlamp (always)"]
        HLC["headlamp-credentials"]
        IAP_HL["gateway-iap-oauth (copy)"]
    end
    subgraph PG["pgadmin (always)"]
        IAP_PG["gateway-iap-oauth (copy)"]
    end
    subgraph ACD["argocd (always)"]
        ACDsvc["ArgoCD server<br/>Google OIDC login"]
    end
    subgraph MS["microservices (always)"]
        GHCR["ghcr-credentials"]
    end
    subgraph JN["jenkins (jenkins-mode only)"]
        JC["jenkins-credentials"]
        IAP_JN["gateway-iap-oauth (copy)"]
    end

    ACDsvc -. "reads IAP client<br/>for OIDC (from headlamp)" .-> IAP_HL
    IAP_HL --> GPHL["GCPBackendPolicy<br/>headlamp IAP"]
    IAP_PG --> GPPG["GCPBackendPolicy<br/>pgadmin IAP"]
    IAP_JN --> GPJN["GCPBackendPolicy<br/>jenkins IAP"]
    JC -. "JCasC (same ns only)" .-> JKS["Jenkins controller"]
    GHCR -. "imagePullSecret" .-> POD["microservices pods"]

    classDef gated stroke-dasharray: 5 5;
    class JN,JC,IAP_JN,GPJN gated;
```

### Diagram 2 — Secret provenance flow

Every in-cluster Secret originates from a GitHub Actions secret (or a Terraform
backend output), is materialised into the **consumer's** namespace, and is read
only from there. **How** it is materialised is selectable — see
[Secrets backend](#secrets-backend-imperative--eso) below. The default
(`imperative`) flow is:

```mermaid
flowchart LR
    subgraph GH["GitHub Actions secrets"]
        S1["IAP_OAUTH_CLIENT_ID/SECRET"]
        S2["REGISTRY_* / GIT_*"]
        S3["HEADLAMP_OIDC_*"]
        S4["K6_CLOUD_* (optional)"]
    end
    subgraph SC["01-namespaces.sh"]
        L["materialise per consumer ns<br/>(idempotent create-or-patch)"]
    end
    S1 --> L
    S2 --> L
    S3 --> L
    S4 --> L
    L --> A["gateway-iap-oauth<br/>→ headlamp / pgadmin / engine ns"]
    L --> B["tekton-registry / tekton-git<br/>→ tekton-ci"]
    L --> C["headlamp-credentials<br/>→ headlamp"]
    L --> D["jenkins-credentials<br/>→ jenkins (jenkins-mode)"]
    A --> E["GCPBackendPolicy IAP + ArgoCD OIDC"]
    B --> F["PipelineRuns"]
    C --> G["Headlamp"]
    D --> H["Jenkins controller"]
```

### Secrets backend (`imperative` | `eso`)

> 🔐 **Pluggable secrets backend.** A feature flag — `secrets.backend` in
> `config/config.yaml` (override `JENKINS2026_SECRETS_BACKEND`, or the
> **`secrets_backend` input** on `Day1.cluster.01` / `Day1.cluster.00`) — selects
> **how** in-cluster Secrets are materialised, the same way `ci.engine` /
> `observability.mode` select their dimensions. The **whole lifecycle** honours it
> and is idempotent: `up.sh` (`01-namespaces.sh` push → `08.6-eso-sync.sh` sync), and
> the **Day2 redeploys that re-run `01-namespaces.sh`** — `Day2.redeploy.03-tekton`,
> `.04-headlamp`, `.05-gateway` — carry the same `secrets_backend` input (so a Day2 on
> an `eso` cluster never recreates the Secret imperatively). Decom needs nothing extra:
> `down.sh` deletes the namespaces (and with them the ExternalSecrets/Secrets), the
> cluster teardown removes the `ClusterSecretStore`, and the Secret Manager entries
> persist by design as the reusable source of truth.

| Backend | How Secrets are made | Source of truth | Audit / versioning | Default |
| :--- | :--- | :--- | :--- | :---: |
| **`imperative`** | `01-namespaces.sh` runs `kubectl create secret` from the GitHub-secret env vars (Diagram 2 above) | GitHub Actions secrets | none in-cluster | ✅ |
| **`eso`** | values pushed to **GCP Secret Manager**; the **External Secrets Operator** syncs them into namespaces via **Workload Identity (keyless)** | GCP Secret Manager (versioned) | **Cloud Audit Logs** + SM versions | |

In `eso` mode the flow becomes (now wired for the gateway IAP secret, the Tekton
pipeline credentials, and `ghcr-credentials`; the rest follows the same pattern —
staged rollout below):

```mermaid
flowchart LR
    GH["GitHub Actions secret<br/>(IAP_OAUTH_*)"] -->|"01-namespaces.sh<br/>(scripts/lib/secrets.sh)"| SM[("GCP Secret Manager<br/>gateway-iap-oauth (versioned)")]
    SM -->|"Workload Identity (keyless)<br/>GSA eso-secret-reader: secretmanager.secretAccessor"| ESO["External Secrets Operator<br/>ClusterSecretStore gcp-store"]
    ESO -->|"08.6-eso-sync.sh applies<br/>ExternalSecret per ns + waits"| K[("k8s Secret gateway-iap-oauth<br/>→ headlamp / pgadmin / engine ns")]
    K --> P["GCPBackendPolicy (IAP)"]
    classDef sm fill:#eef,stroke:#66c;
    class SM,ESO sm;
```

**Why `eso` adds value:** a single managed source of truth, secret **versioning**,
**Cloud Audit Logs** of every access, optional rotation, and it decouples secrets
from the provision script — all keyless (WIF), no Vault/server to run. (Analysis of
why **not** HashiCorp Vault here: it would add a stateful HA service + its own
unseal root-of-trust, over-engineered for an ephemeral single-stack PoC.)

**Coverage by ESO-fitness group.** `eso` is opt-in; the default stays `imperative`,
unchanged until you validate the flag on a Day1 run. Which secrets are projected via
ESO **when the flag is enabled** depends on how well each secret's *value lifecycle*
fits ESO's core assumption — *the value already lives in Secret Manager, read-only*.
The stack's secrets fall into four groups; **this PoC wires groups 1–3** and leaves
only group 4 imperative:

| Group | Secrets | ESO fit | In `eso` mode |
| :--- | :--- | :--- | :--- |
| **1 — clean** *(value is an external, static input)* | `gateway-iap-oauth` (+ its `-client-secret`), `tekton-github-webhook-secret`, `k6-cloud` | ✅ **Native** — `dataFrom.extract` / single `property` | ✅ **wired** |
| **2 — templated** *(typed Secret built from external inputs)* | `ghcr-credentials` + `tekton`-registry (`dockerconfigjson`), `tekton`-git (`basic-auth` + `tekton.dev/git-0`) | ✅ via `target.template` — rebuilds the typed payload from `username`/`password`/`registry` keys | ✅ **wired** |
| **3 — generated / multi-writer** | `jenkins-credentials` (admin pw generated at create; URL + `argocd-token` keys patched by later steps), `headlamp-credentials`, `pac-webhook` (`openssl rand`), `grafana-jenkins-ds` (mirrors the Jenkins pw) | ✅ **seed-then-project** — the generated value is seeded **stable** into SM (`sm_keep_or_generate`), and `jenkins-credentials` uses **`creationPolicy: Merge`** so the imperatively-patched keys survive | ✅ **wired** |
| **4 — no upstream value** | `tekton-argocd` (token **minted in-cluster** by ArgoCD at deploy time), per-mode `grafana-cloud` / `azure-monitor` / `aws-managed` creds (**Terraform outputs**) | ❌ Nothing to sync *from* — the value is produced in-cluster / by Terraform, never pre-placed in SM | ❌ imperative |

*(Validation: groups 1–2 confirmed live on a real Day1 — ExternalSecrets `SecretSynced`,
correct types, consumers working; group 3 is newly wired and should be re-validated on a
Day1 with `secrets_backend=eso`, especially the `jenkins-credentials` Merge + stable
admin-password, since a mistake there affects Jenkins login.)*

**Why group 4 stays imperative.** Groups 1–3 all end with the value *in* Secret Manager:
groups 1–2 because it starts there (an external input), group 3 because we **seed** the
generated value into SM once and keep it stable (`sm_keep_or_generate`) — and for the
multi-writer `jenkins-credentials`, ESO uses `creationPolicy: Merge` so the URL keys (01)
and the ArgoCD token (08.5) patched onto the Secret survive. Group 4 has **no upstream
value to seed**: `tekton-argocd` is minted *by ArgoCD in-cluster at deploy time*, and the
observability backend creds are *Terraform outputs* applied directly by the Day1 workflow.
ESO-ifying those would mean writing an in-cluster / Terraform value *into* SM purely to read
it straight back out — pure indirection with no managed-source-of-truth benefit, so they
stay imperative by design.

**Does the ESO integration add value — partial (1–3) vs complete (also 4)?**

- **Partial (groups 1–3, what ships here): yes — and it now covers the high-value
  secrets too.** It exercises the whole mechanism end-to-end (keyless WI auth, one
  `ClusterSecretStore`, all four projection shapes + `Merge`) and gives a single managed
  source of truth — **versioning + Cloud Audit Logs + rotation** — to the externally-sourced
  creds (registry, IAP OAuth, webhook / k6 tokens) **and** the generated ones (the Jenkins
  admin password, the PaC HMAC), while leaving the `imperative` default untouched (opt-in).
- **Complete (also group 4): not worth it, even in production.** Unlike group 3, group 4
  has no real upstream value — pushing an ArgoCD-minted token or a Terraform output into SM
  just to read it back adds a moving part (a post-mint push-back) for zero centralization
  benefit; those values are already managed where they are produced (ArgoCD / Terraform state).
  So full ESO coverage is **not** a goal: group 4 is correctly left imperative. (Same
  fit-the-tooling reasoning as choosing ESO over a self-hosted Vault above.)

Pieces: the flag ([`config.sh`](../scripts/lib/config.sh)), the push helper
([`scripts/lib/secrets.sh`](../scripts/lib/secrets.sh)), the sync+wait step
([`scripts/08.6-eso-sync.sh`](../scripts/08.6-eso-sync.sh)), the reference manifests
([`infrastructure/secrets/eso-bootstrap.yaml`](../infrastructure/secrets/eso-bootstrap.yaml)),
and the GCP enablement, which has **three** parts (a write side and a read side
either side of Secret Manager):

- **API** — `secretmanager.googleapis.com`, enabled in `terraform/gke` alongside
  `container`/`compute` (left on; unused in imperative mode).
- **Write (push) side** — the CI service account that runs `up.sh` needs
  `roles/secretmanager.admin` (the minimal predefined role that includes
  `secrets.create`); granted in `terraform/bootstrap`'s `ci_roles`. **Adding it
  to an existing bootstrap requires a one-time human `terraform apply` in
  `terraform/bootstrap`** (the CI SA's roles live there, like all the others).
- **Read (sync) side** — the cluster runs **GKE Workload Identity** (`GKE_METADATA`),
  so ESO pods authenticate as the GSA bound to their KSA, **not** the node SA.
  `terraform/gke` creates a dedicated least-privilege GSA (`eso-secret-reader`,
  only `roles/secretmanager.secretAccessor`) and a `workloadIdentityUser` binding
  to the controller KSA `external-secrets/external-secrets`; the KSA is annotated
  with that GSA's email via the external-secrets ArgoCD app's helm values
  (templated in `scripts/08.5-argocd.sh`). Because a pod's GCP identity is fixed
  at creation, `08.6-eso-sync.sh` also **restarts the ESO controller** so it adopts
  the annotation on an idempotent re-run (the controller pod from a prior run
  predates it and would otherwise keep failing to authenticate).

**Active-backend resolution (detection, not just the flag).** Like `ci.engine`
(`j2026_active_ci_engine`), the *active* backend is resolved by
`j2026_active_secrets_backend` ([`common.sh`](../scripts/lib/common.sh)) with the
precedence: **explicit `JENKINS2026_SECRETS_BACKEND` override → detect from the
live cluster → `config.yaml` default**. Detection keys off the `ClusterSecretStore/gcp-store`
CR (created only in eso mode by `08.6`), *not* the ESO operator (installed in both
modes). So a **standalone Day2 redeploy** — or `down.sh` during a Decom — does the
right thing on an eso cluster **even if the operator forgets to pass
`secrets_backend`** (whose default is `imperative`, which would otherwise diverge:
`01-namespaces` would `kubectl`-create the Secret while the ESO `ExternalSecret`
still owns it). Day1 always sets the override explicitly, so provisioning is
unaffected; the `secrets_backend` workflow input is therefore an *optional override*
of the detection, not a requirement.

**Teardown.** In eso mode the Secret Manager secret is the one piece that outlives
the cluster (it's project-level). `down.sh` deletes it on teardown (detected from
the still-running cluster, so the Decom workflows need no `secrets_backend` input);
best-effort, and a future Day1 re-pushes it from the GitHub secret.

### Why the `gateway-iap-oauth` Secret is replicated

This is the one secret that legitimately lives in several namespaces — and it is a
**hard GKE constraint, not a design smell**. A GKE `GCPBackendPolicy` that enables
Identity-Aware Proxy references an OAuth-client `Secret` by name, and that Secret
**must live in the same namespace as the backend `Service`** it protects. There is
no way to point a backend policy at a Secret in another namespace, so the single
OAuth client has to be copied into every IAP-protected backend namespace.

```mermaid
graph TD
    GHS["GitHub secret<br/>IAP_OAUTH_CLIENT_ID/SECRET"] --> NS["01-namespaces.sh<br/>replicate to each IAP backend ns"]
    NS --> H["headlamp/<br/>gateway-iap-oauth"]
    NS --> P["pgadmin/<br/>gateway-iap-oauth"]
    NS --> T["tekton-pipelines/<br/>gateway-iap-oauth<br/>(tekton-mode)"]
    NS --> J["jenkins/<br/>gateway-iap-oauth<br/>(jenkins-mode)"]
    H --> HP["GCPBackendPolicy → Headlamp Service"]
    P --> PP["GCPBackendPolicy → pgAdmin Service"]
    T --> TP["GCPBackendPolicy → Tekton Dashboard Service"]
    J --> JP["GCPBackendPolicy → Jenkins Service"]
    H -. "ArgoCD (no IAP, uses OIDC) reads<br/>the client from headlamp" .-> ACD["argocd/ ArgoCD server"]
```

> ArgoCD is **not** IAP-gated (it has its own Google OIDC login), but it reuses the
> *same* OAuth client. It therefore reads `gateway-iap-oauth` from the always-present
> `headlamp` namespace rather than minting a second client.

### The `platform-ingress` decoupling

Historically the repo was **Jenkins-only**, so the `jenkins` namespace doubled as
the de-facto "platform" namespace: it was always present, so the shared GKE Gateway
was created there and other scripts reached into it for shared-ish values. When
Tekton became a selectable engine and the `jenkins` namespace was gated to
jenkins-mode, that coupling surfaced as bugs. The fixes:

| Coupling (when `jenkins` ns was the "platform" ns) | Fix |
|---|---|
| The **GKE Gateway** lived in `jenkins` → deleting the ns (or running tekton) killed all public access | Gateway moved to the engine-neutral **`platform-ingress`** namespace |
| `08.5-argocd.sh` read the **IAP client** from `jenkins` for ArgoCD's OIDC → empty in tekton-mode | now reads `gateway-iap-oauth` from **`headlamp`** (always present) |
| `03-observability.sh` read `jenkins-credentials` for a **Grafana→Jenkins datasource** | gated to `ci.engine=jenkins` (pointless without Jenkins) |
| `07.5-grafana-alerts.sh` read `jenkins-credentials.oidc-admin-email` as an alert-email fallback | already guarded (`|| true`); yields empty harmlessly in tekton-mode |
| NetworkPolicies / ResourceQuota / LimitRange / RBAC **targeting the `jenkins` ns** applied unconditionally | all gated to `ci.engine=jenkins` (the jenkins-ns NetworkPolicies live in `infrastructure/networkpolicies-jenkins.yaml`) |

The end state matches the design principles above: **secrets per-app**, the IAP
client replicated only because GKE requires it, the public ingress engine-neutral,
and nothing reaching into `jenkins-credentials` except Jenkins itself.

## GKE Cluster Topology & Sizing

The throwaway cluster is provisioned via `terraform/gke/` with a custom VPC-native configuration optimized for stability and cost. A **persistent** global static IP and Google-managed wildcard TLS certificate (`terraform/gateway-bootstrap/`) survive cluster rebuilds so DNS records never need updating.

**Network dataplane**: the cluster runs **GKE Dataplane V2** (Cilium/eBPF, `datapath_provider = ADVANCED_DATAPATH`) so Kubernetes `NetworkPolicy` is actually enforced, with **WireGuard inter-node pod encryption** (`in_transit_encryption_config`) on top — sidecar-free, no service mesh. Both are immutable fields (changing them recreates the cluster). See [`docs/501` § Zero-Trust Security](501-PLATFORM_OPERATIONS.md) for the NetworkPolicy model and the encryption scope/caveats.

<details>
<summary>🔍 Click to expand GKE Cluster Topology Diagram</summary>

```mermaid
graph TD
    subgraph Internet ["Internet"]
        User["User / Browser"]
    end

    subgraph DNS ["DNS (Terraform-managed, idempotent)"]
        ParentNS["Parent domain (Squarespace)<br/>NS jenkins2026 → delegated zone<br/>(one-time delegation)"]
        Zone["Permanent Cloud DNS zone<br/>jenkins-2026-public-zone<br/>(terraform/bootstrap)"]
        WildcardA["*.jenkins2026...com  A → static IP<br/>(records: gateway-bootstrap)"]
        ParentNS --> Zone --> WildcardA
    end

    subgraph GlobalLB ["Global L7 Load Balancer"]
        StaticIP["Static IP<br>jenkins-2026-gateway-ip"]
        CertMap["Cert Map<br>jenkins-2026-cert-map"]
        WildcardTLS["Wildcard TLS<br>*.jenkins2026...com"]
    end

    subgraph VPC ["VPC: jenkins-2026-vpc"]
        subgraph Subnet ["Subnet: jenkins-2026-subnet"]
            SubnetInfo["europe-southwest1"]
            NodeRange["Nodes: 10.10.0.0/20"]
            PodRange["Pods: 10.20.0.0/16"]
            SvcRange["Services: 10.30.0.0/20"]
        end
    end

    subgraph Cluster ["GKE Cluster (v1.35/v1.36)"]
        GatewayAPI["GKE Gateway API<br/>gke-l7-global-external-managed"]
        BackendTLS["BackendTLSPolicy<br/>Secure TLS to pods"]
        WI["Workload Identity Federation"]
    end

    subgraph KarpenterPool ["Karpenter NodePool: ephemeral-runners"]
        PoolInfo["Spot Instances<br/>e2/n2/c2/c3 dynamic scaling"]
    end

    User -->|"resolve host"| ParentNS
    WildcardA -.->|"resolves to"| StaticIP
    User -->|"HTTPS"| StaticIP
    StaticIP --> CertMap
    CertMap --> WildcardTLS
    WildcardTLS -->|"terminates TLS"| GatewayAPI
    GatewayAPI -->|"routes via BackendTLSPolicy"| BackendTLS
    BackendTLS -->|"zero-trust HTTPS"| KarpenterPool
```

</details>

| Layer | Resource | Details |
|---|---|---|
| **Static IP** | `jenkins-2026-gateway-ip` | Global persistent `google_compute_global_address`. Survives cluster rebuilds. |
| **TLS Certificate** | `jenkins-2026-cert` | Google-managed wildcard cert for `jenkins2026.nubenetes.com` + `*.jenkins2026.nubenetes.com`. |
| **GKE Cluster** | `jenkins-2026` | Zonal cluster in `europe-southwest1-a`. VPC-native, Gateway API addon `CHANNEL_STANDARD` (cluster release channel `REGULAR`), Workload Identity enabled. |
| **Karpenter NodePool** | `ephemeral-runners` | Spot instances (`c2`, `n2`, `e2`, `c3` families). Scales to zero under idle conditions. |
| **Node SA** | `jenkins-2026-nodes` | Minimal-privilege: `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/artifactregistry.reader`. |
| **CI Agent SA** | `jenkins-2026-ci-agent` | GitHub Actions OIDC WIF — no static JSON keys. |

### Sizing Rationale

Running Jenkins, ArgoCD, pgAdmin, two Postgres HA clusters (CNPG), OpenTelemetry operators, and the JHipster microservices stack requires significant resources. `e2-standard-8` with 3 nodes ensures a stable environment with enough headroom to spawn dynamic Jenkins build agent pods. Smaller nodes (`e2-standard-2`) would cause OOM kills, CPU starvation, and pending pods.

### FinOps & Cost Analysis

- **Cluster Management Fee**: `$0.10/hour` (waived for first zonal cluster per billing account).
- **Compute**: ~`$0.22/hour` per `e2-standard-8` in Madrid (`europe-southwest1`).
- **Total run rate**: ~`$0.70–$0.80/hour` for the active 3-node cluster.
- **Per-session cost**: ~`$0.10–$0.20` for a full 15–25 minute provision + smoke test + teardown cycle.
- **Always decommission**: Run `Decom.cluster.01 GKE decommission` when finished — never leave the cluster running overnight.

---

[← Previous: 103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md) | [🏠 Home](../README.md) | [→ Next: 301. Observability](./301-OBSERVABILITY.md)

---

*201. Architecture — jenkins-2026*
