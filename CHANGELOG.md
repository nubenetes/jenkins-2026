# Changelog

All notable changes to this project will be documented in this file.

## [v0.17.0] - 2026-06-22

Fix CNPG webhook caBundle race on fresh deploy — GitOps Update now succeeds
first time with any observability mode (including managed-azure).

### Fixed

- **CNPG webhook caBundle silent skip** (`scripts/08.5-argocd.sh`): on a fresh
  cluster, `cnpg-ca-secret` may not exist yet when Phase 4 ran. The kubectl
  command failed silently, leaving `CA_SECRET_SUBJECT=""`. Because
  `CABUNDLE_SUBJECT` was also `""` (caBundle empty), the comparison `"" == ""`
  skipped the patch entirely — the webhook remained broken for every subsequent
  ArgoCD sync, causing the Jenkins pipeline's GitOps Update stage to fail with
  `x509: certificate signed by unknown authority` on the CNPG webhook.
- Phase 3 timeout extended from 2 m → 3 m; self-injection outcome now tracked.
- Phase 4 now waits explicitly for `cnpg-ca-secret` (exit 1 if absent after
  2 m) before any comparison, preventing the silent-skip.
- Patch condition extended: fires when caBundle is **empty** OR has the wrong
  cert (not only on cert-subject mismatch).
- `op:replace` → `op:add` — safe whether the caBundle field is absent, empty,
  or populated with the wrong value.
- Webhook count from `| wc -c` (off-by-one if newline present) → `jq '.webhooks
  | length'` (exact).

## [v0.16.0] - 2026-06-22

Replace and reorganise all NotebookLM media assets.

- **New files** (22 total): 7 EN infographics, 5 ES infographics, 2 EN videos,
  1 ES video, 1 EN audio, 1 ES audio, 3 EN PDFs — all reflecting the current
  stack (GKE + JHipster microservices + full OTel observability). No CrunchyData
  references.
- **Numbering scheme**: `01–09` infographics · `10–19` video · `20–29` audio ·
  `30–39` PDF — consistent within each language folder (`en/`, `es/`).
- **Old files removed** from the repo, from git history (via `git filter-repo`),
  and from git LFS (via `git lfs prune`). Remote LFS objects are unreferenced
  and will be garbage-collected by GitHub.
- **README** rewritten: two collapsible `<details>` blocks (EN × 7, ES × 5
  infographics) plus plain lists for video/audio/PDF. CrunchyData warning
  callout removed.
- `.gitattributes`: added `docs/notebooklm/en/*` LFS rule.

## [v0.15.0] - 2026-06-22

Per-mode Grafana alert email secrets, Alert Rules banner link, and a full
GitHub secrets/variables inventory with Day-0/Day-1/Day-2 operational
classification for all workflows.

### Added

- **`GRAFANA_ALERT_EMAIL_<MODE>` per-mode secret pattern** — replaces the
  single `GRAFANA_ALERT_EMAIL` secret with a per-mode hierarchy:
  `GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD` / `_OSS` / `_MANAGED_AZURE` /
  `_MANAGED_AWS` take priority over the generic `GRAFANA_ALERT_EMAIL`
  fallback, which in turn falls back to `jenkins-credentials.oidc-admin-email`.
  Necessary because Grafana Cloud requires the contact-point email to be a
  registered org member, which may differ from the OIDC admin email used by
  other backends. `resolve_email()` derives the mode var name at runtime via
  `tr` — no case statement needed.

- **Alert Rules link in Jenkins system banner** — `jcasc-base.yaml` now
  includes a `${GRAFANA_BASE_URL}/alerting/list` link in the Observability
  section. The path is identical on all four Grafana backends; `GRAFANA_BASE_URL`
  is already injected via `jenkins-credentials`, so no script changes were needed.

- **`docs/103-GITHUB_SECRETS_INVENTORY.md`** — new reference document covering
  all 34 GitHub secrets and 1 repository variable. Grouped into 8 subsections
  (GCP core, Grafana Cloud, alert emails, Azure, AWS, Jenkins OIDC,
  Headlamp/IAP, registry/git). Each entry documents sensitivity, source,
  setup command, and which workflows consume it. Wired into the doc nav chain
  (102 → 103 → 201), README index, and CLAUDE.md.

- **Day-0 / Day-1 / Day-2 section in `docs/101-GITHUB_ACTIONS_WORKFLOWS.md`**
  — defines the three-tier operations model (Day-0 = persistent bootstrap,
  Day-1 = cluster provisioning, Day-2 = running-system operations) and maps
  all 16 workflows into a matrix table (day, cluster required, idempotent,
  typical frequency). Replaces the ASCII session lifecycle block with a
  colour-coded Mermaid `flowchart TD` diagram showing workflow nodes,
  sub-groups, GCS-state reuse arrow, and the re-provision loop back from
  Decommission to Day-1.

### Fixed

- **`scripts/07.5-grafana-alerts.sh`** — contact-point upsert is now
  non-fatal on HTTP 400: warns with Grafana Cloud org-member guidance and
  skips the notification policy, but continues to provision alert rules.
  Script header comment and all `log_warn` fallback messages updated to
  reference `GRAFANA_ALERT_EMAIL_<MODE>` as the primary override.

