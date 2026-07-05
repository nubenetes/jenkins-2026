# Developer Skills Guide - jenkins-2026

This document lists the core scripting workflows and capabilities (or "skills") available in the `jenkins-2026` repository. Use this to quickly perform operational tasks on the Kubernetes cluster.

---

## 🛠️ System Orchestration Skills

Skills 1–7 follow the real dependency order [`scripts/up.sh`](scripts/up.sh) runs the steps in
(00 → 01 → 02 → 08.5 → 08.6 → 03 → 04-`<engine>` → 06-`<engine>` → 07 → 07.5 → 08 → 09) —
in particular ArgoCD (Skill 4) must precede observability (Skill 5) and the CI engine (Skill 6).

### Skill 1: Validate Prerequisites & Register Helm Repositories
Use this to ensure all required CLI tools are present and configure Helm charts before deployment.
*   **Command:**
    ```bash
    ./scripts/00-check-prereqs.sh
    ```
*   **Implications:** Modifies local Helm repository configuration.

### Skill 2: Create Core Namespaces & Secrets
Deploys namespaces and bootstrap credentials.
*   **Command:**
    ```bash
    ./scripts/01-namespaces.sh
    ```
*   **Implications:** Deploys the engine-neutral namespaces `platform-ingress` (gateway), `observability`, `headlamp`, `microservices`, `argocd`, `pgadmin` (+ `microservices-develop` when the develop track is on), plus the active CI engine's namespaces: `jenkins` (ci.engine=jenkins) · `tekton-pipelines`/`tekton-ci`/`pipelines-as-code` (tekton) · `arc-systems`/`arc-runners` (githubactions) · `argo`/`argo-events`/`argo-ci` (argoworkflows). Sets up IAP OAuth secrets.

### Skill 3: Deploy the OpenTelemetry Operator
Ensures the mutating webhook and CRDs are running before deployment of microservices or observability.
*   **Command:**
    ```bash
    ./scripts/02-otel-operator.sh
    ```

### Skill 4: Provision ArgoCD
Deploys and configures ArgoCD to reconcile the GitOps repo. Must run BEFORE `03-observability.sh` (oss mode applies the `observability-oss` ArgoCD app-of-apps) and before any `04-<engine>.sh` (each applies an ArgoCD `Application`).
*   **Command:**
    ```bash
    ./scripts/08.5-argocd.sh
    ```

### Skill 5: Provision the Observability Backend
Deploys the OTel collector gateway + logs DaemonSet for the active `observability.mode` (grafana-cloud | oss | managed-azure | managed-aws); in oss mode it applies the `observability-oss` ArgoCD app-of-apps (requires ArgoCD, Skill 4, to have run first).
*   **Command:**
    ```bash
    ./scripts/03-observability.sh
    ```

### Skill 6: Deploy the Active CI Engine (Jenkins default)
Applies the Jenkins ArgoCD `Application` ([`argocd/jenkins-app.yaml`](argocd/jenkins-app.yaml), the official chart) configured with JCasC ([`jenkins/casc/jcasc-base.yaml`](jenkins/casc/jcasc-base.yaml)) to set up credentials, shared libraries, and seed jobs — requires ArgoCD (Skill 4) to be provisioned first. When `ci.engine` is tekton/githubactions/argoworkflows, run `04-tekton.sh` / `04-githubactions.sh` / `04-argoworkflows.sh` instead (each retires the other three engines).
*   **Command:**
    ```bash
    ./scripts/04-jenkins.sh
    ```

### Skill 7: Deploy API Gateway Routing
Sets up GKE Gateway API resources, including HTTPRoutes and health check policies.
*   **Command:**
    ```bash
    ./scripts/09-gateway.sh
    ```

---

## 🔍 Validation and Troubleshooting Skills

### Skill 8: Check Cluster Health and Rollout Status
Displays the deployment, pods, and route endpoints.
*   **Command:**
    ```bash
    ./scripts/status.sh
    ```

### Skill 9: Run Automated E2E Smoke Tests
Runs standard post-deployment integration tests to verify connectivity of components.
*   **Command:**
    ```bash
    ./test/smoke-test.sh
    ```

### Skill 10: Clean Teardown
Gracefully uninstalls all Helm releases, services, and namespaces to avoid cloud costs.
*   **Command:**
    ```bash
    ./scripts/down.sh
    ```
