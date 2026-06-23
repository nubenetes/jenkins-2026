# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

A Jenkins-on-Kubernetes PoC: Jenkins (Helm chart + JCasC) running
pipelines-as-code for the Spring Microservices microservices, with full
OpenTelemetry observability (traces/metrics/logs) into either Grafana Cloud
or an in-cluster OSS Grafana/Loki/Tempo/Prometheus stack. See
[`README.md`](README.md) for the index and quick start. Deep-dive docs live
in [`docs/`](docs/) — all numbered `NNN-TITLE.md` with header/footer
navigation:

- [`101-GITHUB_ACTIONS_WORKFLOWS.md`](docs/101-GITHUB_ACTIONS_WORKFLOWS.md) — CI/CD workflow naming (`DayN.tier.ZZ-resource`), lifecycle matrix, clickable workflow inventory
- [`102-GITHUB_ACTIONS_AUTOMATION.md`](docs/102-GITHUB_ACTIONS_AUTOMATION.md) — WIF setup, GitHub secrets, bootstrapping architecture
- [`103-GITHUB_SECRETS_INVENTORY.md`](docs/103-GITHUB_SECRETS_INVENTORY.md) — complete inventory of every GitHub secret and variable: purpose, sensitivity, source, which workflows use each
- [`201-ARCHITECTURE.md`](docs/201-ARCHITECTURE.md) — system architecture, config, repository layout
- [`301-OBSERVABILITY.md`](docs/301-OBSERVABILITY.md) — OTel components, signal correlation, dashboards, all four obs modes
- [`401-JENKINS.md`](docs/401-JENKINS.md) — Jenkins UI, plugins, JCasC, MCP
- [`402-PIPELINES_AS_CODE.md`](docs/402-PIPELINES_AS_CODE.md) — seed job, pipeline stages, develop tier
- [`403-TEKTON.md`](docs/403-TEKTON.md) — Tekton as the alternative CI engine (`ci.engine` flag), Pipelines/Triggers/Dashboard, IAP-protected Dashboard, the pipeline ported to `tekton/`
- [`501-PLATFORM_OPERATIONS.md`](docs/501-PLATFORM_OPERATIONS.md) — ArgoCD, Headlamp, Gateway API + IAP, chaos/QA
- [`502-MICROSERVICES_GITOPS.md`](docs/502-MICROSERVICES_GITOPS.md) — Helm vs Kustomize, resource lifecycle design decisions
- [`601-DEVSECOPS.md`](docs/601-DEVSECOPS.md) — Semgrep, CodeQL, Trivy, warnings-ng
- [`901-LOCAL_DEVELOPMENT.md`](docs/901-LOCAL_DEVELOPMENT.md) — prerequisites, quick start, e2e test
- [`902-TROUBLESHOOTING.md`](docs/902-TROUBLESHOOTING.md) — common issues

Legacy stubs (`docs/architecture.md`, `docs/observability.md`, `docs/pipelines-as-code.md`) redirect to the numbered equivalents.

## Repo layout

- `scripts/0N-*.sh` - numbered, idempotent setup steps run in order by
  `scripts/up.sh` (and torn down in reverse by `scripts/down.sh`). Every
  script sources `scripts/lib/common.sh` then `scripts/lib/config.sh`.
- `scripts/lib/config.sh` - loads `config/config.yaml` via `yq`, exports it
  as `J2026_*` env vars. `JENKINS2026_PLATFORM` / `JENKINS2026_OBS_MODE` /
  `JENKINS2026_CI_ENGINE` env vars override `platform.target` /
  `observability.mode` / `ci.engine` from the config file for a single run
  (CI matrix override pattern).
- `config/config.yaml` - single source of truth: target platform
  (gke), observability mode (grafana-cloud/oss/managed-azure/managed-aws),
  CI engine (`ci.engine`: jenkins default | tekton),
  Jenkins/Microservices namespaces, branches, registry, service list.
- `helm/jenkins/`, `helm/microservices/` - Helm values overlays.
- `jenkins/casc/` - JCasC YAML (seed jobs, shared library, OTel plugin
  config, RBAC).
- `jenkins/pipelines/` - `Jenkinsfile.microservices`, seed job DSL
  (`seed_jobs.groovy`), `services.yaml` (the shared service registry both CI
  engines read).
- `tekton/` - Tekton pipelines-as-code, used when `ci.engine=tekton` (the
  alternative to Jenkins; Jenkins is the default). Tasks/Pipelines/Triggers/RBAC
  porting the Jenkins shared library in `vars/`. Installed by
  `scripts/04-tekton.sh` + `scripts/06-tekton-pipelines.sh` (the Tekton
  equivalents of `04-jenkins.sh` / `06-seed-pipelines.sh`). Tekton is
  GitOps-managed by ArgoCD via the `argocd/tekton` app-of-apps (see below); the
  Tekton Dashboard is exposed behind Google IAP like Headlamp. See
  [`docs/403-TEKTON.md`](docs/403-TEKTON.md).
