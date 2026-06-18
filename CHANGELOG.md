# Changelog

All notable changes to this project will be documented in this file.

## [v0.10.1] - 2026-06-18

### Added
- **Spanish Multimedia Guide (via NotebookLM)**:
  - Added Spanish video walkthrough: `Fabrica_DevOps_jenkins-2026_Spanish.mp4`.
  - Added Spanish audio explanation: `Infraestructura_completa_por_veinte_céntimos_Spanish.m4a`.
  - Updated `README.md` with explicit English/Spanish labels for all multimedia resources.

## [v0.10.0] - 2026-06-18

### Added
- **Visual & Multimedia Repo Guide (via NotebookLM)**:
  - Integrated a new multimedia section in `README.md` powered by Google's NotebookLM.
  - Added a high-level infographic (`Modern_Automation_and_Observability_Architecture.jpg`).
  - Added a video proof of concept (`Jenkins-2026_PoC.mp4`).
  - Added a detailed technical PDF (`Jenkins_GitOps_Reimagined.pdf`).
  - Added an audio walkthrough of ephemeral GitOps concepts (`Twenty_cent_ephemeral_GitOps_in_2026.m4a`).
- **Operational Stability & Auth Lifecycle**:
  - Finalized ArgoCD token generation refactoring to resolve Jenkins startup race conditions.
  - Standardized Mermaid diagram optimizations across all documentation.

## [v0.9.16] - 2026-06-18

### Fixed
- **GitOps Jenkins Auth & Lifecycle**:
  - Refactored `scripts/08.5-argocd.sh` to unconditionally configure the local `jenkins` account in ArgoCD and generate its API token even when Google OIDC/Gateway is disabled.
  - Swapped execution order in `scripts/up.sh` so that `08.5-argocd.sh` runs before `04-jenkins.sh`. This ensures the Jenkins pod mounts the `ARGOCD_AUTH_TOKEN` correctly on initial startup.
  - Added an automatic recovery check to restart the Jenkins pod if it is running but lacks the `ARGOCD_AUTH_TOKEN` environment variable.
  - Made the `microservicesDeploy.groovy` pipeline step robust against unset parameters under bash `set -u` by using `ARGOCD_AUTH_TOKEN:-`.

## [v0.9.15] - 2026-06-18

### Fixed
- **Documentation**:
  - Further refined text wrapping on GKE/GCP labels in the decommission lifecycle Mermaid diagram to prevent horizontal cutoff of long phrases (e.g. "GCP Network Endpoint Group").

## [v0.9.14] - 2026-06-18

### Fixed
- **Documentation**:
  - Refined the lifecycle decommission Mermaid diagram to use newline `<br/>` tags and standard `-->|label|` links to prevent horizontal text overflow and rendering cutoff.

## [v0.9.13] - 2026-06-18

### Fixed
- **Documentation**:
  - Quoted the subgraph labels containing parentheses in the lifecycle decommission Mermaid diagram to resolve parser error and ensure correct rendering on GitHub.

## [v0.9.12] - 2026-06-18

### Changed
- **Documentation**:
  - Wrapped all 10 Mermaid diagrams in the `README.md` file in collapsible `<details>` blocks to optimize page rendering performance, eliminate loading latency, and improve document readability.

## [v0.9.11] - 2026-06-18

### Added
- **Documentation**:
  - Added the detailed lifecycle and decommission orchestration design decision to `README.md`, including a side-by-side comparison matrix and architecture diagram.

## [v0.9.10] - 2026-06-18

### Fixed
- **Teardown Automation**:
  - Added GCP Network Endpoint Groups (NEGs) wait and force-cleanup logic to `scripts/down.sh`. This prevents `terraform destroy` failures caused by orphaned NEGs blocking the deletion of the VPC network when GKE services are uninstalled.

## [v0.9.9] - 2026-06-18

### Added
- **Observability**:
  - Added the Grafana Cloud Kubernetes Infrastructure monitoring application link (`/a/grafana-k8s-app`) to the Jenkins systemMessage banner.

## [v0.9.8] - 2026-06-18

