# Complete Technical Inventory of English Infographics (35 Files)

This document serves as an architectural inventory and catalog of the 35 English infographics. Each filename in the table is a clickable link to open the corresponding PNG file directly. Below the table, you will find collapsible visual previews for each infographic.

---

## Infographics Matrix Catalog

| Code | Chapter / Category | Infographic File (Clickable Link) | Key Technologies & Components | Detailed Architectural Description (English) |
| :--- | :--- | :--- | :--- | :--- |
| **001** | `000: Platform Overview` | [001_End_to_End_Golden_Path_Platform_and_Developer_Workflow_Overview.png](001_End_to_End_Golden_Path_Platform_and_Developer_Workflow_Overview.png) | IDP, Day 0/Day 1, Dev Workflow | High-level overview of the end-to-end developer journey within the Internal Developer Platform (IDP). Details the separation between Day 0 (core infrastructure bootstrap) and Day 1 (application deployment) workflows. |
| **002** | `000: Platform Overview` | [002_High_Level_Design_and_Multi_Repository_Platform_Architecture.png](002_High_Level_Design_and_Multi_Repository_Platform_Architecture.png) | Git Multi-Repo, Terraform, Jenkins | Illustrates the multi-repository structure decoupling the platform infrastructure configuration (in the Jenkins-2026 repository) from individual application source code repositories, using remote GCS buckets for state storage. |
| **101** | `100: Landing Zone` | [101_GCP_Keyless_Landing_Zone_and_WIF_Federation.png](101_GCP_Keyless_Landing_Zone_and_WIF_Federation.png) | GCP, GitHub Actions, OIDC, WIF | Documents the keyless authentication workflow using Google Workload Identity Federation (WIF). Replaces persistent JSON service account keys with short-lived OAuth2 access tokens exchanged via GitHub OIDC. |
| **102** | `100: Landing Zone` | [102_GKE_Golden_Path_JHipster_Microservice_Architecture.png](102_GKE_Golden_Path_JHipster_Microservice_Architecture.png) | GKE, JHipster, Dataplane V2, eBPF | Maps the internal microservice design deployed within the GKE Golden-Path. Focuses on default-deny network postures enforced by GKE Dataplane V2 and inter-service container communication. |
| **103** | `100: Landing Zone` | [103_Argo_Workflows_and_Argo_Events_on_GKE.png](103_Argo_Workflows_and_Argo_Events_on_GKE.png) | Argo Events, Argo Workflows, GKE | Represents the event-driven CI/CD control plane on GKE. Details the Argo Events webhook listener architecture, GKE Gateway API ingress routing, and the 10-stage execution pipeline contract. |
| **104** | `100: Landing Zone` | [104_GKE_Zero_Trust_Ingress_North_South_Traffic_Lifecycle_with_BackendTLS.png](104_GKE_Zero_Trust_Ingress_North_South_Traffic_Lifecycle_with_BackendTLS.png) | BackendTLSPolicy, Gateway API, Google IAP | Traces the zero-trust lifecycle of North-South ingress traffic. Details SSL termination at the global L7 Load Balancer, Google IAP context-aware authorization, HTTPRoute definition, BackendTLSPolicy enforcement, and direct NEG routing to pods with 100% continuous transit encryption. |
| **105** | `100: Landing Zone` | [105_GKE_Golden_Path_High_Availability_PostgreSQL_with_CloudNativePG.png](105_GKE_Golden_Path_High_Availability_PostgreSQL_with_CloudNativePG.png) | PostgreSQL, CloudNativePG, PgBouncer | Illustrates the database clustering setup using CloudNativePG on GKE. Explains high-availability replication across multiple zones, read/write splitting, and pgBouncer pooled connection proxying. |
| **201** | `200: Node Provisioning` | [201_GKE_Cluster_Topology_and_Karpenter_Native_Node_Auto_Provisioning.png](201_GKE_Cluster_Topology_and_Karpenter_Native_Node_Auto_Provisioning.png) | GKE NAP, Karpenter-native, quotas | Details GKE node auto-provisioning (NAP) behaving similarly to Karpenter. Explains quota ceilings, hard technical limits for SSD/disks, and the lifecycle of pending pods triggering dynamic node spin-up. |
| **202** | `200: Node Provisioning` | [202_GitHub_Actions_on_GKE_ARC_and_Spot_Runners.png](202_GitHub_Actions_on_GKE_ARC_and_Spot_Runners.png) | GitHub ARC, Spot Instances, WIF | Analyzes GitHub Actions Runner Controller (ARC) deployments on GKE. Shows how ephemeral runners are scheduled dynamically on cost-effective GCP Spot VMs, with WIF providing secure identity mappings. |
| **203** | `200: Node Provisioning` | [203_Jenkins_2026_GitHub_Actions_Workflow_Catalog_Map.png](203_Jenkins_2026_GitHub_Actions_Workflow_Catalog_Map.png) | GitHub Actions, Git Workflows, GKE | Provides a comprehensive directory of the 29 GitHub Actions workflows managing the GKE Golden-Path platform, detailing naming patterns, push/PR triggers, and operational dependencies. |
| **301** | `300: Dataplane Security` | [301_GKE_Dataplane_V2_eBPF_Zero_Trust_Isolation_Matrix.png](301_GKE_Dataplane_V2_eBPF_Zero_Trust_Isolation_Matrix.png) | Dataplane V2, eBPF, NetworkPolicies | Maps the default-deny matrix for the microservices namespace. Explains how Cilium/eBPF enforces network isolation at the kernel level, blocking all non-whitelisted cross-pod interactions. |
| **302** | `300: Dataplane Security` | [302_GKE_Dataplane_V2_Zero_Trust_Networking_Architecture.png](302_GKE_Dataplane_V2_Zero_Trust_Networking_Architecture.png) | Linux Kernel, Cilium, BPF filters | Explains the low-level network packet flow inside the Linux Kernel using eBPF JIT-compiled programs, TC (Traffic Control) network hooks, and secure socket redirections bypass. |
| **303** | `300: Dataplane Security` | [303_JHipster_Gateway_Architecture_and_Observability_Map.png](303_JHipster_Gateway_Architecture_and_Observability_Map.png) | JHipster Gateway, Webpack, Faro | Details the Gateway layer of the application, contrasting dev (Webpack reload) vs prod profiles, route proxying to downstream microservices, and OpenTelemetry instrumentation hooks. |
| **304** | `300: Dataplane Security` | [304_GKE_Golden_Path_IDP_Runtime_Traffic_and_Data_Integration.png](304_GKE_Golden_Path_IDP_Runtime_Traffic_and_Data_Integration.png) | Ingress Routing, Egress Policies, IDP | Represents an expert guide for handling data integration and security. Covers ingress-to-pod mappings, egress whitelist policies, and OTel collector ingestion paths for tracing. |
| **305** | `300: Dataplane Security` | [305_GKE_Platform_Networking_Blueprint_Zero_Trust_North_South_Ingress.png](305_GKE_Platform_Networking_Blueprint_Zero_Trust_North_South_Ingress.png) | GKE Gateway API, Google IAP, BackendTLSPolicy, NEGs | Outlines the zero-trust landing zone network blueprint for GKE North-South ingress. Focuses on edge TLS termination, Google IAP user authorization, and secondary handshakes to container-native NEGs with certificates from GKE-managed CAs. |
| **401** | `400: Secrets & DevSecOps` | [401_Zero_Trust_Keyless_Secrets_Lifecycle_via_ESO_and_WIF.png](401_Zero_Trust_Keyless_Secrets_Lifecycle_via_ESO_and_WIF.png) | Secret Manager, ESO, GKE Secrets | Outlines the keyless replication of secrets from Google Secret Manager to Kubernetes Secrets using the External Secrets Operator (ESO) and GCP Workload Identity. |
| **402** | `400: Secrets & DevSecOps` | [402_DevSecOps_Multilayer_Scanning_and_SARIF_Flow.png](402_DevSecOps_Multilayer_Scanning_and_SARIF_Flow.png) | Semgrep, CodeQL, Trivy, SARIF | Displays the pluggable 4-layer security scanning pipeline (lightweight SAST, deep SAST, dependency check, and container scan) consolidating vulnerabilities into standard SARIF files. |
| **501** | `500: CI Engines` | [501_Jenkins_2026_Automated_CI_Engine_Architecture.png](501_Jenkins_2026_Automated_CI_Engine_Architecture.png) | Jenkins, JCasC, Helm, GKE Agents | Details the fully GitOps-managed Jenkins engine. Features declarative Configuration-as-Code (JCasC), Helm-managed state, and dynamic on-demand agent scaling on GKE. |
| **502** | `500: CI Engines` | [502_Tekton_CI_Engine_Architecture_with_Pipelines_as_Code_and_SLSA.png](502_Tekton_CI_Engine_Architecture_with_Pipelines_as_Code_and_SLSA.png) | Tekton, SLSA, Pipelines-as-Code | Showcases the cloud-native Tekton CI model. Describes event-based triggers, Git pipelines-as-code controllers, and SLSA provenance attestation generators for builds. |
| **601** | `600: Deployment & GitOps` | [601_Two_Repo_GitOps_State_Machine_with_ArgoCD_and_CI_Workflow.png](601_Two_Repo_GitOps_State_Machine_with_ArgoCD_and_CI_Workflow.png) | GitOps, ArgoCD Sync, Multi-Engine CI | Maps the two-repo GitOps decoupling. Explains how CI processes push container tags to the app repository, and how ArgoCD reconciles the cluster to match the Git state. |
| **602** | `600: Deployment & GitOps` | [602_Terraform_IaC_Idempotency_and_Day_1_State_Flow.png](602_Terraform_IaC_Idempotency_and_Day_1_State_Flow.png) | Terraform, State Locking, GCS | Traces the execution flow of Terraform infrastructure code. Illustrates safe state locking in GCP GCS buckets and the transition from Day 0 setup to Day 1 updates. |
| **603** | `600: Deployment & GitOps` | [603_Sidecar_Free_Progressive_Delivery_with_Argo_Rollouts_and_GKE_Gateway_API.png](603_Sidecar_Free_Progressive_Delivery_with_Argo_Rollouts_and_GKE_Gateway_API.png) | Argo Rollouts, GKE Gateway, Canary | Illustrates a progressive delivery architecture. Argo Rollouts manages canary traffic splitting directly through GKE Gateway routing, bypassing the need for sidecar-heavy service meshes like Istio. |
| **604** | `600: Deployment & GitOps` | [604_Sidecar_Free_Zero_Trust_BackendTLS_and_GitOps_Workflow.png](604_Sidecar_Free_Zero_Trust_BackendTLS_and_GitOps_Workflow.png) | ArgoCD, GKE Gateway, BackendTLSPolicy, GKE CA | Maps the GitOps reconciliation flow of zero-trust components in GKE. Details how ArgoCD syncs Gateway and BackendTLSPolicy manifests, terminating TLS at target microservices by validating pod certificates against GKE-managed CAs. |
| **701** | `700: Tool Comparisons` | [701_Advanced_CI_Architecture_Jenkins_vs_Tekton_on_GKE.png](701_Advanced_CI_Architecture_Jenkins_vs_Tekton_on_GKE.png) | Jenkins, Tekton, GKE scheduler | Compares structural architecture of Jenkins vs Tekton. Focuses on persistent master controllers vs serverless CRD-driven pods, and the impact on resource scheduling. |
| **702** | `700: Tool Comparisons` | [702_Spot_Instance_Resiliency_Jenkins_vs_GitHub_Actions_ARC.png](702_Spot_Instance_Resiliency_Jenkins_vs_GitHub_Actions_ARC.png) | Spot Nodes, Evictions, ARC, Jenkins | Benchmarks Spot instance node evictions. Compares Jenkins master-agent connection drops with GitHub Actions ARC runner rescheduling and recovery metrics. |
| **703** | `700: Tool Comparisons` | [703_CI_Battle_Jenkins_Groovy_vs_Argo_Workflows_DAG_and_UI_Strategy.png](703_CI_Battle_Jenkins_Groovy_vs_Argo_Workflows_DAG_and_UI_Strategy.png) | Groovy script, YAML DAG, Jenkins, Argo | Compares the imperative scripting style of Jenkins Groovy pipelines against the declarative YAML DAG model of Argo Workflows on GKE. Details the Jenkins UI strategy, explicitly replacing deprecated Blue Ocean with Classic UI and warnings-ng. |
| **704** | `700: Tool Comparisons` | [704_CI_Grand_Master_Battlecard_4_Way_GKE_Matrix.png](704_CI_Grand_Master_Battlecard_4_Way_GKE_Matrix.png) | CI Matrix, Jenkins, Tekton, Argo, GHA | Provides a 4-way architectural comparison battlecard evaluating the performance, scaling latency, and storage overhead of Jenkins, Tekton, Argo, and GHA. |
| **705** | `700: Tool Comparisons` | [705_Jenkins_Dominance_Pluggable_CI_4_Way_Matrix_and_Classic_UI_Transition.png](705_Jenkins_Dominance_Pluggable_CI_4_Way_Matrix_and_Classic_UI_Transition.png) | Jenkins, CI Matrix, GKE | Features the Pluggable CI 4-Way comprehensive matrix, detailing resource footprint and scheduling, and noting the deprecation/replacement of Blue Ocean with Classic UI + warnings-ng. |
| **706** | `700: Tool Comparisons` | [706_Why_Jenkins_Wins_Battlecard_and_UI_Security_Strategy.png](706_Why_Jenkins_Wins_Battlecard_and_UI_Security_Strategy.png) | Jenkins, DevSecOps, Pluggable CI | Explains the technical benefits of Jenkins in a pluggable CI platform, detailing usability, native security integrations, and the UI security strategy mitigating deprecated Blue Ocean CVE risks. |
| **801** | `800: Observability` | [801_Grafana_OSS_Self_Hosted_OTel_Signal_Flow.png](801_Grafana_OSS_Self_Hosted_OTel_Signal_Flow.png) | Grafana OSS, OTel Collector, Faro | Illustrates the self-hosted observability signal flow. Shows how Java/JVM apps send logs, metrics, and traces to OpenTelemetry collectors, which correlate data for Grafana. |
| **802** | `800: Observability` | [802_Optimized_OTel_Data_Flow_and_Grafana_Cloud_Free_Tier.png](802_Optimized_OTel_Data_Flow_and_Grafana_Cloud_Free_Tier.png) | OTel Gateway, Grafana Cloud, Free Tier | Guides developers on configuring custom metric filtering, span dropping, and lean telemetry rules in the OTel Gateway to fit within Grafana Cloud free tier quotas. |
| **803** | `800: Observability` | [803_JVM_Tuning_and_Hotspot_Runtime_Strategy.png](803_JVM_Tuning_and_Hotspot_Runtime_Strategy.png) | JVM Tuning, Hotspot GC, Limits | Resolves the "container-default trap" (where JVM limits default to 25% heap). Optimizes memory allocations and Garbage Collector flags (G1GC) for Docker containers. |
| **804** | `800: Observability` | [804_End_to_End_Frontend_Observability_RUM_with_Grafana_Faro_and_OTel.png](804_End_to_End_Frontend_Observability_RUM_with_Grafana_Faro_and_OTel.png) | Grafana Faro, RUM, Trace Propagation | Traces client-side Real User Monitoring (RUM) beacon propagation. Demonstrates traceparent header injection from the browser into backend APIs using OpenTelemetry. |
| **901** | `900: Load & Lifecycle` | [901_k6_Traffic_Simulation_Unified_Workload_Profiles.png](901_k6_Traffic_Simulation_Unified_Workload_Profiles.png) | k6, Traffic Simulation, Load Tests | Explains the k6 workload profile setup, including environment variable injection (`k6sim_*`) and automated load test scenarios mimicking user concurrency peaks. |
| **902** | `900: Load & Lifecycle` | [902_GKE_Golden_Path_IDP_Platform_Lifecycle_and_Rebuild_Safety_Matrix.png](902_GKE_Golden_Path_IDP_Platform_Lifecycle_and_Rebuild_Safety_Matrix.png) | Platform Lifecycle, Backups, Recovery | Outlines the platform rebuild-safety matrix, defining backup strategies, disaster recovery runbooks, and recovery point objectives (RPO) for cluster states. |

