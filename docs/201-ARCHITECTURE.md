[← Previous: 104. Rebuild-Safety](./104-REBUILD_SAFETY.md) | [🏠 Home](../README.md) | [→ Next: 202. Microservices App Architecture](./202-MICROSERVICES-APP-ARCHITECTURE.md)

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

## Understanding the architecture (newcomers → specialists)

One file (`config/config.yaml`) drives everything, three feature flags pick the variant, and the rest is GitOps. Read this once and every section below is "where each piece lives".

<details>
<summary>🧠 System mental model (mindmap)</summary>

```mermaid
mindmap
  root((jenkins-2026))
    Source of truth
      config.yaml
      J2026 env vars
      three feature flags
    CI engine
      Jenkins default
      Tekton · GitHub Actions/ARC · Argo Workflows
      one of four · mutually exclusive
    GitOps CD
      ArgoCD
      gitops-config repo
      app-of-apps
    Workloads
      gateway + jhipster
      CNPG Postgres HA
      PgBouncer poolers
    Observability
      OpenTelemetry
      oss · grafana-cloud
      managed-azure · managed-aws
    Platform
      Gateway API + IAP
      Dataplane V2 + WireGuard
      secrets imperative or eso
```

</details>

**Reading it —** the six branches are the planes the rest of this doc details: a single **source of truth** (`config.yaml` → `J2026_*` env via [`scripts/lib/config.sh`](../scripts/lib/config.sh)), a pick-one **CI engine**, **ArgoCD** as the always-on GitOps CD, the **workloads** (the two JHipster services + their HA CNPG Postgres), **OpenTelemetry** flowing to one of four backends, and the **platform** layer (ingress/IAP, Dataplane V2, pluggable secrets). The three feature flags — `ci.engine`, `observability.mode`, `secrets.backend` — are the only knobs that change the shape.

<details>
<summary>🟢 For newcomers — what this deploys</summary>

| Piece | In plain terms |
|---|---|
| **Single source of truth** | `config/config.yaml` holds every setting; scripts load it as `J2026_*` env vars. Change config, re-run — no hand-editing manifests. |
| **CI** | One of four engines — **Jenkins** (default), **Tekton**, **GitHub Actions (ARC)**, or **Argo Workflows** — builds each service, pushes the image to GHCR, then **commits the new image tag** to the GitOps repo. |
| **CD (GitOps)** | **ArgoCD** watches the GitOps repo and reconciles the cluster to match it. CI never `kubectl apply`s the apps. |
| **Apps** | Two JHipster services — `gateway` (Spring Boot + Angular UI) and `jhipstersamplemicroservice` — each with a 3-node **HA Postgres** (CloudNative-PG) behind a PgBouncer pooler. |
| **Observability** | Everything emits **OpenTelemetry** (traces/metrics/logs) to an in-cluster collector, which forwards to one of four backends. |
| **Three switches** | `ci.engine` (jenkins\|tekton\|githubactions\|argoworkflows), `observability.mode` (grafana-cloud\|oss\|managed-azure\|managed-aws), `secrets.backend` (imperative\|eso) — each deterministic & idempotent. |

</details>

<details>
<summary>🔴 For specialists — how the pieces are wired</summary>

- **Two-repo GitOps**: this **infra repo** (bootstrap, the chosen CI engine, ArgoCD, observability) vs the **gitops-config repo** (microservices Helm + CNPG manifests + image tags). CI writes tags into the latter; ArgoCD reconciles from it.
- **`ci.engine` — one of four** (Jenkins default · Tekton · GitHub Actions/ARC · Argo Workflows), mutually exclusive and **engine-gated**: each engine's namespaces exist only in its mode — `jenkins`, the `tekton-*` set, `arc-systems`/`arc-runners` (ARC), or `argo`/`argo-events`/`argo-ci`. All four share the same 10-stage contract + `services.yaml` + `resources/patch-app-source.sh`. Switching engines retires the other three (the shared `retire_ci_engine` helper). The public ingress is engine-neutral (`platform-ingress`).
- **`observability.mode` — four backends**, the OTel collector reconfigured per mode; each branch retires the others' agents on a switch.
- **`secrets.backend` — `imperative` (default) vs `eso`**: ESO syncs from **GCP Secret Manager** over **keyless Workload Identity**; groups 1–3 are wired, group 4 (in-cluster/Terraform-minted) stays imperative.
- **Platform**: one GKE **Gateway** + **Google IAP**, **Dataplane V2** (Cilium/eBPF NetworkPolicy enforcement) + **WireGuard** inter-node encryption, **Node Auto-Provisioning** (GKE-native, GA) Spot CI-agent nodes via a Custom **ComputeClass**, and the IAP OAuth secret **replicated** per backend namespace (a GKE constraint, not a smell).
- Each in-cluster Secret lives in its **consumer's** namespace (locality for tight RBAC + clean teardown); see the Namespace & Secret topology below.

</details>

## System Architecture

<details>
<summary>🔍 Click to expand System Architecture Diagram</summary>