### Fixed
- **GitOps Push Authentication**:
  - Resolved `exit code 128` (authentication failed) in `microservicesDeploy.groovy` during the `git push origin main` stage.
  - Configured GKE cluster `jenkins-credentials` Secret dynamic mappings for `git-username` and `git-token` to properly authenticate Jenkins pipelines.
  - Documented requirements for configuring `GIT_USERNAME` and `GIT_TOKEN` as GitHub repository secrets in `README.md`.

## [v0.9.6] - 2026-06-17

### Added
- **GitOps Design Decision (Helm vs. Kustomize)**:
  - Documented the architectural decision comparing the current parameterized Helm loop-based microservices packaging versus a Kustomize-based overlay structure in `README.md`.

## [v0.9.5] - 2026-06-17

### Added
- **Environment Protection CLI Automation Documentation**:
  - Documented programmatic setup instructions in `README.md` to automate creating and configuring the `gke-production` environment and registering required reviewers via the GitHub CLI (`gh api`).

## [v0.9.4] - 2026-06-17

### Changed
- **Default Branch Transition to `main`**:
  - Configured `main` as the repository's default branch on GitHub, ensuring the GitHub Actions UI dropdown ("Use workflow from") defaults to the stable branch.
  - Updated the central config (`config/config.yaml`) to set `jenkins.selfRepoBranch` to `main` so that Jenkins JCasC resolves shared libraries and seed jobs from the stable branch.

## [v0.9.3] - 2026-06-17

### Added
- **Manual Approvals via GitHub Environments**:
  - Bound GKE provision (`02.01`), GKE decommission (`02.99`), Gateway decommission (`01.99`), and Grafana Cloud decommission (`01.98`) workflows to the `gke-production` environment.
  - Implemented environment protection rules requiring authorized reviewers' approval before executing sensitive GHA terraform applies and destroys.
- **Environment Protections Documentation**:
  - Documented environment config guidelines, required setup steps, and the cost control (FinOps) benefits in `README.md`.

## [v0.9.2] - 2026-06-17

### Changed
- **GHA Parameterized Fallback Mechanics**:
  - Refactored `git_ref` workflow inputs in all GKE pipelines to be optional (`required: false`) and default to empty (`""`).
  - Added logical fallback in checkout tasks (`inputs.git_ref || github.ref`) to use the native branch dropdown ("Use workflow from") if the text box is left blank, resolving interface conflicts.
- **Form Fields Documentation**:
  - Added a detailed user reference guide in `README.md` explaining every input field, type, default, and purpose on the GKE provision workflow form.

## [v0.9.1] - 2026-06-17

### Added
- **Manual SCM Reference Inputs in GitHub Actions**:
  - Parameterized GKE lifecycle workflows (`02.01`, `02.02`, `02.03`, and `02.99`) with a custom `git_ref` trigger input (defaults to `develop`) to support provisioning and decommissioning GKE using specific git branches, tags, or commit SHAs.
  - Configured repository SCM checkout tasks inside GHA workflows to dynamically bind to the selected input reference.
- **Vulnerability Visualization Documentation**:
  - Documented the Jenkins `warnings-ng` plugin configurations and user dashboards inside `README.md`.
- **Operational Version Pinning Guide**:
  - Added warnings and alignment instructions in `README.md` to prevent Terraform state conflicts and database operator secret mismatches during lifecycle runs.

## [v0.9.0] - 2026-06-17

### Added
- **Argo CD v3.5.0-rc1 baseline & Dynamic Upgrade Mechanism**:
  - Upgraded Argo CD installation baseline to `v3.5.0-rc1` (configured in `config/config.yaml`).
  - Added a dynamic patch version resolver (`resolve_argocd_version`) in `scripts/08.5-argocd.sh` to automatically check, resolve, and deploy the latest stable patch version within the `v3.5.x` lifecycle at deploy-time.
  - Implemented an in-cluster daily cronjob (`argocd-version-patch-watcher` in `argocd` namespace) that polls the GitHub releases API, compares versions, and automatically upgrades Argo CD if a newer `v3.5.x` patch version becomes available.
  - Standardized resource requests/limits on the `argocd-token-gen` pod (`128Mi` request, `256Mi` limit) and introduced robust wait conditions to prevent resource quota exhaustion during rollouts.