---

## 🖼️ Visual Previews Catalog

Browse the infographics visually using the collapsible previews below. Click any preview header to reveal the full high-resolution diagram.

<details>
<summary>⚡ Click here to expand ALL 35 Infographics at once (for sequential scrolling) ⚡</summary>
<br>

### 001 - End to End Golden Path Platform and Developer Workflow Overview
![001 - Platform Overview](./001_End_to_End_Golden_Path_Platform_and_Developer_Workflow_Overview.png)

---

### 002 - High Level Design and Multi Repository Platform Architecture
![002 - High Level Design](./002_High_Level_Design_and_Multi_Repository_Platform_Architecture.png)

---

### 101 - GCP Keyless Landing Zone and WIF Federation
![101 - WIF Federation](./101_GCP_Keyless_Landing_Zone_and_WIF_Federation.png)

---

### 102 - GKE Golden Path JHipster Microservice Architecture
![102 - JHipster Microservice](./102_GKE_Golden_Path_JHipster_Microservice_Architecture.png)

---

### 103 - Argo Workflows and Argo Events on GKE
![103 - Argo Workflows](./103_Argo_Workflows_and_Argo_Events_on_GKE.png)

---

### 104 - GKE Zero Trust Ingress North South Traffic Lifecycle with BackendTLS
![104 - BackendTLS North-South](./104_GKE_Zero_Trust_Ingress_North_South_Traffic_Lifecycle_with_BackendTLS.png)

