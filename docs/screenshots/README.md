# Live Platform Screenshot Catalog (83 Files)

A visual inventory of **83 screenshots** of the *running* jenkins-2026 platform — the real tool UIs captured across the Day0 to Decom lifecycle, spanning all four interchangeable CI engines and all four observability backends.

Files are named `NNN_Title_Words.png` so the folder stays self-sorting by category, mirroring the [Technical Infographics Catalog](../infographics/README.md). Images are stored with **Git LFS**.

---

## Screenshot Catalog Index

<details>
<summary>📋 Click to view the full detailed index list (83 entries)</summary>
<br>

1. **000: Developer Portal (Backstage)**
   - [[001]](#001---backstage-gateway-component-overview-with-relations-graph) - [Backstage Gateway Component Overview With Relations Graph](001_Backstage_Gateway_Component_Overview_With_Relations_Graph.png)
   - [[002]](#002---backstage-ci-cd-tab-with-tekton-pipeline-graph) - [Backstage CI CD Tab With Tekton Pipeline Graph](002_Backstage_CI_CD_Tab_With_Tekton_Pipeline_Graph.png)
   - [[003]](#003---backstage-kubernetes-tab-with-tekton-taskrun-inventory) - [Backstage Kubernetes Tab With Tekton TaskRun Inventory](003_Backstage_Kubernetes_Tab_With_Tekton_TaskRun_Inventory.png)
   - [[004]](#004---backstage-monitoring-tab-with-grafana-dashboards-and-alerts) - [Backstage Monitoring Tab With Grafana Dashboards And Alerts](004_Backstage_Monitoring_Tab_With_Grafana_Dashboards_And_Alerts.png)
   - [[005]](#005---backstage-monitoring-tab-managed-aws-deep-link-card) - [Backstage Monitoring Tab Managed AWS Deep Link Card](005_Backstage_Monitoring_Tab_Managed_AWS_Deep_Link_Card.png)
   - [[006]](#006---backstage-scaffolder-golden-path-template-picker) - [Backstage Scaffolder Golden Path Template Picker](006_Backstage_Scaffolder_Golden_Path_Template_Picker.png)
   - [[007]](#007---backstage-scaffolder-service-details-form-step) - [Backstage Scaffolder Service Details Form Step](007_Backstage_Scaffolder_Service_Details_Form_Step.png)
   - [[008]](#008---backstage-scaffolder-review-step-before-opening-prs) - [Backstage Scaffolder Review Step Before Opening PRs](008_Backstage_Scaffolder_Review_Step_Before_Opening_PRs.png)
   - [[009]](#009---backstage-scaffolder-final-review-summary-table) - [Backstage Scaffolder Final Review Summary Table](009_Backstage_Scaffolder_Final_Review_Summary_Table.png)
   - [[010]](#010---backstage-scaffolder-task-run-opening-two-pull-requests) - [Backstage Scaffolder Task Run Opening Two Pull Requests](010_Backstage_Scaffolder_Task_Run_Opening_Two_Pull_Requests.png)

2. **100: CI Engine (Jenkins)**
   - [[101]](#101---jenkins-dashboard-with-seeded-microservices-pipeline-jobs) - [Jenkins Dashboard With Seeded Microservices Pipeline Jobs](101_Jenkins_Dashboard_With_Seeded_Microservices_Pipeline_Jobs.png)
   - [[102]](#102---jenkins-gateway-stage-view-on-stable-tier) - [Jenkins Gateway Stage View On Stable Tier](102_Jenkins_Gateway_Stage_View_On_Stable_Tier.png)
   - [[103]](#103---jenkins-microservice-stage-view-with-seed-job-provenance) - [Jenkins Microservice Stage View With Seed Job Provenance](103_Jenkins_Microservice_Stage_View_With_Seed_Job_Provenance.png)
   - [[104]](#104---jenkins-develop-tier-stage-view-for-microservice) - [Jenkins Develop Tier Stage View For Microservice](104_Jenkins_Develop_Tier_Stage_View_For_Microservice.png)
   - [[105]](#105---jenkins-pipeline-graph-view-with-parallel-static-analysis) - [Jenkins Pipeline Graph View With Parallel Static Analysis](105_Jenkins_Pipeline_Graph_View_With_Parallel_Static_Analysis.png)
   - [[106]](#106---jenkins-warnings-ng-report-aggregating-semgrep-and-codeql) - [Jenkins Warnings NG Report Aggregating Semgrep And CodeQL](106_Jenkins_Warnings_NG_Report_Aggregating_Semgrep_And_CodeQL.png)

3. **200: CI Engine (Tekton)**
   - [[201]](#201---tekton-dashboard-pipelineruns-all-succeeded) - [Tekton Dashboard PipelineRuns All Succeeded](201_Tekton_Dashboard_PipelineRuns_All_Succeeded.png)
   - [[202]](#202---tekton-pipelinerun-task-breakdown-with-logs) - [Tekton PipelineRun Task Breakdown With Logs](202_Tekton_PipelineRun_Task_Breakdown_With_Logs.png)
   - [[203]](#203---tekton-dashboard-concurrent-running-pipelineruns) - [Tekton Dashboard Concurrent Running PipelineRuns](203_Tekton_Dashboard_Concurrent_Running_PipelineRuns.png)
   - [[204]](#204---tekton-gitops-deploy-task-argocd-sync-logs) - [Tekton GitOps Deploy Task ArgoCD Sync Logs](204_Tekton_GitOps_Deploy_Task_ArgoCD_Sync_Logs.png)

4. **300: CI Engine (GitHub Actions and ARC)**
   - [[301]](#301---github-actions-full-workflow-catalog-sidebar) - [GitHub Actions Full Workflow Catalog Sidebar](301_GitHub_Actions_Full_Workflow_Catalog_Sidebar.png)
   - [[302]](#302---day1-everything-up-dispatch-form-inputs) - [Day1 Everything Up Dispatch Form Inputs](302_Day1_Everything_Up_Dispatch_Form_Inputs.png)
   - [[303]](#303---day1-dispatch-backstage-and-grafana-toggles) - [Day1 Dispatch Backstage And Grafana Toggles](303_Day1_Dispatch_Backstage_And_Grafana_Toggles.png)
   - [[304]](#304---day1-dispatch-ref-verbosity-and-grafana-tier) - [Day1 Dispatch Ref Verbosity And Grafana Tier](304_Day1_Dispatch_Ref_Verbosity_And_Grafana_Tier.png)
   - [[305]](#305---day1-dispatch-service-mesh-and-binary-authorization) - [Day1 Dispatch Service Mesh And Binary Authorization](305_Day1_Dispatch_Service_Mesh_And_Binary_Authorization.png)
   - [[306]](#306---intra-cluster-tls-posture-dropdown-expanded) - [Intra Cluster TLS Posture Dropdown Expanded](306_Intra_Cluster_TLS_Posture_Dropdown_Expanded.png)
   - [[311]](#311---day1-everything-up-run-graph-and-approval) - [Day1 Everything Up Run Graph And Approval](311_Day1_Everything_Up_Run_Graph_And_Approval.png)
   - [[312]](#312---approving-pending-deployment-for-aws-bootstrap) - [Approving Pending Deployment For AWS Bootstrap](312_Approving_Pending_Deployment_For_AWS_Bootstrap.png)
   - [[313]](#313---aws-bootstrap-terraform-apply-managed-grafana-backend) - [AWS Bootstrap Terraform Apply Managed Grafana Backend](313_AWS_Bootstrap_Terraform_Apply_Managed_Grafana_Backend.png)
   - [[314]](#314---aws-managed-grafana-bootstrap-apply-complete) - [AWS Managed Grafana Bootstrap Apply Complete](314_AWS_Managed_Grafana_Bootstrap_Apply_Complete.png)
   - [[315]](#315---approving-gke-production-deployment-for-cluster-provision) - [Approving GKE Production Deployment For Cluster Provision](315_Approving_GKE_Production_Deployment_For_Cluster_Provision.png)
   - [[316]](#316---terraform-apply-provisioning-the-gke-cluster) - [Terraform Apply Provisioning The GKE Cluster](316_Terraform_Apply_Provisioning_The_GKE_Cluster.png)
   - [[317]](#317---namespaces-prereqs-and-azure-credentials-secret) - [Namespaces Prereqs And Azure Credentials Secret](317_Namespaces_Prereqs_And_Azure_Credentials_Secret.png)
   - [[318]](#318---up-script-secrets-quotas-and-otel-operator) - [Up Script Secrets Quotas And OTel Operator](318_Up_Script_Secrets_Quotas_And_OTel_Operator.png)
   - [[319]](#319---deploying-otel-operator-and-argocd-into-cluster) - [Deploying OTel Operator And ArgoCD Into Cluster](319_Deploying_OTel_Operator_And_ArgoCD_Into_Cluster.png)
   - [[320]](#320---argocd-install-and-iap-authproxy-sso) - [ArgoCD Install And IAP Authproxy SSO](320_ArgoCD_Install_And_IAP_Authproxy_SSO.png)
   - [[321]](#321---gitops-bootstrap-cnpg-rollouts-and-applicationset) - [GitOps Bootstrap CNPG Rollouts And ApplicationSet](321_GitOps_Bootstrap_CNPG_Rollouts_And_ApplicationSet.png)
   - [[322]](#322---internal-ca-backend-tls-certificates-and-collectors) - [Internal CA Backend TLS Certificates And Collectors](322_Internal_CA_Backend_TLS_Certificates_And_Collectors.png)
   - [[323]](#323---cert-manager-backend-tls-and-aws-observability-install) - [Cert Manager Backend TLS And AWS Observability Install](323_Cert_Manager_Backend_TLS_And_AWS_Observability_Install.png)
   - [[324]](#324---jenkins-install-binauthz-signer-and-seed-jobs) - [Jenkins Install Binauthz Signer And Seed Jobs](324_Jenkins_Install_Binauthz_Signer_And_Seed_Jobs.png)
   - [[325]](#325---jenkins-seed-job-and-binauthz-signer-on-aws-run) - [Jenkins Seed Job And Binauthz Signer On AWS Run](325_Jenkins_Seed_Job_And_Binauthz_Signer_On_AWS_Run.png)
   - [[326]](#326---provision-job-generating-gateway-routes-and-iap-policies) - [Provision Job Generating Gateway Routes And IAP Policies](326_Provision_Job_Generating_Gateway_Routes_And_IAP_Policies.png)
   - [[327]](#327---access-urls-and-managed-grafana-dashboard-publish) - [Access URLs And Managed Grafana Dashboard Publish](327_Access_URLs_And_Managed_Grafana_Dashboard_Publish.png)
   - [[331]](#331---github-actions-run-workflow-form-with-k6-presets) - [GitHub Actions Run Workflow Form With k6 Presets](331_GitHub_Actions_Run_Workflow_Form_With_k6_Presets.png)
   - [[341]](#341---decom-infra-everything-umbrella-in-progress) - [Decom Infra Everything Umbrella In Progress](341_Decom_Infra_Everything_Umbrella_In_Progress.png)
   - [[342]](#342---decom-cluster-teardown-toolchain-setup-steps) - [Decom Cluster Teardown Toolchain Setup Steps](342_Decom_Cluster_Teardown_Toolchain_Setup_Steps.png)
   - [[343]](#343---tear-down-the-stack-script-log-detail) - [Tear Down The Stack Script Log Detail](343_Tear_Down_The_Stack_Script_Log_Detail.png)
   - [[344]](#344---decommission-tear-down-then-terraform-destroy) - [Decommission Tear Down Then Terraform Destroy](344_Decommission_Tear_Down_Then_Terraform_Destroy.png)
   - [[345]](#345---terraform-destroy-complete-42-resources-destroyed) - [Terraform Destroy Complete 42 Resources Destroyed](345_Terraform_Destroy_Complete_42_Resources_Destroyed.png)
   - [[346]](#346---decommission-revoking-grafana-cloud-access-tokens) - [Decommission Revoking Grafana Cloud Access Tokens](346_Decommission_Revoking_Grafana_Cloud_Access_Tokens.png)
   - [[347]](#347---decom-cluster-run-succeeded-step-summary) - [Decom Cluster Run Succeeded Step Summary](347_Decom_Cluster_Run_Succeeded_Step_Summary.png)

5. **400: CI Engine (Argo Workflows)**
   - [[401]](#401---argo-workflows-list-of-succeeded-ci-runs) - [Argo Workflows List Of Succeeded CI Runs](401_Argo_Workflows_List_Of_Succeeded_CI_Runs.png)
   - [[402]](#402---argo-workflows-graph-for-gateway-stable-build) - [Argo Workflows Graph For Gateway Stable Build](402_Argo_Workflows_Graph_For_Gateway_Stable_Build.png)
   - [[403]](#403---argo-workflows-timeline-and-node-summary) - [Argo Workflows Timeline And Node Summary](403_Argo_Workflows_Timeline_And_Node_Summary.png)
   - [[404]](#404---argo-workflows-expanded-rows-with-platform-labels) - [Argo Workflows Expanded Rows With Platform Labels](404_Argo_Workflows_Expanded_Rows_With_Platform_Labels.png)

6. **500: GitOps and In-Cluster Admin**
   - [[501]](#501---argocd-applications-all-synced-on-develop) - [ArgoCD Applications All Synced On Develop](501_ArgoCD_Applications_All_Synced_On_Develop.png)
   - [[502]](#502---argocd-seventeen-applications-healthy-tracking-main) - [ArgoCD Seventeen Applications Healthy Tracking Main](502_ArgoCD_Seventeen_Applications_Healthy_Tracking_Main.png)
   - [[503]](#503---headlamp-workloads-overview-with-cluster-health-donuts) - [Headlamp Workloads Overview With Cluster Health Donuts](503_Headlamp_Workloads_Overview_With_Cluster_Health_Donuts.png)
   - [[504]](#504---headlamp-gateway-api-view-showing-platform-ingress) - [Headlamp Gateway API View Showing Platform Ingress](504_Headlamp_Gateway_API_View_Showing_Platform_Ingress.png)
   - [[505]](#505---pgadmin-browsing-stable-microservice-cnpg-database) - [pgAdmin Browsing Stable Microservice CNPG Database](505_pgAdmin_Browsing_Stable_Microservice_CNPG_Database.png)
   - [[506]](#506---jhipster-sample-gateway-application-homepage) - [JHipster Sample Gateway Application Homepage](506_JHipster_Sample_Gateway_Application_Homepage.png)

7. **600: GKE and Google Cloud Console**
   - [[601]](#601---gke-cluster-nodes-tab-with-nap-overflow-node) - [GKE Cluster Nodes Tab With NAP Overflow Node](601_GKE_Cluster_Nodes_Tab_With_NAP_Overflow_Node.png)
   - [[602]](#602---gke-workloads-list-of-full-platform-plane) - [GKE Workloads List Of Full Platform Plane](602_GKE_Workloads_List_Of_Full_Platform_Plane.png)
   - [[603]](#603---gke-persistent-volume-claims-for-platform-and-microservices) - [GKE Persistent Volume Claims For Platform And Microservices](603_GKE_Persistent_Volume_Claims_For_Platform_And_Microservices.png)
   - [[604]](#604---gke-workloads-observability-cpu-dashboard) - [GKE Workloads Observability CPU Dashboard](604_GKE_Workloads_Observability_CPU_Dashboard.png)

8. **700: Observability (In-Cluster OSS)**
   - [[701]](#701---grafana-ci-cd-observability-folder-dashboard-listing) - [Grafana CI CD Observability Folder Dashboard Listing](701_Grafana_CI_CD_Observability_Folder_Dashboard_Listing.png)
   - [[702]](#702---grafana-microservices-overview-with-red-golden-signals) - [Grafana Microservices Overview With RED Golden Signals](702_Grafana_Microservices_Overview_With_RED_Golden_Signals.png)
   - [[703]](#703---grafana-dora-metrics-dashboard-with-four-headline-stats) - [Grafana DORA Metrics Dashboard With Four Headline Stats](703_Grafana_DORA_Metrics_Dashboard_With_Four_Headline_Stats.png)
   - [[704]](#704---grafana-jenkins-controller-dashboard-with-agent-metrics) - [Grafana Jenkins Controller Dashboard With Agent Metrics](704_Grafana_Jenkins_Controller_Dashboard_With_Agent_Metrics.png)
   - [[705]](#705---grafana-tekton-ci-observability-dashboard) - [Grafana Tekton CI Observability Dashboard](705_Grafana_Tekton_CI_Observability_Dashboard.png)
   - [[706]](#706---grafana-jvm-internals-dashboard-for-java-services) - [Grafana JVM Internals Dashboard For Java Services](706_Grafana_JVM_Internals_Dashboard_For_Java_Services.png)
   - [[707]](#707---grafana-postgresql-cloudnativepg-cluster-health-dashboard) - [Grafana PostgreSQL CloudNativePG Cluster Health Dashboard](707_Grafana_PostgreSQL_CloudNativePG_Cluster_Health_Dashboard.png)
   - [[708]](#708---grafana-node-auto-provisioning-spot-ci-nodes-dashboard) - [Grafana Node Auto Provisioning Spot CI Nodes Dashboard](708_Grafana_Node_Auto_Provisioning_Spot_CI_Nodes_Dashboard.png)
   - [[709]](#709---grafana-frontend-rum-angular-faro-core-web-vitals) - [Grafana Frontend RUM Angular Faro Core Web Vitals](709_Grafana_Frontend_RUM_Angular_Faro_Core_Web_Vitals.png)

9. **800: Observability (Managed and Cloud)**
   - [[801]](#801---grafana-cloud-jvm-internals-dashboard) - [Grafana Cloud JVM Internals Dashboard](801_Grafana_Cloud_JVM_Internals_Dashboard.png)
   - [[802]](#802---amazon-managed-grafana-cicd-observability-folder-index) - [Amazon Managed Grafana CICD Observability Folder Index](802_Amazon_Managed_Grafana_CICD_Observability_Folder_Index.png)
   - [[803]](#803---amazon-managed-grafana-dora-metrics-dashboard) - [Amazon Managed Grafana DORA Metrics Dashboard](803_Amazon_Managed_Grafana_DORA_Metrics_Dashboard.png)
   - [[804]](#804---amazon-managed-grafana-microservices-overview-dashboard) - [Amazon Managed Grafana Microservices Overview Dashboard](804_Amazon_Managed_Grafana_Microservices_Overview_Dashboard.png)
   - [[805]](#805---amazon-managed-grafana-cloudnativepg-postgresql-dashboard) - [Amazon Managed Grafana CloudNativePG PostgreSQL Dashboard](805_Amazon_Managed_Grafana_CloudNativePG_PostgreSQL_Dashboard.png)
   - [[806]](#806---amazon-managed-grafana-gke-spot-node-autoprovisioning-dashboard) - [Amazon Managed Grafana GKE Spot Node Autoprovisioning Dashboard](806_Amazon_Managed_Grafana_GKE_Spot_Node_Autoprovisioning_Dashboard.png)
   - [[807]](#807---amazon-managed-grafana-kubernetes-global-cluster-view) - [Amazon Managed Grafana Kubernetes Global Cluster View](807_Amazon_Managed_Grafana_Kubernetes_Global_Cluster_View.png)
   - [[808]](#808---amazon-managed-grafana-kubernetes-namespaces-view) - [Amazon Managed Grafana Kubernetes Namespaces View](808_Amazon_Managed_Grafana_Kubernetes_Namespaces_View.png)
   - [[809]](#809---amazon-managed-grafana-provisioned-cicd-alert-rules) - [Amazon Managed Grafana Provisioned CICD Alert Rules](809_Amazon_Managed_Grafana_Provisioned_CICD_Alert_Rules.png)

</details>

---

## 🖼️ Visual Previews Catalog

<details>
<summary>📂 Expand 000: Developer Portal (Backstage) (10 Screenshots)</summary>

### 001 - Backstage Gateway Component Overview With Relations Graph
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Software Catalog, ArgoCD, TechDocs
* **Description**: The Overview tab of the `gateway` Component in the Backstage software catalog: About card (owner platform-team, lifecycle production), the entity Relations graph and an ArgoCD Deployment Summary reporting `microservices-stable` Synced and Healthy. Shows the full per-entity tab strip (Overview, CI/CD, Deployments, Kubernetes, Monitoring, Security, Scorecard, API, Dependencies, Docs).

![001 - Backstage Gateway Component Overview With Relations Graph](./001_Backstage_Gateway_Component_Overview_With_Relations_Graph.png)

---

### 002 - Backstage CI CD Tab With Tekton Pipeline Graph
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Tekton plugin, PipelineRun, Binary Authorization
* **Description**: The `gateway` entity's CI/CD tab rendering the Tekton plugin for cluster `gke`, with PipelineRun `gateway-stable-r9djc` Succeeded in 14m 9s. The expanded task DAG reveals the build-push-image steps build-jib, build-kaniko and sign-attest (the Binary Authorization signing step).

![002 - Backstage CI CD Tab With Tekton Pipeline Graph](./002_Backstage_CI_CD_Tab_With_Tekton_Pipeline_Graph.png)

---

### 003 - Backstage Kubernetes Tab With Tekton TaskRun Inventory
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Kubernetes plugin, Tekton TaskRun, GKE
* **Description**: The `gateway` entity's Kubernetes tab listing live objects on the `gke` cluster (11 pods, no errors): the PipelineRun and each of its ten TaskRuns alongside the resulting `gateway` Deployment and Service. Correlates CI execution objects and deployed workloads in one portal view.

![003 - Backstage Kubernetes Tab With Tekton TaskRun Inventory](./003_Backstage_Kubernetes_Tab_With_Tekton_TaskRun_Inventory.png)

---

### 004 - Backstage Monitoring Tab With Grafana Dashboards And Alerts
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Grafana, OpenTelemetry, Prometheus
* **Description**: The Monitoring tab of the `gateway` entity rendering live Grafana cards: the CI-CD Observability dashboard list and the six provisioned alert rules. Captured on a Tekton-engine cluster, showing the tab is engine-independent and switches only on `observability.mode`.

![004 - Backstage Monitoring Tab With Grafana Dashboards And Alerts](./004_Backstage_Monitoring_Tab_With_Grafana_Dashboards_And_Alerts.png)

---

### 005 - Backstage Monitoring Tab Managed AWS Deep Link Card
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Amazon Managed Grafana, AWS SigV4
* **Description**: The Monitoring tab under `observability.mode=managed-aws`, showing the deliberate deep-link card instead of live dashboards. The text records the decision: Amazon Managed Grafana authenticates with short-lived IAM/SigV4 tokens while the Backstage Grafana plugin can only send a static Bearer token.

![005 - Backstage Monitoring Tab Managed AWS Deep Link Card](./005_Backstage_Monitoring_Tab_Managed_AWS_Deep_Link_Card.png)

---

### 006 - Backstage Scaffolder Golden Path Template Picker
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Scaffolder, GitOps, GitHub Pull Requests
* **Description**: The Scaffolder "Create a new component" page listing the platform's single golden-path template, *Onboard an existing service*. The card states it wires an existing service into the CI registry all four engines read, the catalog and the GitOps values by opening one pull request per repo, never creating a repo.

![006 - Backstage Scaffolder Golden Path Template Picker](./006_Backstage_Scaffolder_Golden_Path_Template_Picker.png)

---

### 007 - Backstage Scaffolder Service Details Form Step
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Scaffolder, JHipster, Spring Boot Actuator
* **Description**: Step 1 of the onboarding wizard filled in for a `demo-service` entry, with source repo, container port 8082 and the `/management/health` Actuator endpoint. Inline helper text explains each field's downstream effect on the Jenkins job, the Kubernetes workload and the catalog entity.

![007 - Backstage Scaffolder Service Details Form Step](./007_Backstage_Scaffolder_Service_Details_Form_Step.png)

---

### 008 - Backstage Scaffolder Review Step Before Opening PRs
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Scaffolder, GitOps, GitHub
* **Description**: The final Review step of the onboarding wizard summarising every collected parameter before Create is pressed. Shows the confirm-before-PR gate of the Scaffolder golden path.

![008 - Backstage Scaffolder Review Step Before Opening PRs](./008_Backstage_Scaffolder_Review_Step_Before_Opening_PRs.png)

---

### 009 - Backstage Scaffolder Final Review Summary Table
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Scaffolder, GitOps, Software Catalog
* **Description**: The Review summary table for the `demo-service` onboarding run with the Back and Create actions. Illustrates that the template collects only six inputs before generating pull requests.

![009 - Backstage Scaffolder Final Review Summary Table](./009_Backstage_Scaffolder_Final_Review_Summary_Table.png)

---

### 010 - Backstage Scaffolder Task Run Opening Two Pull Requests
* **Category**: `000: Developer Portal (Backstage)`
* **Key Technologies & Components**: Backstage, Scaffolder, GitOps, GitHub Pull Requests
* **Description**: The Scaffolder task-run page for a completed onboarding, all eight steps green plus the two resulting PR links. The streamed log shows the append-only edits to `services.yaml`, the Backstage catalog and the GitOps `values-stable.yaml`.

![010 - Backstage Scaffolder Task Run Opening Two Pull Requests](./010_Backstage_Scaffolder_Task_Run_Opening_Two_Pull_Requests.png)

---

</details>

<details>
<summary>📂 Expand 100: CI Engine (Jenkins) (6 Screenshots)</summary>

### 101 - Jenkins Dashboard With Seeded Microservices Pipeline Jobs
* **Category**: `100: CI Engine (Jenkins)`
* **Key Technologies & Components**: Jenkins, JCasC, Job DSL seed job, Grafana
* **Description**: The Jenkins landing dashboard whose JCasC-managed welcome panel links every deployed endpoint (ArgoCD, pgAdmin, Headlamp, Backstage, microservices, Grafana). The job table lists the four seeded jobs (`gateway`, `jhipstersamplemicroservice`, `microservices-k6-smoke`, `seed-jobs`), all green.

![101 - Jenkins Dashboard With Seeded Microservices Pipeline Jobs](./101_Jenkins_Dashboard_With_Seeded_Microservices_Pipeline_Jobs.png)

---

### 102 - Jenkins Gateway Stage View On Stable Tier
* **Category**: `100: CI Engine (Jenkins)`
* **Key Technologies & Components**: Jenkins Pipeline Stage View, JHipster gateway, Maven, Kaniko
* **Description**: Stage View of the Java JHipster `gateway` job on the stable tier: build #1 green across all 15 stages in ~19m 41s (Build and Test 4m 57s, Build and Push Image 1m 20s, GitOps Update 2m 22s). The footer carries the seed-job drift notice.

![102 - Jenkins Gateway Stage View On Stable Tier](./102_Jenkins_Gateway_Stage_View_On_Stable_Tier.png)

---

### 103 - Jenkins Microservice Stage View With Seed Job Provenance
* **Category**: `100: CI Engine (Jenkins)`
* **Key Technologies & Components**: Jenkins Pipeline Stage View, Job DSL, Kaniko, GHCR
* **Description**: Stage View of `jhipstersamplemicroservice` on the `main` stable branch, build #1 fully green across the 15-stage pipeline in ~17m 34s, the slowest stage being Build and Push Image at 7m 12s. The footer credits `seed-jobs` as the generating seed job, evidencing the Job DSL pipelines-as-code provenance.

![103 - Jenkins Microservice Stage View With Seed Job Provenance](./103_Jenkins_Microservice_Stage_View_With_Seed_Job_Provenance.png)

---

### 104 - Jenkins Develop Tier Stage View For Microservice
* **Category**: `100: CI Engine (Jenkins)`
* **Key Technologies & Components**: Jenkins Pipeline Stage View, shared library, Semgrep, Trivy
* **Description**: Stage View of `jhipstersamplemicroservice` tracked via the `develop` branch, build #3 green across all 15 stages from Checkout through Patch App Source, Static Analysis, Build and Push Image, GitOps Update and the k6 smoke tests, in ~14m 59s. Demonstrates the develop promotion tier.

![104 - Jenkins Develop Tier Stage View For Microservice](./104_Jenkins_Develop_Tier_Stage_View_For_Microservice.png)

---

### 105 - Jenkins Pipeline Graph View With Parallel Static Analysis
* **Category**: `100: CI Engine (Jenkins)`
* **Key Technologies & Components**: Jenkins Pipeline Graph View, Semgrep, CodeQL, Trivy, SARIF
* **Description**: The modern Pipeline Graph view where Static Analysis fans out into three genuinely parallel branches (Semgrep SAST, CodeQL Analysis, Trivy IaC Scan) before Build and Push Image and the k6 smoke tests. The right pane expands the Semgrep step showing its `--config=p/security-audit --config=p/owasp-top-ten` invocation writing SARIF.

![105 - Jenkins Pipeline Graph View With Parallel Static Analysis](./105_Jenkins_Pipeline_Graph_View_With_Parallel_Static_Analysis.png)

---

### 106 - Jenkins Warnings NG Report Aggregating Semgrep And CodeQL
* **Category**: `100: CI Engine (Jenkins)`
* **Key Technologies & Components**: warnings-ng plugin, Semgrep, CodeQL, SARIF, DevSecOps
* **Description**: The Static Analysis Warnings report with severity/reference donut charts and a trend graph. The Tools table aggregates the SARIF output of both scanners (CodeQL 3 findings, Semgrep 18, total 21, 0 new), surfacing DevSecOps results natively in Jenkins.

![106 - Jenkins Warnings NG Report Aggregating Semgrep And CodeQL](./106_Jenkins_Warnings_NG_Report_Aggregating_Semgrep_And_CodeQL.png)

---

</details>

<details>
<summary>📂 Expand 200: CI Engine (Tekton) (4 Screenshots)</summary>

### 201 - Tekton Dashboard PipelineRuns All Succeeded
* **Category**: `200: CI Engine (Tekton)`
* **Key Technologies & Components**: Tekton Dashboard, Tekton Pipelines, PipelineRun
* **Description**: The Tekton Dashboard PipelineRuns list showing three completed runs in the `tekton-ci` namespace, all Succeeded: the k6 smoke (2m 12s) plus `jhipstersamplemicroservice-stable` (16m 31s) and `gateway-stable` (14m 11s) on `microservices-pipeline`.

![201 - Tekton Dashboard PipelineRuns All Succeeded](./201_Tekton_Dashboard_PipelineRuns_All_Succeeded.png)

---

### 202 - Tekton PipelineRun Task Breakdown With Logs
* **Category**: `200: CI Engine (Tekton)`
* **Key Technologies & Components**: Tekton Dashboard, TaskRun, Semgrep, CodeQL, Trivy
* **Description**: Detail view of a Succeeded PipelineRun with all ten Tasks green in sequence (fetch-source, semgrep-scan, codeql-analyze, trivy-iac, build-test, build-push-image, trivy-image, gitops-deploy, smoke-test, k6-smoke). The Logs tab of `fetch-source` is open, showing its clone and gateway-patch steps.

![202 - Tekton PipelineRun Task Breakdown With Logs](./202_Tekton_PipelineRun_Task_Breakdown_With_Logs.png)

---

### 203 - Tekton Dashboard Concurrent Running PipelineRuns
* **Category**: `200: CI Engine (Tekton)`
* **Key Technologies & Components**: Tekton Dashboard, Tekton Pipelines, PipelineRun, k6
* **Description**: The PipelineRuns list mid-build, with both microservices Running at 10m 59s on `microservices-pipeline` above four earlier Succeeded runs. Demonstrates the two services building in parallel in the `tekton-ci` namespace.

![203 - Tekton Dashboard Concurrent Running PipelineRuns](./203_Tekton_Dashboard_Concurrent_Running_PipelineRuns.png)

---

### 204 - Tekton GitOps Deploy Task ArgoCD Sync Logs
* **Category**: `200: CI Engine (Tekton)`
* **Key Technologies & Components**: Tekton Dashboard, ArgoCD, GitOps, CloudNativePG
* **Description**: Live log view of a Running PipelineRun with the `gitops-deploy` TaskRun expanded: the bump-and-push step is done and `argocd-sync` streams `argocd app sync microservices-stable`, listing every resource turning Synced/Healthy. Shows the image-tag bump handing off to ArgoCD as the deploy mechanism.

![204 - Tekton GitOps Deploy Task ArgoCD Sync Logs](./204_Tekton_GitOps_Deploy_Task_ArgoCD_Sync_Logs.png)

---

</details>

<details>
<summary>📂 Expand 300: CI Engine (GitHub Actions and ARC) (31 Screenshots)</summary>

### 301 - GitHub Actions Full Workflow Catalog Sidebar
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GitHub Actions, GKE, Terraform, Grafana
* **Description**: The Actions tab "All workflows" sidebar listing the complete `DayN.tier.ZZ` catalog from Day0.infra.01 Gateway through the Day2 redeploy/publish/registry/scale/traffic family to Decom.infra.04. Also shows the non-lifecycle guards: Dependabot, Gitflow Guard, Mermaid validate and Terraform validate.

![301 - GitHub Actions Full Workflow Catalog Sidebar](./301_GitHub_Actions_Full_Workflow_Catalog_Sidebar.png)

---

### 302 - Day1 Everything Up Dispatch Form Inputs
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GitHub Actions, workflow_dispatch, GKE, Terraform
* **Description**: The Run workflow dispatch panel for `Day1.cluster.00 Everything up`, with the observability backend, CI engine and secrets backend dropdowns. Below them sit the Gateway auto-bootstrap checkbox, the destructive purge of unselected backends, the lean develop tier and the opt-in LB-to-pod backend TLS toggles.

![302 - Day1 Everything Up Dispatch Form Inputs](./302_Day1_Everything_Up_Dispatch_Form_Inputs.png)

---

### 303 - Day1 Dispatch Backstage And Grafana Toggles
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Backstage, GHCR, Grafana LLM, Vertex AI
* **Description**: The same dispatch form scrolled to the Backstage developer portal checkbox (on by default) and the force-fresh-image opt-in, plus the two oss-only observability opt-ins for the keyless Grafana LLM app and the Grafana Assistant chat.

![303 - Day1 Dispatch Backstage And Grafana Toggles](./303_Day1_Dispatch_Backstage_And_Grafana_Toggles.png)

---

### 304 - Day1 Dispatch Ref Verbosity And Grafana Tier
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: workflow_dispatch, Terraform, Grafana Cloud, Loki
* **Description**: The tail of the dispatch form: the free-text git ref override, the script/Terraform verbosity selector, the Grafana Cloud tier profile and the minimum log severity override.

![304 - Day1 Dispatch Ref Verbosity And Grafana Tier](./304_Day1_Dispatch_Ref_Verbosity_And_Grafana_Tier.png)

---

### 305 - Day1 Dispatch Service Mesh And Binary Authorization
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Cloud Service Mesh, Binary Authorization, Cloud KMS
* **Description**: The dispatch form on `develop` with the mutually exclusive intra-cluster TLS posture set to cloud-service-mesh (managed Istio, standalone SKU), and the orthogonal Binary Authorization admission checkbox ticked alongside Backstage.

![305 - Day1 Dispatch Service Mesh And Binary Authorization](./305_Day1_Dispatch_Service_Mesh_And_Binary_Authorization.png)

---

### 306 - Intra Cluster TLS Posture Dropdown Expanded
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Cloud Service Mesh, cert-manager, Gateway API
* **Description**: The same form with the single `intra_cluster_tls` dropdown opened, revealing its three mutually exclusive values none, backend-tls and cloud-service-mesh. This one control is why a mesh and backend TLS can never both be enabled.

![306 - Intra Cluster TLS Posture Dropdown Expanded](./306_Intra_Cluster_TLS_Posture_Dropdown_Expanded.png)

---

### 311 - Day1 Everything Up Run Graph And Approval
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GitHub Actions, GKE, Backstage, Azure
* **Description**: `Day1.cluster.00 Everything up` in progress with the banner "The deployments have been approved". The job graph shows precheck feeding gateway-bootstrap and backstage-image-bootstrap into the nested provision reusable workflow.

![311 - Day1 Everything Up Run Graph And Approval](./311_Day1_Everything_Up_Run_Graph_And_Approval.png)

---

### 312 - Approving Pending Deployment For AWS Bootstrap
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GitHub Actions, deployment environments, Terraform, AWS OIDC
* **Description**: A Day1 run in Waiting status, blocked on a deployment protection rule, with the Review pending deployments dialog ready to approve the `aws-bootstrap` environment. Shows the human gate in front of billed cloud resources.

![312 - Approving Pending Deployment For AWS Bootstrap](./312_Approving_Pending_Deployment_For_AWS_Bootstrap.png)

---

### 313 - AWS Bootstrap Terraform Apply Managed Grafana Backend
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Terraform, Amazon Managed Grafana, Amazon Managed Prometheus, IAM OIDC
* **Description**: The `aws-bootstrap` job running Terraform apply with a plan of 13 adds: the Amazon Managed Grafana workspace, the `jenkins-2026-amp` Prometheus workspace, a CloudWatch log group, the GKE OIDC provider and the collector IAM roles.

![313 - AWS Bootstrap Terraform Apply Managed Grafana Backend](./313_AWS_Bootstrap_Terraform_Apply_Managed_Grafana_Backend.png)

---

### 314 - AWS Managed Grafana Bootstrap Apply Complete
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Terraform, Amazon Managed Grafana, Amazon Managed Prometheus
* **Description**: The same job succeeded in 4m 41s with "Apply complete! Resources: 13 added", emitting the amp_query_url, amp_remote_write_endpoint, collector_role_arn and grafana_endpoint outputs consumed later by the cluster provision.

![314 - AWS Managed Grafana Bootstrap Apply Complete](./314_AWS_Managed_Grafana_Bootstrap_Apply_Complete.png)

---

### 315 - Approving GKE Production Deployment For Cluster Provision
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GitHub Actions, deployment environments, GKE
* **Description**: The run waiting again, now on the `gke-production` environment, with the protection-rules table showing `aws-bootstrap` already approved minutes earlier. The AWS managed-grafana backend summary and its Grafana endpoint appear below.

![315 - Approving GKE Production Deployment For Cluster Provision](./315_Approving_GKE_Production_Deployment_For_Cluster_Provision.png)

---

### 316 - Terraform Apply Provisioning The GKE Cluster
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Terraform, GKE, VPC, Binary Authorization
* **Description**: The provision job's Terraform apply step: VPC and subnet, binauthz-signer Workload Identity bindings for the jenkins and argo-ci service accounts, cluster created after 7m 33s and node pool after 1m 44s, ending "Apply complete! Resources: 40 added, 1 changed".

![316 - Terraform Apply Provisioning The GKE Cluster](./316_Terraform_Apply_Provisioning_The_GKE_Cluster.png)

---

### 317 - Namespaces Prereqs And Azure Credentials Secret
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: NetworkPolicy, ComputeClass, Terraform, Azure Monitor
* **Description**: The Namespaces and prereqs step complete (LimitRanges, per-namespace NetworkPolicies, the `ci-spot` Node Auto-Provisioning ComputeClass, NEG self-heal), then the step that reads the azure-managed-grafana Terraform state from GCS and creates `secret/azure-monitor-credentials`.

![317 - Namespaces Prereqs And Azure Credentials Secret](./317_Namespaces_Prereqs_And_Azure_Credentials_Secret.png)

---

### 318 - Up Script Secrets Quotas And OTel Operator
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Kubernetes Secrets, ResourceQuota, OpenTelemetry Operator, Helm
* **Description**: The `scripts/up.sh` step showing the idempotent reconcile pass: orphan disk sweep, unchanged namespaces and keep-if-present handling of every platform secret, before applying ResourceQuotas, LimitRanges and NetworkPolicies and installing the OpenTelemetry Operator.

![318 - Up Script Secrets Quotas And OTel Operator](./318_Up_Script_Secrets_Quotas_And_OTel_Operator.png)

---

### 319 - Deploying OTel Operator And ArgoCD Into Cluster
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: OpenTelemetry Operator, ArgoCD, NetworkPolicy, GKE ComputeClass
* **Description**: The provision job applying quotas, limits, NetworkPolicies and the `ci-spot` ComputeClass, installing the OpenTelemetry Operator and then ArgoCD v3.4.5 with backend TLS, IAP authproxy SSO and OIDC/RBAC configuration.

![319 - Deploying OTel Operator And ArgoCD Into Cluster](./319_Deploying_OTel_Operator_And_ArgoCD_Into_Cluster.png)

---

### 320 - ArgoCD Install And IAP Authproxy SSO
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: ArgoCD, Helm, Google IAP, backend TLS
* **Description**: The log advancing past the OTel Operator readiness gate into step 08.5-argocd, resolving the 3.4.x constraint to v3.4.5 and installing it with backend TLS so argocd-server serves TLS without `--insecure`. It then patches argocd-cm and argocd-rbac-cm to wire IAP authproxy SSO.

![320 - ArgoCD Install And IAP Authproxy SSO](./320_ArgoCD_Install_And_IAP_Authproxy_SSO.png)

---

### 321 - GitOps Bootstrap CNPG Rollouts And ApplicationSet
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: ArgoCD, CloudNativePG, Argo Rollouts, cert-manager
* **Description**: The log building the GitOps plane: an ArgoCD API token minted for the jenkins account, the microservices AppProject, the platform-config and platform-postgres app-of-apps, a CNPG webhook caBundle patch, External Secrets, Argo Rollouts, Headlamp and the microservices ApplicationSet. It also clears the stale WAL archive from the persistent backups bucket on fresh provision.

![321 - GitOps Bootstrap CNPG Rollouts And ApplicationSet](./321_GitOps_Bootstrap_CNPG_Rollouts_And_ApplicationSet.png)

---

### 322 - Internal CA Backend TLS Certificates And Collectors
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: cert-manager, backend TLS, OpenTelemetry Collector, Azure Monitor
* **Description**: The log bootstrapping the cluster-internal CA, minting per-backend server certs for headlamp, faro, pgadmin, argocd-server, jenkins, backstage and the gateway, and projecting the CA trust bundles. It then runs 03-observability in managed-azure mode, installing kube-state-metrics, node-exporter and the collectors.

![322 - Internal CA Backend TLS Certificates And Collectors](./322_Internal_CA_Backend_TLS_Certificates_And_Collectors.png)

---

### 323 - Cert Manager Backend TLS And AWS Observability Install
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: cert-manager, backend TLS, kube-state-metrics, OpenTelemetry Collector
* **Description**: The same phase on a managed-aws run: cert-manager installed via ArgoCD, the internal CA bootstrapped and per-backend certs minted, then the observability stack wired to Amazon Managed Prometheus, X-Ray and CloudWatch.

![323 - Cert Manager Backend TLS And AWS Observability Install](./323_Cert_Manager_Backend_TLS_And_AWS_Observability_Install.png)

---

### 324 - Jenkins Install Binauthz Signer And Seed Jobs
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Jenkins, JCasC, Binary Authorization, ArgoCD
* **Description**: Step 04-jenkins applying the JCasC ConfigMaps and the Jenkins ArgoCD Application with the TLS values overlay, and annotating the Jenkins KSA to impersonate the `jenkins-2026-binauthz-signer` service account for image signing. It then triggers the seed job, which creates the four pipeline jobs.

![324 - Jenkins Install Binauthz Signer And Seed Jobs](./324_Jenkins_Install_Binauthz_Signer_And_Seed_Jobs.png)

---

### 325 - Jenkins Seed Job And Binauthz Signer On AWS Run
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Jenkins, JCasC, ArgoCD, Binary Authorization
* **Description**: The same 04-jenkins step on the managed-aws run, with "Binary Authorization active" annotating the Jenkins KSA and `seed-jobs` build #1 succeeding to create the four pipeline jobs. Demonstrates the identical engine install across observability backends.

![325 - Jenkins Seed Job And Binauthz Signer On AWS Run](./325_Jenkins_Seed_Job_And_Binauthz_Signer_On_AWS_Run.png)

---

### 326 - Provision Job Generating Gateway Routes And IAP Policies
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GKE Gateway API, Backstage, Headlamp, BackendTLSPolicy
* **Description**: The provision job with Headlamp ready and Backstage configured, and 09-gateway generating the Gateway, HTTPRoutes, BackendTLSPolicies, HealthCheckPolicies and the IAP GCPBackendPolicies that protect every private endpoint.

![326 - Provision Job Generating Gateway Routes And IAP Policies](./326_Provision_Job_Generating_Gateway_Routes_And_IAP_Policies.png)

---

### 327 - Access URLs And Managed Grafana Dashboard Publish
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Google IAP, Amazon Managed Grafana, Grafana alerting
* **Description**: The provision job succeeded in 31m 35s: the Access URLs step prints the IAP-protected ArgoCD/Jenkins/Headlamp/pgAdmin/Backstage hosts plus the open microservices and Faro RUM endpoints, then the dashboard script publishes 12 dashboards (skipping non-active engines) and 6 alert rules into Amazon Managed Grafana.

![327 - Access URLs And Managed Grafana Dashboard Publish](./327_Access_URLs_And_Managed_Grafana_Dashboard_Publish.png)

---

### 331 - GitHub Actions Run Workflow Form With k6 Presets
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GitHub Actions, workflow_dispatch, k6, Grafana Faro
* **Description**: The workflow_dispatch panel with the k6 preset dropdown expanded: none, smoke, load-baseline, frontend-only, develop-smoke, stress-peak, spike-recovery, soak-endurance, rps-steady, breakpoint-capacity and rum-faro. Inline help explains that rum-faro emits synthetic Grafana Faro RUM beacons (oss and grafana-cloud only).

![331 - GitHub Actions Run Workflow Form With k6 Presets](./331_GitHub_Actions_Run_Workflow_Form_With_k6_Presets.png)

---

### 341 - Decom Infra Everything Umbrella In Progress
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GitHub Actions, Terraform, GKE, Grafana Cloud
* **Description**: The `Decom.infra.00 Everything (cluster + all backends)` umbrella in progress after approval: the grafana-cloud and aws-grafana teardown jobs are green while azure-grafana and the gke-production cluster teardown still run and the gateway jobs are queued.

![341 - Decom Infra Everything Umbrella In Progress](./341_Decom_Infra_Everything_Umbrella_In_Progress.png)

---

### 342 - Decom Cluster Teardown Toolchain Setup Steps
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: GKE, gcloud CLI, Terraform, Helm
* **Description**: `Decom.cluster.01 GKE` with the decommission job running at 27m and the guard job already green. The gke-gcloud-auth-plugin step is expanded showing the gcloud CLI and plugin install, followed by the Terraform, kubectl, Helm and yq setup steps.

![342 - Decom Cluster Teardown Toolchain Setup Steps](./342_Decom_Cluster_Teardown_Toolchain_Setup_Steps.png)

---

### 343 - Tear Down The Stack Script Log Detail
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Kubernetes, Helm, ArgoCD, Gateway API
* **Description**: The `scripts/down.sh` step deleting PodDisruptionBudgets and every mutating/validating webhook config (including the binauthz admission controller) to avoid namespace-deletion deadlocks, then removing the ArgoCD apps, uninstalling 14 Helm releases in parallel and dropping the Gateway API objects.

![343 - Tear Down The Stack Script Log Detail](./343_Tear_Down_The_Stack_Script_Log_Detail.png)

---

### 344 - Decommission Tear Down Then Terraform Destroy
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Kubernetes, GKE NEGs, Terraform, CloudNativePG
* **Description**: The teardown job after `down.sh` has force-deleted namespaces and released the container-native load-balancer NEGs, with the Terraform destroy of the cluster, VPC and node pool just starting.

![344 - Decommission Tear Down Then Terraform Destroy](./344_Decommission_Tear_Down_Then_Terraform_Destroy.png)

---

### 345 - Terraform Destroy Complete 42 Resources Destroyed
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Terraform, GKE, VPC, Google Cloud APIs
* **Description**: The Terraform destroy step with the GKE cluster destroyed after 8m 46s, then the subnet, VPC and the project service APIs (Cloud KMS, Binary Authorization, Container Analysis, Mesh), ending "Destroy complete! Resources: 42 destroyed".

![345 - Terraform Destroy Complete 42 Resources Destroyed](./345_Terraform_Destroy_Complete_42_Resources_Destroyed.png)

---

### 346 - Decommission Revoking Grafana Cloud Access Tokens
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Terraform, Grafana Cloud, GCS remote state
* **Description**: The tail of a succeeded teardown showing the grafana-cloud-token module steps: GCS backend config, init and the destroy that revokes the Grafana Cloud access policy and tokens, followed by the decommissioned summary.

![346 - Decommission Revoking Grafana Cloud Access Tokens](./346_Decommission_Revoking_Grafana_Cloud_Access_Tokens.png)

---

### 347 - Decom Cluster Run Succeeded Step Summary
* **Category**: `300: CI Engine (GitHub Actions and ARC)`
* **Key Technologies & Components**: Terraform, GKE, Grafana Cloud, CSI
* **Description**: `Decom.cluster.01 GKE` finished green in 42m 4s with every step checked. The long poles are `down.sh` at 30m 16s and the Terraform destroy at 10m 45s, followed by the orphaned PersistentVolume disk sweep and the Grafana Cloud token revocation.

![347 - Decom Cluster Run Succeeded Step Summary](./347_Decom_Cluster_Run_Succeeded_Step_Summary.png)

---

</details>

<details>
<summary>📂 Expand 400: CI Engine (Argo Workflows) (4 Screenshots)</summary>

### 401 - Argo Workflows List Of Succeeded CI Runs
* **Category**: `400: CI Engine (Argo Workflows)`
* **Key Technologies & Components**: Argo Workflows, Kubernetes, JHipster, k6
* **Description**: The Argo Workflows Workflows list filtered to the `argo-ci` namespace, showing three green Succeeded runs: `gateway-stable` (19/19, 16m 8s), `jhipstersamplemicroservice-stable` (19/19, 14m 19s) and the k6 smoke (3/3, 2m 38s).

![401 - Argo Workflows List Of Succeeded CI Runs](./401_Argo_Workflows_List_Of_Succeeded_CI_Runs.png)

---

### 402 - Argo Workflows Graph For Gateway Stable Build
* **Category**: `400: CI Engine (Argo Workflows)`
* **Key Technologies & Components**: Argo Workflows, Semgrep, CodeQL, Trivy
* **Description**: The Workflow Details graph view of a completed `gateway-stable` run with every node green: fetch-source, semgrep, scan, upload-sarif, codeql, analyze and trivy-iac. The toolbar exposes Resubmit, Logs and Open Workflow Template.

![402 - Argo Workflows Graph For Gateway Stable Build](./402_Argo_Workflows_Graph_For_Gateway_Stable_Build.png)

---

### 403 - Argo Workflows Timeline And Node Summary
* **Category**: `400: CI Engine (Argo Workflows)`
* **Key Technologies & Components**: Argo Workflows, Trivy, Jib, Kaniko, GKE
* **Description**: The timeline (Gantt) view of a microservice run showing sequential steps from fetch-source through scan, analyze, clone-gitops, trivy-config, build-test and build-jib to the pending build-kaniko and build-sign rows. The Summary panel details the selected pod node, its phase, duration and GKE node.

![403 - Argo Workflows Timeline And Node Summary](./403_Argo_Workflows_Timeline_And_Node_Summary.png)

---

### 404 - Argo Workflows Expanded Rows With Platform Labels
* **Category**: `400: CI Engine (Argo Workflows)`
* **Key Technologies & Components**: Argo Workflows, Kubernetes labels, k6, GitOps
* **Description**: The Workflows list with rows expanded to show conditions, resource duration and labels: a k6 smoke Succeeded while `gateway-stable` and a microservice run are still Running. Visible labels include `jenkins2026.io/env=stable` and `jenkins2026.io/service=gateway`.

![404 - Argo Workflows Expanded Rows With Platform Labels](./404_Argo_Workflows_Expanded_Rows_With_Platform_Labels.png)

---

</details>

<details>
<summary>📂 Expand 500: GitOps and In-Cluster Admin (6 Screenshots)</summary>

### 501 - ArgoCD Applications All Synced On Develop
* **Category**: `500: GitOps and In-Cluster Admin`
* **Key Technologies & Components**: ArgoCD, GitOps, Helm, CloudNativePG
* **Description**: The ArgoCD Applications tiles view showing all 16 platform and workload apps Healthy and Synced, with the repo-sourced apps tracking the `develop` target revision and sidebar counters reading 16 Synced / 16 Healthy and zero OutOfSync or Degraded.

![501 - ArgoCD Applications All Synced On Develop](./501_ArgoCD_Applications_All_Synced_On_Develop.png)

---

### 502 - ArgoCD Seventeen Applications Healthy Tracking Main
* **Category**: `500: GitOps and In-Cluster Admin`
* **Key Technologies & Components**: ArgoCD, GitOps, Helm, cert-manager
* **Description**: The same dashboard after promotion to `main`, now listing 17 apps (the develop set plus cert-manager, the in-cluster CA for backend TLS), every tile Healthy and Synced against target revision `main`.

![502 - ArgoCD Seventeen Applications Healthy Tracking Main](./502_ArgoCD_Seventeen_Applications_Healthy_Tracking_Main.png)

---

### 503 - Headlamp Workloads Overview With Cluster Health Donuts
* **Category**: `500: GitOps and In-Cluster Admin`
* **Key Technologies & Components**: Headlamp, Kubernetes, GKE, JHipster
* **Description**: Headlamp's Workloads overview with donut gauges for Pods (96 running), Deployments (37), StatefulSets (7), DaemonSets, ReplicaSets and CronJobs. The table lists 142 workloads including the microservices ReplicaSets, the Jenkins StatefulSet, Backstage and the observability stack.

![503 - Headlamp Workloads Overview With Cluster Health Donuts](./503_Headlamp_Workloads_Overview_With_Cluster_Health_Donuts.png)

---

### 504 - Headlamp Gateway API View Showing Platform Ingress
* **Category**: `500: GitOps and In-Cluster Admin`
* **Key Technologies & Components**: Headlamp, Gateway API, GKE
* **Description**: Headlamp's Gateway (beta) section listing the single `jenkins-2026-gateway` in the `platform-ingress` namespace on the `gke-l7-global-external-managed` GatewayClass with an Accepted condition. The sidebar exposes the related HTTPRoute and BackendTLSPolicy kinds.

![504 - Headlamp Gateway API View Showing Platform Ingress](./504_Headlamp_Gateway_API_View_Showing_Platform_Ingress.png)

---

### 505 - pgAdmin Browsing Stable Microservice CNPG Database
* **Category**: `500: GitOps and In-Cluster Admin`
* **Key Technologies & Components**: pgAdmin, PostgreSQL, CloudNativePG, Liquibase
* **Description**: pgAdmin's Object Explorer connected to the Stable server group, drilled into the `jhipstersamplemicroservice` database's public schema and its `bank_account` plus Liquibase changelog tables. The right pane shows the server Dashboard activity graphs and the tree confirms the CNPG standby replicas and pooler roles.

![505 - pgAdmin Browsing Stable Microservice CNPG Database](./505_pgAdmin_Browsing_Stable_Microservice_CNPG_Database.png)

---

### 506 - JHipster Sample Gateway Application Homepage
* **Category**: `500: GitOps and In-Cluster Admin`
* **Key Technologies & Components**: JHipster, Angular, Java, Spring Boot
* **Description**: The deployed demo application itself: the JhipsterSampleGateway home page served by the Java gateway, rendering the Angular SPA's "Welcome, Java Hipster!" landing view in its anonymous state. This is the end-user-facing product of the whole pipeline.

![506 - JHipster Sample Gateway Application Homepage](./506_JHipster_Sample_Gateway_Application_Homepage.png)

---

</details>

<details>
<summary>📂 Expand 600: GKE and Google Cloud Console (4 Screenshots)</summary>

### 601 - GKE Cluster Nodes Tab With NAP Overflow Node
* **Category**: `600: GKE and Google Cloud Console`
* **Key Technologies & Components**: GKE, Node Auto-Provisioning, Container-Optimized OS
* **Description**: Kubernetes Engine, cluster `jenkins-2026`, Nodes tab: the static `jenkins-2026-pool` (e2-standard-8, 3 nodes) alongside an auto-provisioned `nap-e2-standard-2` pool. A banner reports 5 cluster scaling problems, and the node table shows the tiny NAP node at 1.25 of 1.93 CPU already requested.

![601 - GKE Cluster Nodes Tab With NAP Overflow Node](./601_GKE_Cluster_Nodes_Tab_With_NAP_Overflow_Node.png)

---

### 602 - GKE Workloads List Of Full Platform Plane
* **Category**: `600: GKE and Google Cloud Console`
* **Key Technologies & Components**: GKE, ArgoCD, Backstage, CloudNativePG, OpenTelemetry
* **Description**: Kubernetes Engine, Workloads overview filtered to non-system objects, listing all 38 user workloads and every one OK or Running. Spans the ArgoCD control plane, Backstage and its database, cert-manager, External Secrets, Headlamp, pgAdmin, the Jenkins StatefulSet, the OTel collectors and both microservices with their three-replica Postgres clusters.

![602 - GKE Workloads List Of Full Platform Plane](./602_GKE_Workloads_List_Of_Full_Platform_Plane.png)

---

### 603 - GKE Persistent Volume Claims For Platform And Microservices
* **Category**: `600: GKE and Google Cloud Console`
* **Key Technologies & Components**: GKE, PersistentVolumeClaims, CloudNativePG, Backstage
* **Description**: Kubernetes Engine, Storage, Persistent Volume Claims: all 14 PVCs in the cluster, every one Bound. Includes Jenkins and pgAdmin on `standard-rwo` plus the CloudNativePG data and WAL pairs for both three-replica Postgres clusters on `premium-rwo`.

![603 - GKE Persistent Volume Claims For Platform And Microservices](./603_GKE_Persistent_Volume_Claims_For_Platform_And_Microservices.png)

---

### 604 - GKE Workloads Observability CPU Dashboard
* **Category**: `600: GKE and Google Cloud Console`
* **Key Technologies & Components**: GKE, Cloud Monitoring, OpenTelemetry Collector
* **Description**: Kubernetes Engine, Workloads, Observability tab with the CPU section selected: last-hour charts for CPU request utilization, cores used, cores requested and unused requested cores across the top workloads, covering the OTel collector and logs agent, the managed Prometheus collector and Jenkins build pods.

![604 - GKE Workloads Observability CPU Dashboard](./604_GKE_Workloads_Observability_CPU_Dashboard.png)

---

</details>

<details>
<summary>📂 Expand 700: Observability (In-Cluster OSS) (9 Screenshots)</summary>

### 701 - Grafana CI CD Observability Folder Dashboard Listing
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, provisioned dashboards, OpenTelemetry, Prometheus
* **Description**: The in-cluster Grafana Dashboards browser listing the provisioned CI-CD Observability folder: DORA Metrics, Jenkins Controller, k6 Observability, Microservices Overview, Node Auto-Provisioning (Spot), PostgreSQL (CloudNativePG), Frontend RUM and JVM internals, each with its tag set.

![701 - Grafana CI CD Observability Folder Dashboard Listing](./701_Grafana_CI_CD_Observability_Folder_Dashboard_Listing.png)

---

### 702 - Grafana Microservices Overview With RED Golden Signals
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, Prometheus, OpenTelemetry, Tempo span metrics
* **Description**: The Microservices Overview board scoped to the stable tier: 2 services reporting, 0.9 req/s, 0.00% 5xx error rate and latency p50/p95/p99 of 7.4 / 9.8 / 12.9 ms. Lower sections show HTTP status codes, top routes, span metrics from traces, the gateway-to-microservice dependency graph and per-service JVM panels.

![702 - Grafana Microservices Overview With RED Golden Signals](./702_Grafana_Microservices_Overview_With_RED_Golden_Signals.png)

---

### 703 - Grafana DORA Metrics Dashboard With Four Headline Stats
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, Prometheus, ArgoCD, DORA metrics
* **Description**: The engine-neutral DORA Metrics board, led by a "how to read this" panel with the canonical-metric versus proxy table and the elite/high performance bands, above the four headline stats. Below sit deployments per day, the lead-time p50/p95 trend, sync outcomes by phase and an `argocd_app_info` table.

![703 - Grafana DORA Metrics Dashboard With Four Headline Stats](./703_Grafana_DORA_Metrics_Dashboard_With_Four_Headline_Stats.png)

---

### 704 - Grafana Jenkins Controller Dashboard With Agent Metrics
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, Prometheus, Jenkins, OpenTelemetry plugin
* **Description**: The Jenkins Controller board: build success rate, builds completed and failed, agents online and cloud agent pods, then pipeline run outcomes, run-duration percentiles, ephemeral Kubernetes build agents with executor and queue states, and controller JVM heap, GC pause p99 and live threads.

![704 - Grafana Jenkins Controller Dashboard With Agent Metrics](./704_Grafana_Jenkins_Controller_Dashboard_With_Agent_Metrics.png)

---

### 705 - Grafana Tekton CI Observability Dashboard
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, Prometheus, Tempo, OpenTelemetry, Tekton
* **Description**: The per-engine Tekton CI Observability board tracking the Tekton Pipelines controller: 0 failed PipelineRuns, 25 total TaskRuns, mean PipelineRun duration 16.5 mins and a 100% success rate. Lower rows show the outcome donut, top pipelines by volume, Tekton pod logs and a traces table.

![705 - Grafana Tekton CI Observability Dashboard](./705_Grafana_Tekton_CI_Observability_Dashboard.png)

---

### 706 - Grafana JVM Internals Dashboard For Java Services
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, OpenTelemetry Java agent, Prometheus, Loki, Tempo
* **Description**: The JVM Internals board covering all Java microservices plus the Jenkins controller: JVM CPU load, heap used, live threads and GC time per second, then G1 collection detail, heap versus non-heap, memory pools, HTTP latency, a runtime-context table and correlated Loki logs beside Tempo traces.

![706 - Grafana JVM Internals Dashboard For Java Services](./706_Grafana_JVM_Internals_Dashboard_For_Java_Services.png)

---

### 707 - Grafana PostgreSQL CloudNativePG Cluster Health Dashboard
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, Prometheus, CloudNativePG, PostgreSQL
* **Description**: The PostgreSQL (CloudNativePG) board: 6 instances up, 2 primaries, 2 streaming replicas, 48 connections, 0s max replication lag and a 100% cache hit ratio. Sections cover connections by state, commits versus rollbacks, tuple operations, WAL bytes and checkpoints, and streaming replication lag.

![707 - Grafana PostgreSQL CloudNativePG Cluster Health Dashboard](./707_Grafana_PostgreSQL_CloudNativePG_Cluster_Health_Dashboard.png)

---

### 708 - Grafana Node Auto Provisioning Spot CI Nodes Dashboard
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana, GKE Node Auto-Provisioning, Spot VMs, ComputeClass
* **Description**: The Node Auto-Provisioning (Spot) board demonstrating the scale-to-zero CI cost model, with the cluster idle: 3 total nodes, 0 Spot CI nodes, 0 ci-spot ComputeClass nodes and 3 static platform nodes. The inventory table tags each node Spot/NAP or Static.

![708 - Grafana Node Auto Provisioning Spot CI Nodes Dashboard](./708_Grafana_Node_Auto_Provisioning_Spot_CI_Nodes_Dashboard.png)

---

### 709 - Grafana Frontend RUM Angular Faro Core Web Vitals
* **Category**: `700: Observability (In-Cluster OSS)`
* **Key Technologies & Components**: Grafana Faro, Loki, Angular SPA, Core Web Vitals
* **Description**: The Frontend RUM (Angular / Faro) board for the angular-gateway app: 632 sessions, 124 exceptions and p75 Core Web Vitals of LCP 2.54s, INP 249ms, CLS 0.12, FCP 1.62s, TTFB 618ms. The pass-rate tiles are red/amber and the exceptions log is dominated by one recurring TypeError across four browsers.

![709 - Grafana Frontend RUM Angular Faro Core Web Vitals](./709_Grafana_Frontend_RUM_Angular_Faro_Core_Web_Vitals.png)

---

</details>

<details>
<summary>📂 Expand 800: Observability (Managed and Cloud) (9 Screenshots)</summary>

### 801 - Grafana Cloud JVM Internals Dashboard
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Grafana Cloud, OpenTelemetry, JVM, Loki, Tempo
* **Description**: The same JVM Internals board rendered in Grafana Cloud against the hosted `grafanacloud-*-prom/-logs/-traces` datasources, with overview stats, GC, heap, memory-pool and HTTP-latency sections. The bottom correlates the OTel-agent runtime inventory with Loki errors and Tempo traces.

![801 - Grafana Cloud JVM Internals Dashboard](./801_Grafana_Cloud_JVM_Internals_Dashboard.png)

---

### 802 - Amazon Managed Grafana CICD Observability Folder Index
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, dashboard provisioning, Prometheus
* **Description**: The CI-CD Observability folder listing in Amazon Managed Grafana with all twelve provisioned dashboards and their tags, including the four Kubernetes Views boards and Node Exporter Full. Proves the same dashboards land identically in a managed workspace.

![802 - Amazon Managed Grafana CICD Observability Folder Index](./802_Amazon_Managed_Grafana_CICD_Observability_Folder_Index.png)

---

### 803 - Amazon Managed Grafana DORA Metrics Dashboard
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, ArgoCD, DORA metrics, Prometheus
* **Description**: The engine-neutral DORA Metrics board over the last 7 days, anchored on ArgoCD sync metrics: deployment frequency 2, lead time p50 (Jenkins) 1.8 mins, change failure rate 0.0% and time to restore 9 min. In-board panels define each metric's PromQL proxy and trust boundary.

![803 - Amazon Managed Grafana DORA Metrics Dashboard](./803_Amazon_Managed_Grafana_DORA_Metrics_Dashboard.png)

---

### 804 - Amazon Managed Grafana Microservices Overview Dashboard
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, Amazon Managed Prometheus, OpenTelemetry
* **Description**: The Microservices Overview board for the stable tier: edge latency percentiles, a JVM summary for the gateway and Kubernetes pod/container infra panels with zero pod restarts. The lower half stitches in ArgoCD pod logs and a recent-traces table of health-endpoint GETs returning 200.

![804 - Amazon Managed Grafana Microservices Overview Dashboard](./804_Amazon_Managed_Grafana_Microservices_Overview_Dashboard.png)

---

### 805 - Amazon Managed Grafana CloudNativePG PostgreSQL Dashboard
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, Amazon Managed Prometheus, CloudNativePG
* **Description**: The PostgreSQL (CloudNativePG) board off the `amazon-managed-prometheus` datasource, with replication (4 replica WAL receivers up, 4 active slots), storage and XID-wraparound panels, and WAL-archiving panels reading "no backups configured". A Postgres log stream fed by the OTel collector fills the bottom.

![805 - Amazon Managed Grafana CloudNativePG PostgreSQL Dashboard](./805_Amazon_Managed_Grafana_CloudNativePG_PostgreSQL_Dashboard.png)

---

### 806 - Amazon Managed Grafana GKE Spot Node Autoprovisioning Dashboard
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, GKE Node Auto-Provisioning, Spot VMs
* **Description**: The Node Auto-Provisioning (Spot) elasticity board rendered from the managed workspace, with the cluster idle at 4 total nodes and 0 Spot CI nodes. The node-detail inventory distinguishes the `nap-e2` Spot/NAP entries from the static pool nodes.

![806 - Amazon Managed Grafana GKE Spot Node Autoprovisioning Dashboard](./806_Amazon_Managed_Grafana_GKE_Spot_Node_Autoprovisioning_Dashboard.png)

---

### 807 - Amazon Managed Grafana Kubernetes Global Cluster View
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, Prometheus, Kubernetes, GKE
* **Description**: The Kubernetes Views Global board for the cluster: 9.34% real CPU against 43.5% requests and 310% limits, 19.03% real RAM, 4 nodes, 22 namespaces and 97 running pods, with breakdowns highlighting jenkins, microservices, kube-system and backstage as top consumers.

![807 - Amazon Managed Grafana Kubernetes Global Cluster View](./807_Amazon_Managed_Grafana_Kubernetes_Global_Cluster_View.png)

---

### 808 - Amazon Managed Grafana Kubernetes Namespaces View
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, Prometheus, kube-state-metrics
* **Description**: The Kubernetes Views Namespaces board: 6.12% of cluster CPU and 18.98% of RAM in use, plus per-pod CPU and memory, CPU throttling, QoS class and pod-state panels. OOM events show no data and the only container restarts come from the pgAdmin pod.

![808 - Amazon Managed Grafana Kubernetes Namespaces View](./808_Amazon_Managed_Grafana_Kubernetes_Namespaces_View.png)

---

### 809 - Amazon Managed Grafana Provisioned CICD Alert Rules
* **Category**: `800: Observability (Managed and Cloud)`
* **Key Technologies & Components**: Amazon Managed Grafana, Grafana Alerting, ArgoCD, CloudNativePG
* **Description**: The Alerting rules page showing all 6 provisioned rules in the `CI-CD Observability > jenkins-2026` group: Microservice Pod NotReady, ArgoCD Application Degraded, CNPG PostgreSQL Pod NotReady, High HTTP 5xx Error Rate, JVM Heap Above 85% and OTel Collector Memory Above 70%. The first is expanded showing its evaluation interval, labels and datasource.

![809 - Amazon Managed Grafana Provisioned CICD Alert Rules](./809_Amazon_Managed_Grafana_Provisioned_CICD_Alert_Rules.png)

---

</details>

> [!TIP]
> Each screenshot is named systematically (`NNN_Title.png`) to guarantee the folder stays sorted by category. The hundreds digit is the category band; sequence within a band is insertion order.
