# Release Notes: v0.10.0

We are pleased to announce the release of **v0.10.0** for the Jenkins-2026 stack! This release focuses on improving the reliability of the GitOps deployment lifecycle and resolving authentication dependency cycles.

---

## 🚀 What's New in v0.10.0

### 1. GitOps Jenkins Auth & Lifecycle Improvements
*   **Resolved Startup Dependency Cycle**: Refactored `08.5-argocd.sh` to unconditionally generate the Jenkins API token. This ensures that the Jenkins pod can mount the required `ARGOCD_AUTH_TOKEN` correctly on initial startup, even when OIDC is not yet fully configured.
*   **Sequential Bootstrapping**: Swapped the execution order in `up.sh` so that ArgoCD configuration precedes Jenkins deployment, guaranteeing auth token availability.
*   **Automated Recovery**: Added health checks to the Jenkins initialization to detect and restart the pod if it starts without a valid ArgoCD token.

### 2. Documentation & Visualization Polish
*   **Mermaid Diagram Optimization**: Refined all architectural diagrams (Lifecycle, Decommission, GKE Topology) with improved text wrapping and collapsible blocks to improve README rendering performance and readability.
*   **GitOps Robustness**: Enhanced pipeline shared libraries to handle unset parameters gracefully under strict shell modes.