---

### 105 - GKE Golden Path High Availability PostgreSQL with CloudNativePG
![105 - CloudNativePG](./105_GKE_Golden_Path_High_Availability_PostgreSQL_with_CloudNativePG.png)

---

### 201 - GKE Cluster Topology and Karpenter Native Node Auto Provisioning
![201 - Node Auto Provisioning](./201_GKE_Cluster_Topology_and_Karpenter_Native_Node_Auto_Provisioning.png)

---

### 202 - GitHub Actions on GKE ARC and Spot Runners
![202 - GitHub ARC](./202_GitHub_Actions_on_GKE_ARC_and_Spot_Runners.png)

---

### 203 - Jenkins 2026 GitHub Actions Workflow Catalog Map
![203 - GHA Catalog Map](./203_Jenkins_2026_GitHub_Actions_Workflow_Catalog_Map.png)

---

### 301 - GKE Dataplane V2 eBPF Zero Trust Isolation Matrix
![301 - eBPF Isolation](./301_GKE_Dataplane_V2_eBPF_Zero_Trust_Isolation_Matrix.png)

---

### 302 - GKE Dataplane V2 Zero Trust Networking Architecture
![302 - eBPF Networking](./302_GKE_Dataplane_V2_Zero_Trust_Networking_Architecture.png)