- `observability/` - otel-operator, otel-collector, and Grafana (OSS +
  dashboards) Helm values + the `grafana-cloud-credentials` secret template.
- `argocd/` - ArgoCD `Application`/`ApplicationSet` manifests (the GitOps
  layer): External Secrets, Headlamp, the microservices AppSet, plus three
  **app-of-apps** (each a small Helm chart so repo/branch/version flow down to
  its children): `platform-postgres/` (the CNPG operator + pgAdmin that
  administers it), `observability-oss/`, which deploys the in-cluster OSS
  stack (kube-prometheus-stack/Loki/Tempo) when `observability.mode=oss`, and
  `tekton/` (with `components/*/kustomization.yaml` pulling the pinned upstream
  Tekton release YAMLs as kustomize remote resources + the `tekton/`
  pipelines-as-code), applied by `04-tekton.sh` when `ci.engine=tekton`. Because of
  this, `scripts/up.sh` installs ArgoCD (`08.5`) **before** observability
  (`03`), and `03-observability.sh` (oss) applies the app-of-apps + its
  script-managed companion objects (dashboards ConfigMap, `grafana-jenkins-ds`
  Secret, `grafana-runtime-config` ConfigMap) rather than `helm install`-ing the
  charts directly. See [`argocd/README.md`](argocd/README.md).