- **`5.1.05-publish-grafana-alerts.yml`** — workflow passes all five alert
  email env vars (`GRAFANA_ALERT_EMAIL` + four mode-specific variants);
  unset secrets expand to empty and fall through the priority chain silently.
  Header comment and step summary updated to document the full resolution
  chain.

### Documentation

- `docs/102-GITHUB_ACTIONS_AUTOMATION.md` — optional secrets table expanded
  with per-mode `GRAFANA_ALERT_EMAIL_*` rows (five entries replacing one).
- `docs/301-OBSERVABILITY.md` — Contact Point section replaced with a full
  3-level priority table, per-mode secret mapping, and Grafana Cloud
  org-member callout.
- README index and CLAUDE.md updated with `103` entry and `101` Day-0/1/2
  anchor.

## [v0.14.1] - 2026-06-22

Extends Grafana alerting (v0.14.0) to all four observability modes and adds
a dedicated GitHub Actions workflow to provision alerts independently of the
full cluster lifecycle.

### Added

- **`5.1.05-publish-grafana-alerts.yml`** — new manually-triggered workflow
  (`workflow_dispatch`) that provisions alert rules, contact point, and
  notification policy without re-running the full `0.2.01` lifecycle.
  Accepts an optional `observability_mode` input (defaults to
  `config/config.yaml`). Authenticates via GCP WIF + kubeconfig (same
  pattern as `5.2.02`); conditionally adds AWS OIDC (`managed-aws`) and
  Azure OIDC (`managed-azure`) steps. Respects the `jenkins-2026-gke`
  concurrency group. Optional `GRAFANA_ALERT_EMAIL` repo secret overrides
  the default email source.

### Changed

- **`scripts/07.5-grafana-alerts.sh`** — all four observability modes now
  fully implemented (previously `oss`/`managed-azure`/`managed-aws` were
  `TODO` stubs):
  - `grafana-cloud`: unchanged (same behaviour as v0.14.0)
  - `oss`: port-forwards `kube-prometheus-stack-grafana`, reads admin
    password from the `kube-prometheus-stack-grafana` Secret, mints a
    300-second Admin API key, then calls the same Grafana HTTP provisioning
    API. Email alerts require SMTP configured in `values-oss.yaml`
    (`grafana.grafana.ini.smtp.*`); rules appear in Grafana regardless.
  - `managed-azure`: obtains an Azure AD bearer token via
    `az account get-access-token --resource https://grafana.azure.com/`,
    reads the AMG endpoint from `GRAFANA_BASE_URL` env var or
    `azure-monitor-credentials` Secret key `AZURE_GRAFANA_ENDPOINT`.
  - `managed-aws`: mints a short-lived AMG service-account key via
    `aws grafana create-workspace-api-key`, reads endpoint + workspace ID
    from env vars or `aws-managed-credentials` Secret.
  - Script refactored to share `provision_alerts()` and `resolve_email()`
    helpers — all four modes use identical provisioning logic, only auth
    and URL acquisition differ.

- **`docs/301-OBSERVABILITY.md`** — "Grafana Alerting" mode support table
  updated: all four modes now show ✅ with auth mechanism details. Optional
  `GRAFANA_ALERT_EMAIL` GitHub secret documented.

## [v0.14.0] - 2026-06-22

Grafana alerting provisioned as code: 5 alert rules covering the most
critical failure modes, email contact point using the existing admin
email secret, automatic provisioning on every `scripts/up.sh` run.

### Added

- **`observability/grafana/alerting/`** — alerting resources as code:
  - `contact-points.json` — email contact point (`jenkins-2026-email`),
    address read from `GRAFANA_ALERT_EMAIL` env var or the existing
    `jenkins-credentials` Secret key `oidc-admin-email` (no new secret needed)
  - `notification-policy.json` — routes all alerts to the email contact
    point; group_wait=30s, group_interval=5m, repeat_interval=4h
  - `rules/01-pods-not-ready.json` — Critical / 2 min: any microservice
    pod NotReady (`kube_pod_status_ready == 0` in `microservices` ns)
  - `rules/02-argocd-degraded.json` — Warning / 5 min: any ArgoCD
    Application health=Degraded (`argocd_app_info`)
  - `rules/03-cnpg-degraded.json` — Critical / 2 min: any PostgreSQL pod
    NotReady (`postgres-.*` pods in `microservices` ns)
  - `rules/04-http-5xx-rate.json` — Warning / 3 min: HTTP 5xx rate > 5%
    for any microservice (OTel metric `http_server_request_duration_seconds_count`)
  - `rules/05-jvm-heap-high.json` — Warning / 5 min: JVM heap > 85% for
    any microservice (OTel metric `jvm_memory_used_bytes`)

- **`scripts/07.5-grafana-alerts.sh`** — new idempotent script that
  provisions the contact point, notification policy, and all alert rules
  via the Grafana HTTP provisioning API (`/api/v1/provisioning/...`).
  Fully implemented for `grafana-cloud` (upserts by UID — safe to re-run).
  `oss` / `managed-azure` / `managed-aws` modes have `TODO(obs-mode)` stubs
  with descriptive `log_warn` messages.

- **`scripts/up.sh`** — calls `07.5-grafana-alerts.sh` automatically
  after `07-grafana-dashboards.sh` on every deploy (non-fatal: failure
  logs a warning but does not abort the deploy).