---

### 303 - JHipster Gateway Architecture and Observability Map
![303 - Gateway Observability](./303_JHipster_Gateway_Architecture_and_Observability_Map.png)

---

### 304 - GKE Golden Path IDP Runtime Traffic and Data Integration
![304 - Traffic Data Integration](./304_GKE_Golden_Path_IDP_Runtime_Traffic_and_Data_Integration.png)

---

### 305 - GKE Platform Networking Blueprint Zero Trust North South Ingress
![305 - Networking Blueprint](./305_GKE_Platform_Networking_Blueprint_Zero_Trust_North_South_Ingress.png)

---

### 401 - Zero Trust Keyless Secrets Lifecycle via ESO and WIF
![401 - Secret Lifecycle](./401_Zero_Trust_Keyless_Secrets_Lifecycle_via_ESO_and_WIF.png)

---

### 402 - DevSecOps Multilayer Scanning and SARIF Flow
![402 - DevSecOps Scanning](./402_DevSecOps_Multilayer_Scanning_and_SARIF_Flow.png)

---

### 501 - Jenkins 2026 Automated CI Engine Architecture
![501 - Jenkins CI](./501_Jenkins_2026_Automated_CI_Engine_Architecture.png)

---

### 502 - Tekton CI Engine Architecture with Pipelines as Code and SLSA
![502 - Tekton CI](./502_Tekton_CI_Engine_Architecture_with_Pipelines_as_Code_and_SLSA.png)

---

### 601 - Two Repo GitOps State Machine with ArgoCD and CI Workflow
![601 - GitOps State Machine](./601_Two_Repo_GitOps_State_Machine_with_ArgoCD_and_CI_Workflow.png)

---

### 602 - Terraform IaC Idempotency and Day 1 State Flow
![602 - Terraform state flow](./602_Terraform_IaC_Idempotency_and_Day_1_State_Flow.png)

---

### 603 - Sidecar Free Progressive Delivery with Argo Rollouts and GKE Gateway API
![603 - Progressive Delivery](./603_Sidecar_Free_Progressive_Delivery_with_Argo_Rollouts_and_GKE_Gateway_API.png)

---

### 604 - Sidecar Free Zero Trust BackendTLS and GitOps Workflow
![604 - BackendTLS GitOps](./604_Sidecar_Free_Zero_Trust_BackendTLS_and_GitOps_Workflow.png)

---

### 701 - Advanced CI Architecture Jenkins vs Tekton on GKE
![701 - Jenkins vs Tekton](./701_Advanced_CI_Architecture_Jenkins_vs_Tekton_on_GKE.png)

---

### 702 - Spot Instance Resiliency Jenkins vs GitHub Actions ARC
![702 - Spot Resiliency](./702_Spot_Instance_Resiliency_Jenkins_vs_GitHub_Actions_ARC.png)

---

### 703 - CI Battle Jenkins Groovy vs Argo Workflows DAG and UI Strategy
![703 - CI Battle UI](./703_CI_Battle_Jenkins_Groovy_vs_Argo_Workflows_DAG_and_UI_Strategy.png)

---

### 704 - CI Grand Master Battlecard 4 Way GKE Matrix
![704 - 4-Way CI Matrix](./704_CI_Grand_Master_Battlecard_4_Way_GKE_Matrix.png)

---

### 705 - Jenkins Dominance Pluggable CI 4 Way Matrix and Classic UI Transition
![705 - Pluggable CI Matrix](./705_Jenkins_Dominance_Pluggable_CI_4_Way_Matrix_and_Classic_UI_Transition.png)

---

