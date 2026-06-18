# Release Notes: v0.9.4

We are pleased to announce the release of **v0.9.4** for the Jenkins-2026 stack! This release completes the transition of the default repository and workflow branch to `main`, ensuring safe, consistent, and predictable manual triggers.

---

## 🚀 What's New in v0.9.4

### 1. Default Branch Transition to `main`
* **Workflow Dispatch Safety**: The repository's default branch on GitHub is now configured as `main`. This ensures that the native "Use workflow from" dropdown defaults to `main` when triggerable manual workflows are loaded, preventing accidental runs from the unstable `develop` branch.
* **Central Coordinate Alignment**: Updated `config/config.yaml` to set `jenkins.selfRepoBranch` to `main`. Jenkins Configuration-as-Code (JCasC) and the seed jobs will now check out and resolve global shared libraries and pipeline code from the stable `main` branch.
* **Consistent Checkout Fallback**: Parameterized workflows fallback seamlessly to `main` when manual inputs are left empty, matching the default Git checkout targets.