- **`docs/301-OBSERVABILITY.md`** — new "Grafana Alerting" section
  documenting the 5 rules, the email secret resolution order, the mode
  support matrix, and how to add custom rules (drop a JSON in
  `observability/grafana/alerting/rules/`).

## [v0.13.5] - 2026-06-22

Fix: Grafana dashboards empty after first Jenkins pipeline run because the
OTel Java agent was not injected into the microservice pods (race condition
between ArgoCD sync and the OTel Operator admission webhook).

### Fixed

- **`vars/microservicesDeploy.groovy`** — after the ArgoCD sync+wait succeeds,
  a new step checks whether the freshly-deployed pod has `-javaagent` in
  `JAVA_TOOL_OPTIONS`. If it doesn't (race condition: pod was admitted before
  the `Instrumentation` CR or the webhook were ready), the step does a
  `kubectl rollout restart` automatically and verifies the agent is injected
  after the new pod comes up. Idempotent: skips the restart when the agent is
  already present. Runs on every pipeline build so any future regression is
  self-corrected.

### Root cause

The OTel Operator's pod-mutation webhook (`mpod.kb.io`) uses
`failurePolicy: Ignore` by design. A pod admitted to the cluster before the
`Instrumentation` CR existed or before the webhook was serving starts without
the Java agent — `JAVA_TOOL_OPTIONS` is empty — and silently emits no
metrics, traces or logs. The existing `scripts/ensure-otel-injection.sh`
runs at the end of `scripts/up.sh` (cluster bootstrap), but microservice
pods are only created for the first time by the Jenkins pipeline build, which
runs after `up.sh` completes — so the guard ran too early and found no
deployments to check.

## [v0.13.4] - 2026-06-22

Fix the root cause of the CNPG webhook x509 error: the operator (v0.28.x on GKE)
injects the leaf TLS serving cert into the `caBundle` instead of the CA cert,
causing the kube-apiserver to reject every call to the CNPG admission webhook with
`x509: certificate signed by unknown authority`.

### Fixed

- **`scripts/08.5-argocd.sh`** — Phase 4 added to the CNPG readiness block:
  after the webhook caBundle is populated (Phase 3), the script now compares
  its `subject` against the subject of `cnpg-ca-secret`. If they differ (leaf
  cert instead of CA cert), it automatically patches all mutating and validating
  webhook configurations to replace the caBundle with the correct CA cert from
  `cnpg-ca-secret`. This makes the fix fully automatic on fresh cluster deploys.
- **Phase 1** of the same block now discovers the CNPG deployment by label
  (`app.kubernetes.io/name=cloudnative-pg`) instead of hardcoding the name
  `cnpg-controller-manager` — the Helm chart names the deployment after the
  release (`cnpg-operator-cloudnative-pg`), not after the container binary.

### Root cause

CloudNative-PG Helm chart `0.28.x` on GKE initialises the webhook secret in
two separate steps: it first creates `cnpg-webhook-cert` (the serving cert),
then separately injects the CA into the webhook configuration. On GKE the
injection lands the serving cert (`CN=cnpg-webhook-service.cnpg-system.svc`)
in `caBundle` instead of the CA cert (`CN=cnpg-ca-secret`). The kube-apiserver
uses `caBundle` as the trust anchor when calling the webhook — if it contains
the leaf cert, the CA of that cert is unknown, and every admission call is
rejected. All CNPG resources (`Cluster`, `Pooler`, `ScheduledBackup`) stay
`OutOfSync/Missing` in ArgoCD, and microservice Deployments fail to roll out
(no database).

## [v0.13.3] - 2026-06-22

Fix race condition: first Jenkins pipeline run failing at "GitOps Update"
stage with `x509: certificate signed by unknown authority` on the CNPG
webhook, because ArgoCD deploys CNPG asynchronously and the controller was
not yet ready when the seed job triggered the first build.

### Fixed

- **`scripts/08.5-argocd.sh`**: after `kubectl apply -f cnpg-app.yaml`, the
  script now blocks in three sequential phases before continuing:
  1. **Chart sync** — `timeout 300` loop until `cnpg-controller-manager`
     Deployment exists in `cnpg-system` (ArgoCD has pulled and applied the
     Helm chart).
  2. **Pod ready** — `wait_for_deployment cnpg-controller-manager cnpg-system 5m`
     (same helper used for Jenkins/ArgoCD elsewhere).
  3. **Webhook caBundle** — `timeout 120` loop until
     `cnpg-mutating-webhook-configuration` has a non-empty `caBundle` (the
     controller has self-injected its CA cert into the webhook config, ~10-20 s
     after the pod becomes Ready).
  Without this wait, the first pipeline run races against CNPG init and
  ArgoCD sync fails with the x509 error on every fresh cluster deployment.

## [v0.13.2] - 2026-06-22

Comprehensive Table of Contents added to README covering every section and
sub-section across all 11 numbered docs and runbooks. The `log-correlation-validation`
runbook is now surfaced in the observability doc and in the TOC.

### Added

- **README `## Table of Contents`** — inserted immediately before the Document
  Inventory, covering:
  - All 5 README sections (local anchor links)
  - Every `##` and `###` heading from all 11 numbered docs (`101`–`902`) with
    deep links directly into the relevant file and section
  - **Runbooks** block at the end with the full sub-section outline of
    `docs/runbooks/log-correlation-validation.md`
  - Total coverage: 132 section headings + 75 sub-section headings across 11 docs