### 706 - Why Jenkins Wins Battlecard and UI Security Strategy
![706 - Why Jenkins Wins](./706_Why_Jenkins_Wins_Battlecard_and_UI_Security_Strategy.png)

---

### 801 - Grafana OSS Self Hosted OTel Signal Flow
![801 - Grafana OSS OTel](./801_Grafana_OSS_Self_Hosted_OTel_Signal_Flow.png)

---

### 802 - Optimized OTel Data Flow and Grafana Cloud Free Tier
![802 - OTel Grafana Cloud](./802_Optimized_OTel_Data_Flow_and_Grafana_Cloud_Free_Tier.png)

---

### 803 - JVM Tuning and Hotspot Runtime Strategy
![803 - JVM Tuning GC](./803_JVM_Tuning_and_Hotspot_Runtime_Strategy.png)

---

### 804 - End to End Frontend Observability RUM with Grafana Faro and OTel
![804 - Faro RUM](./804_End_to_End_Frontend_Observability_RUM_with_Grafana_Faro_and_OTel.png)

---

### 901 - k6 Traffic Simulation Unified Workload Profiles
![901 - k6 Simulation](./901_k6_Traffic_Simulation_Unified_Workload_Profiles.png)

---

### 902 - GKE Golden Path IDP Platform Lifecycle and Rebuild Safety Matrix
![902 - Rebuild Safety](./902_GKE_Golden_Path_IDP_Platform_Lifecycle_and_Rebuild_Safety_Matrix.png)
</details>



### 001 - End to End Golden Path Platform and Developer Workflow Overview
* **Category**: `000: Platform Overview`
* **Key Technologies & Components**: IDP, Day 0/Day 1, Dev Workflow
* **Description**: High-level overview of the end-to-end developer journey within the Internal Developer Platform (IDP). Details the separation between Day 0 (core infrastructure bootstrap) and Day 1 (application deployment) workflows.

<details>
<summary>🔍 Expand infographic preview (001)</summary>

![001 - Platform Overview](./001_End_to_End_Golden_Path_Platform_and_Developer_Workflow_Overview.png)

</details>

---

### 002 - High Level Design and Multi Repository Platform Architecture
* **Category**: `000: Platform Overview`
* **Key Technologies & Components**: Git Multi-Repo, Terraform, Jenkins
* **Description**: Illustrates the multi-repository structure decoupling the platform infrastructure configuration (in the Jenkins-2026 repository) from individual application source code repositories, using remote GCS buckets for state storage.

<details>
<summary>🔍 Expand infographic preview (002)</summary>

![002 - High Level Design](./002_High_Level_Design_and_Multi_Repository_Platform_Architecture.png)

</details>

---

### 101 - GCP Keyless Landing Zone and WIF Federation
* **Category**: `100: Landing Zone`
* **Key Technologies & Components**: GCP, GitHub Actions, OIDC, WIF
* **Description**: Documents the keyless authentication workflow using Google Workload Identity Federation (WIF). Replaces persistent JSON service account keys with short-lived OAuth2 access tokens exchanged via GitHub OIDC.

<details>
<summary>🔍 Expand infographic preview (101)</summary>

![101 - WIF Federation](./101_GCP_Keyless_Landing_Zone_and_WIF_Federation.png)

</details>

---

### 102 - GKE Golden Path JHipster Microservice Architecture
* **Category**: `100: Landing Zone`
* **Key Technologies & Components**: GKE, JHipster, Dataplane V2, eBPF
* **Description**: Maps the internal microservice design deployed within the GKE Golden-Path. Focuses on default-deny network postures enforced by GKE Dataplane V2 and inter-service container communication.

<details>
<summary>🔍 Expand infographic preview (102)</summary>

![102 - JHipster Microservice](./102_GKE_Golden_Path_JHipster_Microservice_Architecture.png)

</details>

---

### 103 - Argo Workflows and Argo Events on GKE
* **Category**: `100: Landing Zone`
* **Key Technologies & Components**: Argo Events, Argo Workflows, GKE
* **Description**: Represents the event-driven CI/CD control plane on GKE. Details the Argo Events webhook listener architecture, GKE Gateway API ingress routing, and the 10-stage execution pipeline contract.

<details>
<summary>🔍 Expand infographic preview (103)</summary>

![103 - Argo Workflows](./103_Argo_Workflows_and_Argo_Events_on_GKE.png)

</details>

---

### 104 - GKE Zero Trust Ingress North South Traffic Lifecycle with BackendTLS
* **Category**: `100: Landing Zone`
* **Key Technologies & Components**: BackendTLSPolicy, Gateway API, Google IAP
* **Description**: Traces the zero-trust lifecycle of North-South ingress traffic. Details SSL termination at the global L7 Load Balancer, Google IAP context-aware authorization, HTTPRoute definition, BackendTLSPolicy enforcement, and direct NEG routing to pods with 100% continuous transit encryption.

<details>
<summary>🔍 Expand infographic preview (104)</summary>

![104 - BackendTLS North-South](./104_GKE_Zero_Trust_Ingress_North_South_Traffic_Lifecycle_with_BackendTLS.png)

</details>

---

### 105 - GKE Golden Path High Availability PostgreSQL with CloudNativePG
* **Category**: `100: Landing Zone`
* **Key Technologies & Components**: PostgreSQL, CloudNativePG, PgBouncer
* **Description**: Illustrates the database clustering setup using CloudNativePG on GKE. Explains high-availability replication across multiple zones, read/write splitting, and pgBouncer pooled connection proxying.

<details>
<summary>🔍 Expand infographic preview (105)</summary>

![105 - CloudNativePG](./105_GKE_Golden_Path_High_Availability_PostgreSQL_with_CloudNativePG.png)

</details>

---

