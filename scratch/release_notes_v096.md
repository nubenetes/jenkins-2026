# Release Notes: v0.9.6

We are pleased to announce the release of **v0.9.6** for the Jenkins-2026 stack! This release introduces an Architecture Decision Record (ADR) detailing the design rationale of using Helm Charts over Kustomize for deploying the microservices stack.

---

## 🚀 What's New in v0.9.6

### 1. GitOps Design Decision (Helm vs. Kustomize) ADR
* Added a new section **GitOps Design Decision: Helm vs. Kustomize** in `README.md`.
* Documents the comparative matrix table across DRY compliance, platform portability, microservice provisioning ease, and upgrade overhead.
* Details the technical rationale behind Helm's loop-based dynamic manifests, platform conditional formats, and pipeline yq tag updates.