- **`docs/301-OBSERVABILITY.md`** — runbook callout block added after the k6
  smoke-test section so `log-correlation-validation.md` is surfaced in context
  (not just as an orphaned directory entry)

## [v0.13.1] - 2026-06-22

README restructured into a numbered document library under `docs/` and translated fully to English.

### Changed

- **README**: 3 141 lines → 146-line index. Now contains only a brief intro,
  Quick Start one-liner, Architecture Overview (compact Mermaid), GitHub
  Actions summary table, Prerequisites, and the **Document Inventory** — which
  is now section 1 (immediately visible) rather than buried at line 2 238.
- **`docs/` restructure** — all content moved to 11 numbered docs following
  the `NNN-TITLE_IN_CAPS.md` convention, each with `← Previous | 🏠 Home | → Next →`
  header and footer navigation:
  - `101-GITHUB_ACTIONS_WORKFLOWS.md` — CI/CD workflow naming (`Y.X.ZZ`),
    lifecycle phases, Phase×Step matrix, ZZ resource identity, Mermaid diagram,
    full 15-row numbered inventory with clickable GitHub Actions links
  - `102-GITHUB_ACTIONS_AUTOMATION.md` — WIF setup, GitHub secrets, bootstrapping
    architecture, `git_ref` parameter
  - `201-ARCHITECTURE.md` — component diagram, microservices database
    architecture (CNPG), configuration, repository layout, GKE topology
  - `301-OBSERVABILITY.md` — OTel Operator/agent/RUM/Collector, signal
    correlation, dashboards, k6 smoke test, all four observability modes
  - `401-JENKINS.md` — Jenkins UI, Google OIDC, plugins, JCasC, MCP server
  - `402-PIPELINES_AS_CODE.md` — seed job, pipeline stages, optional `develop`
    tier, container security
  - `501-PLATFORM_OPERATIONS.md` — ArgoCD inventory, telemetry simulation,
    chaos/QA, Golden Path modernizations, Headlamp, GKE Gateway + IAP
  - `502-MICROSERVICES_GITOPS.md` — Helm vs. Kustomize, resource lifecycle &
    decommission orchestration, NEG synchronization barrier
  - `601-DEVSECOPS.md` — Semgrep SAST, CodeQL, Trivy, warnings-ng SARIF
  - `901-LOCAL_DEVELOPMENT.md` — prerequisites, Quick Start, step-by-step
    deployment guide, `test/e2e.sh`
  - `902-TROUBLESHOOTING.md` — common issues, ArgoCD OIDC, Terraform, Jenkins
    authentication failures
- **Legacy stubs** (`docs/architecture.md`, `docs/observability.md`,
  `docs/pipelines-as-code.md`) now redirect to the numbered equivalents so
  existing links remain valid.
- **English-only**: all Spanish text in the workflow inventory matrix table
  translated to English (column headers, row descriptions, prerequisites,
  frequency cells).
- **`CLAUDE.md`**: updated docs/ reference list to new numbered filenames.

## [v0.13.0] - 2026-06-22

Complete redesign of GitHub Actions workflow naming from `CC.NN` to `Y.X.ZZ`,
making the filesystem sort order in the GitHub Actions UI **identical to the
correct execution order** across all lifecycle phases. Plus a new standalone
workflow to publish Azure Managed Grafana dashboards without a running cluster
(parity with the existing AWS equivalent).

### Changed

- **Workflow naming scheme**: All 15 GitHub Actions workflows renamed from
  `CC.NN-<name>.yml` to `Y.X.ZZ-<name>.yml`:
  - `Y` = lifecycle phase — `0` create/bootstrap, `5` update/redeploy, `9` destroy
  - `X` = execution step within the phase (positional; **inverts between create and
    destroy** to match dependency order: in phase `0`, X=1=persistent resources
    first, X=2=GKE second; in phase `9`, X=1=GKE first, X=2=persistent last)
  - `ZZ` = resource identifier, constant for the same resource across all phases
    (ZZ=03 is always Azure Managed Grafana, ZZ=04 is always AWS AMG, etc.)
  - Alphabetical sort in GitHub Actions UI = correct runbook order; no separate
    documentation needed to know what to run next
  - Dashboard-publish workflows (`5.1.03`, `5.1.04`) correctly reclassified to
    category `1` (persistent resources) from the old `02.xx` (GKE lifecycle)
  - Mirror relationship between bootstrap and decommission is now explicit via
    matching ZZ: `0.1.03` ↔ `9.2.03` (Azure), `0.1.04` ↔ `9.2.04` (AWS), etc.

- **`name:` fields** inside all 15 workflow YAMLs updated to match new codes.
- **README "CI/CD pipelines"** section fully rewritten:
  - `Y.X.ZZ` naming convention explained with component table and Phase×Step
    matrix showing why X inverts between create and destroy
  - Resource identity table (ZZ by resource, across all lifecycle phases)
  - Full workflow matrix (resource × lifecycle phase, clickable links)
  - Collapsible Mermaid lifecycle diagram (phase 0 → phase 5 → phase 9 with
    intra-phase dependency arrows)
  - **Unified numbered inventory matrix** (15 workflows, one numbered row each,
    with Y / X / ZZ as separate columns, detailed description, prerequisites,
    and frequency — all links go directly to the GitHub Actions dispatch page)
  - Rationale for no automatic workflow chaining (`workflow_run:` design decision)