### 201 - GKE Cluster Topology and Karpenter Native Node Auto Provisioning
* **Category**: `200: Node Provisioning`
* **Key Technologies & Components**: GKE NAP, Karpenter-native, quotas
* **Description**: Details GKE node auto-provisioning (NAP) behaving similarly to Karpenter. Explains quota ceilings, hard technical limits for SSD/disks, and the lifecycle of pending pods triggering dynamic node spin-up.

<details>
<summary>🔍 Expand infographic preview (201)</summary>

![201 - Node Auto Provisioning](./201_GKE_Cluster_Topology_and_Karpenter_Native_Node_Auto_Provisioning.png)

</details>

---

### 202 - GitHub Actions on GKE ARC and Spot Runners
* **Category**: `200: Node Provisioning`
* **Key Technologies & Components**: GitHub ARC, Spot Instances, WIF
* **Description**: Analyzes GitHub Actions Runner Controller (ARC) deployments on GKE. Shows how ephemeral runners are scheduled dynamically on cost-effective GCP Spot VMs, with WIF providing secure identity mappings.

<details>
<summary>🔍 Expand infographic preview (202)</summary>

![202 - GitHub ARC](./202_GitHub_Actions_on_GKE_ARC_and_Spot_Runners.png)

</details>

---

### 203 - Jenkins 2026 GitHub Actions Workflow Catalog Map
* **Category**: `200: Node Provisioning`
* **Key Technologies & Components**: GitHub Actions, Git Workflows, GKE
* **Description**: Provides a comprehensive directory of the 29 GitHub Actions workflows managing the GKE Golden-Path platform, detailing naming patterns, push/PR triggers, and operational dependencies.

<details>
<summary>🔍 Expand infographic preview (203)</summary>

![203 - GHA Catalog Map](./203_Jenkins_2026_GitHub_Actions_Workflow_Catalog_Map.png)

</details>

---

### 301 - GKE Dataplane V2 eBPF Zero Trust Isolation Matrix
* **Category**: `300: Dataplane Security`
* **Key Technologies & Components**: Dataplane V2, eBPF, NetworkPolicies
* **Description**: Maps the default-deny matrix for the microservices namespace. Explains how Cilium/eBPF enforces network isolation at the kernel level, blocking all non-whitelisted cross-pod interactions.

<details>
<summary>🔍 Expand infographic preview (301)</summary>

![301 - eBPF Isolation](./301_GKE_Dataplane_V2_eBPF_Zero_Trust_Isolation_Matrix.png)

</details>

---

### 302 - GKE Dataplane V2 Zero Trust Networking Architecture
* **Category**: `300: Dataplane Security`
* **Key Technologies & Components**: Linux Kernel, Cilium, BPF filters
* **Description**: Explains the low-level network packet flow inside the Linux Kernel using eBPF JIT-compiled programs, TC (Traffic Control) network hooks, and secure socket redirections bypass.

<details>
<summary>🔍 Expand infographic preview (302)</summary>

![302 - eBPF Networking](./302_GKE_Dataplane_V2_Zero_Trust_Networking_Architecture.png)

</details>

---

### 303 - JHipster Gateway Architecture and Observability Map
* **Category**: `300: Dataplane Security`
* **Key Technologies & Components**: JHipster Gateway, Webpack, Faro
* **Description**: Details the Gateway layer of the application, contrasting dev (Webpack reload) vs prod profiles, route proxying to downstream microservices, and OpenTelemetry instrumentation hooks.

<details>
<summary>🔍 Expand infographic preview (303)</summary>

![303 - Gateway Observability](./303_JHipster_Gateway_Architecture_and_Observability_Map.png)

</details>

---

### 304 - GKE Golden Path IDP Runtime Traffic and Data Integration
* **Category**: `300: Dataplane Security`
* **Key Technologies & Components**: Ingress Routing, Egress Policies, IDP
* **Description**: Represents an expert guide for handling data integration and security. Covers ingress-to-pod mappings, egress whitelist policies, and OTel collector ingestion paths for tracing.

<details>
<summary>🔍 Expand infographic preview (304)</summary>

![304 - Traffic Data Integration](./304_GKE_Golden_Path_IDP_Runtime_Traffic_and_Data_Integration.png)

</details>

---

### 305 - GKE Platform Networking Blueprint Zero Trust North South Ingress
* **Category**: `300: Dataplane Security`
* **Key Technologies & Components**: GKE Gateway API, Google IAP, BackendTLSPolicy, NEGs
* **Description**: Outlines the zero-trust landing zone network blueprint for GKE North-South ingress. Focuses on edge TLS termination, Google IAP user authorization, and secondary handshakes to container-native NEGs with certificates from GKE-managed CAs.

<details>
<summary>🔍 Expand infographic preview (305)</summary>

![305 - Networking Blueprint](./305_GKE_Platform_Networking_Blueprint_Zero_Trust_North_South_Ingress.png)

</details>

---

### 401 - Zero Trust Keyless Secrets Lifecycle via ESO and WIF
* **Category**: `400: Secrets & DevSecOps`
* **Key Technologies & Components**: Secret Manager, ESO, GKE Secrets
* **Description**: Outlines the keyless replication of secrets from Google Secret Manager to Kubernetes Secrets using the External Secrets Operator (ESO) and GCP Workload Identity.

<details>
<summary>🔍 Expand infographic preview (401)</summary>

![401 - Secret Lifecycle](./401_Zero_Trust_Keyless_Secrets_Lifecycle_via_ESO_and_WIF.png)

</details>

---

### 402 - DevSecOps Multilayer Scanning and SARIF Flow
* **Category**: `400: Secrets & DevSecOps`
* **Key Technologies & Components**: Semgrep, CodeQL, Trivy, SARIF
* **Description**: Displays the pluggable 4-layer security scanning pipeline (lightweight SAST, deep SAST, dependency check, and container scan) consolidating vulnerabilities into standard SARIF files.

