# Changelog

All notable changes to **jenkins-2026** are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

- **`Unreleased`** — changes accumulate under the section below as PRs merge; cutting
  a release renames it to a dated `## [vX.Y.Z]` section and starts a fresh `Unreleased`.
- **Versioning** — **`v1.0.0` is the stable baseline.** From 1.0 on: **minor** (`v1.Y.0`)
  at a feature milestone, **patch** (`v1.Y.Z`) for hotfixes, **major** (`v2.0.0`) for
  breaking changes. Every version is a git **tag** *and* a GitHub **release**, one-to-one,
  cut from its section by [`scripts/cut-release.sh`](scripts/cut-release.sh). See
  [`RELEASING.md`](RELEASING.md) for the full flow.
- **Pre-1.0 history** — the **`v0.x` line (v0.1.0 – v0.29.0)** was rapid pre-release
  development; those releases are a **frozen historical record** (never renumbered — that
  would break version immutability). Versions **≤ v0.28.56** live verbatim in
  [`CHANGELOG-ARCHIVE.md`](CHANGELOG-ARCHIVE.md) to keep this file scannable; the
  [release index](#release-index) links every milestone.

## [Unreleased]

_Post-1.0 observability & idempotency fixups — an **Azure Managed Grafana** bring-up pass that
uncovered several managed-mode (OTLP → Azure/AWS managed-Prometheus) query incompatibilities,
plus a robust-retire hardening for feature-flag switches._

### Added
- **README header + Stack badges (#500–#502).** Status badges (release, CI, license) and a full **46-badge Stack inventory** grouped by feature-flag axis; fixed a stale Jenkins-only blurb (this runs four CI engines).
- **Collector memory-pressure alert — `06-otel-collector-memory` (#510).** Warns at gateway-collector RSS > 70 % of its limit, *before* the 80 % `memory_limiter` silent-drop threshold, so a future dropped-scrape "No data" surfaces loudly instead of silently.
- **`rum-faro` in the k6 GitHub Actions `run_all` matrix (#503).**

### Changed
- **Container CPU panel shows millicores (#517)** instead of fractional cores — readable for small pods.
- **managed-azure OTel collector memory 512Mi → 1Gi (#508).** The gateway self-scrapes high-cardinality cAdvisor there; the smaller limit tripped the `memory_limiter`, silently dropping infra metrics.
- **The `pod & container infra` dashboard row is backend-neutral (#513).** The "free tier / leanMetrics" caveat is Grafana-Cloud-only; the row populates normally on OSS/Azure/AWS.
- **Mode/engine switches are now robustly idempotent (#518).** `remove_oss_observability_app` + `retire_ci_engine` force-prune workloads by Helm `instance` label and strip a stuck ArgoCD `resources-finalizer`, so a switch converges with **no manual `kubectl`** even from a mixed state — and no longer risks deleting a managed-mode standalone node-exporter via a shared label.
- **Jenkins plugin pins bumped to latest available (7 plugins).** `apache-httpcomponents-client-5-api`, `caffeine-api`, `jackson2-api`, `jackson3-api`, `pipeline-graph-view`, `workflow-cps` (Pipeline: Groovy), `pipeline-input-step` — in [`helm/jenkins/values-common.yaml`](helm/jenkins/values-common.yaml). Applied on the next Jenkins (re)deploy.

### Fixed
- **Container CPU / memory now correct on managed-azure/aws (#511 → #514 → #519).** The OTLP round-trip to managed-Prometheus drops the cAdvisor `container` label **and the per-app-container series entirely** (only the pod-level cgroup + pause survive), so both `container!=""` and `image!=""` read ≈0. Final fix takes the pod-level total via **`max by (pod)`**; live-verified against `kubectl top`.
- **Azure-safe dashboard queries (#512, #506).** Azure Managed Prometheus rejects `__name__=~` regex (`501 Not Implemented`), so all such selectors now use exact names unioned with `or` — which also fixes the CNPG counter `_total` OTLP-suffix divergence (#506).
- **Collector-memory alert corrected for managed modes (#516).** It filtered `image!=""` (same trap as the panels — on Azure that matched only the ~0 pause container); now `max by (pod)` on the collector pod.
- **`Error rate by service (4xx+5xx)` showed "No data" instead of 0 (#505)** when all traffic was 2xx — added a per-service zero fallback.
- **`Day2.publish.03` no longer re-publishes off-engine CI dashboards (#515).** Its CI-dashboard gating was a stale jenkins/tekton binary that kept re-creating the github-actions + argo-workflows boards on a Jenkins cluster; now the full 4-engine keep/delete gating, matching Day1 and `07`.
- **Day1 `grafana-cloud-token` teardown order on a `destroy_unused_backends` switch (#507).**
- **Faro/RUM dashboard defaulted to the empty `develop` tier.** RUM beacons are tagged `deployment_environment=stable` (the SPA-serving gateway and the `rum-faro` synthetic test run in the **stable** tier; `develop` is the lean optional tier with no RUM), but `rum-frontend` defaulted its `deployment_environment` variable to `develop` → "No data". Now defaults to `stable`, consistent with `microservices-overview` / `k6-smoke-overview`.
- **Argo Workflows engine: the `github` EventSource + eventbus wouldn't come up.** Two issues: (1) the EventSource used an empty `repositories: []` (manual-webhook design) which **Argo Events v1.9.4** rejects (`either repositories or organizations is required`) → it never provisioned; now `organizations: [nubenetes]` satisfies the validation while keeping the no-static-list / no-auto-register (no `apiToken`) design. (2) On a switch **away** from argoworkflows, the `default` eventbus got stuck `Terminating` (its `eventbus-controller` finalizer refuses to complete while an EventSource is connected, and the controller is deleted alongside it) → no NATS + no `eventbus-default-client` secret → the sensor stuck `ContainerCreating`. `retire_ci_engine` now strips the Argo Events (sensor/eventsource/eventbus) finalizers before deleting the namespace, so an engine switch no longer deadlocks — the same finalizer-deadlock class as #518, extended to Argo Events.
- **Argo Workflows `fetch-source` failed for the gateway (`bash: not found`, exit 127) (#525).** The step runs on the busybox-only `alpine/git` image but invoked the shared `patch-app-source.sh` (the gateway MySQL→PostgreSQL + NoOp-cache patch) with `bash`, which that image lacks. It now runs it with `sh`; the script is POSIX-sh-compatible (verified parse-clean), and the other three engines keep running it with `bash` in bash-having images.
- **Argo Workflows git-push webhook wasn't wired end-to-end (#526).** Three faults on the public `argo-events.<domain>/push` path: (1) `06-argoworkflows-pipelines.sh` built the hook URL without the `/push` suffix the github EventSource serves on, so a hook to the bare host `404`s; now `…/push`. (2) The `argo-events` HTTPRoute had **no `HealthCheckPolicy`**, so the GKE Gateway's default HTTP-GET-`/` probe hit the POST-only receiver, marked the backend unhealthy, and the endpoint **`503`'d** (same failure mode the faro receiver already guards against) — added a **TCP `HealthCheckPolicy` on :12000**. (3) The webhook reconcile only skipped an *exact-match* hook, leaving a previous engine's hook (e.g. Tekton's `pac.<domain>`) behind on the forks 404ing forever; it now **prunes any stale project-domain hook** before ensuring the desired one, so an engine switch self-heals on the fork side too. Verified live: a GitHub test push returns `200 OK` and the Sensor submits a Workflow.
- **Argo Workflows UI had no IAP + its live-events SSE dropped every 30s, in ESO mode (#527).** `08.6-eso-sync.sh`'s IAP-namespace list was a binary `tekton` / `else→jenkins`, so with `ci.engine=argoworkflows` + `secrets.backend=eso` it emitted the `gateway-iap-oauth` ExternalSecret for the **absent `jenkins`** namespace instead of `argo` → the argo-server's `GCPBackendPolicy` referenced a missing secret + empty clientID → **`Attached=False (Invalid)`**. Two consequences: (a) IAP wasn't enforced, so the `--auth-mode=server` UI was reachable **unauthenticated**; (b) the policy's `timeoutSec: 3600` never applied, so the GKE LB's default 30 s backend timeout severed the `/api/v1/workflow-events` SSE stream → the UI's recurring "Failed to connect" toast. Fixed: the emitter now uses the same `tekton`/`jenkins`/`argoworkflows` elif chain as `01-namespaces.sh` and `09-gateway.sh` (githubactions adds none), so the IAP secret lands in `argo` and the policy attaches.
- **Tekton PaC engine: stale fork webhooks weren't pruned on a CI-engine switch (symmetric to #526).** `06-tekton-pipelines.sh`'s webhook reconcile only *skipped an exact-URL match*, so switching **to** Tekton left the previous engine's hook (e.g. argo-events' `argo-events.<domain>/push`) on the forks, `404`ing on every delivery forever. It now applies the same reconcile as argoworkflows' `06`: prune any hook whose `config.url` is under this project's base domain and isn't the desired `pac.<domain>`, then ensure the desired one — so an engine switch self-heals on the fork side for Tekton too. Tekton's EventListener serves health on `/`, so no `HealthCheckPolicy` is needed here (unlike argo-events) — only the prune applies.

### Documentation
- **Per-mode OTel collector metrics-collection & memory sizing (#509).** A matrix (which component scrapes the infra per mode, collector memory per mode) + the silent `memory_limiter` drop signature and the managed-mode query gotchas (dropped `container` label / per-app-container series, `__name__=~` 501, counter `_total`), in `docs/301` + `docs/902`.
- **`run_all` now includes `rum-faro` (#504)** in `docs/302`.

<!--
Template — keep only the sections you use, in this order:
### Added        — new features
### Changed      — changes in existing behaviour
### Deprecated   — soon-to-be-removed features
### Removed      — removed features
### Fixed        — bug fixes
### Security     — vulnerability fixes
### Documentation — docs-only changes
-->

## [v1.0.0] - 2026-07-02

_First stable release._ Promotes **jenkins-2026** from its `v0.x` rapid-development line (v0.1.0–v0.29.0, now a frozen historical record — its last increment consolidated in [v0.29.0](#v0290---2026-07-02)) to a stable **1.0** baseline. No functional change versus v0.29.0; this release declares the reference PoC feature-complete and adopts the 1.0 versioning policy in [`RELEASING.md`](RELEASING.md) (from here: minor = features, patch = fixes, major = breaking).

### What v1.0.0 delivers

The complete, working reference platform — a Jenkins-on-Kubernetes CI/CD PoC with full OpenTelemetry observability, pluggable along three axes:

- **CI engine** (`ci.engine`) — **four interchangeable engines** running the same 10-stage pipeline from one `jenkins/pipelines/services.yaml`: **Jenkins** (default), **Tekton**, **GitHub Actions/ARC**, **Argo Workflows**. Switching engines fully retires the previous one.
- **Observability backend** (`observability.mode`) — **four backends** with correlated traces/metrics/logs, dashboards + alerts provisioned as code, and synthetic Faro RUM: in-cluster **OSS** (Grafana/Loki/Tempo/Prometheus), **Grafana Cloud**, **Azure Managed Grafana**, **Amazon Managed Grafana**.
- **Secrets backend** (`secrets.backend`) — `imperative` (default) or `eso` (GCP Secret Manager + External Secrets Operator, keyless WIF).
- **Platform** — GitOps via **ArgoCD** (app-of-apps), **HA CloudNative-PG** Postgres, **Gateway API + Google IAP** ingress, **Dataplane V2 + WireGuard** networking, elastic **Spot Node Auto-Provisioning**.
- **Lifecycle** — a clean, idempotent **Day0 → Day1 → Day2 → Decom** flow; one-command bootstrap; **rebuild-safe** by design (`docs/104-REBUILD_SAFETY.md`).
- **Docs & release process** — ~20 numbered deep-dive docs, plus this scannable changelog + [`RELEASING.md`](RELEASING.md) convention with [`scripts/cut-release.sh`](scripts/cut-release.sh).

### Changed
- **Adopted a stable `v1.0.0` baseline and 1.0 versioning semantics.** The `v0.x` line is frozen as pre-release history (not renumbered — preserving version immutability); [`RELEASING.md`](RELEASING.md) now documents minor/patch/major from 1.0 on.

## [v0.29.0] - 2026-07-02

_rebuild-safety & observability hardening._ Consolidates everything since **v0.28.56** (31 PRs, #467–#497). Two hardening initiatives dominate: a **system-wide rebuild-safety audit** — persistent/external state colliding with a fresh Decom+Day1 — now captured as `docs/104-REBUILD_SAFETY.md` with the gaps it found closed, and a **Grafana/observability fixup pass** clearing "No data" panels, enforcing an obs-mode single-active-credential invariant, and refreshing every dashboard to its AI-optimized export. Rounded out by k6 cold-start/summary hardening, deadlock-proof CI-engine retirement, and a large 2→4-CI-engine docs alignment. The final three fixes (#495–#497) were live-validated on a real cluster.

### Added
- **Rebuild-safety deep-dive — `docs/104-REBUILD_SAFETY.md` (#490).** Documents the "persistent/external state vs. a fresh Decom+Day1 rebuild" bug class: a safe-by-design matrix of the ~30 mechanisms that already survive a rebuild, plus the collision/residue failure modes to watch for.
- **Obs-mode single-active credential-Secret invariant (#492, #493).** Only the active `observability.mode` should have a live credential Secret in-cluster; the doc now states the invariant and `docs/201` cross-links it (#494) to its group-4 (imperative) provisioning rationale.

### Changed
- **CloudNativePG operator pinned to v1.30.0 (chart 0.29.0) (#486).** Version-pin bump for the CNPG Postgres operator.

### Fixed
- **Rebuild-safety: 4 persistent-state/rebuild collision gaps closed (#488).** GSA tombstone adoption (`create_ignore_already_exists`), ghcr retention set to delete-only-untagged, the Jenkins image tag now carries the commit SHA, and per-state-prefix concurrency so parallel runs can't clobber shared Terraform state.
- **Rebuild-safety: deferred audit items closed (#489).** grafana-token teardown-order guard and a shared tflock-cleanup composite action.
- **CNPG WAL archiving is now rebuild-safe (#487).** A fresh Postgres provision clears the stale barman/WAL path in the persistent backups bucket, so archiving no longer breaks with `Expected empty archive` after a Decom+Day1.
- **Obs-mode switch retires other modes' credential Secrets on provision (#492).** Fixes a stale Grafana Cloud link surfacing on an `oss` cluster; enforces the single-active-Secret invariant.
- **Broken `https://grafana.null` links fixed (#495).** Corrected a wrong `yq` key that was producing dead Grafana URLs. _(live-validated)_
- **RUM Sessions panels no longer error (#496).** Raised Loki `max_query_series` so the RUM Sessions panels stop hitting the series limit. _(live-validated)_
- **Node-pool resize can no longer stall on pause (#497).** PodDisruptionBudgets are deleted up front so the scale-to-zero resize isn't blocked. _(live-validated)_
- **Grafana "No data" panel fixes (#484, #485).** JVM runtime-context panel now filters `target_info` by `job` instead of `service_name` (#484); the Postgres dashboard drops the wrong `_total` suffix on `cnpg_pg_stat_*` metrics (#485).
- **k6 warm-up traffic excluded from smoke dashboards (#482, #483).** Warm-up requests are filtered out of the smoke dashboard panels (#482), with the same filter applied to the cloud-export V1/V2 dashboard backups (#483).
- **Dashboards refreshed to AI-optimized exports (#467, #470).** NAP/Spot auto-import updated to the 9-panel AI-optimized version (#467); jenkins/postgres/jvm/rum deployed dashboards refreshed from their AI-optimized exports (#470).
- **k6 cold-start no longer flips smoke to UNSTABLE (#481).** A readiness gate in `setup()` waits for the app to warm up before asserting thresholds.
- **k6 per-check pass/fail tree in the summary (#480).** The summary text now shows the per-check tree across all engines, making a threshold breach diagnosable from the logs.
- **`Show Results Summary` no longer exits 5 on the rum-faro run (#491).** The metrics-less rum-faro summary no longer crashes the summary step.
- **Complete, deadlock-proof CI-engine retirement (#475, #476).** A shared `retire_ci_engine` helper fully removes the previous engine's ArgoCD apps/namespaces without the NEG-finalizer/namespace-finalizer deadlock (#475); the observability-mode switch likewise deletes stale oss child apps explicitly, plus a lifecycle audit (#476).
- **GitHub Actions security hardening (#472).** Dropped the `pull_request` trigger, added deploy-step guards, and applied light branch protection on the app forks.

### Documentation
- **Exhaustive 2→4 CI-engine alignment across the docs (#477).** Updated ~29 docs from the old two-engine (Jenkins/Tekton) framing to all four engines, with factual fixes throughout.
- **Architecture diagram redesign (#473, #474, #478).** `docs/201` System Architecture diagram redrawn — 4 CI engines, per-zone colours, square ELK layout, fixed arrows (#473); surrounding prose restructured into nested bullets + numbered "Pluggable choices" (#474); remaining mermaid diagrams aligned with main and 2 pre-existing broken diagrams fixed (#478).
- **Why JHipster / why this demo app (#471).** New `docs/202` rationale section with a README mirror and a 404 pointer.
- **`runNodePool` is per-engine for all four engines (#479).** Clarified the per-engine `runNodePool` flag and fixed a stale `docs/501` anchor.
- **cloud-export dashboard inventory (#468, #469).** Completed the cloud-export set (10 × v1+v2) with canonical `<slug>.vN.ext` names and a single matrix inventory (#469); README updated with the NAP v1 export and corrected provisioning notes (API not gcx, V1/V2 compatibility) (#468).

---

## Release index

Every milestone release (git tag + GitHub release), newest first. Full detail for
**v0.28.56 and earlier** lives in [`CHANGELOG-ARCHIVE.md`](CHANGELOG-ARCHIVE.md).

| Version | Date | Theme |
|---|---|---|
| [v1.0.0](#v100---2026-07-02) | 2026-07-02 | **first stable release** — reference platform baseline |
| [v0.29.0](#v0290---2026-07-02) | 2026-07-02 | rebuild-safety & observability hardening (last v0.x) |
| [v0.28.56](CHANGELOG-ARCHIVE.md) | 2026-06-30 | two new CI engines — GitHub Actions/ARC + Argo Workflows |
| [v0.28.54](CHANGELOG-ARCHIVE.md) | 2026-06-30 | elastic CI — GKE Node Auto-Provisioning (Spot) + per-engine runNodePool |
| [v0.28.0](CHANGELOG-ARCHIVE.md) | 2026-06-28 | Faro RUM, JVM tuning everywhere, build speed, immutable tags |
| [v0.26.0](CHANGELOG-ARCHIVE.md) | 2026-06-27 | public develop microservices URL + Tekton URL annotations |
| [v0.25.0](CHANGELOG-ARCHIVE.md) | 2026-06-27 | k6 committed config presets (dropdown-selectable) |
| [v0.23.0](CHANGELOG-ARCHIVE.md) | 2026-06-27 | lean develop microservices tier (CI-gated, engine-neutral) |
| [v0.22.0](CHANGELOG-ARCHIVE.md) | 2026-06-26 | Tekton CI engine, pluggable secrets (ESO), Dataplane V2, managed-Grafana parity |
| [v0.21.0](CHANGELOG-ARCHIVE.md) | 2026-06-23 | redeploy tier + verb-free workflow names |
| [v0.20.0](CHANGELOG-ARCHIVE.md) | 2026-06-23 | Day2.deploy.01-argocd + ArgoCD-first deploy tier |
| [v0.19.0](CHANGELOG-ARCHIVE.md) | 2026-06-23 | DayN workflow scheme + ArgoCD app-of-apps |
| [v0.15.0](CHANGELOG-ARCHIVE.md) | 2026-06-22 | per-mode alert emails, Alert Rules banner, secrets inventory & Day-0/1/2 docs |
| [v0.14.0](CHANGELOG-ARCHIVE.md) | 2026-06-22 | Grafana alerting provisioned as code |
| [v0.13.0](CHANGELOG-ARCHIVE.md) | 2026-06-22 | Y.X.ZZ workflow naming + Azure dashboard publish |
| [v0.12.0](CHANGELOG-ARCHIVE.md) | 2026-06-21 | Managed Cloud Observability (Azure/AWS), OSS-Live & optional develop tier |
| [v0.11.0](CHANGELOG-ARCHIVE.md) | 2026-06-20 | Observability deep-dive & signal correlation |
| [v0.8.0](CHANGELOG-ARCHIVE.md) | 2026-06-17 | CloudNative-PG migration & GKE cluster observability |
| [v0.7.0](CHANGELOG-ARCHIVE.md) | 2026-06-17 | comprehensive GKE topology rewrite |
| [v0.6.0](CHANGELOG-ARCHIVE.md) | 2026-06-16 | k6 smoke dashboard + dynamic Jenkins/Grafana URLs |
| [v0.5.0](CHANGELOG-ARCHIVE.md) | 2026-06-14 | smart-polling deploys, JCasC hardening |
| [v0.1.0](CHANGELOG-ARCHIVE.md) | 2026-06-13 | initial PoC |

_The `v0.x` line (v0.1.0 – v0.29.0) was pre-1.0 rapid development — its interim patch
versions (e.g. the `v0.28.x` series) are consolidated under their milestone in the
archive. **v1.0.0 is the stable baseline**; from here the changelog uses 1.0 semantics
(minor = features, patch = fixes, major = breaking)._