- **DevSecOps Multi-Layer Scanning in Pipelines**:
  - Integrated three scanning layers into the microservices build execution helper (`vars/microservicesBuild.groovy`): Semgrep, CodeQL, and Trivy.
  - Enabled checkout of the infrastructure repository on the agent's workspace to provision custom configuration files (`.semgrep.yaml`, etc.).
  - Configured git `safe.directory` rules in all agent containers to prevent dubious ownership issues during scanning.
  - Implemented dynamic curl installations in minimal git agent containers.
  - Added clickable GitHub Code Scanning URLs directly to pipeline log consoles for easy alert triaging.
  - Integrated the Jenkins `warnings-ng` plugin in `vars/microservicesBuild.groovy` to parse and visualize Semgrep and CodeQL SARIF scan results on the Jenkins build UI.
- **Headlamp Google OIDC SSO & GKE Hardening**:
  - Upgraded Headlamp to version `0.43.0` and enabled native Google OIDC SSO configuration.
  - Fixed an ID token verification failure (`Failed to verify ID Token: oidc: malformed jwt: oidc: malformed jwt payload: illegal base64 data`) by configuring verification via the Google OIDC `id_token` payload rather than the raw access token (`OIDC_USE_ACCESS_TOKEN=false` in secrets and Helm values).
  - Configured Headlamp to safely utilize the pod's service account token (`unsafeUseServiceAccountToken: true`) to authenticate API traffic with Google OIDC GKE compatibility.
  - Fixed a default Secret setting in `scripts/01-namespaces.sh` to set `OIDC_USE_ACCESS_TOKEN` to `"false"` by default, preventing future deployment OIDC breakages on fresh cluster provisioning.

### Changed
- **Pipeline Resource Optimization**:
  - Optimized agent JVM parameters by limiting the heap to `1.5G` (`-Xms512m -Xmx1524m`) and configuring the Serial Garbage Collector (`-XX:+UseSerialGC`) to prevent sudden agent OOM kills.
  - Set limits on Maven fork and surefire test processes (`-Dmaven.compiler.fork=true -DforkCount=1 -DreuseForks=true`) to avoid node memory starvation.
  - Set the `GOGC=20` garbage collection tuning parameter and raised memory limits to `3.5Gi` for Trivy container image scanning to prevent OOM kills.
  - Raised default Jenkins namespace `ResourceQuota` limits and optimized node pool capabilities to support high concurrent builds without bottlenecking.
- **Jenkins Maintenance & Stability**:
  - Pinned `configuration-as-code` (JCasC) and `pipeline-graph-view` plugins to latest stable versions.
  - Resolved 5 "Manage Jenkins" administrative and security alerts via updated JCasC global configurations.
- **GKE Node Pool Scaling**:
  - Upgraded GKE default worker node pool to `e2-standard-8` (and scaled up ResourceQuota in the `jenkins` namespace) to support concurrent build pipelines and OTel collector gateway resource requests.
- **Documentation cleanup**:
  - Pruned obsolete Crunchy Postgres, cross-platform EKS/AKS/OpenShift references, and deleted files (such as `docs/platforms.md`) from `README.md`, `CLAUDE.md`, and script logs.

## [v0.8.0] - 2026-06-17

### Added
- **GKE Cluster Observability**: Integrated the official `grafana/k8s-monitoring` Helm chart (v4.0+) to collect GKE cluster metrics, host/node metrics, and cluster events in `scripts/03-observability.sh`.
- **Automated Data Source Configuration**: Implemented automatic settings provisioning for the Grafana Kubernetes Monitoring app using `gcx api` inside `scripts/07-grafana-dashboards.sh` to pre-link Prometheus, Loki, and Tempo data sources.
- **Zero-Trust Hardening & Identity**: Documented Multi-User Identity vs DB User configurations in `README.md` and added OIDC write permission in GitHub Actions for secure dynamic secret resolution.
- **Compliance Validation Gate**: Added an automated compliance validation gate script (`test/validation_gate.sh`).