- `terraform/`:
  - `bootstrap/` - **one-time, local state**, run by hand. Creates the GCS
    Terraform state bucket + GitHub OIDC/Workload Identity Federation trust
    for `Day1.cluster.01-gke.yml`/`Decom.cluster.01-gke.yml`.
  - `gke/` - the throwaway GKE cluster. Local state for `test/e2e.sh`; GCS
    remote state (via a `backend_override.tf` written by the workflows) in
    CI.
  - `grafana-cloud-stack/` - the `observability.mode=grafana-cloud` backend:
    creates the Grafana Cloud stack with a **Terraform-generated slug**
    (`<prefix><random>`, so destroy+recreate never hits Grafana Cloud's
    reserved-slug cooldown). GCS remote state via `backend_override.tf` (prefix
    `grafana-cloud-stack`); applied by `Day0.infra.02-grafana-cloud.yml`,
    destroyed by `Decom.infra.02-grafana-cloud.yml` - the
    bootstrap/decommission tier, exactly like the Azure/AWS backends. Ephemeral
    (no `delete_protection`); the Grafana Cloud **org/account/free tier** is
    created once by hand and never Terraform-managed. The slug is an **output**
    (no `GRAFANA_CLOUD_STACK_SLUG` secret/var) that `Day1.cluster.01` reads from the GCS
    state.
  - `grafana-cloud-token/` - ephemeral access-policy + service-account
    tokens scoped to the stack above, looked up by slug via a data source (slug
    read from `grafana-cloud-stack`'s state output and passed in by the workflow).
    Same GCS-remote-state-via-`backend_override.tf` pattern as `terraform/gke`;
    applied by `Day1.cluster.01-gke.yml`, destroyed by `Decom.cluster.01-gke.yml`.
  - `azure-managed-grafana/` - the `observability.mode=managed-azure` backend:
    Azure Managed Grafana, Azure Monitor workspace + DCE/DCR (managed
    Prometheus), Application Insights + Log Analytics, and the Entra service
    principal the collector uses. Applied **one-time** by `Day0.infra.03-azure-grafana.yml`
    (GCS remote state via `backend_override.tf`, GitHub-OIDC -> Azure auth, no
    stored client secret; same persistent-bootstrap role as
    `grafana-cloud-stack`). `Day1.cluster.01-gke.yml` (managed-azure) reads its
    outputs straight from the GCS state to build the `azure-monitor-credentials`
    Secret - those backend credentials never become GitHub secrets. Only
    identifiers (`AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID`/
    `AZURE_GRAFANA_ADMIN_OBJECT_IDS`) are GitHub secrets.
  - `aws-managed-grafana/` - the `observability.mode=managed-aws` backend (AWS
    analogue of `azure-managed-grafana`): Amazon Managed Grafana, Amazon Managed
    Service for Prometheus, a CloudWatch log group, the GKE→AWS OIDC provider
    and the collector IAM role (AssumeRoleWithWebIdentity - no access keys).
    Applied **one-time** by `Day0.infra.04-aws-grafana.yml` (GCS remote state, GitHub
    OIDC → AWS auth). `Day1.cluster.01-gke.yml` (managed-aws) reads its outputs
    from the GCS state to build the `aws-managed-credentials` Secret; the
    collector authenticates at runtime via a projected SA web-identity token.
    Only identifiers (`AWS_BOOTSTRAP_ROLE_ARN`/`AWS_REGION`/`GKE_OIDC_ISSUER_URL`)
    are GitHub secrets.
- `test/e2e.sh` - full local lifecycle: provision GKE, deploy everything,
  smoke test, tear down. `test/smoke-test.sh` is the smoke test alone.
- `.github/workflows/` - workflows named `DayN.tier.ZZ-resource.yml`. **DayN** =
  lifecycle phase, self-documenting: `Day0` (persistent bootstrap) · `Day1`
  (cluster) · `Day2` (running-cluster ops) · `Decom` (teardown). **tier** = a
  brief semantic word from a controlled vocabulary (`infra`, `cluster`, `redeploy`,
  `publish`, `traffic`). **ZZ** = a per-resource id, stable for the same resource
  across all phases (e.g. ZZ=03 is always Azure: `Day0.infra.03-azure-grafana` →
  `Day2.publish.03-azure-grafana` → `Decom.infra.03-azure-grafana`). **-resource**
  identifies the resource only — no action verb, since the `DayN` prefix already
  says bootstrap/publish/teardown. Alphabetical sort of the workflow `name:`
  fields in the GitHub Actions UI **is** the correct execution order (`Decom`
  sorts after `Day2`, keeping teardown last); each `name:` therefore begins with
  its `DayN.tier.ZZ` prefix. `Day1.cluster.01-gke.yml` and
  `Decom.cluster.01-gke.yml` are the CI equivalent of `test/e2e.sh`, split
  so the cluster can be left running between runs; all GKE-touching workflows
  share `concurrency: group: jenkins-2026-gke`. See
  [`docs/101-GITHUB_ACTIONS_WORKFLOWS.md`](docs/101-GITHUB_ACTIONS_WORKFLOWS.md)
  for the full inventory, per-phase tables, and rationale.

## Conventions

- **Branches**: `main` and `develop` branches are supported. The stable Microservices pipeline jobs (`gateway`, `jhipstersamplemicroservice`, `microservices-k6-smoke`) are generated at the root. They dynamically determine their configuration (target namespace, environment, and library branch) based on the branch (`JENKINS2026_REPO_BRANCH`) that is currently active/deployed. Upstream Microservices repositories track `main` for both branches since they have no `develop` branch.
- **Secrets never committed**: `observability/otel-collector/secret.yaml`,
  `**/secret.local.yaml`, `*.env`, all `*.tfstate*`, `**/.terraform/`,
  `terraform/*/terraform.tfvars`, and the CI-written `backend_override.tf`
  files are gitignored. Always extend `.gitignore` rather than committing
  examples - use `*.example.yaml` / `terraform.tfvars.example` instead.
- **Idempotency**: every `scripts/0N-*.sh` step and Terraform module should
  be safe to re-run. `up.sh`/`down.sh` and the GitHub Actions workflows rely
  on this.
- **Feature-flag pattern**: durable default in `config/config.yaml`,
  ephemeral override via `JENKINS2026_*` env var - follow this pattern for
  any new config knobs rather than adding new flags ad hoc.
- Shell scripts: `bash`, `set -euo pipefail` via `lib/common.sh`, `yq` for
  YAML. Don't introduce other YAML tooling.

## Working on this repo

- Don't run `test/e2e.sh` or trigger `Day1.cluster.01-gke`/`Decom.cluster.01-gke`
  (or `Day2.redeploy.02-jenkins` / `Day2.redeploy.03-tekton` against a real
  cluster) workflows without explicit confirmation - they create/modify real,
  billed GCP (and optionally Grafana Cloud) resources. Always pair a provision
  with a decommission.
- `terraform/bootstrap` is a one-time, human-run step with local gitignored
  state - never wire it into CI, and never re-run `terraform apply` there without
  checking the existing state file first (re-creating it would orphan/duplicate
  persistent resources). (`terraform/grafana-cloud-stack` used to be in this
  category but is now CI-managed with GCS remote state and a generated slug -
  see the `terraform/` layout above.)
- When editing Terraform, run `terraform fmt -recursive` and
  `terraform validate` (after `terraform init -backend=false` if no backend
  is configured yet) before considering the change done.
- Required GitHub repo secrets are documented in README.md "GitHub Actions
  automation" - keep that table in sync with any new secrets a workflow
  starts consuming.