<details>
<summary>🔍 Expand infographic preview (402)</summary>

![402 - DevSecOps Scanning](./402_DevSecOps_Multilayer_Scanning_and_SARIF_Flow.png)

</details>

---

### 501 - Jenkins 2026 Automated CI Engine Architecture
* **Category**: `500: CI Engines`
* **Key Technologies & Components**: Jenkins, JCasC, Helm, GKE Agents
* **Description**: Details the fully GitOps-managed Jenkins engine. Features declarative Configuration-as-Code (JCasC), Helm-managed state, and dynamic on-demand agent scaling on GKE.

<details>
<summary>🔍 Expand infographic preview (501)</summary>

![501 - Jenkins CI](./501_Jenkins_2026_Automated_CI_Engine_Architecture.png)

</details>

---

### 502 - Tekton CI Engine Architecture with Pipelines as Code and SLSA
* **Category**: `500: CI Engines`
* **Key Technologies & Components**: Tekton, SLSA, Pipelines-as-Code
* **Description**: Showcases the cloud-native Tekton CI model. Describes event-based triggers, Git pipelines-as-code controllers, and SLSA provenance attestation generators for builds.

<details>
<summary>🔍 Expand infographic preview (502)</summary>

![502 - Tekton CI](./502_Tekton_CI_Engine_Architecture_with_Pipelines_as_Code_and_SLSA.png)

</details>

---

### 601 - Two Repo GitOps State Machine with ArgoCD and CI Workflow
* **Category**: `600: Deployment & GitOps`
* **Key Technologies & Components**: GitOps, ArgoCD Sync, Multi-Engine CI
* **Description**: Maps the two-repo GitOps decoupling. Explains how CI processes push container tags to the app repository, and how ArgoCD reconciles the cluster to match the Git state.

<details>
<summary>🔍 Expand infographic preview (601)</summary>

![601 - GitOps State Machine](./601_Two_Repo_GitOps_State_Machine_with_ArgoCD_and_CI_Workflow.png)

</details>

---

### 602 - Terraform IaC Idempotency and Day 1 State Flow
* **Category**: `600: Deployment & GitOps`
* **Key Technologies & Components**: Terraform, State Locking, GCS
* **Description**: Traces the execution flow of Terraform infrastructure code. Illustrates safe state locking in GCP GCS buckets and the transition from Day 0 setup to Day 1 updates.

<details>
<summary>🔍 Expand infographic preview (602)</summary>

![602 - Terraform state flow](./602_Terraform_IaC_Idempotency_and_Day_1_State_Flow.png)

</details>

---

### 603 - Sidecar Free Progressive Delivery with Argo Rollouts and GKE Gateway API
* **Category**: `600: Deployment & GitOps`
* **Key Technologies & Components**: Argo Rollouts, GKE Gateway, Canary
* **Description**: Illustrates a progressive delivery architecture. Argo Rollouts manages canary traffic splitting directly through GKE Gateway routing, bypassing the need for sidecar-heavy service meshes like Istio.

<details>
<summary>🔍 Expand infographic preview (603)</summary>

![603 - Progressive Delivery](./603_Sidecar_Free_Progressive_Delivery_with_Argo_Rollouts_and_GKE_Gateway_API.png)

</details>

---

### 604 - Sidecar Free Zero Trust BackendTLS and GitOps Workflow
* **Category**: `600: Deployment & GitOps`
* **Key Technologies & Components**: ArgoCD, GKE Gateway, BackendTLSPolicy, GKE CA
* **Description**: Maps the GitOps reconciliation flow of zero-trust components in GKE. Details how ArgoCD syncs Gateway and BackendTLSPolicy manifests, terminating TLS at target microservices by validating pod certificates against GKE-managed CAs.

<details>
<summary>🔍 Expand infographic preview (604)</summary>

![604 - BackendTLS GitOps](./604_Sidecar_Free_Zero_Trust_BackendTLS_and_GitOps_Workflow.png)

</details>

---

### 701 - Advanced CI Architecture Jenkins vs Tekton on GKE
* **Category**: `700: Tool Comparisons`
* **Key Technologies & Components**: Jenkins, Tekton, GKE scheduler
* **Description**: Compares structural architecture of Jenkins vs Tekton. Focuses on persistent master controllers vs serverless CRD-driven pods, and the impact on resource scheduling.

<details>
<summary>🔍 Expand infographic preview (701)</summary>

![701 - Jenkins vs Tekton](./701_Advanced_CI_Architecture_Jenkins_vs_Tekton_on_GKE.png)

</details>

---

### 702 - Spot Instance Resiliency Jenkins vs GitHub Actions ARC
* **Category**: `700: Tool Comparisons`
* **Key Technologies & Components**: Spot Nodes, Evictions, ARC, Jenkins
* **Description**: Benchmarks Spot instance node evictions. Compares Jenkins master-agent connection drops with GitHub Actions ARC runner rescheduling and recovery metrics.

<details>
<summary>🔍 Expand infographic preview (702)</summary>

![702 - Spot Resiliency](./702_Spot_Instance_Resiliency_Jenkins_vs_GitHub_Actions_ARC.png)

</details>

---

### 703 - CI Battle Jenkins Groovy vs Argo Workflows DAG and UI Strategy
* **Category**: `700: Tool Comparisons`
* **Key Technologies & Components**: Groovy script, YAML DAG, Jenkins, Argo
* **Description**: Compares the imperative scripting style of Jenkins Groovy pipelines against the declarative YAML DAG model of Argo Workflows on GKE. Details the Jenkins UI strategy, explicitly replacing deprecated Blue Ocean with Classic UI and warnings-ng.

