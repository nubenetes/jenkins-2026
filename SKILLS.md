# Developer Skills Guide - jenkins-2026

This document lists the core scripting workflows and capabilities (or "skills") available in the `jenkins-2026` repository. Use this to quickly perform operational tasks on the Kubernetes cluster.

---

## 🛠️ System Orchestration Skills

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
*   **Implications:** Deploys namespaces `jenkins`, `observability`, `argocd`, `pgadmin`, `headlamp`, `microservices` (+ the gateway namespace; `tekton`/`tekton-pipelines`/`pipelines-as-code` when `ci.engine=tekton`). Sets up IAP OAuth secrets.

### Skill 3: Deploy the OpenTelemetry Operator
Ensures the mutating webhook and CRDs are running before deployment of microservices or observability.
*   **Command:**
    ```bash
    ./scripts/02-otel-operator.sh
    ```

### Skill 4: Provision Grafana Cloud Observability Gateway
Deploys the OTel collector and agents, and logs collectors.
*   **Command:**
    ```bash
    ./scripts/03-observability.sh
    ```

### Skill 5: Deploys Jenkins with JCasC configuration
Deploys the Jenkins Helm chart. Jenkins is configured with JCasC ([`jenkins/casc/jcasc-base.yaml`](jenkins/casc/jcasc-base.yaml)) to set up credentials, shared libraries, and seed jobs.
*   **Command:**
    ```bash
    ./scripts/04-jenkins.sh
    ```

### Skill 6: Provision ArgoCD
Deploys and configures ArgoCD to reconcile the GitOps repo.
*   **Command:**
    ```bash
    ./scripts/08.5-argocd.sh
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