### Changed
- **Database Operator Migration**: Migrated database orchestration operator from Crunchy PGO to CloudNative-PG (CNPG) and updated corresponding playbooks, architecture diagrams, and runbooks.
- **pgAdmin Enhancements**: Restricted visible databases in pgAdmin via `DBRestriction` in `servers.json`, disabled the master password prompt, and corrected absolute passfile paths.
- **k6 Telemetry Overhaul**: Switched the k6 simulation exporter to OTLP/HTTP, formatted endpoints to exclude scheme/path prefixes, and updated the service name to `k6-microservices-smoke`.
- **Resource Quotas**: Increased `observability-quota` ResourceQuota limits (CPU limit: 6.0, memory limit: 10.0Gi) to accommodate the newly introduced telemetry collector and exporter daemons.
- **Dashboard Optimization**: Updated Grafana trace panels in Jenkins Overview, Microservices Overview, and k6 smoke test dashboards to use high-performance table views and filter out `/management/health` probe traces.

## [v0.7.2] - 2026-06-17

### Documentation
- **Table of Contents**: Added a comprehensive nested Table of Contents to the main `README.md`.

## [v0.7.1] - 2026-06-17

### Documentation
- **Mermaid Layout**: Corrected GKE node pool topology subgraph title overlap in README.

## [v0.7.0] - 2026-06-17

### Documentation
- **Cluster Topology**: Rewrote GKE Cluster Topology reference section in `README.md` for clearer documentation on Karpenter, subnets, and node types.

## [v0.6.9] - 2026-06-17

### Documentation
- **Mermaid Layout**: Shortened Workload Identity mapping node labels to prevent rendering cutoffs.

## [v0.6.8] - 2026-06-17

### Documentation
- **Mermaid Layout**: Aggressively shortened node labels across all architectural flowcharts.

## [v0.6.7] - 2026-06-17

### Documentation
- **Mermaid Layout**: Fixed text cutoff in all three main Mermaid diagrams.

## [v0.6.6] - 2026-06-17

### Fixes
- **Workflow Cleanup**: Added `gsutil rm` command to clear orphaned GCS state lock file before executing `terraform destroy` in GKE decommissioning.

## [v0.6.5] - 2026-06-17

### Fixes
- **ArgoCD namespace finalizer hang** (`scripts/down.sh`): Expanded `drain_namespace()` to strip object-level finalizers from **all** Terminating resources in a namespace before deletion — not just PVCs. This covers ArgoCD `Application` resources (which carry `resources-finalizer.argocd.argoproj.io`) that would hang forever once the ArgoCD controller is already uninstalled.
- **Terraform stale state lock** (`.github/workflows/02.99-gke-decommission.yml`): Added a `terraform force-unlock` step before `terraform destroy` to automatically clear any orphaned GCS state lock left by a previously cancelled run. Prevents `Error acquiring the state lock / conditionNotMet` failures on re-runs.

## [v0.6.3] - 2026-06-17

### Removed
- **GKE-Only Platform Scope**: Removed all non-GKE platform support to focus exclusively on Google Kubernetes Engine.
  - Deleted Helm values overrides for AKS (`values-aks.yaml`), EKS (`values-eks.yaml`), and OpenShift (`values-openshift.yaml`).
  - Deleted OpenShift Route template (`helm/jenkins/openshift/route.yaml`).
  - Deleted multi-platform documentation (`docs/platforms.md`).
  - Removed EKS, AKS, and OpenShift configuration blocks from `config/config.yaml`.
  - Removed platform-switching logic from `scripts/lib/config.sh`; `J2026_PLATFORM` is now hardcoded to `gke`.
  - Removed OpenShift-specific API server prerequisite checks from `scripts/00-check-prereqs.sh`.
  - Removed OpenShift Route deployment from `scripts/04-jenkins.sh`.
  - Removed OpenShift route cleanup from `scripts/down.sh`.

### Updated
- **README**: Overhauled prerequisites and introduction to reflect GKE-only deployment model.
- **Architecture Docs**: Updated `docs/architecture.md` to remove cross-platform references.
- **Shared Library**: Updated `vars/MicroservicesPipeline.groovy` and `vars/microservicesDeploy.groovy` to document `gke` as the only supported platform value.
- **CLAUDE.md**: Updated project scope description.