<details>
<summary>🔍 Expand infographic preview (703)</summary>

![703 - CI Battle UI](./703_CI_Battle_Jenkins_Groovy_vs_Argo_Workflows_DAG_and_UI_Strategy.png)

</details>

---

### 704 - CI Grand Master Battlecard 4 Way GKE Matrix
* **Category**: `700: Tool Comparisons`
* **Key Technologies & Components**: CI Matrix, Jenkins, Tekton, Argo, GHA
* **Description**: Provides a 4-way architectural comparison battlecard evaluating the performance, scaling latency, and storage overhead of Jenkins, Tekton, Argo, and GHA.

<details>
<summary>🔍 Expand infographic preview (704)</summary>

![704 - 4-Way CI Matrix](./704_CI_Grand_Master_Battlecard_4_Way_GKE_Matrix.png)

</details>

---

### 705 - Jenkins Dominance Pluggable CI 4 Way Matrix and Classic UI Transition
* **Category**: `700: Tool Comparisons`
* **Key Technologies & Components**: Jenkins, CI Matrix, GKE
* **Description**: Features the Pluggable CI 4-Way comprehensive matrix, detailing resource footprint and scheduling, and noting the deprecation/replacement of Blue Ocean with Classic UI + warnings-ng.

<details>
<summary>🔍 Expand infographic preview (705)</summary>

![705 - Pluggable CI Matrix](./705_Jenkins_Dominance_Pluggable_CI_4_Way_Matrix_and_Classic_UI_Transition.png)

</details>

---

### 706 - Why Jenkins Wins Battlecard and UI Security Strategy
* **Category**: `700: Tool Comparisons`
* **Key Technologies & Components**: Jenkins, DevSecOps, Pluggable CI
* **Description**: Explains the technical benefits of Jenkins in a pluggable CI platform, detailing usability, native security integrations, and the UI security strategy mitigating deprecated Blue Ocean CVE risks.

<details>
<summary>🔍 Expand infographic preview (706)</summary>

![706 - Why Jenkins Wins](./706_Why_Jenkins_Wins_Battlecard_and_UI_Security_Strategy.png)

</details>

---

### 801 - Grafana OSS Self Hosted OTel Signal Flow
* **Category**: `800: Observability`
* **Key Technologies & Components**: Grafana OSS, OTel Collector, Faro
* **Description**: Illustrates the self-hosted observability signal flow. Shows how Java/JVM apps send logs, metrics, and traces to OpenTelemetry collectors, which correlate data for Grafana.

<details>
<summary>🔍 Expand infographic preview (801)</summary>

![801 - Grafana OSS OTel](./801_Grafana_OSS_Self_Hosted_OTel_Signal_Flow.png)

</details>

---

### 802 - Optimized OTel Data Flow and Grafana Cloud Free Tier
* **Category**: `800: Observability`
* **Key Technologies & Components**: OTel Gateway, Grafana Cloud, Free Tier
* **Description**: Guides developers on configuring custom metric filtering, span dropping, and lean telemetry rules in the OTel Gateway to fit within Grafana Cloud free tier quotas.

<details>
<summary>🔍 Expand infographic preview (802)</summary>

![802 - OTel Grafana Cloud](./802_Optimized_OTel_Data_Flow_and_Grafana_Cloud_Free_Tier.png)

</details>

---

### 803 - JVM Tuning and Hotspot Runtime Strategy
* **Category**: `800: Observability`
* **Key Technologies & Components**: JVM Tuning, Hotspot GC, Limits
* **Description**: Resolves the "container-default trap" (where JVM limits default to 25% heap). Optimizes memory allocations and Garbage Collector flags (G1GC) for Docker containers.

<details>
<summary>🔍 Expand infographic preview (803)</summary>

![803 - JVM Tuning GC](./803_JVM_Tuning_and_Hotspot_Runtime_Strategy.png)

</details>

---

### 804 - End to End Frontend Observability RUM with Grafana Faro and OTel
* **Category**: `800: Observability`
* **Key Technologies & Components**: Grafana Faro, RUM, Trace Propagation
* **Description**: Traces client-side Real User Monitoring (RUM) beacon propagation. Demonstrates traceparent header injection from the browser into backend APIs using OpenTelemetry.

<details>
<summary>🔍 Expand infographic preview (804)</summary>

![804 - Faro RUM](./804_End_to_End_Frontend_Observability_RUM_with_Grafana_Faro_and_OTel.png)

</details>

---

### 901 - k6 Traffic Simulation Unified Workload Profiles
* **Category**: `900: Load & Lifecycle`
* **Key Technologies & Components**: k6, Traffic Simulation, Load Tests
* **Description**: Explains the k6 workload profile setup, including environment variable injection (`k6sim_*`) and automated load test scenarios mimicking user concurrency peaks.

<details>
<summary>🔍 Expand infographic preview (901)</summary>

![901 - k6 Simulation](./901_k6_Traffic_Simulation_Unified_Workload_Profiles.png)

</details>

---

### 902 - GKE Golden Path IDP Platform Lifecycle and Rebuild Safety Matrix
* **Category**: `900: Load & Lifecycle`
* **Key Technologies & Components**: Platform Lifecycle, Backups, Recovery
* **Description**: Outlines the platform rebuild-safety matrix, defining backup strategies, disaster recovery runbooks, and recovery point objectives (RPO) for cluster states.

<details>
<summary>🔍 Expand infographic preview (902)</summary>

![902 - Rebuild Safety](./902_GKE_Golden_Path_IDP_Platform_Lifecycle_and_Rebuild_Safety_Matrix.png)

</details>

---

> [!TIP]
> Each infographic is named systematically to guarantee they stay sorted. Click any of the files in the **Infographic File (Clickable Link)** column to navigate directly to it.
