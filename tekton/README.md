# `tekton/` — pipelines-as-code for the Tekton CI engine

Active when `ci.engine: tekton` (config/config.yaml) or
`JENKINS2026_CI_ENGINE=tekton`. This is the Tekton port of the Jenkins shared
library in [`vars/`](../vars/) and the seed job in
[`jenkins/pipelines/seed/`](../jenkins/pipelines/seed/). Jenkins remains the
default engine; see [`docs/403-TEKTON.md`](../docs/403-TEKTON.md).

Installed by [`scripts/04-tekton.sh`](../scripts/04-tekton.sh) (control plane +
Dashboard + RBAC) and applied by
[`scripts/06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh) (these
manifests + one PipelineRun per service from
[`jenkins/pipelines/seed/services.yaml`](../jenkins/pipelines/seed/services.yaml),
the shared service registry both engines read).

```
tekton/
  rbac/      triggers ServiceAccount + role bindings (EventListener)
  tasks/     one Task per Jenkins pipeline stage (see table below)
  pipelines/ microservices-pipeline (full CI/CD) + microservices-k6-smoke
  triggers/  EventListener + TriggerTemplate + TriggerBinding (API/webhook runs)
  pac/       Pipelines-as-Code Repository CRs (git-push-driven runs)
  runs/      ready-to-run PipelineRun manifests (one-click / kubectl create -f) —
             SA + workspaces pre-bound, so the Dashboard's "Create" doesn't need
             hand-filling; the Jenkins-one-click equivalent
```

## Stage mapping (Jenkins → Tekton)

| Jenkins stage ([`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy)) | Tekton Task |
|---|---|
| Checkout source (+ gateway patch) / Checkout infra | `fetch-source` |
| Semgrep SAST + SARIF upload | `semgrep-scan` |
| CodeQL Analysis + SARIF upload | `codeql-analyze` |
| Trivy IaC Scan | `trivy-iac` |
| Build & Test | `maven-build-test` |
| Build & Push Image | `build-push-image` (Jib for java, Kaniko for angular — daemonless) |
| Trivy Image Scan | `trivy-image` |
| Deploy to Kubernetes (GitOps + ArgoCD + OTel self-heal) | `gitops-deploy` |
| Smoke Test | `smoke-test` |
| Integration k6 | `k6-smoke` (also a standalone `microservices-k6-smoke` Pipeline) |

## Credentials (created by `scripts/01-namespaces.sh` in the pipeline namespace)

- `tekton-registry` — ghcr.io dockerconfigjson (Jib/Kaniko/Trivy via `DOCKER_CONFIG`)
- `tekton-git` — git basic-auth, annotated `tekton.dev/git-0` (clone/push) + read as env for SARIF upload
- `tekton-argocd` — ArgoCD API token (created by [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh))
- `tekton-github-webhook-secret` — optional GitHub HMAC token for the EventListener

The Task YAML references these by their default names; if you change them in
[`config/config.yaml`](../config/config.yaml) (`ci.tekton.*CredentialsSecretName`), update the Tasks too.