- **CLAUDE.md**: Workflow naming convention updated from `CC.NN` to `Y.X.ZZ`
  with full explanation of Y/X/ZZ semantics and inversion rule.

### Added

- **`5.1.03-publish-azure-dashboards.yml`** (new) — standalone workflow to
  (re)publish `observability/grafana/dashboards-azure/` to Azure Managed Grafana
  **without a running GKE cluster**: authenticates via GitHub OIDC (the OIDC SP
  holds Grafana Admin), discovers the instance via `az grafana list`, substitutes
  the `${appinsights}` placeholder at publish time. Parity with the existing
  `5.1.04-publish-aws-dashboards.yml`. Requires `AZURE_CLIENT_ID` /
  `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` secrets (provisioned by `0.1.03`).

## [v0.12.0] - 2026-06-22

Managed cloud observability backends (**Azure** & **AWS**), the in-cluster
**OSS** stack made live & publicly exposed, plus an optional `develop` deploy
tier — taking `observability.mode` to four fully working backends
(`grafana-cloud` | `oss` | `managed-azure` | `managed-aws`).

### Added

- **`observability.mode=managed-azure`** — full Azure-native backend: Azure
  Monitor workspace (managed Prometheus via DCE/DCR), Application Insights + Log
  Analytics, and Azure Managed Grafana. Authenticated by a GitHub-OIDC-bootstrapped
  Entra service principal — **no client secret stored in the repo**; only
  identifiers are GitHub secrets.
  - Terraform `terraform/azure-managed-grafana/` (one-time `01.03-azure-bootstrap.yml`),
    `02.01-gke-provision.yml` reads its outputs straight from GCS state to build
    the `azure-monitor-credentials` Secret.
  - managed-azure dashboard variants (Azure Monitor Logs/Traces), click-through
    trace correlation via the `operation_Id` data link, k8s infra metrics, and
    AMG's **built-in** Kubernetes dashboards fed from native scrape.
  - `02.03`-style auto-publish of AMG dashboards + manual approval gates on the
    infra workflows.
  - **Files**: `terraform/azure-managed-grafana/`, `observability/**`,
    `.github/workflows/01.03-azure-bootstrap.yml`, `02.01-gke-provision.yml`.
- **`observability.mode=managed-aws`** — AWS analogue: Amazon Managed Service for
  Prometheus (AMP), AWS X-Ray, CloudWatch Logs, and Amazon Managed Grafana (AMG).
  Collector authenticates at runtime via a projected SA web-identity token
  (AssumeRoleWithWebIdentity — **no access keys**).
  - Dedicated `02.04` workflow to publish dashboards to AMG **without a cluster**
    (reads Terraform GCS state + AWS OIDC), plus in-CI least-privilege auto-publish.
  - Community Kubernetes dashboards (dotdc + node-exporter) bound to AMP with
    Prometheus-native metric names; X-Ray datasource plugin for trace panels.
  - **Files**: `terraform/aws-managed-grafana/`, `observability/**`,
    `.github/workflows/01.04-aws-bootstrap.yml`, `02.04-*.yml`.
- **`observability.mode=oss` made live** — the in-cluster
  Grafana/Loki/Tempo/Prometheus stack (Grafana OSS 13.0.2) is now publicly
  exposed via the GKE Gateway API + IAP with Google SSO (auth-proxy), emits k8s
  events, and supports full metrics↔traces↔logs correlation. Clean switching
  between modes.
  - **Files**: `observability/grafana/values-oss.yaml`,
    `observability/otel-collector/values-oss.yaml`, `scripts/03-*`, `scripts/09-gateway.sh`.
- **Optional `develop` deploy tier** (feature flag, **off by default**) — an
  opt-in second microservices tier (`microservices-develop` namespace +
  `<svc>-develop` Jenkins jobs + its own ListView, tracking the gitops-config
  `develop` branch). Same app image as stable (upstream has no develop branch);
  shared observability stack. Durable default `microservices.developTrackEnabled`,
  ephemeral override `JENKINS2026_DEVELOP_TRACK_ENABLED`.
  - **Files**: `config/config.yaml`, `scripts/lib/config.sh`, `scripts/08.5-argocd.sh`,
    `scripts/04-jenkins.sh`, `argocd/microservices-appset.yaml`,
    `jenkins/pipelines/seed/{services.yaml,seed_jobs.groovy}`,
    `vars/microservicesDeploy.groovy`, `README.md`.
- **OTel auto-instrumentation injection-race guard** — protects against
  microservices starting without the Java agent when the `Instrumentation` CR and
  Deployment race on a fresh deploy.
- **Jenkins system banner — managed Grafana links per mode** — direct links to the
  active backend's Grafana and to key built-in Kubernetes dashboards (AMG/Azure),
  surfaced according to `observability.mode`.

### Changed

- **CI provision defaults to `enable_gateway=true`** in `02.01-gke-provision.yml`
  — the project's intended public-access path.
