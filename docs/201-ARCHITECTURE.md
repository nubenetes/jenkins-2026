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
- **CloudNative-PG (CNPG)**: HA PostgreSQL 18 clusters (1 Primary + 2 Replicas) provisioned via CNPG CRDs, with PgBouncer connection pooling.

> **Two-repo GitOps setup.** This is the **infra repo** (cluster bootstrap, Jenkins, ArgoCD, observability). Image tags and ArgoCD manifests live in the companion **[`nubenetes/jenkins-2026-gitops-config`](https://github.com/nubenetes/jenkins-2026-gitops-config)** repo.

## System Architecture

<details>
<summary>🔍 Click to expand System Architecture Diagram</summary>

```mermaid
graph TB
    subgraph "External Services"
        GH["GitHub"]
        GC["Grafana Cloud"]
        GCP["GCP IAP /<br/>DNS / OAuth"]
    end

    subgraph "GKE Cluster"
        subgraph "ingress-nginx / Gateway API"
            GW["GKE Gateway"]
        end

        subgraph "jenkins namespace"
            J["Jenkins Controller"]
            JC["JCasC / Jobs"]
        end

        subgraph "argocd namespace"
            ACD["ArgoCD Server"]
            DEX["ArgoCD Dex /<br/>OIDC"]
        end

        subgraph "observability namespace"
            OTEL["OTel Operator/<br/>Collector"]
            K8S["k8s-monitoring<br/>(Grafana Alloy)"]
        end

        subgraph "microservices namespace"
            PCS["Microservices<br/>Services"]
        end

        subgraph "GKE Cluster Infrastructure"
            NODES["Nodes & Kubelet"]
            EVENTS["Kubernetes Events"]
        end
    end

    GH -->|SCM| J
    GH -->|SCM| ACD
    GCP -->|"IAP / OAuth"| GW
    GW --> J
    GW --> ACD
    GW --> PCS
    J -->|"CI / Build"| GH
    ACD -->|"CD / GitOps"| PCS
    PCS -->|OTLP| OTEL
    J -->|OTLP| OTEL
    OTEL -->|OTLP/HTTP| GC

    NODES -->|Scraped by| K8S
    EVENTS -->|Collected by| K8S
    K8S -->|OTLP/HTTP| GC
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

## Configuration (`config/config.yaml`)

Single source of truth, loaded by every script via [`scripts/lib/config.sh`](../scripts/lib/config.sh) (`yq` → `J2026_*` env vars). Feature flags:

| Key | Default | Override | Meaning |
|---|---|---|---|
| `observability.mode` | `grafana-cloud` | edit `config.yaml` | `grafana-cloud`\|`oss`\|`managed-azure`\|`managed-aws` — where traces/metrics/logs go |
| `microservices.developTrackEnabled` | `false` | `JENKINS2026_DEVELOP_TRACK_ENABLED` | Optional second microservices tier (`microservices-develop` namespace, GitOps `develop` branch) |

Other notable sections: `jenkins.*` (chart coordinates, namespace, this repo's own URL/branch), `observability.*` (operator/collector chart coordinates, release names, Secret name), `microservices.*` (namespaces, git org/repos/branches, target registry, list of 2 services seeded into Jenkins).

## Repository Layout

```
config/config.yaml          single source of truth (feature flags above)
helm/jenkins/                jenkinsci/helm-charts values + values-gke.yaml overlay
helm/microservices/          local chart for the Microservices workloads (2 envs)
helm/headlamp/               kubernetes-sigs/headlamp values (cluster management UI)
jenkins/casc/                JCasC: security, OTel exporter, seed job
jenkins/pipelines/           Jenkinsfile.microservices + seed job (Job DSL + services.yaml)
vars/, resources/            Jenkins global shared library (must be at repo root)
observability/               OTel Operator/Collector + Grafana/Loki/Tempo/Prometheus values + dashboards
scripts/                     00-09 numbered steps + up.sh / down.sh / status.sh
terraform/gke/               throwaway GKE cluster for test/e2e.sh
terraform/bootstrap/         one-time setup for GitHub Actions automation (state bucket + WIF)
terraform/gateway-bootstrap/ one-time setup for public access (static IP + managed certificate)
scripts/08.5-argocd.sh       ArgoCD installation and OIDC configuration
test/                        e2e.sh (provision → up.sh → smoke-test.sh → down.sh → destroy)
.github/workflows/           Y.X.ZZ-<name>.yml — see 101. GitHub Actions Workflows
docs/                        numbered docs (this file and siblings)
```

## GKE Cluster Topology & Sizing

The throwaway cluster is provisioned via `terraform/gke/` with a custom VPC-native configuration optimized for stability and cost. A **persistent** global static IP and Google-managed wildcard TLS certificate (`terraform/gateway-bootstrap/`) survive cluster rebuilds so DNS records never need updating.

<details>
<summary>🔍 Click to expand GKE Cluster Topology Diagram</summary>

```mermaid
graph TD
    subgraph Internet ["Internet"]
        User["User / Browser"]
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
        GatewayAPI["GKE Gateway API<br/>gke-l7-gxlb"]
        BackendTLS["BackendTLSPolicy<br/>Secure TLS to pods"]
        WI["Workload Identity Federation"]
    end

    subgraph KarpenterPool ["Karpenter NodePool: ephemeral-runners"]
        PoolInfo["Spot Instances<br/>e2/n2/c2/c3 dynamic scaling"]
    end

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
| **GKE Cluster** | `jenkins-2026` | Zonal cluster in `europe-southwest1-a`. VPC-native, Gateway API `CHANNEL_STANDARD`, Workload Identity enabled. |
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
