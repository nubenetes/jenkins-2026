# Changelog

All notable changes to this project will be documented in this file.

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