### Fixes
- **Stuck Namespace Termination** (`scripts/down.sh`): Replaced the naive `kubectl delete namespace --timeout=1m` with a `drain_namespace` helper that first strips `kubernetes.io/pvc-protection` finalizers from all PVCs in the namespace (the most common cause of `jenkins` and `headlamp` namespaces hanging in `Terminating`), then issues the delete with a 2-minute timeout, and — if the namespace is still stuck — patches the namespace `spec.finalizers` to `[]` via the `/finalize` sub-resource API to force the API server to release it.

## [v0.6.2] - 2026-06-17

### Fixes
- **Jenkins Kubernetes Cloud**: Restored the `kubernetes` cloud configuration in custom JCasC base configuration (`jenkins/casc/jcasc-base.yaml`). This resolves the pipeline execution failure (`ERROR: No Kubernetes cloud was found`) introduced by disabling `controller.JCasC.defaultConfig`.
- **Jenkins URL Configuration**: Defined `unclassified.location.url` dynamically in JCasC based on the new `JENKINS_PUBLIC_URL` environment variable, ensuring the correct URL is sent for Google OIDC login requests and resolving `redirect_uri_mismatch` errors.
- **pgAdmin Alpine Compatibility**: Fixed the pgAdmin `setup-pgpass` init container's wait loops to use a POSIX-compliant `while` loop, resolving Alpine `/bin/sh` compatibility errors (unsupported brace expansion `{1..30}`).
- **ArgoCD CLI Timeout & Script Fix**: Increased the `kubectl wait` pull timeout to `3m` in `scripts/08.5-argocd.sh` and resolved an undefined `log_debug` runtime error.
- **k6 Shared Library OpenTelemetry**: Updated the k6 runner in `vars/microservicesK6Smoke.groovy` to use the stable `-o opentelemetry` output flag instead of the deprecated `-o experimental-opentelemetry` flag.
- **Teardown Namespace Timeout**: Added a timeout to namespace deletion in `down.sh` to prevent hanging during stack destruction.

### Documentation
- **Workflow Architecture Diagrams**: Added detailed Mermaid flowchart diagrams in `README.md` illustrating the naming conventions and execution lifecycles of persistent bootstrap/decommission workflows (`01.01`, `01.02`, `01.98`, `01.99`) and GKE cluster provision/teardown lifecycles.
- **GKE Cluster Topology & FinOps**: Documented the GKE node pool configuration, network subnet topology, and cost optimization guidelines (FinOps) in `README.md`, including a Mermaid network layout diagram.

## [v0.6.1] - 2026-06-16

### Documentation
- **Bootstrapping Architecture**: Added a comprehensive section to the `README.md` explaining the lifecycle design separating persistent, account-level bootstrap resources (WIF, remote GCS state, persistent Grafana Cloud instances, and global static IP/SSL gateway configurations) from short-lived workload resources (GKE cluster, Helm releases).

## [v0.6.0] - 2026-06-16


### JHipster Microservices & GitOps Migration
- **JHipster Migration**: Migrated the microservices to official JHipster sample applications (Gateway and backend microservice).
- **Two-Repo GitOps Layout**: Configured continuous delivery via ArgoCD using a separate companion repository `jenkins-2026-gitops-config` to store manifests and reconcile image tags.
- **Pipeline Modernization**: Restored real Maven, Node.js, and Docker-in-Docker (DinD) build and push stages in the declarative shared library, removing mocks.