- **Banner links are mode-aware** — the "Kubernetes Infrastructure" / Grafana
  k8s-app links now point to (or hide for) the correct backend per
  `observability.mode` instead of assuming grafana-cloud.

### Fixed

- **Azure**: Managed Grafana major version `11 → 12` (Standard SKU only supports
  12); App Insights **classic schema** in dashboard log/trace queries; log/trace
  panels bound to a concrete resource + stable datasource UID; robust community
  dashboard import via the import API (+ cluster label); region split
  (spaincentral backends + francecentral AMG) that also unblocks decommission.
- **AWS**: Grafana workspace requires `CUSTOMER_MANAGED` role with
  `CURRENT_ACCOUNT`; collector memory bumped to 1Gi (cadvisor/kubelet
  cardinality); reuse AMG's built-in datasources **by type, not by name**; install
  the X-Ray datasource plugin so trace panels render; skip CI dashboard publish
  until the publisher-role secret is set.
- **ArgoCD / CloudNative-PG**: `ServerSideDiff` then `Replace=true` for the
  cnpg-operator app (CRD annotation limit / SSA not honored on ArgoCD v3.5).
- **OSS**: point the Grafana Tempo datasource at `3200` (chart has no `3100`);
  unbreak Tempo OOM, exemplar correlation, and the k8s banner link.

### Docs

- managed-aws GitHub secrets, full workflow inventory, and `CLAUDE.md` terraform
  layout; AMG first-login runbook (graceful skip when unauthenticated); Grafana
  Cloud p99 fixed `[15m]` rate-window rationale + AWS publish secret consumers;
  microservices log-levels + signal-correlation testing runbook.

---

## [v0.11.0] - 2026-06-20

### Added
- **Span metrics + service graph generated in the OTel gateway collector**:
  - The traces pipeline now fans every span out to the `span_metrics` and `service_graph` connectors, with a dedicated `metrics/spanmetrics` pipeline exporting their output.
  - **Why**: without them no span-derived metrics exist, so Tempo's **Service Map / node graph stays empty** and there are no RED (Rate/Errors/Duration) metrics to pivot to from a trace. They produce `traces_spanmetrics_*` (with `trace_id` exemplars) and `traces_service_graph_request_*`. Both connectors ship in the `otelcol-k8s` image, so no image change was needed.
  - **Files**: `observability/otel-collector/values-grafana-cloud.yaml`
- **OSS collector parity**: the same `span_metrics` + `service_graph` connectors in the in-cluster path, exporting via `prometheusremotewrite` to the bundled Prometheus, so all four correlation directions work in `observability.mode: oss` too.
  - **Files**: `observability/otel-collector/values-oss.yaml`, `observability/grafana/values-oss.yaml`
- **Observability deep-dive documentation** in `README.md`: end-to-end telemetry architecture, signal correlation (metrics↔traces↔logs), structured-logging chain, dashboard provisioning, and OSS in-cluster topology — each with a collapsible Mermaid diagram (rendered and verified for text fit).
  - **Files**: `README.md`

### Changed
- **Portable dashboards**: panels reference `${DS_PROMETHEUS}` / `${DS_LOKI}` / `${DS_TEMPO}` template variables (defaulting to `grafanacloud-*`, degrading to the matching-type default in OSS) instead of hardcoded datasource UIDs — the same JSON works in both modes. A hidden `namespace` variable scopes log panels/links per environment (`stable`→`microservices` vs `develop`→`microservices-develop`).
  - **Files**: `observability/grafana/dashboards/*.json`

### Fixed
- **Robust log `line_format` across all dashboards**: a fallback template renders ECS-JSON app logs (`.message`), CloudNativePG/sidecar JSON (`.msg`) and plain-text lines (`__line__`) without ever showing blank lines.
  - **Files**: `observability/grafana/dashboards/*.json`

---

## [v0.10.16] - 2026-06-19

### Changed
- **pgAdmin upgraded from 9.15 → 9.16**:
  - Pinned `image.tag: "9.16"` in `helm/pgadmin/values.yaml`.
  - The upstream runix Helm chart `1.65.0` (which will ship 9.16) is not yet published; the image override allows the upgrade without waiting for the chart release.
  - ArgoCD auto-sync picks up the change from `main` with no manual intervention required.

---

## [v0.10.15] - 2026-06-19

### Fixed
- **Semgrep SAST / CodeQL Analysis — `curl: not found` (exit 127) fails stage**:
  - Moved both SARIF-upload blocks from `container('git')` to `container('helm')`.
  - **Root cause**: `alpine/git` runs as `runAsUser: 1000` (non-root, hardened in v0.10.12). `apk add curl` requires root, so it fails silently — curl is never installed. Jenkins runs `sh` with `-xe` by default, so `RESPONSE=$(curl ...)` exits 127 and kills the stage, causing all downstream stages (CodeQL, Trivy, Build, Deploy, Smoke Test) to be skipped.
  - **Fix**: `alpine/k8s` (the `helm` container) ships curl, git, gzip, and base64 pre-installed and already runs as UID 1000. Moving both SARIF upload blocks there eliminates the runtime package-install dependency entirely.
  - **Files**: `vars/MicroservicesPipeline.groovy`

---

## [v0.10.14] - 2026-06-19

