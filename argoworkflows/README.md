# `argoworkflows/` — pipelines-as-code for the Argo Workflows CI engine

Active when `ci.engine: argoworkflows` (config/config.yaml) or
`JENKINS2026_CI_ENGINE=argoworkflows`. This is the **fourth** CI engine's port of
the Jenkins shared library in [`vars/`](../vars/) and the seed job in
[`jenkins/pipelines/seed/`](../jenkins/pipelines/seed/) — Jenkins remains the
default; see [`docs/405-ARGO_WORKFLOWS.md`](../docs/405-ARGO_WORKFLOWS.md). The
four engines (jenkins · tekton · githubactions · argoworkflows) are mutually
exclusive: selecting one retires the other three.

The whole Jenkins microservices pipeline
([`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy)) is
ported to a single **`WorkflowTemplate`** (`microservices-pipeline`) whose
`templates:` list holds **one template per stage** (the Tekton Tasks) and a `dag`
entrypoint that sequences them (the Tekton `runAfter` chain). All four engines read
**the same service registry**
([`jenkins/pipelines/seed/services.yaml`](../jenkins/pipelines/seed/services.yaml)).

Installed by [`scripts/04-argoworkflows.sh`](../scripts/04-argoworkflows.sh), which
applies the ArgoCD app-of-apps
([`argocd/argoworkflows-app.yaml`](../argocd/argoworkflows-app.yaml)) — a local Helm
chart ([`argocd/argoworkflows/`](../argocd/argoworkflows/)) that renders child
Applications for the **Argo Workflows** control plane (`workflow-controller` +
`argo-server`), **Argo Events** (unified `controller-manager` + EventBus), and the
pipelines-as-code under this directory. The pinned component versions are **vendored**
at `argocd/argoworkflows/components/*/` (`release.yaml`): Argo Workflows `v3.7.15` +
Argo Events `v1.9.4` (config/config.yaml `argoworkflows.versions`; see
[`docs/602`](../docs/602-VERSION_PINNING.md)).
[`scripts/06-argoworkflows-pipelines.sh`](../scripts/06-argoworkflows-pipelines.sh)
then activates CI imperatively (see **How runs are created** below).

```
argoworkflows/
  agent-image-prepull.yaml  step-image pre-pull DaemonSet (fast Workflow starts; applied by 04-argoworkflows.sh)
  templates/ the ported pipeline as WorkflowTemplates
             microservices-wftmpl.yaml      microservices-pipeline (full CI/CD; one template per stage — see table below)
             microservices-k6-wftmpl.yaml   microservices-k6-smoke (standalone k6 WorkflowTemplate)
  events/    the git-push → Workflow wiring (Argo Events)
             eventsource.yaml   github EventSource (webhook receiver Service github-eventsource-svc:12000)
             sensor.yaml        Sensor: on a push, submit a Workflow from microservices-pipeline
             sensor-rbac.yaml   operate-workflow-sa + RBAC (the Sensor creates Workflows in the run ns)
  rbac/      pipeline-rbac.yaml  Workflow-execution SA (argoworkflows-ci) + RBAC (pull/push, OTel self-heal, argocd sync)
  runs/      ready-to-submit Workflow manifests (one-click / kubectl create -f) — SA + args pre-set,
             so the Server UI's "Submit"/"Resubmit" doesn't need hand-filling; the Jenkins-one-click
             equivalent (seeded on Day1 when argoworkflows.seedRuns=true; *-develop.yaml + k6-load
             gated by the develop track)
```

`generateName` (not a stable `name`) Workflows in `runs/` can't be GitOps-owned, so
ArgoCD manages everything under this tree **except** `runs/` (the same exclusion
Tekton makes for `tekton/runs/`).

## Stage mapping (Jenkins → Tekton → Argo Workflows)

Every `microservices-pipeline` template mirrors a Tekton Task, which mirrors a Jenkins
stage. The full three-column table (with the notable per-engine differences) lives in
[`docs/405-ARGO_WORKFLOWS.md`](../docs/405-ARGO_WORKFLOWS.md#the-pipeline-ported).

| Jenkins stage ([`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy)) | Argo Workflows template |
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
| Integration k6 | `k6-smoke` (also the standalone `microservices-k6-smoke` WorkflowTemplate) |

## How runs are created

`06-argoworkflows-pipelines.sh` does the imperative "activation" ArgoCD can't, in one
of two modes:

- **Webhook mode** (the primary, git-driven model — gateway enabled **and** the Argo
  Events `github-eventsource-svc` present): for each service the script reconciles a
  GitHub webhook → the public Argo Events EventSource (via the
  `argo-events.<baseDomain>` Gateway route, HMAC-protected, **not** behind IAP — GitHub
  must reach it). The hook URL includes the `/push` path (the EventSource 404s a bare
  `/`). A push then fires the `github` EventSource, the **Sensor** (`events/sensor.yaml`)
  submits a Workflow from `microservices-pipeline`. This is the Argo Events analogue of
  Tekton Pipelines-as-Code. Switching engines prunes the previous engine's stale hooks.
- **Fallback / seed mode** (gateway disabled or EventSource absent, e.g. local): the
  script generates and `kubectl create`s **one Workflow per service** directly (stable,
  plus develop when the develop track is on).

<details>
<summary><b><code>argoworkflows.seedRuns</code> — pre-populating the Server UI</b></summary>

In webhook mode the git-push trigger is the default, so the Server UI starts empty. The
opt-in `argoworkflows.seedRuns` flag (`JENKINS2026_ARGOWORKFLOWS_SEED_RUNS`, default
`true` — parity with `tekton.seedRuns`) makes Day1 **also** submit one Workflow per
service from the `runs/` manifests, so the UI has runnable entries (Resubmit) from the
first provision, at the cost of one build per service. `runs/*-develop.yaml` and
`runs/k6-load.yaml` are gated behind the develop-track flag (skipped when it is off),
matching the Jenkins seed's `*-develop` job gating. The seeded runs (and the
webhook/fallback ones) carry the same engine-neutral `jenkins2026.io/url-*` access-URL
annotations the Jenkins `systemMessage` banner surfaces, so the public URLs render in
the run-detail view.
</details>

<details>
<summary><b>Run-pod placement (<code>argoworkflows.runNodePool</code>)</b></summary>

`06-argoworkflows-pipelines.sh` patches `workflow-controller-configmap.workflowDefaults`
so **every** Workflow (seeded, webhook-triggered, or UI-created) places its step pods
predictably. ArgoCD ignores this field (`ignoreDifferences` in
`argocd/argoworkflows/templates/workflows.yaml`), so the imperative patch isn't reverted.

- **`static`** (default): the long-lived `jenkins-2026-pool` (`app=jenkins-2026`,
  `e2-standard-8`). **Recommended** — a Workflow's steps share one RWO `source` workspace
  PVC bound to a single node, so a Spot preemption would kill the whole run.
- **`ci-spot`**: the NAP Spot ComputeClass (needs `nodeAutoProvisioning.enabled`) —
  cheaper but Spot/quota-dependent (opt-in). See
  [`docs/501`](../docs/501-PLATFORM_OPERATIONS.md#the-engines-on-spot-ci-spot--why-the-placement-flag-is-per-engine).
</details>

## Credentials

In-cluster Secrets the templates reference **by name**, created imperatively (they hold
env-sourced material and can't be GitOps-managed). The run-namespace ones
(`argoworkflows.runNamespace`, default `argo-ci`) are created by
[`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) /
[`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh); the webhook HMAC lives in the
events namespace (`argoworkflows.eventsNamespace`, default `argo-events`):

- `argoworkflows-registry` — ghcr.io dockerconfigjson, mounted at `$DOCKER_CONFIG` (Jib/Kaniko/Trivy)
- `argoworkflows-git` — git basic-auth (`username`/`password`), used to clone + `git push origin main` the gitops-config repo and for SARIF upload
- `argoworkflows-argocd` — ArgoCD API token for `argocd app sync` (created by [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh))
- `argoworkflows-github-webhook` — GitHub HMAC secret shared between the fork webhooks and the `github` EventSource (in the events namespace; generated by `06-argoworkflows-pipelines.sh` if none provided)
- `k6-cloud` — optional Grafana Cloud k6 token/project/url consumed by the `k6-smoke` template (empty → cloud output skipped)

The template YAML references the registry/git Secrets by their **default** names; if you
rename them in [`config/config.yaml`](../config/config.yaml)
(`argoworkflows.registryCredentialsSecretName` / `argoworkflows.gitCredentialsSecretName`),
update the templates too — the same coupling gotcha
[`tekton/README.md`](../tekton/README.md) documents for `tekton.*CredentialsSecretName`.

See [`docs/405-ARGO_WORKFLOWS.md`](../docs/405-ARGO_WORKFLOWS.md) for the full engine
architecture, the IAP-protected Server UI (`argo.<domain>`), Argo Events triggering, and
the Jenkins → Tekton → Argo stage-mapping table with per-engine differences.