### PostgreSQL Operator & Automated Database Connections
- **Postgres Operator**: Integrated the Crunchy Data Postgres Operator (`postgres-operator`) via ArgoCD to manage Postgres databases natively.
- **Zero-Password pgAdmin Login**: Designed a secure automated pgAdmin database connection workflow:
  - Created a cross-namespace RBAC `Role` and `RoleBinding` (`pgadmin-secret-reader`) to grant the `pgadmin` ServiceAccount read-only access to Postgres credentials.
  - Implemented a `setup-pgpass` init container that dynamically queries credentials, escapes colons (`:`) and backslashes (`\`) for `.pgpass` formatting, and writes them with `0600` permissions.
  - Added a custom Python WSGI middleware copier in `config_local.py` that dynamically replicates the shared `pgpass` file into each user's specific storage directory (e.g. `inafev_gmail.com/pgpass`) on every request.
  - Preconfigured pgAdmin to auto-connect via SSL by setting `SSLMode` to `require`.

### Security, IAP, & Authentication
- **GKE Gateway & Google IAP**: Secured Jenkins, pgAdmin, and Headlamp endpoints behind GKE Gateway and Google Identity-Aware Proxy (IAP).
- **ArgoCD & Jenkins OIDC SSO**: Integrated Google OIDC login in Jenkins and ArgoCD (via Dex) with dynamic administrator mapping using the `J2026_JENKINS_OIDC_ADMIN_EMAIL` parameter.
- **Headlamp Hardening**: Disabled the broken Headlamp in-app OIDC buttons and documented secure token-based dashboard logins.

### Resource Management & Quotas
- **Concurrent Build Optimization**: Raised the `jenkins` namespace `ResourceQuota` limits (`limits.cpu: 14`, `limits.memory: 16Gi`) to prevent agent pod admission failures during concurrent gateway and microservice builds.
- **Resource Constraints**: Capped pgAdmin, Headlamp, and ArgoCD resource requests/limits and namespace quotas to avoid GKE auto-scaling and manage costs.

### Observability & Dashboards
- **Dashboards Refactoring**: Upgraded Jenkins Overview, Microservices Overview, and k6 smoke test Grafana dashboards.
- **Trace-to-Log Correlation**: Optimized Loki log query regex, Prometheus rate intervals, and trace-to-log correlation utilizing MDC `trace_id` logging.

### Documentation
- **Visual Flowcharts**: Added detailed Mermaid architecture, GitOps sync, and pgAdmin zero-password connection flow diagrams to `README.md`.
- **Reference Matrices**: Included comprehensive authentication, authorization, and GKE resource limit reference tables.

## [v0.5.0] - 2026-06-14


### Observability & Grafana Cloud Integration
- **gcx CLI GitOps**: Refactored dashboard deployment to use the native `gcx` CLI (`gcx resources push`) instead of raw API calls.
  - Implemented automated `gcx login --yes` to discover stack ID and namespace.
  - Automatically wraps raw JSON dashboards into Kubernetes-style `apiVersion: dashboard.grafana.app/v1` manifests.
  - Pushes both Folders and Dashboards declaratively with `--include-managed`.
- **Private Data Source Connect (PDC)**: Implemented Grafana PDC for secure Jenkins datasource access from Grafana Cloud.
- **Jenkins Datasource**: Added automated provisioning of the Jenkins datasource via Terraform.
- **Dashboard Portability**: Removed hardcoded cloud datasource names to ensure dashboards are fully portable between OSS and Cloud modes.
- **OTel Configuration**: Ensured consistent resource attributes and robust dashboard queries across metrics and traces.

### Script & Deployment Performance
- **Smart Polling**: Replaced blocking `helm --wait` commands with active explicit `kubectl rollout status` checks, implementing smart polling for resource readiness.
- **Sequential Execution**: Optimized the deployment scripts to run major steps (like observability) sequentially to avoid SSA conflicts and reduce debug log noise.
- **Helm Rollbacks**: Replaced deprecated `helm --atomic` with `--rollback-on-failure`.
- **StatefulSet Monitoring**: Fixed readiness checks to monitor `statefulset/jenkins` instead of `deployment/jenkins`.

### Documentation
- Updated `README.md` with detailed instructions for the new PDC, `gcx`, and MCP features.
- Documented mandatory Grafana Cloud manual setup steps and necessary permissions for the Jenkins plugin.
- Clarified the required token scopes and datasource information.

### Fixes
- **Terraform**: Fixed Grafana provider configuration to resolve client initialization errors and ensure proper use of service account tokens for instance-level resources.
- **Helm SSA**: Resolved Helm Server-Side Apply (SSA) conflicts by pre-deleting the `otel-collector-gateway` ConfigMap during redeployments.