### Fixed
- **`container('git')` — `bitnami/git:latest` runs as root, rejected by `runAsNonRoot`**:
  - Reverted to `alpine/git:latest` with an explicit `securityContext.runAsUser: 1000` and `env HOME=/tmp`.
  - **Root cause**: `bitnami/git:latest` on Docker Hub has no `USER` instruction — the effective UID is 0. Kubernetes `runAsNonRoot: true` rejects the container at startup with `CreateContainerConfigError`.
  - **Why `alpine/git` works**: Kubernetes `runAsUser: 1000` overrides the image default at runtime (the process is non-root even though the image has no `USER` instruction). `HOME=/tmp` is required so `git config --global` writes to `/tmp/.gitconfig` instead of `//` (which would be EPERM under UID 1000 with an unset HOME).
  - **Files**: `vars/MicroservicesPipeline.groovy`

---

## [v0.10.13] - 2026-06-19

### Fixed
- **`container('git')` — `ErrImagePull: bitnami/git:2-debian-12` tag does not exist**:
  - Changed image reference from `bitnami/git:2-debian-12` to `bitnami/git:latest`.
  - Docker Hub's bitnami/git repository only publishes a `latest` tag; versioned tags (`2-debian-12`, etc.) are only available on `registry.hub.docker.com` via Bitnami's own registry, not the standard Docker Hub pull path.
  - **Files**: `vars/MicroservicesPipeline.groovy`

---

## [v0.10.12] - 2026-06-19

### Security
- **Non-root container hardening across all Jenkins pipeline agent containers**:
  - Added `securityContext.allowPrivilegeEscalation: false` to all containers: `maven`, `node`, `helm`, `git`, `semgrep`, `trivy`, `jnlp`.
  - Set `securityContext.runAsUser: 1000` + `env HOME=/tmp` on `helm` (alpine/k8s) and `git` containers so processes run as a non-root UID.
  - Switched `git` container from `alpine/git:latest` to `bitnami/git:latest` (Debian-based, no root default) — subsequently reverted in v0.10.13/v0.10.14 due to image availability and root-image issues.
  - Added `securityContext.runAsNonRoot: true` on `helm` and `git` containers to enforce the constraint at the Kubernetes API level.
  - Containers that legitimately require root are explicitly documented and kept as `runAsUser: 0`: `docker` (DinD requires root for the daemon), `codeql` (requires `apt-get` for Node.js installation).
  - **Files**: `vars/MicroservicesPipeline.groovy`, `vars/MicroservicesK6SmokePipeline.groovy`

---

## [v0.10.11] - 2026-06-19

### Fixed
- **`MicroservicesK6SmokePipeline` — `Checkout Infra` OOM / `ClosedChannelException`**:
  - Applied the same JENKINS-30600 fix from v0.10.8 to the k6 smoke pipeline's `Checkout Infra` stage.
  - The DSL `git url:` step was running inside the 256 Mi JNLP container (ignoring the `container('helm')` wrapper), causing OOM-kill on the k6 agent pod.
  - **Fix**: Replaced DSL `git url:` with `sh "git clone --depth 1 --branch ..."` inside `container('helm')`, which has 128 Mi headroom and `GIT_LFS_SKIP_SMUDGE=1` to avoid downloading LFS assets.
  - **Files**: `vars/MicroservicesK6SmokePipeline.groovy`

---

## [v0.10.10] - 2026-06-19

### Reverted
- **Reverted premature `runAsUser: 1000` on `container('git')`** (introduced experimentally, not released):
  - Setting `runAsUser: 1000` on `alpine/git` without also setting `HOME=/tmp` caused `git config --global` to write to `//.gitconfig` (`HOME=/` is the image default), which failed with EPERM under UID 1000 and disconnected the agent — all subsequent `sh` steps returned exit 127.
  - The correct approach (setting both `runAsUser` and `HOME=/tmp`) was implemented in v0.10.14.

---

## [v0.10.9] - 2026-06-19

### Fixed
- **`Deploy to Kubernetes` stage — EPERM on `deleteDir()` / `find -delete`**:
  - Renamed the GitOps working directory from `jenkins-2026-infra` to `jenkins-2026-gitops` to avoid naming collisions with the `Checkout Infra configs` stage.
  - Moved the `find . -mindepth 1 -delete` cleanup inside `container('git')` so the same UID that created the files (root, via `alpine/git` at the time) can delete them.
  - **Root cause**: `deleteDir()` called from the JNLP context (UID 1000) could not remove files owned by root (UID 0, from `alpine/git`), causing `Operation not permitted (EPERM)` and breaking the deploy stage on subsequent runs.
  - **Files**: `vars/microservicesDeploy.groovy`

---

## [v0.10.8] - 2026-06-19

### Fixed
- **JENKINS-30600 — DSL `git url:` step ignores `container()` wrapper, runs in JNLP (OOM)**:
  - Replaced all DSL `git url: ..., branch: ...` calls in `MicroservicesPipeline.groovy` with explicit `sh "git clone --depth 1 -c filter.lfs.smudge= ..."` inside the target container block.
  - **Root cause**: A long-standing Jenkins Kubernetes plugin bug (JENKINS-30600) causes the built-in `git` pipeline step to always execute in the JNLP sidecar container, regardless of any surrounding `container('...')` block. The JNLP container has only 256 Mi of memory and performs a full (non-shallow) clone including LFS pointer resolution, causing OOM-kill.
  - **Fix**: Using `sh "git clone"` inside a `container()` block correctly honours the container override. `--depth 1` reduces the clone to a single commit; `GIT_LFS_SKIP_SMUDGE=1` skips LFS asset downloads entirely.
  - **Files**: `vars/MicroservicesPipeline.groovy`