Two pluggable choices, both deterministic & idempotent: the **CI engine** (`ci.engine`: one of four — **Jenkins** default / **Tekton** / **GitHub Actions (ARC)** / **Argo Workflows**, all sharing one 10-stage contract) and the **observability backend** (`observability.mode`: one of oss / grafana-cloud / managed-azure / managed-aws). ArgoCD is always the CD/GitOps engine. This is the same overview as [README § 3](../README.md#3-architecture-overview); the [Component Diagram](#component-diagram) below drills into the Jenkins/microservices/observability internals.

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
        PGBK[("postgres-backups bucket")]:::prov
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
        LB["L7 LB · wildcard TLS · re-encrypt"]:::edge
        IAPN["Identity-Aware Proxy<br/>admin allowlist"]:::edge
        GW["Gateway (ns platform-ingress)<br/>HTTPRoutes · GCPBackendPolicy"]:::edge
      end

      subgraph CP["L3 · Control plane (GKE)"]
        direction TB
        ACD["ArgoCD 3.4.x (always the CD engine)<br/>1 AppSet · app-of-apps · single apps"]:::ctrl
        subgraph CIENG["CIENG · pick EXACTLY ONE (ci.engine)"]
          direction TB
          CONTRACT["shared 10-stage contract<br/>patch-app-source.sh · services.yaml"]:::contract
            JEN["JEN · jenkins (default *)<br/>chart · JCasC · IAP UI"]:::eng1
            TEK["TEK · tekton<br/>CRDs · IAP Dash · PaC"]:::eng2
            GHAARC["GHA-ARC · GitHub Actions/ARC<br/>ephemeral · ci-spot · NO in-cluster UI"]:::eng3
            ARGOWF["ARGOWF · argoworkflows<br/>WF v3.7.15 + Events · IAP UI"]:::eng4
        end
        OPS["OPS · Operators<br/>ESO · OTel · CNPG · Argo Rollouts"]:::ctrl
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
          AZ["managed-azure<br/>azuremonitor · keyless Entra"]:::bk3
          AWS["managed-aws<br/>xray+cloudwatch · keyless OIDC"]:::bk4
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
    GW -->|"open: microservices·faro·argocd"| GWAPP & SRCS & ACD
    GW -->|"HMAC public"| ARGOEV & PACWH

    CISA -->|"up.sh 00→09"| ACD
    ACD -->|"installs / syncs"| CONTRACT & OPS & GWAPP
    PUSH -. "companions" .-> CONTRACT & GWAPP
    OPS -. "OTel inject · ESO/CNPG WIF" .-> GWAPP
    CONTRACT --- JEN & TEK & GHAARC & ARGOWF
    TEK -. "webhook" .-> PACWH
    ARGOWF -. "webhook" .-> ARGOEV

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

- **L0 · Day0 root-of-trust** — human-run, *never* torn down: WIF/OIDC keyless trust · the GCS Terraform-state bucket · the permanent DNS zone.
- **L1 · Provisioning / IaC** — Terraform (one state bucket, per-module prefixes).
- **L2 · GCP edge** — DNS → L7 LB → **IAP** → Gateway.
- **L3 · Control plane** —
  - **ArgoCD** — always the CD/GitOps engine.
  - the **chosen CI engine** — 1 of 4 (Jenkins · Tekton · GitHub Actions/ARC · Argo Workflows); see *Pluggable choices* below.
  - **operators** — External Secrets · OTel · CNPG · Argo Rollouts.
  - the imperative **push** lane ArgoCD doesn't own.
- **L4 · Data / runtime plane** — the JHipster gateway + microservice + CloudNative-PG, on the static-vs-NAP node substrate.
- **L5 · Observability pipeline** — the OpenTelemetry collectors.
- **L6 · Backend store** — the one active backend.

**Colours:**

- **Fill colour = component *type*.** Each node & subgraph is tinted by type — external · Day0 root-of-trust · L1 IaC · edge · control plane · data/runtime · develop tier · node substrate · imperative-push · observability · shared CI contract · Secret Manager. Every subgraph carries its own tint, so no two containers share one colour (the old diagram's flaw).
  - The **four CI engines** each get a distinct hue, grouped in the pick-ONE `CIENG` box.
  - The **four observability backends** each get a distinct hue, grouped in the pick-ONE `BK` box.

**Pluggable choices** — each deterministic & idempotent, exactly **one value per cluster**, set in `config/config.yaml` (or the `Day1.cluster.01` inputs) and switched on a re-run. (**ArgoCD is always the CD/GitOps engine** — not pluggable.)

1. **CI engine** (`ci.engine`) — **one of four**, mutually exclusive; all four share the same **10-stage contract** + the shared **`resources/patch-app-source.sh`** + the `services.yaml` registry:
   - **Jenkins** *(default)* — in-cluster UI behind IAP.
   - **Tekton** — in-cluster Dashboard behind IAP.
   - **GitHub Actions (ARC)** — **no in-cluster UI** (github.com is the UI); triggers **branch-based** on a push to the fork's `main` / `develop`.
   - **Argo Workflows** — in-cluster Argo Server UI behind IAP.
2. **Observability backend** (`observability.mode`) — **one of four**: `oss` (in-cluster) · `grafana-cloud` · `managed-azure` · `managed-aws`. The three external ones are decoupled, persistent, **keyless** (WIF/OIDC) Day0 resources.
3. **Secrets backend** (`secrets.backend`) — `imperative` *(default)*, or `eso` → pushed to **GCP Secret Manager** + synced by the **External Secrets Operator** (keyless WIF).
4. **Lean `develop` tier** (`microservices.developTrackEnabled`, **off by default**) — a non-HA `microservices-develop` namespace alongside `stable`, folded into **L4**, sharing the same observability stack.

The [Component Diagram](#component-diagram) below drills into the Jenkins / microservices / observability namespace internals.

## Component Diagram

<details>
<summary>📊 Component diagram — CI engine / microservices / observability namespaces</summary>

```mermaid
flowchart TD
    repo["github.com/nubenetes/jenkins-2026<br/>vars/ shared library + MicroservicesPipeline.groovy,<br/>seed/services.yaml, resources/patch-app-source.sh,<br/>Helm charts, tekton/ + argoworkflows/ + .github pipelines"]

    subgraph ci_ns["namespace: the active CI engine (ci.engine)<br/>jenkins · tekton-* · arc-systems/arc-runners · argo/argo-events/argo-ci"]
        ci["CI engine — one of four (mutually exclusive)<br/>Jenkins (default) · Tekton · GitHub Actions/ARC · Argo Workflows<br/>- shared 10-stage contract + services.yaml + patch-app-source.sh<br/>- builds gateway / jhipstersamplemicroservice, runs microservices-k6-smoke<br/>- each run uses a pod agent<br/>  (maven / node / docker:dind / helm+kubectl / k6 containers)"]
    end

    repo -->|"shared library + pipeline-as-code<br/>(checkout scm)"| ci

    subgraph microservices_ns["namespace: microservices (stable, tracks main)"]
        microservices["gateway (Spring Boot + Angular UI),<br/>jhipstersamplemicroservice (Spring Boot backend)"]
    end

    subgraph microservices_dev_ns["namespace: microservices-develop (optional develop tier)"]
        microservices_dev["same services · deployment.environment=develop<br/>lean CNPG: 1 instance · no backups"]
    end

    ci -->|"image-tag bump → ArgoCD syncs<br/>(per-service, via gitops-config)"| microservices
    ci -. "develop track on (optional)" .-> microservices_dev
    classDef optTier stroke-dasharray:5 5;
    class microservices_dev_ns,microservices_dev optTier;

    subgraph observability_ns["namespace: observability"]
        otel["OpenTelemetry Operator (CRDs: Instrumentation,<br/>OpenTelemetryCollector) - Java auto-instrumentation<br/>otel-collector-gateway (Deployment, OTLP receiver)<br/>otel-collector-logs (DaemonSet, filelog receiver)"]
        k8s_mon["k8s-monitoring (Grafana Alloy Operator & StatefulSet)<br/>- Scrapes cluster metrics (kube-state-metrics)<br/>- Scrapes host metrics (node-exporter)<br/>- Collects cluster events"]
    end

    ci -->|OTLP| otel
    microservices -->|"OTLP (traces / metrics / logs)"| otel

    gke["GKE Cluster Infrastructure<br/>(Nodes, Kubelet, Events)"] --> k8s_mon

    subgraph backends["observability.mode — one of four (mutually exclusive)"]
        oss["oss<br/>In-cluster kube-prometheus-stack<br/>(Prometheus + Grafana) + Loki + Tempo"]
        grafana_cloud["grafana-cloud<br/>OTLP gateway -> Mimir, Loki, Tempo + Grafana"]
        azure["managed-azure<br/>Azure Monitor / App Insights + Managed Grafana"]
        aws["managed-aws<br/>X-Ray + CloudWatch + Amazon Managed Prometheus/Grafana"]
    end

    otel -->|"exactly ONE active"| oss & grafana_cloud & azure & aws
    k8s_mon -->|"OTLP/HTTP (grafana-cloud mode only)"| grafana_cloud
```

</details>

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
    participant J as CI engine (one of four)
    participant GH_GitOps as GitHub (GitOps Config Repo)
    participant ACD as ArgoCD (CD)
    participant K8s as Kubernetes (GKE)
    participant Obs as Observability (Grafana)

    Note over J: Jenkins · Tekton · GitHub Actions/ARC · Argo Workflows<br/>same 10-stage contract + services.yaml + patch-app-source.sh
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

**Progressive delivery**: the platform installs **Argo Rollouts** + the Gateway API traffic-router plugin (GitOps via [`argocd/argo-rollouts-app.yaml`](../argocd/argo-rollouts-app.yaml)), so the microservices can roll out as weighted **canaries** by shifting the GKE Gateway HTTPRoute backend weights — sidecar-free, no service mesh. See [`docs/501` § Progressive Delivery](501-PLATFORM_OPERATIONS.md).

Single source of truth, loaded by every script via [`scripts/lib/config.sh`](../scripts/lib/config.sh) (`yq` → `J2026_*` env vars). Feature flags:

| Key | Default | Override | Meaning |
|---|---|---|---|
| `observability.mode` | `grafana-cloud` | edit `config.yaml` | `grafana-cloud`\|`oss`\|`managed-azure`\|`managed-aws` — where traces/metrics/logs go |
| `ci.engine` | `jenkins` | `JENKINS2026_CI_ENGINE` | `jenkins`\|`tekton`\|`githubactions`\|`argoworkflows` — one of four mutually-exclusive engines running the pipelines-as-code (Jenkins default). See [403. Tekton](./403-TEKTON.md), [404. GitHub Actions](./404-GITHUB_ACTIONS.md), [405. Argo Workflows](./405-ARGO_WORKFLOWS.md) |
| `microservices.developTrackEnabled` | `false` | `JENKINS2026_DEVELOP_TRACK_ENABLED` | Optional second microservices tier (`microservices-develop` namespace, GitOps `develop` branch) |

Other notable sections: `jenkins.*` (chart coordinates, namespace, this repo's own URL/branch), `observability.*` (operator/collector chart coordinates, release names, Secret name), `microservices.*` (namespaces, git org/repos/branches, target registry, list of 2 services seeded into Jenkins).

### CI engine: one of four (Jenkins · Tekton · GitHub Actions/ARC · Argo Workflows)

The `ci.engine` flag (`jenkins` default, override `JENKINS2026_CI_ENGINE`) selects which of **four mutually-exclusive** CI engines runs the pipelines-as-code — same durable-default/ephemeral-override pattern as `observability.mode`. Each engine has its own `scripts/04-<engine>.sh` + `scripts/06-<engine>-pipelines.sh` pair that takes the place of [`scripts/04-jenkins.sh`](../scripts/04-jenkins.sh) / [`scripts/06-seed-pipelines.sh`](../scripts/06-seed-pipelines.sh), and each begins by **retiring the other three** via the shared [`retire_ci_engine`](../scripts/lib/common.sh) helper (deletes their ArgoCD apps + all children + namespaces, and clears stuck GKE NEG finalizers) — so a switch never leaves orphans:

- **Jenkins** *(default)* — `helm install`-ed directly (chart + JCasC); its Job-DSL seed generates the pipeline jobs.
- **Tekton** — [`04-tekton.sh`](../scripts/04-tekton.sh) applies the **`argocd/tekton` app-of-apps** (ArgoCD installs Pipelines/Triggers/Dashboard + the pipelines-as-code under `tekton/`), then [`06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh) waits for the sync and seeds one PipelineRun per service. See [403. Tekton](./403-TEKTON.md).
- **GitHub Actions (ARC)** — [`04-githubactions.sh`](../scripts/04-githubactions.sh) applies the `argocd/githubactions` app-of-apps (Actions Runner Controller + the ephemeral runner scale set); the pipeline is a `.github/workflows` file rendered into each fork. **No in-cluster UI** (github.com is the UI). See [404. GitHub Actions](./404-GITHUB_ACTIONS.md).
- **Argo Workflows** — [`04-argoworkflows.sh`](../scripts/04-argoworkflows.sh) applies the `argocd/argoworkflows` app-of-apps (Argo Workflows controller+Server + Argo Events + the WorkflowTemplates/EventSource/Sensor under `argoworkflows/`); the Server UI is IAP-protected like the Tekton Dashboard. See [405. Argo Workflows](./405-ARGO_WORKFLOWS.md).

All four share the same ~10-stage pipeline contract, the [`jenkins/pipelines/seed/services.yaml`](../jenkins/pipelines/seed/services.yaml) registry, and the [`resources/patch-app-source.sh`](../resources/patch-app-source.sh) build-time app patch (Tekton/ARC/Argo Workflows are GitOps-managed via ArgoCD, unlike Jenkins which is `helm install`-ed directly).

## Repository Layout

```
config/config.yaml          single source of truth (feature flags above)
helm/jenkins/                jenkinsci/helm-charts values + values-gke.yaml overlay
helm/headlamp/               kubernetes-sigs/headlamp values (cluster management UI)
helm/pgadmin/                pgAdmin values (CNPG admin UI)
helm/argocd-values.yaml      ArgoCD install values
jenkins/casc/                JCasC: security, OTel exporter, seed job
jenkins/pipelines/           seed/ (seed job: Job DSL + Jenkinsfile.seed + services.yaml) + k6/ (smoke script)
vars/                        Jenkins global shared library (must be at repo root; MicroservicesPipeline.groovy — the microservices pipeline — lives here)
resources/                   patch-app-source.sh — the shared build-time app patch (gateway MySQL→Postgres + NoOp cache) all four engines call
tekton/                      Tekton pipelines-as-code (ci.engine=tekton): Tasks/Pipelines/Triggers/RBAC + port of the Jenkins shared library (vars/)
argoworkflows/               Argo Workflows pipelines-as-code (ci.engine=argoworkflows): WorkflowTemplates + EventSource/Sensor (the GitHub Actions/ARC pipeline is a .github/workflows file rendered into each fork)
observability/               OTel Operator/Collector + Grafana/Loki/Tempo/Prometheus values + dashboards
argocd/                      ArgoCD Applications/ApplicationSets + app-of-apps (platform-postgres, observability-oss, tekton, githubactions, argoworkflows) + argo-rollouts-app.yaml
infrastructure/              engine-neutral platform manifests applied by 01-namespaces / 08.5-argocd: NetworkPolicies (default + per-engine: -jenkins/-tekton/-githubactions/-argoworkflows), Gateway, Node Auto-Provisioning ComputeClasses (compute-classes/), scheduling, Argo Rollouts Gateway-API RBAC, secrets
scripts/                     00-09 numbered steps + up.sh / down.sh / status.sh
terraform/gke/               throwaway GKE cluster for test/e2e.sh
terraform/bootstrap/         one-time setup for GitHub Actions automation (state bucket + WIF + permanent public DNS zone)
terraform/gateway-bootstrap/ one-time setup for public access (static IP + managed certificate + DNS records in the zone)
scripts/08.5-argocd.sh       ArgoCD installation and OIDC configuration
test/                        e2e.sh (provision → up.sh → smoke-test.sh → down.sh → destroy)
.github/workflows/           DayN.tier.ZZ-resource.yml — see 101. GitHub Actions Workflows
docs/                        numbered docs (this file and siblings)
```

## Imperative (push) vs GitOps (pull): the provisioning split

The platform is provisioned by **two cooperating planes**, and which one owns a
resource is a deliberate, per-resource decision — not an accident of history.

- **GitOps plane (pull).** ArgoCD continuously **pulls** declarative manifests
  from this git repo and reconciles the cluster to match — drift-detected,
  self-healed, pruned. This owns everything that *can* be expressed as a static
  (or parameter-templated) manifest: the Helm charts and the workloads. See
  [`argocd/README.md`](../argocd/README.md) for the Application/ApplicationSet/
  app-of-apps topology.
- **Imperative plane (push).** The numbered `scripts/0N-*.sh` **push** resources
  with `kubectl`/`helm`/`kubectl patch`. This owns everything that *can't* live in
  the pull loop: the bootstrap of ArgoCD itself, secret **values**, runtime-derived
  manifests, live-reload companions, and genuinely external side-effects.

> **The mental model:** ArgoCD is the steady-state reconciler; the scripts are the
> bootstrapper and the bridge for everything git can't hold. The scripts even
> *plant* the ArgoCD `Application`s (one `kubectl apply` each) — so "imperative"
> here is often **how you hand a resource to GitOps**, not an alternative to it.

### The decision framework — six reasons a resource stays imperative

A resource is GitOps-managed **by default**. It stays imperative only if it hits
one of these (each is a hard constraint, not a preference):

1. **Bootstrap paradox.** ArgoCD can't deploy ArgoCD. The CD engine itself (plus
   the OTel Operator and the otel-collector it configures from runtime values) is
   `helm upgrade --install`-ed by [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) / `02` / `03`. [`up.sh`](../scripts/up.sh)
   installs ArgoCD (`08.5`) **before** observability (`03`) precisely so `03` can
   then apply the `observability-oss` app-of-apps.
2. **Secret values never enter git.** All `Secret` *material* originates outside
   git (GitHub Actions secrets, generated, or Terraform outputs). The delivery
   *mechanism* is selectable — `imperative` (`kubectl create`) or `eso` (push to
   GCP Secret Manager, the External Secrets Operator syncs it back, GitOps-style) —
   but the value's origin is never the repo. Full detail:
   [Secrets backend](#secrets-backend-imperative--eso) and the
   [Secret provenance flow](#diagram-2--secret-provenance-flow).
3. **Runtime-derived values not known at commit time.** The IAP `client_id` read
   live from a cluster Secret, the generated Grafana Cloud slug, the static IP, the
   interpolated domain/branch, the ArgoCD-minted API token. The whole
   Gateway / HTTPRoute / HealthCheckPolicy / GCPBackendPolicy set is **generated
   per-run** from `config.yaml` into `.generated/` and applied ([`09-gateway.sh`](../scripts/09-gateway.sh)).
4. **Live-reload single-source companions.** The JCasC ConfigMaps ([`04-jenkins.sh`](../scripts/04-jenkins.sh)
   from `jenkins/casc/*`) and the OSS-Grafana companion `grafana-jenkins-ds` Secret
   / `grafana-runtime-config` ConfigMap (`03`) are kept **out of GitOps on purpose**
   so a single source stays canonical and the sidecar can hot-reload without a sync.
   See [301 § script-managed companions](./301-OBSERVABILITY.md).
5. **External side-effects ArgoCD has no verb for.** Pushing `.tekton/` to the
   GitHub forks + creating webhooks + seeding the first PipelineRuns
   ([`06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh)), minting the ArgoCD API token, patching the CNPG
   webhook `caBundle` (`08.5`). These are *actions*, not manifests.
6. **Enforcement-ordering sensitivity.** A few static manifests must land **before
   the workloads they protect** — the **NetworkPolicies** and
   **ResourceQuotas/LimitRanges** in [`01-namespaces.sh`](../scripts/01-namespaces.sh). Under Dataplane V2 the OTel
   Operator's `:9443` webhook allow and the `microservices-cnpg-platform` egress
   must exist *before* those pods come up, or the workloads wedge (OutOfSync /
   Degraded). An ArgoCD app would sync them *concurrently* with the workloads — a
   timing regression — so they are deliberately kept on the early imperative path.

### Complete inventory — who owns what, and why

| Resource | Plane | Where | Why this plane |
|---|---|---|---|
| Jenkins, External-Secrets, Headlamp, Argo-Rollouts charts | **GitOps** | `argocd/*-app.yaml` (single Applications) | One chart each; declarative, versioned, self-healed. |
| Microservices (per service, per tier) | **GitOps** | [`argocd/microservices-appset.yaml`](../argocd/microservices-appset.yaml) (ApplicationSet) | Homogeneous fleet from the service registry; CI bumps image tags in the gitops-config repo, ArgoCD syncs. |
| CNPG+pgAdmin · OSS Prometheus/Loki/Tempo/Grafana · Tekton stack · **ARC** (GitHub Actions runners) · **Argo Workflows + Argo Events** | **GitOps** | `platform-postgres` / `observability-oss` / `tekton` / `githubactions` / `argoworkflows` app-of-apps | Heterogeneous, ordered (sync-waves), per-child sync options. The `githubactions` app-of-apps (when `ci.engine=githubactions`) syncs the ARC controller (wave 0) + the runner scale set / `AutoscalingRunnerSet` (wave 1) as two **OCI Helm** child apps. The `argoworkflows` app-of-apps (when `ci.engine=argoworkflows`) syncs three children — the Argo Workflows controller+server (wave 0) + Argo Events controller-manager + EventBus (wave 1) + the pipeline-as-code WorkflowTemplates/EventSource/Sensor (wave 2) — from **vendored** upstream release YAMLs (`argocd/argoworkflows/components/{workflows,events}/release.yaml`, like Tekton). |
| **Static platform RBAC** (Jenkins/Tekton SA `edit`, pgAdmin secret-reader, OTel-instrumentation `ClusterRole`) | **GitOps** | [`argocd/platform-config/`](../argocd/platform-config/) (new) — planted by `08.5` | Timing-insensitive (consumers run long after sync); textbook GitOps. *Migrated here from `01`/`02` — see [argocd/README](../argocd/README.md).* |
| ArgoCD itself · OTel Operator · otel-collector | **Imperative** | `08.5` / `02` / `03` `helm upgrade --install` | Bootstrap paradox (#1); the collector is also runtime-config-coupled (#4). |
| The ArgoCD `Application`/`AppSet`/`AppProject`/app-of-apps manifests (incl. [`argocd/microservices-project.yaml`](../argocd/microservices-project.yaml)) | **Imperative→GitOps** | `08.5` / `03` `kubectl apply` (sed-substituted) | *Planting* the root apps **is** how GitOps starts (the app-of-apps bootstrap). |
| ArgoCD version patch-watcher ([`argocd/argocd-version-patch-watcher.yaml`](../argocd/argocd-version-patch-watcher.yaml) — CronJob + RBAC) | **Imperative** | `08.5` `kubectl apply` | Daily watcher that tracks the latest ArgoCD `3.4.x` patch within the pinned minor (see [602](./602-VERSION_PINNING.md)); a cluster-side CronJob, not a GitOps app. |
| ArgoCD self-config (`argocd-cm`/`argocd-rbac-cm` OIDC/RBAC/CI account) | **Imperative** | `08.5` `kubectl patch` | Bootstrap paradox (#1) — how the engine learns to log in. |
| All in-cluster `Secret`s (jenkins/headlamp/IAP/tekton/**arc-github-app**/**arc-registry**/**argoworkflows-registry**/**argoworkflows-git**/**argoworkflows-github-webhook**/**argoworkflows-argocd**/ghcr/grafana-ds…) | **Imperative** *(or ESO)* | `01` / `03` / `08.5`; `08.6` in `eso` mode | Secret values never in git (#2). `eso` makes *delivery* GitOps-style. The ARC GitHub App creds (`arc-github-app`) + ghcr imagePullSecret (`arc-registry`) follow the same rule as the Tekton `tekton-registry`/`tekton-git` Secrets — built by `01-namespaces.sh` in `arc-runners` (ESO parity wired in `08.6`). The Argo Workflows engine follows the same rule: `argoworkflows-registry` (ghcr) + `argoworkflows-git` (basic-auth) + `k6-cloud` in `argo-ci` and `argoworkflows-github-webhook` (HMAC) in `argo-events` are built by `01-namespaces.sh`, and `argoworkflows-argocd` (ArgoCD API token) in `argo-ci` by `08.5-argocd.sh` (ESO parity in `08.6`). |
| Gateway · HTTPRoutes · HealthCheckPolicies · GCPBackendPolicies (IAP) | **Imperative** | [`09-gateway.sh`](../scripts/09-gateway.sh) → `.generated/` | Generated per-run with the live domain/IP/IAP-client-id (#3). |
| Runtime patches into `jenkins-credentials`/`headlamp-credentials` (URLs, tokens, banner links) | **Imperative** | `01` / `04` / `08.5` `kubectl patch` | Values discovered at run time (#3). |
| JCasC ConfigMaps · `grafana-jenkins-ds` · `grafana-runtime-config` | **Imperative** | `04` / `03` | Live-reload single-source companions (#4). |
| Tekton PaC push/webhooks/seed · ArgoCD token mint · CNPG `caBundle` patch | **Imperative** | `06` / `08.5` | External / in-cluster side-effects (#5). |
| **NetworkPolicies** · **ResourceQuotas/LimitRanges** | **Imperative** | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | Must land **before** workloads for Dataplane V2 enforcement timing (#6). |
| Namespace creation + labels | **Imperative** | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | The floor everything else lands in; must exist before any apply/sync. |
| Headlamp per-email admin `ClusterRoleBinding`s | **Imperative** | [`08-headlamp.sh`](../scripts/08-headlamp.sh) | Derived from a user list, not a static manifest. |

### The two planes (diagram)

<details>
<summary>📊 Provisioning planes — push (scripts) vs pull (ArgoCD)</summary>

```mermaid
flowchart TD
    subgraph BOOT["Bootstrap (imperative, helm/kubectl) — the floor"]
        NS["01: namespaces + labels"]
        SEC["01/03/08.5: Secrets (or ESO)"]
        NP["01: NetworkPolicies + Quotas<br/>(early, before workloads — DPv2 timing)"]
        OP["02/03: OTel Operator + collector"]
        ARGO["08.5: helm install ArgoCD<br/>+ patch OIDC/RBAC"]
    end
    subgraph PLANT["Hand-off — scripts plant the root Applications"]
        APPS["08.5/03: kubectl apply argocd/*-app.yaml<br/>(sed-substituted repo/branch/engine)"]
    end
    subgraph PULL["GitOps plane (ArgoCD reconciles — pull, self-heal, prune)"]
        CHARTS["charts: Jenkins · ESO · Headlamp · Rollouts"]
        FLEET["AppSet: microservices (per tier)"]
        AOA["app-of-apps: postgres · observability-oss<br/>+ active CI engine (tekton / githubactions / argoworkflows)"]
        PCFG["platform-config: static RBAC"]
    end
    subgraph RUNTIME["Imperative, AFTER ArgoCD is up (runtime-derived)"]
        GW["09: Gateway/HTTPRoutes/IAP (.generated/)"]
        JCASC["04: JCasC ConfigMaps (live-reload)"]
        SIDE["06: Tekton PaC push/webhooks/seed"]
    end

    BOOT --> PLANT --> PULL
    ARGO -.->|"installs/syncs"| PULL
    BOOT --> RUNTIME
    PULL -.->|"steady state: drift-detect + self-heal"| PULL

    classDef imp fill:#fde,stroke:#c39;
    classDef git fill:#eef,stroke:#66c;
    class NS,SEC,NP,OP,ARGO,APPS,GW,JCASC,SIDE imp;
    class CHARTS,FLEET,AOA,PCFG git;
```

</details>

### The irreducible imperative core

Even with maximal GitOps adoption, five things can **never** move to the pull loop:
(1) **ArgoCD itself + its self-config** — the engine can't bootstrap the engine;
(2) **secret source values** — they originate outside git, ESO only changes
*delivery*; (3) **external side-effects** — pushing to GitHub forks, creating
webhooks; (4) **live-reload single-source companions** — JCasC + Grafana inputs,
migrating them regresses the hot-reload design; (5) **reconciliation race-fixes** —
the CNPG `caBundle` patch and the token mint. Everything else is GitOps-managed, or
is a deliberate, documented exception above.

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
2. **The CI engine is mutually exclusive and engine-gated.** Exactly **one of four**
   engines is deployed (`ci.engine`: Jenkins · Tekton · GitHub Actions/ARC · Argo
   Workflows), never more than one — switching retires the other three (the shared
   `retire_ci_engine` helper). Each engine's namespaces and credentials are created
   **only** in its mode: the `jenkins` namespace + `jenkins-credentials` when
   `ci.engine=jenkins`; the `tekton-*` namespaces when `ci.engine=tekton`;
   `arc-systems`/`arc-runners` when `ci.engine=githubactions`; `argo`/`argo-events`/
   `argo-ci` when `ci.engine=argoworkflows`.
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
| `arc-systems` | **only `ci.engine=githubactions`** | ARC controller (`gha-runner-scale-set-controller`) |
| `arc-runners` | **only `ci.engine=githubactions`** | ephemeral GitHub Actions runner pods + their creds (`arc-github-app`, `arc-registry`) |
| `argo` | **only `ci.engine=argoworkflows`** | Argo Workflows control plane (controller + Server UI) + an IAP secret copy |
| `argo-events` | **only `ci.engine=argoworkflows`** | Argo Events controller-manager + EventBus + `argoworkflows-github-webhook` |
| `argo-ci` | **only `ci.engine=argoworkflows`** | Workflow execution: the `argoworkflows-ci` SA + its creds (`argoworkflows-registry`/`argoworkflows-git`/`argoworkflows-argocd`/`k6-cloud`) |

### In-cluster Secret inventory (the matrix)

| Secret | Namespace(s) | Contents | Shared / replicated? | Created by | Consumed by |
|---|---|---|---|---|---|
| **`jenkins-credentials`** | `jenkins` *(jenkins-mode)* | admin-password · registry user/pass · git user/token · oidc-client-id/secret · **oidc-admin-email** · microservices URLs · k6-cloud token/project | No — Jenkins config bundle | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | Jenkins controller (JCasC) |
| **`gateway-iap-oauth`** | `headlamp`, `pgadmin` (+ `grafana-oss` / `tekton-pipelines` / `jenkins` per mode) | IAP OAuth `client_id` / `client_secret` | **YES — replicated** (GKE constraint) | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | each ns's `GCPBackendPolicy` (IAP); `08.5` reads it (**from `headlamp`**) for ArgoCD's Google OIDC |
| `headlamp-credentials` | `headlamp` | OIDC client id/secret (+ issuer/scopes/callback) | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | Headlamp deployment |
| `tekton-registry` | `tekton-ci` *(tekton-mode)* | `dockerconfigjson` (ghcr.io push/pull, Jib auth) | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | PipelineRuns (build-push-image) |
| `tekton-git` | `tekton-ci` *(tekton-mode)* | git basic-auth, annotated for `github.com` | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | clone / gitops-deploy tasks |
| `tekton-github-webhook-secret` · `pac-webhook` | `tekton-ci` · `pipelines-as-code` *(tekton-mode)* | webhook HMAC token | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | Triggers EventListener / PaC |
| `k6-cloud` | `tekton-ci` *(tekton-mode; same keys also in `jenkins-credentials`)* | `K6_CLOUD_TOKEN` / `K6_CLOUD_PROJECT_ID` | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | k6 tasks (`--out cloud`, the k6-app) |
| `arc-github-app` | `arc-runners` *(githubactions-mode)* | GitHub App `app_id` / `installation_id` / `private_key` (or `github_token` PAT fallback) | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | ARC controller (runner registration) |
| `arc-registry` | `arc-runners` *(githubactions-mode)* | `dockerconfigjson` (ghcr.io) imagePullSecret | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | runner pods (image pull) |
| `argoworkflows-registry` · `argoworkflows-git` | `argo-ci` *(argoworkflows-mode)* | `dockerconfigjson` (ghcr.io push/pull) · git basic-auth | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | Workflow steps (build-push-image / clone / gitops-deploy) |
| `argoworkflows-argocd` | `argo-ci` *(argoworkflows-mode)* | ArgoCD API token (account `argoworkflows`) | No | [`08.5-argocd.sh`](../scripts/08.5-argocd.sh) | Workflow `argocd app sync` step |
| `argoworkflows-github-webhook` | `argo-events` *(argoworkflows-mode)* | GitHub webhook HMAC token | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | Argo Events GitHub EventSource |
| `ghcr-credentials` | `microservices` (+ `-develop`) | `dockerconfigjson` imagePullSecret | No | [`01-namespaces.sh`](../scripts/01-namespaces.sh) | microservices pods (image pull) |
| `grafana-jenkins-ds` | `grafana-oss` *(oss + jenkins-mode)* | `apiToken` (mirror of Jenkins admin password) | No | [`03-observability.sh`](../scripts/03-observability.sh) *(gated to jenkins-mode)* | Grafana → Jenkins datasource |
| `grafana-cloud-credentials` / `azure-monitor-credentials` / `aws-managed-credentials` | `observability` | backend endpoint + token/SP/role per `observability.mode` — **[group 4](#secrets-backend-imperative--eso) (Terraform outputs)**, so these stay **imperative even under `secrets.backend=eso`** (nothing to sync *from* — the value is a Day1 Terraform output, never pre-placed in Secret Manager). **Single-active-mode invariant:** only the active mode's Secret exists — [`03-observability.sh`](../scripts/03-observability.sh) retires the other two on provision, so a mode switch leaves no stale Secret to mislead `Day2.traffic.01-k6`'s secret-presence mode auto-detection (a leftover once produced a dead "VIEW IN GRAFANA" link — see [104](104-REBUILD_SAFETY.md) / [902](902-TROUBLESHOOTING.md)). | No | Day1 workflow / scripts | otel-collector exporter |

### Diagram 1 — Namespace & Secret topology

Each app's Secret sits in that app's namespace; the only cross-namespace **reads**
are the two that the IAP design forces (ArgoCD pulling the OAuth client) and that
the IAP backend policies need (the replicated client). `jenkins` is dashed — it
exists only in jenkins-mode (replace it mentally with the chosen engine's namespaces
in the other three modes: `tekton-*`, `arc-systems`/`arc-runners`, or
`argo`/`argo-events`/`argo-ci`).

<details>
<summary>📊 Diagram 1 — Namespace &amp; Secret topology</summary>

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
    subgraph MSD["microservices-develop (develop track only)"]
        GHCRD["ghcr-credentials"]
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
    GHCRD -. "imagePullSecret" .-> PODD["microservices-develop pods"]

    classDef gated stroke-dasharray: 5 5;
    class JN,JC,IAP_JN,GPJN,MSD,GHCRD,PODD gated;
```

</details>

### Diagram 2 — Secret provenance flow

Every in-cluster Secret originates from a GitHub Actions secret (or a Terraform
backend output), is materialised into the **consumer's** namespace, and is read
only from there. **How** it is materialised is selectable — see
[Secrets backend](#secrets-backend-imperative--eso) below. The default
(`imperative`) flow is:

<details>
<summary>📊 Diagram 2 — Secret provenance flow (imperative)</summary>

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

</details>

### Secrets backend (`imperative` | `eso`)

> 🔐 **Pluggable secrets backend.** A feature flag — `secrets.backend` in
> `config/config.yaml` (override `JENKINS2026_SECRETS_BACKEND`, or the
> **`secrets_backend` input** on `Day1.cluster.01` / `Day1.cluster.00-all`) — selects
> **how** in-cluster Secrets are materialised, the same way `ci.engine` /
> `observability.mode` select their dimensions. The **whole lifecycle** honours it
> and is idempotent: [`up.sh`](../scripts/up.sh) ([`01-namespaces.sh`](../scripts/01-namespaces.sh) push → [`08.6-eso-sync.sh`](../scripts/08.6-eso-sync.sh) sync), and
> the **Day2 redeploys that re-run [`01-namespaces.sh`](../scripts/01-namespaces.sh)** — `Day2.redeploy.03-tekton`,
> `.04-headlamp`, `.05-gateway` — carry the same `secrets_backend` input (so a Day2 on
> an `eso` cluster never recreates the Secret imperatively). Decom needs nothing extra:
> `down.sh` deletes the namespaces (and with them the ExternalSecrets/Secrets), the
> cluster teardown removes the `ClusterSecretStore`, and the Secret Manager entries
> persist by design as the reusable source of truth.

| Backend | How Secrets are made | Source of truth | Audit / versioning | Default |
| :--- | :--- | :--- | :--- | :---: |
| **`imperative`** | [`01-namespaces.sh`](../scripts/01-namespaces.sh) runs `kubectl create secret` from the GitHub-secret env vars (Diagram 2 above) | GitHub Actions secrets | none in-cluster | ✅ |
| **`eso`** | values pushed to **GCP Secret Manager**; the **External Secrets Operator** syncs them into namespaces via **Workload Identity (keyless)** | GCP Secret Manager (versioned) | **Cloud Audit Logs** + SM versions | |

In `eso` mode the flow becomes (now wired for the gateway IAP secret, the Tekton
pipeline credentials, and `ghcr-credentials`; the rest follows the same pattern —
staged rollout below):

<details>
<summary>📊 ESO sync flow (secrets.backend=eso) — Secret Manager → Workload Identity → k8s Secret</summary>

```mermaid
flowchart LR
    GH["GitHub Actions secret<br/>(IAP_OAUTH_*)"] -->|"01-namespaces.sh<br/>(scripts/lib/secrets.sh)"| SM[("GCP Secret Manager<br/>gateway-iap-oauth (versioned)")]
    SM -->|"Workload Identity (keyless)<br/>GSA eso-secret-reader: secretmanager.secretAccessor"| ESO["External Secrets Operator<br/>ClusterSecretStore gcp-store"]
    ESO -->|"08.6-eso-sync.sh applies<br/>ExternalSecret per ns + waits"| K[("k8s Secret gateway-iap-oauth<br/>→ headlamp / pgadmin / engine ns")]
    K --> P["GCPBackendPolicy (IAP)"]
    classDef sm fill:#eef,stroke:#66c;
    class SM,ESO sm;
```

</details>

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

- **API** — `secretmanager.googleapis.com`, enabled in [`terraform/gke`](../terraform/gke/) alongside
  `container`/`compute` (left on; unused in imperative mode).
- **Write (push) side** — the CI service account that runs [`up.sh`](../scripts/up.sh) needs
  `roles/secretmanager.admin` (the minimal predefined role that includes
  `secrets.create`); granted in [`terraform/bootstrap`](../terraform/bootstrap/)'s `ci_roles`. **Adding it
  to an existing bootstrap requires a one-time human `terraform apply` in
  [`terraform/bootstrap`](../terraform/bootstrap/)** (the CI SA's roles live there, like all the others).
- **Read (sync) side** — the cluster runs **GKE Workload Identity** (`GKE_METADATA`),
  so ESO pods authenticate as the GSA bound to their KSA, **not** the node SA.
  [`terraform/gke`](../terraform/gke/) creates a dedicated least-privilege GSA (`eso-secret-reader`,
  only `roles/secretmanager.secretAccessor`) and a `workloadIdentityUser` binding
  to the controller KSA `external-secrets/external-secrets`; the KSA is annotated
  with that GSA's email via the external-secrets ArgoCD app's helm values
  (templated in [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh)). Because a pod's GCP identity is fixed
  at creation, [`08.6-eso-sync.sh`](../scripts/08.6-eso-sync.sh) also **restarts the ESO controller** so it adopts
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

### Feature-flag convergence — idempotency vs in-place switching

Two distinct properties, often conflated:

- **Idempotency** — re-running `Day1` (or any `0N` step) with the **same** flags is a
  no-op (`helm upgrade --install`, `kubectl apply`, `terraform apply` converge then do
  nothing). This holds **universally**.
- **Convergence on a flag CHANGE** — flipping a flag on a **live** cluster and re-running
  should retire the **old** mode's resources and install the new one, not accumulate
  orphans. The repo implements this with a deliberate **"retire the mode we are switching
  away from"** pattern:

| Flag | In-place switch | How the old mode is retired |
| :--- | :--- | :--- |
| **`ci.engine`** (Jenkins · Tekton · GitHub Actions/ARC · Argo Workflows) | ✅ | each `04-<engine>.sh` calls the shared [`retire_ci_engine`](../scripts/lib/common.sh) helper on the **other three** engines — deleting their ArgoCD apps + all children + namespaces and clearing stuck GKE NEG finalizers (engines are mutually exclusive; the retired engines are cleared symmetrically). |
| **`observability.mode`** oss/grafana-cloud/managed-azure/managed-aws | ✅ | every branch of [`03-observability.sh`](../scripts/03-observability.sh) retires the *other* modes' agents/stacks (e.g. it waits out the OSS node-exporter DaemonSet; [`07-grafana-dashboards.sh`](../scripts/07-grafana-dashboards.sh) publishes only the active engine's CI overview — one of the four `jenkins-overview`/`tekton-overview`/`github-actions-ci`/`argo-workflows-ci` — and deletes the other three). See [902](./902-TROUBLESHOOTING.md). |
| **`secrets.backend`** `imperative`↔`eso` | ✅ | `imperative→eso`: `08.6` installs the `ClusterSecretStore` + `ExternalSecrets`. `eso→imperative`: `08.6` **retires ESO** — RETAINs each target Secret (`deletionPolicy: Retain` + strips the `ownerReference` so the Owner ExternalSecret's GC can't delete it; Merge ones aren't owned), deletes the `ExternalSecrets`, and deletes `gcp-store`. `01-namespaces` already wrote imperative copies, so the Secrets survive and consumers keep working. |

So **all three fundamental flags converge in place** — flip any of them and re-run `Day1`
without a Decom; the cluster retires the old mode rather than leaving orphans. Two
`secrets.backend`-specific subtleties:

- **The first `eso→imperative` flip needs the explicit `secrets_backend=imperative` input.**
  Detection (`j2026_active_secrets_backend`) is **sticky to eso** while `gcp-store` exists —
  by design, so a Day2 redeploy that forgets the input can't silently revert and
  double-provision. The explicit input overrides detection and triggers the retirement; once
  that deletes `gcp-store`, detection resolves to `imperative` on its own thereafter. So
  cycling the flag across many runs (`eso→imperative→eso→…`) **works and is symmetric**.
- **A Jenkins restart is needed only ONCE — the first time the admin password changes**, not
  per cycle. `jenkins-credentials`' `admin-password` is seeded **stable** into Secret Manager
  (`sm_keep_or_generate`) and reused every run (eso reuses the SM value; imperative
  skips-if-exists), so once Jenkins has adopted it (JCasC re-applies `securityRealm` on pod
  start) it stays valid across flips. It only changes on the very first `imperative→eso`
  migration of a cluster whose Jenkins **predates** the seeded password — there, delete the
  `jenkins-0` pod once so JCasC adopts the Secret's value (see [902](./902-TROUBLESHOOTING.md)).
  The Secret Manager secrets are left intact across flips (reused on switch-back; `down.sh`
  removes them on teardown).

### Why the `gateway-iap-oauth` Secret is replicated

This is the one secret that legitimately lives in several namespaces — and it is a
**hard GKE constraint, not a design smell**. A GKE `GCPBackendPolicy` that enables
Identity-Aware Proxy references an OAuth-client `Secret` by name, and that Secret
**must live in the same namespace as the backend `Service`** it protects. There is
no way to point a backend policy at a Secret in another namespace, so the single
OAuth client has to be copied into every IAP-protected backend namespace.

<details>
<summary>📊 Why the gateway-iap-oauth Secret is replicated per backend namespace</summary>

```mermaid
graph TD
    GHS["GitHub secret<br/>IAP_OAUTH_CLIENT_ID/SECRET"] --> NS["01-namespaces.sh<br/>replicate to each IAP backend ns"]
    NS --> H["headlamp/<br/>gateway-iap-oauth"]
    NS --> P["pgadmin/<br/>gateway-iap-oauth"]
    NS --> J["engine ns with an IAP UI/<br/>gateway-iap-oauth<br/>jenkins · tekton-pipelines · argo<br/>(per ci.engine; ARC has NO UI → no copy)"]
    H --> HP["GCPBackendPolicy → Headlamp Service"]
    P --> PP["GCPBackendPolicy → pgAdmin Service"]
    J --> JP["GCPBackendPolicy → Jenkins / Tekton Dashboard / Argo Server"]
    H -. "ArgoCD (no IAP, uses OIDC) reads<br/>the client from headlamp" .-> ACD["argocd/ ArgoCD server"]
```

</details>

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
| The **GKE Gateway** lived in `jenkins` → deleting the ns (or running any non-Jenkins engine) killed all public access | Gateway moved to the engine-neutral **`platform-ingress`** namespace |
| [`08.5-argocd.sh`](../scripts/08.5-argocd.sh) read the **IAP client** from `jenkins` for ArgoCD's OIDC → empty in any non-jenkins mode | now reads `gateway-iap-oauth` from **`headlamp`** (always present) |
| [`03-observability.sh`](../scripts/03-observability.sh) read `jenkins-credentials` for a **Grafana→Jenkins datasource** | gated to `ci.engine=jenkins` (pointless without Jenkins) |
| [`07.5-grafana-alerts.sh`](../scripts/07.5-grafana-alerts.sh) read `jenkins-credentials.oidc-admin-email` as an alert-email fallback | already guarded (`|| true`); yields empty harmlessly in any non-jenkins mode |
| NetworkPolicies / ResourceQuota / LimitRange / RBAC **targeting the `jenkins` ns** applied unconditionally | all gated to `ci.engine=jenkins` (the jenkins-ns NetworkPolicies live in [`infrastructure/networkpolicies-jenkins.yaml`](../infrastructure/networkpolicies-jenkins.yaml)) |

The end state matches the design principles above: **secrets per-app**, the IAP
client replicated only because GKE requires it, the public ingress engine-neutral,
and nothing reaching into `jenkins-credentials` except Jenkins itself.

## GKE Cluster Topology & Sizing

The throwaway cluster is provisioned via [`terraform/gke/`](../terraform/gke/) with a custom **VPC-native** configuration optimized for **stability and cost**. A **persistent** global static IP and Google-managed wildcard TLS certificate ([`terraform/gateway-bootstrap/`](../terraform/gateway-bootstrap/)) survive cluster rebuilds so DNS records never need updating.

**Network dataplane**: the cluster runs **GKE Dataplane V2** (Cilium/eBPF, `datapath_provider = ADVANCED_DATAPATH`) so Kubernetes `NetworkPolicy` is actually enforced, with **WireGuard inter-node pod encryption** (`in_transit_encryption_config`) on top — sidecar-free, no service mesh. Both are immutable fields (changing them recreates the cluster). See [`docs/501` § Zero-Trust Security](501-PLATFORM_OPERATIONS.md) for the NetworkPolicy model and the encryption scope/caveats, and **[`docs/503` Networking](503-NETWORKING.md)** for the full network architecture — the landing zone (single-VPC, *not* hub-spoke), VPC/subnet + pod/service **CIDR plan**, north-south ingress/egress, east-west, and the segmentation model end to end.

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

    subgraph Cluster ["GKE Cluster (release channel: REGULAR)"]
        GatewayAPI["GKE Gateway API<br/>gke-l7-global-external-managed"]
        BackendTLS["BackendTLSPolicy<br/>Secure TLS to pods"]
        WI["Workload Identity Federation"]
    end

    subgraph StaticPool ["Static node pool: jenkins-2026-pool (e2-standard-8, min2/max4)"]
        StaticInfo["Long-lived platform<br/>ArgoCD/Jenkins/observability/CNPG<br/>+ CI build pods by DEFAULT (runNodePool=static)"]
    end

    subgraph NAPSpotPool ["NAP Spot pools (ComputeClass ci-spot)"]
        PoolInfo["Auto-created Spot nodes<br/>c3/n2/c2/e2 · scale-to-zero<br/>CI build pods only when runNodePool=ci-spot (opt-in)"]
    end

    User -->|"resolve host"| ParentNS
    WildcardA -.->|"resolves to"| StaticIP
    User -->|"HTTPS"| StaticIP
    StaticIP --> CertMap
    CertMap --> WildcardTLS
    WildcardTLS -->|"terminates TLS"| GatewayAPI
    GatewayAPI -->|"routes via BackendTLSPolicy"| BackendTLS
    BackendTLS -->|"zero-trust HTTPS"| StaticPool
    BackendTLS -->|"zero-trust HTTPS"| NAPSpotPool
```

</details>

| Layer | Resource | Details |
|---|---|---|
| **Static IP** | `jenkins-2026-gateway-ip` | Global persistent `google_compute_global_address`. Survives cluster rebuilds. |
| **TLS Certificate** | `jenkins-2026-cert` | Google-managed wildcard cert for `jenkins2026.nubenetes.com` + `*.jenkins2026.nubenetes.com`. |
| **GKE Cluster** | `jenkins-2026` | Zonal cluster in `europe-southwest1-a`. VPC-native, Gateway API addon `CHANNEL_STANDARD` (cluster release channel `REGULAR`), Workload Identity enabled. |
| **Static node pool** | `jenkins-2026-pool` | `e2-standard-8`, min 2 / max 4. Hosts the long-lived platform (ArgoCD/Jenkins/observability/CNPG) **and the CI build pods by default** (`jenkins` / `tekton` / `argoworkflows` default `runNodePool: static` — robust, no NAP/Spot/quota dependency; `githubactions` defaults `ci-spot`). |
| **NAP Spot pools** | ComputeClass `ci-spot` | GKE Node Auto-Provisioning auto-creates Spot pools (`c3`, `n2`, `c2`, `e2` families), scale-to-zero. Used for CI build pods **only when an engine opts in** with `runNodePool: ci-spot` (single-pod engines — Jenkins, GitHub Actions/ARC — are the good Spot fits, and ARC ships `ci-spot` by default; shared-workspace engines — Tekton, Argo Workflows — stay `static` — see [docs/501](501-PLATFORM_OPERATIONS.md#the-engines-on-spot-ci-spot--why-the-placement-flag-is-per-engine)). |
| **Node SA** | `jenkins-2026-nodes` | Minimal-privilege: `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/artifactregistry.reader`. |
| **CI Agent SA** | `jenkins-2026-ci-agent` | GitHub Actions OIDC WIF — no static JSON keys. |

### Sizing Rationale

Running Jenkins, ArgoCD, pgAdmin, two Postgres HA clusters (CNPG), OpenTelemetry operators, and the JHipster microservices stack requires significant resources. **`e2-standard-8` with 3 nodes** ensures a stable environment with enough headroom to spawn dynamic Jenkins build agent pods. Smaller nodes (`e2-standard-2`) would cause **OOM kills, CPU starvation, and pending pods**.

### FinOps & Cost Analysis

- **Cluster Management Fee**: `$0.10/hour` (waived for first zonal cluster per billing account).
- **Compute**: ~`$0.22/hour` per `e2-standard-8` in Madrid (`europe-southwest1`).
- **Total run rate**: ~`$0.70–$0.80/hour` for the active 3-node cluster.
- **Per-session cost**: ~`$0.10–$0.20` for a full 15–25 minute provision + smoke test + teardown cycle.
- **Disk floor (paused)**: with `Day2.scale.01 Pause` (nodes → 0) compute stops but the **~102 GB of persistent PVs** (CNPG databases + platform) remain — ≈`$13/month` of `pd-balanced`/`pd-ssd` (+ the static IP ~`$7`). `Decom` drops this to ~`$0`.
- **The `SSD_TOTAL_GB` quota is the binding capacity ceiling** (500 GB; every node boot disk + PV counts) and the limit on `ci-spot` Spot CI concurrency. For the full **disk-quota computation diagram, per-state usage %, cost breakdown, and the Google increase request (500 → 2000)** see [docs/501 § The `SSD_TOTAL_GB` quota](./501-PLATFORM_OPERATIONS.md#the-ssd_total_gb-quota--how-its-computed-what-it-costs-and-the-increase-request).
- **Always decommission**: Run `Decom.cluster.01 GKE decommission` when finished — never leave the cluster running overnight.

---

[← Previous: 104. Rebuild-Safety](./104-REBUILD_SAFETY.md) | [🏠 Home](../README.md) | [→ Next: 202. Microservices App Architecture](./202-MICROSERVICES-APP-ARCHITECTURE.md)

---

*201. Architecture — jenkins-2026*