---

## [v0.10.7] - 2026-06-19

### Fixed
- **Jenkins agent pods — missing `JENKINS2026_REPO_BRANCH` and other env vars**:
  - Added `globalNodeProperties` to `jenkins/casc/jcasc-base.yaml` to propagate `JENKINS2026_REPO_BRANCH`, `JENKINS2026_REPO_URL`, and `JENKINS2026_GITOPS_REPO_URL` as global environment variables available to all agent pods.
  - Without this, pipeline stages that reference `env.JENKINS2026_REPO_BRANCH` (e.g. shared library version selection, GitOps branch targeting) received empty strings.
- **Jenkins agent pods — missing Karpenter toleration**:
  - Added `tolerations: [{key: jenkins-agent, operator: Equal, value: "true", effect: NoSchedule}]` to the agent pod spec in `MicroservicesPipeline.groovy`.
  - Without this toleration, agent pods could not be scheduled onto Karpenter-managed nodes tainted with `jenkins-agent=true:NoSchedule`, causing pipeline builds to queue indefinitely.
- **`microservicesDeploy.groovy` — ArgoCD sync/wait timeout too short**:
  - Extended the ArgoCD `app wait --timeout` from 120 seconds to 300 seconds to accommodate slower rollouts (image pull, CNPG cluster readiness).
- **Files**: `jenkins/casc/jcasc-base.yaml`, `vars/MicroservicesPipeline.groovy`, `vars/microservicesDeploy.groovy`

---

## [v0.10.6] - 2026-06-19

### Fixed
- **Jenkins Seed Job - Agent Pod Memory Limit**:
  - Increased JNLP agent pod memory limit from 256Mi to 512Mi in `Jenkinsfile.seed`.
  - The undersized memory limit was causing the agent pod to be OOM-killed during git checkout operations, resulting in `java.nio.channels.ClosedChannelException` and seed-jobs build failures on GKE cluster provision.
  - Also increased CPU request from 10m to 50m and limit from 200m to 500m to improve checkout performance during cluster bootstrap.
  - **Root Cause**: When Git LFS files were not yet skipped (before v0.10.4), the pod exhausted memory attempting to download 152MB of media assets. Now, even with LFS skip in place, the pod had insufficient headroom for reliable git operations. Increasing to 512Mi provides a reliable buffer.
- **Jenkins Seed-Pipelines - Build Timeout & Queue Tracking** (continuation of v0.10.5 work):
  - Extended seed-jobs build timeout from 6 minutes to 7.5 minutes to allow Jenkins plugins to fully initialize on fresh cluster provisions.
  - Refactored build tracking to use Jenkins queue API instead of blind polling, providing immediate failure detection and clearer error messages.
  - Fixed job-count verification threshold to match smoke-test expectations (NUM_SERVICES + 2 instead of + 1).

## [v0.10.5] - 2026-06-19

### Fixed
- **Jenkins Seed-Pipelines - Build Timeout & Job Count Verification**:
  - Extended timeout for seed-jobs build completion from 60 seconds to 360 seconds (6 minutes).
  - Refactored build status polling to use Jenkins queue API for direct build tracking instead of blind polling.
  - Fixed job-count threshold from (NUM_SERVICES + 1) to (NUM_SERVICES + 2) to align with smoke test expectations.
## [v0.10.4] - 2026-06-19

### Fixed
- **Jenkins Seed Job - Git LFS skip on checkout**:
  - Added `GIT_LFS_SKIP_SMUDGE=1` env var to the `Checkout jenkins-2026` stage in `Jenkinsfile.seed`.
  - The seed job's lightweight JNLP agent (256Mi) was attempting to download ~234 MB of Git LFS media assets on every checkout, causing the build to fail/hang and preventing pipeline job creation (broke the `02.01 GKE provision` smoke test).

## [v0.10.3] - 2026-06-19

### Added
- **README - CNPG Clarification Banner**:
  - Added a prominent banner in the NotebookLM multimedia section clarifying that the project uses **CloudNative-PG (CNPG)**, not CrunchyData PGO.
  - The NotebookLM-generated multimedia assets (video, audio, PDF, infographic) incorrectly reference CrunchyData PGO despite being generated after the migration to CNPG.
  - The banner directs readers to the authoritative `cnpg-app.yaml` and the companion GitOps config repo for the current PostgreSQL operator configuration.

## [v0.10.2] - 2026-06-18

### Fixed
- **Jenkins Pipelines - Git LFS skip on infra checkout**:
  - Added `GIT_LFS_SKIP_SMUDGE=1` env var to the `Checkout Infra configs` stage in `MicroservicesPipeline.groovy` and the `Checkout Infra` stage in `MicroservicesK6SmokePipeline.groovy`.
  - Prevents Jenkins agents from downloading ~234 MB of Git LFS media assets (MP4/M4A/PDF/JPG stored under `docs/notebooklm/`) on every pipeline run, regardless of whether `git-lfs` is installed in the agent pod.

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
