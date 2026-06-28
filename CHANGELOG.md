# Changelog

All notable changes to this project will be documented in this file.

## [v0.28.9] - 2026-06-28

Increment over v0.28.8 (postgres dashboard validation fix).

### Fixed
- **Postgres dashboard "WAL receiver up" always showed down.** It used
  `min(cnpg_pg_replication_is_wal_receiver_up)`, which includes the primary (whose receiver is
  always 0) and so masked healthy replicas. Changed to `sum(...)` → "Replica WAL receivers up"
  shows the count actually streaming (4 on stable; 0 on develop, mapped to "no replicas
  (single-instance)"). Full validation under live k6 load confirms **every panel returns series
  on both the stable and develop tiers** (no "No data"); remaining zeros are healthy state
  (0 replication lag, 0 deadlocks, 100% cache → 0 disk-read time) or by-design on the lean
  develop tier (single-instance, no backups).

## [v0.28.8] - 2026-06-28

Increment over v0.28.7 (fix CNPG WAL archiving / backups).

### Fixed
- **CNPG WAL archiving + backups were failing 403 — now work.** The `<cluster>-pg-backups` GSA
  (impersonated by the postgres pods via Workload Identity) had `roles/storage.objectAdmin` on
  the backups bucket, which lacks `storage.buckets.get` — the permission
  `barman-cloud-check-wal-archive` calls when validating the destination. Result: every WAL
  archive failed (`ContinuousArchivingFailing`, 1000+ failures, `.ready` WAL piling up) and no
  base backup could run, so the dashboard's backup/archiving panels read "no backups configured".
  Fix: grant the GSA `roles/storage.admin` **scoped to the backups bucket** (mirrors
  `ci_postgres_backups`; still least-privilege). After applying, archiving recovered
  (`ContinuousArchivingSuccess`) and base backups for both stable clusters completed. develop is
  unaffected (lean tier — no `barmanObjectStore`, so it never archived). `terraform/gke`.

## [v0.28.7] - 2026-06-28

Increment over v0.28.6 (postgres dashboard polish + traces-sampling rationale).

### Fixed
- **PostgreSQL/CNPG dashboard: no empty panels, no layout gaps.** Every band now tiles to a
  full 24-col width at a uniform height (0 overlaps, 0 gaps). Resilience added so stats render
  `0`/explanatory text instead of "No data": collector-errors, backup/recoverability (mapped to
  "no backups configured"), archival counters, and the replication-detail panels (which are
  empty on single-instance tiers like develop) now read `0` with descriptions noting they need
  replicas. Verified against the live Grafana Cloud Prometheus on both the stable and develop tiers.

### Docs
- **Documented why traces are not sampled on the free tier** — in `docs/301` and in the
  `grafana_cloud_tier` GHA dropdown description itself: traces ship at 100% on both tiers because
  the PoC volume fits the free tier and sampling would break trace↔log/metric correlation.

## [v0.28.6] - 2026-06-28

Increment over v0.28.5 (deep CloudNativePG/PostgreSQL dashboard).

### Changed
- **`CI-CD / PostgreSQL (CloudNativePG)` dashboard rebuilt** from 11 → 62 panels across 10
  sections, modelled on the official CloudNativePG dashboard + Postgres SRE practice, driven
  by the live `cnpg_*` metric set (PG 18.3 / current CNPG): cluster health & topology
  (primary/replicas/version/uptime/switchover/fencing), connections & sessions (by
  state/instance/db/user, waiting, longest txn), throughput/TPS & row activity (commits vs
  rollbacks, rollback ratio, tuple ops, temp spill, deadlocks/conflicts), cache & block I/O
  (hit ratio, read/write time), WAL & checkpoints (bytes/records/FPI, buffers-full, timed vs
  requested, write/sync time), streaming replication (lag seconds, write/flush/replay lag &
  diff bytes, slots/retained WAL, WAL receiver), storage + **transaction-ID/multixact
  wraparound** monitoring, WAL archiving & backups, bgwriter & collector health, and a logs
  panel with the `$level` filter. New template vars: `pod` (instance) and `datname` (database),
  both multi-select. All queries verified against the live Grafana Cloud Prometheus.

## [v0.28.5] - 2026-06-28

Increment over v0.28.4 (Grafana Cloud tier profile).

### Added
- **`observability.grafanaCloudTier` (`free` default | `paid`)** — a one-switch profile that
  sets the volume-control defaults so the free tier stays under its limits. `free` →
  `leanMetrics` on + `logMinSeverity=warn`; `paid` → full metrics + ship all logs (`trace`).
  It governs **metrics (`leanMetrics`) and logs (`logMinSeverity`)** — **not traces yet.**
  `leanMetrics`/`logMinSeverity` now default to **`auto`** (derive from the tier); an explicit
  value, the `JENKINS2026_*` env, or the GHA dropdown overrides it (precedence: env > explicit
  config > tier). Exposed as a **`grafana_cloud_tier`** dropdown on the workflows that re-apply
  `03-observability` (`Day1.cluster.01-gke` + the `Day1.cluster.00-all` umbrella +
  `Day2.redeploy.01-argocd`); `log_min_severity` gained an `auto` option (now its default).
  Only meaningful in grafana-cloud mode (other backends stay neutral: lean off, severity info).

## [v0.28.4] - 2026-06-28

Increment over v0.28.3 (severity parsing + per-panel level filtering in Grafana).

### Added
- **Filter logs by level in the Grafana dashboards.** Every logs panel now carries a
  multi-select **`Log level`** variable wired as `… | detected_level=~"$level"` —
  interactive, non-destructive slicing by severity (`error/warn/info/debug/trace/unknown`,
  `All` includes plain-text). Default **All** on the 6 overview dashboards; **`error|warn`**
  on `jvm-internals` (troubleshooting-focused).
- **`jvm-internals` gains a Logs & Traces row** — an "Errors & Warnings (selected service)"
  logs panel scoped by `$service_name`, and a "Traces (selected service)" Tempo panel.
  Correlation is inherited from the datasource config (logs↔traces via derived fields /
  tracesToLogs, traces→metrics via tracesToMetrics), so a trace_id in a log line jumps to
  the trace, and a span jumps to its logs/metrics.

### Changed
- **The `logMinSeverity` collector filter now drops by parsed OTLP severity, not body regex.**
  A `regex_parser` in the `otel-collector-logs` filelog receiver extracts the level token from
  all three on-cluster formats (ECS nested `log.level`, flat `level`, logfmt `level=`) and
  **sets the record severity**; `filter/severity` then compares `severity_number`. This both
  hardens the floor filter (no body-regex false positives) and gives Loki a reliable
  `detected_level` on 100% of lines — which is what powers the new `$level` dashboard filter.
  Plain-text lines get `level=unknown` and are never dropped/hidden.

## [v0.28.3] - 2026-06-28

Increment over v0.28.2 (configurable Grafana log severity).

### Added
- **`observability.logMinSeverity` — a global minimum log severity for Grafana.** A `filter`
  processor injected into the `otel-collector-logs` DaemonSet (by `scripts/03-observability.sh`
  via `yq`) drops log records below the chosen level **before** they reach the backend, trimming
  **every** Grafana logs panel — microservices **and** platform components (ArgoCD, CNPG, dex…) —
  across all four obs modes. Matches structured-line level tokens (JSON `"level":"…"`, incl. the
  microservices' ECS nested form, and logfmt `level=…`), case-insensitively; **plain-text lines
  are never dropped** (no accidental blackout). `trace` disables the filter (ship everything).
  Durable default `info` (drops DEBUG/TRACE); per-run override `JENKINS2026_LOG_MIN_SEVERITY`, or
  the **`log_min_severity` dropdown** on the workflows that re-apply `03-observability`:
  `Day1.cluster.01-gke` (+ the `Day1.cluster.00-all` umbrella), and — for a light change on a
  running cluster without a full Day1 — `Day2.redeploy.01-argocd` / `Day2.publish.01-oss-grafana`.
  Distinct from the existing `log_level` knob, which only governs CI script/Terraform verbosity.
  See [docs/301 § Log Levels](docs/301-OBSERVABILITY.md#log-levels).

## [v0.28.2] - 2026-06-28

Increment over v0.28.1 (resume-side recovery).

### Fixed
- **Resume now auto-heals two one-time-init races on fresh nodes.** After `Day2.scale.02 Resume`
  brings new nodes up, CoreDNS/egress is briefly still converging, so a workload whose startup
  init runs once and never retries can fail and stay broken. Two cases were hit and are now
  recovered automatically by a post-resume step: **(1)** CNPG **replicas** the pause's
  force-drain (`--disable-eviction` DELETE) left unstartable (startup probe HTTP 500 forever) are
  **re-cloned** from the primary via `pg_basebackup` (replicas only — the primary is never
  auto-recreated); **(2)** **ArgoCD dex**, whose OIDC connector dial to the SSO provider timed out
  on DNS (`connection refused` on `:5556` at login, even though the pod reports `Ready`), is
  **restarted** so it re-inits cleanly. Both are idempotent no-ops on a clean resume. See
  [docs/501](docs/501-PLATFORM_OPERATIONS.md#the-resume-side-gotcha-one-time-init-races-dns-on-fresh-nodes-real-incident).

## [v0.28.1] - 2026-06-28

Increment over v0.28.0 (post-release fixes + activation).

### Added
- **Angular Faro RUM activated end-to-end.** The gateway SPA's Faro Web SDK is **live on
  the develop tier** (deployed image `gateway:develop-<build#>`, the served bundle posts to
  the public `faro.<baseDomain>` endpoint) and the instrumentation was **promoted to `main`**
  (Faro `environment` flipped to `stable`) so the stable tier gets RUM on its next build.

### Fixed
- **Cost-saving pause/resume no longer stalls.** `Day2.scale.01 Pause`'s graceful node-pool
  resize-to-0 hung indefinitely on **CNPG Postgres PodDisruptionBudgets** (`minAvailable=1`,
  single-instance → 0 allowed disruptions) and **autoRepair** recreating drained nodes. It now
  disables autoscaling **and autoRepair**, force-drains with `kubectl drain --disable-eviction`
  (DELETE, bypasses PDBs; data is on PVs), then resizes to 0; `Day2.scale.02 Resume` re-enables
  autoscaling **and autoRepair**. See [docs/501](docs/501-PLATFORM_OPERATIONS.md).
- **Gateway Angular build with Faro.** `@grafana/faro-*` transitive `.d.ts` reference Node types
  (`global`/`path`) → the Angular build failed (TS2304/TS2307) until `skipLibCheck: true` was
  added to the gateway tsconfig (app fork, develop + main).

## [v0.28.0] - 2026-06-28

### Added

- **`logging.level` verbosity flag (`info` default | `debug`).** Durable default in
  `config/config.yaml` (`logging.level`), per-run override `JENKINS2026_LOG_LEVEL`,
  following the existing feature-flag pattern. `scripts/lib/common.sh` adds `log_debug()`
  (emits only at `debug`, to stderr so it never pollutes a function's captured stdout);
  `scripts/lib/config.sh` adds the config default + validation. Every dispatchable GitHub
  Actions workflow gains a **`log_level` dropdown** (reusable workflows mirror it as a
  `workflow_call` input; umbrellas/preflights pass it down); a top-level `env` exports
  `JENKINS2026_LOG_LEVEL` (drives `log_debug`) and `TF_LOG=DEBUG` for the Terraform steps
  when `debug`. Deliberately **no `trace`/`set -x` level**: bash xtrace would leak
  script-derived secret values (admin password, dockerconfig, ArgoCD token) into the logs,
  which GitHub does not mask — use the native `ACTIONS_STEP_DEBUG` for runner tracing.
- **`Day2.scale.01 Pause` / `Day2.scale.02 Resume` workflows — park the cluster at
  ~zero cost without a Decom+rebuild.** Pause disables autoscaling and scales every GKE
  node pool to 0 (removes the 24/7 worker-VM cost while preserving the cluster, PVs/CNPG
  data, ArgoCD + apps, static IP, DNS, certs); Resume scales the pools back up and
  re-enables autoscaling (inputs default to `terraform/gke`'s node_count/min/max), pods
  reschedule and ArgoCD reconciles in minutes. Imperative `gcloud` (fast); the
  `terraform/gke` state drift is benign and reconciled by Resume or the next Day1.
  Grafana Cloud is free-tier (nothing to pause). See
  [`docs/101`](docs/101-GITHUB_ACTIONS_WORKFLOWS.md).
- **`jvm-internals` dashboard (uid `jenkins2026-jvm-internals`) — deep JVM diagnostics
  for every Java workload.** Modelled on community dashboards 20429 + 18812 but rewritten
  for the OTel metric names: heap by pool (Eden/Survivor/Tenured) + live-set-after-GC,
  non-heap (Metaspace/CodeHeap), GC time/freq/pause-quantiles by collector, threads
  (count/state/daemon), CPU (process + system + load), classes, buffer pools, HTTP
  latency, and a runtime-context table (`target_info`: JDK name/impl/version, OTel agent
  version). Covers the **Jenkins controller** too (filter by `service_name`; the
  `namespace` var uses `allValue='.*'` so the Jenkins JVM series — which carry no
  `k8s_namespace_name` — show under *All*); titled "CI-CD JVM internals (all Java services
  + Jenkins)", tagged `jenkins`/`jvm`. See [`docs/303`](docs/303-JVM-TUNING.md).
- **Angular Faro RUM instrumented end-to-end + activated.** The gateway SPA ships the
  Grafana Faro Web SDK (`@grafana/faro-web-sdk` + `-web-tracing`); deployed live on the
  **develop** tier (image `gateway:develop-<build#>`, bundle serves Faro → public endpoint)
  and **promoted `develop`→`main`** (Faro `environment` flipped to `stable`) so the stable
  tier gets RUM on its next build. Public ingest at `faro.<baseDomain>` (HTTPRoute + TCP
  HealthCheckPolicy). Build needed `skipLibCheck: true` in the gateway tsconfig (see docs/902).
- **`rum-frontend` dashboard (uid `jenkins2026-rum-frontend`) — Angular Real User
  Monitoring via Grafana Faro.** Core Web Vitals (LCP/INP/CLS/FCP/TTFB with Google
  thresholds), JS errors/exceptions, sessions, browser audience, live RUM logs and browser
  traces. Populated by the Faro Web SDK now shipped in the gateway SPA (live on develop, promoted to main — see
  [`docs/202`](docs/202-MICROSERVICES-APP-ARCHITECTURE.md)).
- **Grafana Faro RUM receiver in the otel-collector — on ALL four backends.** Switched the
  gateway collector to the **contrib** distro and added the `faro` receiver (`:8027`, CORS)
  wired into the traces + logs pipelines, so the Angular SPA's browser RUM beacon (Web
  Vitals, errors, sessions, browser spans) rides the same collector→backend path as the
  Java services' telemetry. Added to **all four** collector configs
  (`values-grafana-cloud` / `-oss` / `-managed-azure` / `-managed-aws`), so RUM works on
  every observability backend, not just grafana-cloud (OSS gets fully-functional RUM — its
  in-cluster Loki/Tempo match the dashboard uids). Validated end-to-end (beacon →
  Loki/Tempo).
- **Experimental JVM runtime telemetry** on the OTel Java agent
  (`OTEL_INSTRUMENTATION_RUNTIME_TELEMETRY_EMIT_EXPERIMENTAL_TELEMETRY=true` on the
  `microservices-java` Instrumentation CR) → buffer pools (direct/mapped) + system CPU,
  powering the deeper `jvm-internals` panels.
- **`Day2.traffic.02 Synthetic RUM` workflow** — POSTs synthetic Faro beacons (Web Vitals,
  sessions, JS errors, **and OTLP browser traces**) to the faro receiver via
  `kubectl port-forward`, to populate/demo/validate the RUM dashboard before the Angular SPA
  is instrumented. No environment gate (synthetic telemetry, repo-level secrets); k6
  (HTTP) can't generate RUM — real RUM needs the instrumented SPA driven by a browser.
- **k6 dashboard filters by Runner / Profile / Preset.** Every k6 run is now tagged via
  **k6 `--tag`** — `ci_runner` (`gha`/`jenkins`/`tekton`), `k6_profile`
  (smoke/load/stress/soak/spike/breakpoint) and `k6_preset` (the preset name) — across all
  three runners (`.github/workflows/Day2.traffic.01-k6.yml`, `vars/microservicesK6Smoke.groovy`,
  `tekton/tasks/k6-smoke.yaml`). **Why `--tag` and not OTEL resource attributes:** Grafana
  Cloud's OTLP→Prometheus ingestion only promotes a *fixed* set of resource attributes to
  labels (`deployment.environment` yes; custom ones land only in `target_info`), so they'd
  never reach `iterations_total`/`http_req_*` and the dashboard's `label_values()`/filters
  would stay empty — `--tag` attaches the value to **every** metric series in every output.
  The k6 dashboard gained **Runner** + **Profile** template variables (`allValue='.*'` +
  includeAll, so pre-existing untagged data still shows under *All*) filtering all panels.
  See [`docs/302`](docs/302-K6_LOAD_TESTING.md).
- **`run_all_presets` — one-click "run every k6 use case" (parallel matrix).** A new
  boolean input on `Day2.traffic.01-k6` runs **every** preset in `presets/index.yaml` as a
  parallel GitHub Actions **matrix** (a `prepare` job emits the list via `fromJson`; one
  `k6: <preset>` job each; `fail-fast: false`, `max-parallel: 4`) — one click and all use
  cases land in the dashboard, filterable by Runner/Profile/Preset. Companion
  **`run_all_duration`** input caps **every** preset to one short duration (e.g. `30s`,
  clearing its stages/rps/iterations) for a quick comprehensive pass instead of each file's
  own (e.g. 1h soak) values. `env_name` still selects the tier (preset's pinned `envName` >
  `env_name` input > default `stable`). See [`docs/302`](docs/302-K6_LOAD_TESTING.md).
- **Grafana dashboards inventory** in [`docs/301`](docs/301-OBSERVABILITY.md) (master
  matrix + per-dashboard detail + the label-model / No-Data gotchas).
- **`docs/202-MICROSERVICES-APP-ARCHITECTURE.md`** (the demo app: gateway = Java/Spring
  Cloud Gateway serving the Angular SPA, not Angular itself; Java-vs-Angular matrix;
  request flow; the Angular RUM/Faro roadmap) and **`docs/303-JVM-TUNING.md`** (JVM tuning
  + GC/runtime/OTel-instrumentation matrices, why CRaC over GraalVM Native, how to read the
  JVM dashboard).

- **Public Faro RUM endpoint — `faro.<baseDomain>` (no IAP).** The browser needs to reach
  the Faro receiver, so `scripts/09-gateway.sh` now publishes an HTTPRoute
  `faro.<baseDomain>` → `otel-collector-gateway:8027` with a **TCP** `HealthCheckPolicy`
  (the receiver only answers POST, so an HTTP-GET LB probe would mark it unhealthy; the
  wildcard cert + `*.<baseDomain>` DNS already cover the host). `config.yaml`
  `gateway.hosts.faro` + `J2026_GATEWAY_FARO_HOST`. Surfaced like every other endpoint in
  the Day1 **Access URLs** step and the **Jenkins system banner** — flagged a *beacon
  endpoint, not a UI* (POSTs only).
- **Angular RUM wired end-to-end (Grafana Faro Web SDK).** The gateway's Angular SPA (its
  **`develop`** branch fork) is instrumented with `@grafana/faro-web-sdk` + `-web-tracing`
  (`2.8.0`): `app/core/faro/faro.ts` initialised from `main.ts`, endpoint/`environment`
  from `environments/*`, posting to the public endpoint above. Real RUM flows once
  `gateway-develop` is built+deployed and the develop site is opened in a browser; it
  reaches the **stable** tier by promoting the gateway `develop`→`main` (flip the Faro
  `environment` to `stable`), not by separately instrumenting `main`. See
  [`docs/202`](docs/202-MICROSERVICES-APP-ARCHITECTURE.md).
- **App forks gain a real `develop` branch.** `nubenetes/jhipster-sample-app-gateway`
  and `…-microservice` now carry a `develop` branch (off `main`; upstream `jhipster/*` has
  only `main`), and `services.yaml` `branches.develop=develop` — so the develop tier builds
  the app's **develop** branch (true branch-based promotion), not a re-deploy of `main`.
- **`Day2.registry.01 Image retention` workflow.** Immutable per-build tags accumulate one
  tag per build, so this weekly (+ manual) workflow keeps the most-recent N versions per
  service (`gateway`, `jhipstersamplemicroservice`; default 30, above deploy cadence so the
  deployed tag is never cut) and sweeps untagged layers, bounding ghcr storage. Pure GitHub
  Packages op (no GKE); `keep`/`dry_run` inputs; new `registry` workflow tier — see
  [`docs/101`](docs/101-GITHUB_ACTIONS_WORKFLOWS.md).

### Performance

- **JVM tuning across every JVM in the platform.** The microservices ran on container
  defaults that were wrong for a server workload — HotSpot picks **SerialGC** when the
  memory limit is <1792MB (proven live: `jvm_gc_name={Copy,MarkSweepCompact}`) + only 25%
  heap. Fixed via `JDK_JAVA_OPTIONS` (kept separate from the OTel agent's
  `JAVA_TOOL_OPTIONS`; they compose):
  - **Microservices runtime** (gitops deployment template): `-XX:+UseG1GC`,
    `-XX:MaxRAMPercentage=50`, `-XX:+UseStringDeduplication`, `-XX:+ExitOnOutOfMemoryError`.
  - **Jenkins controller** (`helm/jenkins/values-common.yaml` `controller.javaOpts`):
    `MaxRAMPercentage 25→60` (live heap now ~1.8G), `+UseG1GC +ParallelRefProcEnabled
    +DisableExplicitGC +UseStringDeduplication +ExitOnOutOfMemoryError` (Jenkins was
    already G1 — server-class 3Gi — but heap-starved). The chart still appends
    `-Dcasc.reload.token`.
  - **Maven build JVMs** — Jenkins (`vars/microservicesBuild.groovy`,
    `vars/microservicesImage.groovy`) and Tekton (`tekton/tasks/maven-build-test.yaml`,
    `tekton/tasks/build-push-image.yaml`): dropped `SerialGC` → `G1GC` +
    `ExitOnOutOfMemoryError` (the image-build steps were on SerialGC).
  - Runtime: JDK 25.0.3 LTS / Eclipse Temurin / HotSpot. Rationale, GC/runtime matrices and
    the CRaC vs GraalVM-Native analysis in [`docs/303`](docs/303-JVM-TUNING.md).
- **Faster Jenkins builds — start sooner, run in parallel.** (The concurrency cap was
  already 10, in JCasC `jenkins/casc/jcasc-base.yaml` `containerCapStr`, **not** the helm
  `agent.containerCap` which the JCasC cloud overrides — so it was never the bottleneck.)
  Three levers: an **agent image pre-pull DaemonSet** (`helm/jenkins/agent-image-prepull.yaml`,
  applied by `04-jenkins.sh`) that pre-pulls all 8 agent images (maven/node/dind/helm/git/
  semgrep/**codeql, multi-GB**/trivy) onto every node so a build pod goes *Running* without a
  cold multi-image pull; **`idleMinutes 5`** on the inline pod templates
  (`vars/MicroservicesPipeline.groovy`, `vars/MicroservicesK6SmokePipeline.groovy`) so a
  re-run reuses the warm pod; and a **shallow checkout** — the app-source checkout switched
  from a full `git` clone (all history/branches/tags of the large JHipster repo) to
  `checkout([GitSCM … CloneOption depth:1, noTags, single-branch])`. See
  [`docs/401`](docs/401-JENKINS.md).
- **Faster Tekton builds.** Checkout was already shallow (`--depth 1`). Added **node-local
  Maven/npm caches** (hostPath `/tmp/tekton-*-cache` → `/root/.m2`,`/root/.npm` on
  `maven-build-test` + `build-push-image`, mirroring the Jenkins agents) so deps aren't
  re-downloaded every PipelineRun, plus a **task image pre-pull DaemonSet**
  (`tekton/agent-image-prepull.yaml`, applied by `04-tekton.sh`). See
  [`docs/403`](docs/403-TEKTON.md).
- **Immutable image tags.** Built images are tagged immutably — Jenkins
  `<branch>-<BUILD_NUMBER>` (`vars/MicroservicesPipeline.groovy`), Tekton
  `<branch>-<pipelineRunName>` (`$(context.pipelineRun.name)` appended to the build/trivy
  `image` **and** the gitops `image-tag` so they match, `tekton/pipelines/microservices-pipeline.yaml`)
  — instead of a mutable branch tag every build overwrote. Benefits: reproducible deploys,
  rollback (repoint to a prior tag), and reliable **ArgoCD change-detection** (the gitops
  values tag now changes per build, vs a static `:main` ArgoCD saw no diff on). Tekton
  variant not yet validated (engine inactive); storage bounded by the retention workflow.
  See [`docs/502`](docs/502-MICROSERVICES_GITOPS.md).

### Fixed

- **Cluster pause/resume (`Day2.scale.01`/`.02`) handle CNPG PDBs + autoRepair.** A plain
  `gcloud container clusters resize --num-nodes 0` stalled forever: CNPG Postgres
  PodDisruptionBudgets (`minAvailable=1` on single-instance tiers → ALLOWED DISRUPTIONS=0)
  block the eviction-API drain, and `autoRepair` recreated the drained nodes. Pause now
  disables autoscaling **and** autoRepair, force-drains with `kubectl drain --disable-eviction`
  (DELETE API → bypasses PDBs; data is on the PVs), then resizes to 0; resume re-enables both.
  Documented in [docs/501](docs/501-PLATFORM_OPERATIONS.md#pausing--resuming-the-cluster-cost-saving).

- **Kubernetes probes used the aggregate health endpoint for liveness (anti-pattern).**
  All three Java probes (gitops deployment template) moved to Spring Boot's dedicated
  availability groups: `livenessProbe → /management/health/liveness`, `readiness` +
  `startupProbe → /management/health/readiness`. The aggregate `/management/health`
  includes the DB/R2DBC indicators, so a transient dependency blip was failing liveness
  and restart-looping pods. See [`docs/502`](docs/502-MICROSERVICES_GITOPS.md).
- **Every Loki/Tempo dashboard panel showed No-Data even with data present.** The stack
  has **no default Loki or Tempo datasource** (only Prometheus is the global default), so
  the `${DS_LOKI}`/`${DS_TEMPO}` template variables didn't resolve (and an empty/stale
  `var-DS_LOKI` in a bookmarked URL overrode any binding). Dropped the `DS_LOKI`/`DS_TEMPO`
  template vars and bound the datasource **portably**: the base dashboards reference the
  **neutral uids `loki`/`tempo`** (which match the in-cluster OSS Grafana,
  `grafana/values-oss.yaml`), and `scripts/07-grafana-dashboards.sh` **rewrites them to
  `grafanacloud-logs`/`grafanacloud-traces` at publish time** for grafana-cloud (a `jq walk`)
  — the same per-backend rewrite `generate.py` already does for Loki/Tempo → CloudWatch/X-Ray
  on the aws/azure variants. One base, every backend works (OSS reads it as-is).
- **RUM dashboard query/variable fixes:** Loki `kind` is *structured metadata*, not an
  indexed stream label, so `{kind="measurement"}` in the stream selector returned nothing
  — filter `kind` after `| logfmt`; the `app` variable was an empty time-bounded
  `label_values` query → made it a constant; the Tempo panel used
  `queryType=traceqlSearch` (structured filters) with a raw TraceQL string → changed to
  `traceql`; dropped the deprecated **FID** Web-Vital target (Faro emits **INP**).
- **`microservices-overview` JVM panels + `postgres-overview` were empty** for the
  selected tier: JVM metrics carry `k8s_namespace_name`/`service_name`, not
  `deployment_environment`, so those panels were repointed (the env→namespace mapping is
  derived via `target_info`).

- **k6 run summary showed all-zeros in every engine (GHA, Jenkins, Tekton).** k6 2.0's
  `--summary-export` emits a *flattened* schema (`metrics.<m>.<stat>`), but all three
  consumers parse the nested `metrics.<m>.values.<stat>` (+ `.thresholds[expr].ok`)
  shape, so they silently rendered 0 requests / 0 checks / `[FAIL]` thresholds even when
  the run passed. Fixed at the source: `jenkins/pipelines/k6/microservices-smoke.js` now
  emits the summary via `handleSummary()` (whose `data` keeps the stable `.values.*`
  schema), output path overridable via `K6_SUMMARY_OUT` (Tekton); dropped
  `--summary-export` from all three engines. Also added `summaryTrendStats` with `p(99)`
  (k6's default trend stats omit it, so the summaries printed `p99=0`). Validated: 10/10
  GHA use-cases (default + 9 presets) in parallel, all success, real numbers, thresholds
  PASS. This is the complete fix for the symptom the v0.27.0 boolean-threshold patch only
  partially addressed.
- **Jenkins pipeline targeted namespace `"null"` (k6 hit `gateway.null.svc`, deploy targeted
  namespace `null`).** `MicroservicesPipeline` named its argument map `params` but declares
  **no `parameters{}` block**, so inside the declarative pipeline `params.targetNamespace`
  resolved to the *empty build-params global*, not the seed-baked arg → the literal string
  `"null"`. Renamed the arg to **`cfg`** (the safe pattern every other `vars/*.groovy`
  already uses), pass `TARGET_NAMESPACE`/`ENV_NAME` **explicitly** when triggering the k6 job
  (Jenkins doesn't apply a job's default param values on its first build after a re-seed),
  and added a preset→param→`cfg`→default coalesce in the k6 pipeline. Also fixed a Groovy
  summary crash: `String.format('%.2f', <Integer>)` threw `IllegalFormatConversionException`
  when a rate was exactly `0`/`1` (e.g. `http_req_failed=1` at 100% failure), turning an
  UNSTABLE threshold breach into a hard FAILURE — `numOf()` now returns a primitive `double`.
- **GHA k6 `--tag` aborted under `set -u`** (`PROFILE: unbound variable`): the k6-run step
  referenced `${PROFILE}` (a var from an earlier step) instead of the step-local
  `${K6SIM_PROFILE}` env. Jenkins/Tekton already used the always-set `K6SIM_PROFILE`.
- **Grafana Cloud free-tier 15k active-series cap exceeded → metrics rejected
  (`err-mimir-max-active-series`), so app/JVM dashboard panels churned empty.** Two
  durable cuts: `observability.leanMetrics` default flipped **false → true** (infra
  metrics stay off across redeploys), and the otel-collector `cnpg` scrape now drops
  `cnpg_pg_settings_setting` (~2272 series — one per postgresql.conf setting per
  instance, the single biggest consumer, used by no dashboard) via
  `metric_relabel_configs`. See [`docs/301`](docs/301-OBSERVABILITY.md).
- **Angular build failed after adding Faro (`TS2304: Cannot find name 'global'`,
  `TS2307: Cannot find module 'path'`).** `@grafana/faro-web-sdk`/`-web-tracing` pull
  transitive `.d.ts` (faro-core, `@opentelemetry/instrumentation`) that reference Node
  types, but the gateway's Angular `tsconfig.json` had `types: []` and no `skipLibCheck`,
  so `npm run webapp:build` (frontend-maven-plugin) failed. Fixed by adding
  **`skipLibCheck: true`** to the gateway `tsconfig.json` (develop branch) — skips
  type-checking node_modules `.d.ts` only; the SDKs are browser-safe at runtime. See
  [`docs/902`](docs/902-TROUBLESHOOTING.md).

### Changed

- **`Day2.traffic.01` k6 workflow no longer requires manual approval.** Removed
  `environment: gke-production` (required-reviewers gate) — it only drives read-only HTTP
  traffic against the already-running public endpoints, provisions/destroys nothing, and
  all its secrets are repo-level, so the gate only blocked automation/scheduling. Day1,
  Decom and the heavier Day2.* workflows keep the gate.

- **Per-tier branch model documented + reconciled (three distinct axes).** Clarified the
  confusing branch wiring: (1) **app source** branch the CI builds —
  `jenkins/pipelines/seed/services.yaml` `branches` (stable=`main`, develop=`develop`);
  (2) gitops branch the **develop** ArgoCD app tracks — `config.yaml`
  `microservices.branches.develop` (=`develop`, always); (3) gitops branch the **stable**
  ArgoCD app tracks — the **deploy branch** (`J2026_SELF_REPO_BRANCH`), *not*
  `microservices.branches.stable`: a Day1 from `develop` puts the stable tier's gitops on
  develop too (validate end-to-end before promotion), from `main` → main.
  `microservices.branches.stable` feeds only the **Tekton** stable source branch.
  Documented in `config.yaml` + a pointer in `08.5-argocd.sh`. See
  [`docs/502`](docs/502-MICROSERVICES_GITOPS.md).

> Companion changes in the **`jenkins-2026-gitops-config`** repo (deployed via ArgoCD, not
> tracked here): the lean `develop` tier no longer CrashLoops — raised the Java CPU limit
> 500m→1500m + startup-probe budget 5→10min (CPU-starved cold start), and switched the
> develop deployments to the `Recreate` strategy so a rolling update's overlapping pods
> don't starve the new pod of PgBouncer session-mode connections (its reactive r2dbc
> health check hung → startup probe never passed). Also moved the three Java probes to
> Spring Boot's **dedicated availability groups** (`liveness → /…/liveness`, `readiness` +
> `startup → /…/readiness`) so a transient DB blip no longer fails *liveness* and
> restart-loops the pod; applied the runtime **JVM tuning** (`JDK_JAVA_OPTIONS`: G1 +
> `MaxRAMPercentage=50` + StringDeduplication + ExitOnOOM — kept separate from the OTel
> agent's `JAVA_TOOL_OPTIONS`); and enabled the agent's **experimental runtime telemetry**
> (buffer pools + system CPU) for the deeper `jvm-internals` panels. See
> [`docs/502`](docs/502-MICROSERVICES_GITOPS.md) (probes/strategy) and
> [`docs/303`](docs/303-JVM-TUNING.md) (JVM).

## [v0.27.0] - 2026-06-27

### Added

- **`observability.leanMetrics` feature flag (default off) — fit the develop tier under
  the Grafana Cloud free-tier 15k active-series cap.** When `true` (grafana-cloud mode;
  per-run override `JENKINS2026_OBS_LEAN_METRICS=true`), `scripts/03-observability.sh`
  disables the k8s-monitoring **cluster-infra** metrics (cadvisor/kube-state/node-exporter)
  — the high-cardinality series the custom `jenkins2026-*` dashboards don't use — freeing
  thousands of active series. App/CNPG/Tekton/k6/Jenkins metrics (via the otel-collector)
  are unaffected; `clusterEvents` stays on (→ Loki, ~0 metric series). Trade-off: the
  built-in "K8s Compute" views go empty. Meant as a temporary validation knob; the
  metrics cap doesn't affect Tempo traces / Loki logs, so develop is always verifiable
  there. See [`docs/301`](docs/301-OBSERVABILITY.md).
- **`Day2.publish.02-grafana-cloud` workflow — the missing per-backend dashboard
  publisher.** The per-backend Day2 publish set had `01-oss` / `03-azure` /
  `04-aws` but no **grafana-cloud** entry (ZZ=02), even though grafana-cloud is the
  default mode — so refreshing Grafana Cloud dashboards required a full Day1. The new
  workflow runs `scripts/07-grafana-dashboards.sh` + `07.5-grafana-alerts.sh` in
  grafana-cloud mode (reads `GRAFANA_BASE_URL`/`API_KEY` from the in-cluster
  `grafana-cloud-credentials` Secret, imports via the Grafana API), making the
  observability-backend lifecycle symmetric: every persistent backend now has
  Day0.infra + Day2.publish + Decom.infra. Docs/diagrams in
  [`docs/101`](docs/101-GITHUB_ACTIONS_WORKFLOWS.md) updated.

### Fixed

- **k6 GitHub Actions summary no longer crashes on k6 2.0.0 threshold output.** The
  *Show Results Summary* step's `jq` read each threshold as an object (`.value.ok`),
  but k6 2.0.0 emits thresholds as a plain **boolean** → `jq: Cannot index boolean
  with string "ok"` → the step exited 5 and the whole job went red **even though the
  test ran fine** (and the printed summary showed 0 reqs/iters — a parse artifact,
  not reality: the run actually did 203 iterations / 4 VUs against develop). Now
  handles both shapes (`.value | if type=="object" then .ok else . end`).
- **ArgoCD `microservices` AppProject now allows the `microservices-develop`
  namespace.** Its `destinations` whitelisted only `microservices`, so the develop
  tier's generated Application was rejected with `InvalidSpecError` (namespace not in
  the allowed destinations) → it stayed `Unknown/Unknown`, deployed **zero pods**, and
  any pipeline doing `argocd app wait microservices-develop` (the GitOps Update stage
  of `microservicesDeploy.groovy`) **hung** until timeout; the public develop endpoint
  500'd (Service, no pods). Pre-existing develop-track bug, surfaced once the tier was
  first exercised end-to-end. One-line whitelist add (harmless when the track is off).

### Changed

- **Static platform RBAC moved from imperative `kubectl` to GitOps (new ArgoCD
  `platform-config` app).** The engine-aware, *timing-insensitive* RBAC that
  `scripts/01-namespaces.sh` and `scripts/02-otel-operator.sh` used to
  `kubectl create … | kubectl apply` — the **Jenkins** SA `edit` bindings in the
  microservices namespaces, the **Tekton** develop-tier `tekton-ci-edit` binding,
  the **pgAdmin** `pgadmin-secret-reader` Role/binding, and the
  **`jenkins-otel-instrumentation-editor`** `ClusterRole`+binding — is now rendered
  by a small Helm chart at **`argocd/platform-config/`** and owned by ArgoCD
  (drift-detected + self-healed). `ciEngine`/`developTrackEnabled` flow down as
  `helm.parameters` (planted by `08.5-argocd.sh`), so only the active engine's
  bindings render. Safe to move because every consumer (CI pipelines, pgAdmin) runs
  long after ArgoCD has synced.
  - **Deliberately NOT migrated:** NetworkPolicies and ResourceQuotas/LimitRanges
    stay script-applied in `01-namespaces.sh`. They are applied **early, before any
    workload**, which is required for Dataplane V2 enforcement timing (e.g. the OTel
    Operator's `:9443` webhook allow and the `microservices-cnpg-platform` policy
    must exist before those workloads come up) — an ArgoCD app would sync them
    *concurrently* with workloads, a timing regression. The Headlamp per-email admin
    `ClusterRoleBinding`s stay imperative too (derived from a user list).
  - First step of the GitOps-vs-imperative review roadmap (see
    [`argocd/README.md`](argocd/README.md) topology table).

### Fixed

- **Grafana `postgres-overview` dashboard now covers the develop tier.** Its queries
  were hardcoded to `namespace="microservices"` (stable only), so the optional
  develop tier's CNPG Postgres (`microservices-develop`) was invisible. Added a
  **`Tier (namespace)`** template variable (auto-discovered from the CNPG metrics'
  `namespace` label, so `microservices-develop` appears once its instance is up) and
  parameterized all 8 metric + 1 log queries to `$namespace`. Regenerated the AWS /
  Azure variants via their `generate.py`, so **all four Grafana backends** (OSS,
  Grafana Cloud, AMG, Azure Managed Grafana) get it. (The `microservices-overview`
  and `k6-smoke-overview` dashboards already had the `stable`/`develop` selector;
  `jenkins-overview` and `tekton-overview` are control-plane-scoped — single
  environment — so correctly have none.)

### Documentation

- **New `docs/201` section: "Imperative (push) vs GitOps (pull): the provisioning
  split".** A complete, scannable inventory of which resources ArgoCD pulls vs which
  the setup scripts push, the **six concrete reasons** a resource stays imperative
  (bootstrap paradox · secret values · runtime-derived manifests · live-reload
  companions · external side-effects · Dataplane V2 enforcement timing), a
  resource-by-resource ownership table, a **two-planes Mermaid diagram** (bootstrap →
  hand-off → reconcile), and the "irreducible imperative core". Cross-linked from
  `CLAUDE.md`, `argocd/README.md` (topology table now notes it's only the GitOps
  half + lists `platform-config`), and the existing
  [201 § Secrets backend](docs/201-ARCHITECTURE.md) deep-dive.

## [v0.26.0] - 2026-06-27

### Added

- **The optional `develop` microservices tier is now publicly exposed**, at its
  own host `https://microservices-develop.<gateway.baseDomain>` (e.g.
  `https://microservices-develop.jenkins2026.nubenetes.com`) — previously the
  tier was *in-cluster only* (reachable solely via `kubectl port-forward`). It is
  fully integrated, end to end:
  - **Gateway route** — `scripts/09-gateway.sh` generates a dedicated
    `microservices-develop` `HTTPRoute` + `HealthCheckPolicy` (pointing at the
    develop `gateway` Service), **gated on `microservices.developTrackEnabled`**.
    Public, **no IAP** — same edge posture as the stable `microservices` host —
    and covered by the existing `*.<base_domain>` **wildcard cert/DNS** (no extra
    certificate or DNS record). Disabling the tier on a persistent cluster
    **retires** the route/policy idempotently (mirrors the Grafana enable/cleanup
    pattern). Teardown added to `scripts/down.sh`.
  - **New config knob** `gateway.hosts.microservicesDevelop` (default
    `microservices-develop`) + the `J2026_GATEWAY_HOST_MICROSERVICES_DEVELOP` /
    `J2026_GATEWAY_MICROSERVICES_DEVELOP_HOST` exports in `scripts/lib/config.sh`.
  - **Jenkins system banner** — the develop URL is surfaced in the JCasC
    `systemMessage` via a new pre-rendered `MICROSERVICES_DEVELOP_LINK` (the
    line vanishes when the tier isn't exposed), plus a `MICROSERVICES_DEVELOP_URL`
    env. Patched into `jenkins-credentials` by `scripts/01-namespaces.sh` and
    `scripts/04-jenkins.sh` (and folded into the banner-roll checksum).
  - **GitHub Actions "Access URLs" logs** — `Day1.cluster.01-gke` now prints the
    develop URL (instead of the old `in-cluster only` note), as does the
    `scripts/09-gateway.sh` summary (so `Day2.redeploy.03-tekton` /
    `Day2.redeploy.05-gateway` show it too).
- **Tekton parity for the Jenkins banner** — since the upstream Tekton Dashboard
  has no system-message banner, `scripts/06-tekton-pipelines.sh` now stamps the
  platform's public URLs as `jenkins2026.io/url-*` annotations onto **every**
  seeded PipelineRun (the PaC `.tekton/<svc>.yaml` pushed to forks, the
  `tekton.seedRuns` runs, and the local fallback runs), including
  `url-microservices-develop` when the tier is on. They render in the Dashboard's
  run-detail view; no-op when the Gateway is disabled.

### Changed

- **GitHub Actions k6 (`Day2.traffic.01-k6.yml`): `env_name=develop` now targets
  the public `microservices-develop` host** over the internet (same external
  targeting as `stable`), replacing the previous `kubectl port-forward` to
  `localhost`. The in-cluster Tekton/Jenkins k6 paths still target the tier by
  namespace DNS (correct for a Pod inside the cluster).

### Documentation

- Aligned all docs/diagrams with the develop tier's public exposure: **402**
  (Internal-only → public host + the stable-vs-develop table), **302** (the k6
  GitHub Actions targeting + compatibility matrix + `develop-smoke` note),
  **501** (the public-URL table + traffic-sim tier note), **503** (the public
  hosts table), **403** (a new note documenting the `jenkins2026.io/url-*`
  PipelineRun annotations), and the **README** architecture diagram (the develop
  node now shows its public route).

## [v0.25.2] - 2026-06-27

### Documentation

- **README k6 intro restructured to match the v0.25.1 intro pass.** The dense
  "Closing the loop — load & traffic testing" paragraph became a lead sentence +
  a **"What the k6 engine gives you"** bullet list (one script/one contract; the
  six workload profiles; committed dropdown-selectable presets with
  manual>preset>default precedence; the same test from all three runners across
  `stable`/`develop`; one Grafana + layered analysis), aligned with the
  bullet-driven "What it chains together" / "How it runs" style.

## [v0.25.1] - 2026-06-27

### Documentation

- **README intro expanded and restructured.** The dense single-paragraph "At a
  glance" was rewritten into a scannable, deeper overview: a reframed lead
  sentence (*build → scan → ship → observe → load-test*), a **"What it chains
  together, end to end"** bullet list (one component per bullet — CI engine,
  GitOps CD, observability + the four backends, k6 load testing, DevSecOps,
  platform & networking — each **linking to its numbered doc**), and a **"How it
  runs"** list (keyless WIF, the idempotent Day0→Day1→Day2→Decom lifecycle, and
  the feature flags incl. the ESO secrets backend). The k6 paragraph is unchanged.

## [v0.25.0] - 2026-06-27

### Added

- **k6 config presets — committed, selectable test configurations.** A new
  preset library at **`jenkins/pipelines/k6/presets/`** (`index.yaml` + one
  **YAML** file per preset) bundles a complete named `K6SIM_*` config (profile +
  VUs/duration/stages/rps + scenarios + thresholds + optional target). Instead of
  typing every knob, you **pick a preset from a dropdown** and the runner loads
  it; any field still entered by hand **overrides** it (**precedence: manual >
  preset > script default**). Ships **9 presets** across basic→advanced:
  `smoke`, `load-baseline`, `frontend-only`, `develop-smoke`, `stress-peak`,
  `spike-recovery`, `soak-endurance`, `rps-steady`, `breakpoint-capacity`.
  - **Jenkins**: a `PRESET` choice in *Build with Parameters* (seeded from
    `index.yaml`); the pipeline `readYaml`-merges preset + manual inputs.
  - **GitHub Actions**: a `preset` dropdown input + a *Resolve k6 parameters*
    step (`yq`) that writes the merged contract to `$GITHUB_ENV`.
  - **Tekton**: a `preset` param + a `resolve-preset` step (`yq`) that loads the
    committed file; `run-k6` fills any empty param from it.
  - **YAML, not TOML**, deliberately — reuses the repo's existing `yq` tooling
    rather than adding a second config language.

### Documentation

- **`docs/302`: a full preset section** — how selection/precedence works per
  engine (with a resolution **flowchart**), a detailed **inventory matrix** of all
  9 presets (level, profile, shape, scenarios, budgets, target, use case), and a
  **collapsible diagram per preset** using varied Mermaid types (request-flow
  graphs, `xychart-beta` VUs/rate-over-time charts, a sequence diagram), plus an
  "add a preset" guide and an "easiest — run a preset" tutorial.
- **README intro substantially expanded** to give the k6 load/traffic engine
  first-class billing: a new *"Closing the loop — load & traffic testing"*
  paragraph, a **Load testing** branch in the Mental-model mindmap, and a
  newcomer bullet. Index TOC + Document-Inventory row updated for presets.

## [v0.24.0] - 2026-06-27

### Added

- **k6 turned into a fully parametrizable traffic/load engine — one script, one
  `K6SIM_*` contract, three runners.** `jenkins/pipelines/k6/microservices-smoke.js`
  is now driven by a unified, **backward-compatible** variable contract (no vars =
  the original 4 VUs × 12 iterations smoke test):
  - **Workload profiles**: `smoke` (default) · `load` · `stress` · `soak` ·
    `spike` · `breakpoint`, each mapping to the right k6 executor + shape.
  - **Overrides**: `K6SIM_VUS` / `K6SIM_ITERATIONS` / `K6SIM_DURATION` /
    `K6SIM_STAGES` (custom ramps) / `K6SIM_RPS` (arrival-rate) / `K6SIM_SLEEP`,
    request-flow selection (`K6SIM_SCENARIOS`), tunable thresholds
    (`K6SIM_P95_MS` / `K6SIM_ERROR_RATE`) and `K6SIM_DEBUG`. The `K6SIM_` prefix
    avoids k6's **reserved** execution-option env vars clashing with the
    `scenarios` block; runners no longer pass `--vus`/`--duration` CLI flags.
  - **Jenkins**: `MicroservicesK6SmokePipeline` gains a full **Build with
    Parameters** form; `microservicesK6Smoke` threads the whole contract.
  - **Tekton**: `Task` + `Pipeline` expose every knob; new advanced example
    `tekton/runs/k6-load.yaml` (load profile vs the develop tier).
  - **GitHub Actions** (`Day2.traffic.01-k6`): `profile` / `env_name` / `vus` /
    `duration` / `stages` / `rps` / `scenarios` / threshold inputs; resolves the
    target per tier (**stable** → public host, **develop** → port-forward the
    develop gateway).
- **Layered k6 result analysis (Jenkins + GitHub Actions).** Both runners now
  print **SUMMARY** (checks, error %, RPS) · **LATENCY** (avg/min/med/**p90/p95/
  p99/max** + server TTFB vs connect/TLS) · **THROUGHPUT & RELIABILITY**
  (iterations, **dropped iters**, peak VUs, bytes) · a **THRESHOLDS** PASS/FAIL
  table · and a final **VERDICT** — readable at newcomer, operator and specialist
  depth.

### Fixed

- **k6 develop targeting.** `vars/MicroservicesPipeline.groovy` always triggered
  the hardcoded **stable** `microservices-k6-smoke` job, so a **develop** build
  smoke-tested the wrong namespace. It now hands off to the **tier-matched**
  `microservices-k6-smoke-develop` job. With this, **all three runners
  (Jenkins/Tekton/GitHub Actions) support both `stable` and `develop`** — they
  used to be stable-only in practice.

### Documentation

- **New `docs/302-K6_LOAD_TESTING.md`** — the single home for k6: **🧠 Mental
  model** + **🟢 For newcomers** + **🔵 For specialists** (all collapsible
  diagrams), the **full `K6SIM_*` parameter reference** (basic→advanced tables),
  the **profiles** table + shape diagram, the **three runners**, **basic &
  advanced tutorials**, **basic & expert result-reading** guidance, the **`stable`
  vs `develop` compatibility matrix**, and troubleshooting.
- Navigation + indexes wired up: header/footer nav (`301` ← **`302`** → `401`),
  the **README** Document Inventory, **CLAUDE.md** doc index, and cross-links from
  **`301`** (k6 smoke section), **`402`** (seed job) and **`501`** (telemetry
  simulation).

## [v0.23.9] - 2026-06-27

### Fixed

- **Docs aligned with the real ArgoCD pin (3.4.x, not 3.5.x).** ArgoCD is pinned
  to the latest stable **`3.4.x`** (off the buggy `3.5.0-rc`, until `3.5.0` GAs) —
  `config/config.yaml` `argocd.version: v3.4.4` / `version_constraint: "3.4.x"`.
  Stale "auto-tracking 3.5.x" claims were corrected in **`README.md`** (the
  Document-Inventory row **and** the TOC link, whose anchor was also broken),
  **`docs/501`** (4 spots, incl. the app-of-apps Mermaid watcher node), and
  **`CLAUDE.md`**'s doc index. `docs/602` and `argocd/README.md` already correctly
  documented the 3.4.x pin + the deferred-3.5 rationale. All 501 diagrams revalidated.

## [v0.23.8] - 2026-06-27

### Documentation

- **Strategic bold-emphasis pass across the README + all docs for scannability.**
  - **README Document Inventory**: every row's description now **bolds its key
    terms** (matching the 503 row), and a few were refreshed with recent topics
    (301 alert rules, 402 develop-tier rationale, 502 parameterized CNPG HA, 501
    Argo Rollouts).
  - **All docs (`100`–`902`)**: a judicious, conservative pass bolded the most
    strategic terms in otherwise-flat prose — emphasis only, no wording/fact/
    structure changes; existing bold/italic/code/links preserved; headings, code,
    Mermaid and `🟢`/`🔴`/"Reading it —" blocks left untouched. Already
    emphasis-rich docs (`102`, `902`) needed no change. All 91 diagrams re-validated.

## [v0.23.7] - 2026-06-27

### Documentation

- **`docs/402`: added a consolidated `stable` vs `develop` comparison table + the
  rationale.** One place now spells out, per aspect, how the lean **develop** tier
  differs from the production-representative **stable** tier — CNPG HA (3 vs 1),
  pooler (3 vs 1), backups (on vs off), app resources, **alerts** (yes vs no /
  stable-only), **public access** (Gateway vs internal-only), GitOps branch/values,
  shared observability, and footprint (~12 vs ~4 pods) — **and why** each difference
  exists: develop validates a change cheaply/fast (same app image, CI/CD path and
  observability) while skipping what only matters for production (HA, backups,
  alerting, a public endpoint).

## [v0.23.6] - 2026-06-27

### Documentation

- **`docs/301` Alert Rules: documented the alerting scope w.r.t. the new develop
  tier.** All five rules filter on `namespace="microservices"` (stable), so the
  optional lean `develop` tier is **deliberately excluded** from alerting — a
  disposable validation tier shouldn't page; its telemetry is still visible in the
  env-aware dashboards. Added a note explaining this and how to opt develop in.
- (Repo metadata) refreshed both repos' GitHub **About** descriptions to mention
  the pluggable **secrets backend** (imperative | GCP Secret Manager + ESO), keyless
  WIF, and the optional **lean develop tier** (and, for gitops-config, the
  parameterized CNPG HA: stable HA vs lean develop).

## [v0.23.5] - 2026-06-27

### Documentation

- **Brought the `README.md` intro in line with the docs' explainer pattern**: added
  a collapsible **🧠 Mental model** mindmap (the whole platform in one map), reframed
  the high-level design diagram inside a **🟢 For newcomers** block (plain-terms
  "build-and-ship factory" explanation), and relabelled the existing *In depth*
  section as **🔴 For specialists**. All four README diagrams stay collapsible and
  Mermaid-validated.

## [v0.23.4] - 2026-06-27

### Documentation

- **Cross-linked the new [`503. Networking`](docs/503-NETWORKING.md) doc** from the
  two places readers most likely arrive from: `docs/201` (the GKE-topology /
  network-dataplane note) and `docs/501` (above the NetworkPolicy matrix), so the
  per-namespace policy detail points up to the full network architecture (landing
  zone, CIDR plan, ingress/egress, segmentation) it sits inside.

## [v0.23.3] - 2026-06-27

### Added

- **New doc [`503-NETWORKING.md`](docs/503-NETWORKING.md) — "Network Architecture,
  Landing Zone & Segmentation"**, with the same `🧠 mental model` mindmap +
  `🟢 newcomers` / `🔴 specialists` pattern as the other docs and **8 collapsible,
  Mermaid-validated diagrams**: the VPC/subnet/secondary-range topology, the
  **landing-zone topology pattern** (single-project / single-VPC + Kubernetes-layer
  segmentation — **why it is *not* hub-spoke**, with motivations/justifications and
  the growth path to hub-spoke), the IP-address plan (nodes `10.10.0.0/20` · pods
  `10.20.0.0/16` · services `10.30.0.0/20`), north-south **ingress** (Internet → DNS
  → L7 LB → IAP → Gateway → container-native NEG → pod, as a sequence) and **egress**
  (no Cloud NAT, the four observability backends), east-west pod/service networking
  (VPC-native alias IPs · Dataplane V2/Cilium eBPF · WireGuard inter-node), the
  NetworkPolicy **segmentation** model (default-deny / deny-ingress baseline / open
  operator namespaces), and a defense-in-depth summary. All values verbatim from
  `terraform/gke`, `gateway-bootstrap`, `infrastructure/networkpolicies*`, `config`.
- Wired the new page into navigation (header/footer prev/next: `502 → 503 → 601`)
  and the **README** (Table of Contents + Document Inventory) and **CLAUDE.md** index.

## [v0.23.2] - 2026-06-27

### Documentation

- **Overhauled the `README.md` introduction and reviewed the whole file for
  integrity with the current platform.** The old intro mentioned only Jenkins + the
  four Grafana backends and was otherwise stale. The new intro is in **two parts,
  each with a collapsible design diagram**:
  - **High-level** — an "at a glance" paragraph + a **high-level design** Mermaid
    diagram (collapsible).
  - **Low-level** — a collapsible *In depth* section with a **low-level (planes &
    components) design** Mermaid diagram, a **feature-flag table** (default vs
    optional: `ci.engine` jenkins|**tekton**, `observability.mode`
    grafana-cloud/oss/managed-azure/managed-aws, `secrets.backend` imperative|**eso**
    = GCP Secret Manager + ESO, `microservices.developTrackEnabled` = the lean
    **develop tier**, `gateway.baseDomain` = IAP public access), the **always-on**
    platform, and a "what's inside, by area" breakdown.
  - Also: the **§3 Architecture Overview** diagram now shows the optional
    `microservices-develop` tier (dashed) + the `eso` secrets path in its caption.
    All three README diagrams are **collapsible** and validated against the Mermaid
    parser; verified the workflow count, script references, and the doc inventory.

## [v0.23.1] - 2026-06-27

### Documentation

- **Audited every existing Mermaid diagram for `develop`-tier integrity** and
  updated the 4 where the optional tier is genuinely part of the model, marking it
  **dashed / "(optional · develop track)"** and reflecting its lean shape (1 CNPG
  instance, no backups):
  - **`docs/201`** — the Component diagram gains a dashed `microservices-develop`
    namespace (`deployment.environment=develop`, lean CNPG); the Namespace & Secret
    topology gains the optional develop `ghcr-credentials`.
  - **`docs/501`** — the ArgoCD app-of-apps tree gains a dashed
    `microservices-develop` (lean tier) under the microservices ApplicationSet; the
    NetworkPolicy flow gains an optional `microservices-develop` node with its
    dashed OTLP/`:9187` link.
  - The remaining diagrams were reviewed and **intentionally left unchanged**:
    env-agnostic ones (all of `docs/301` — develop flows identically, distinguished
    by the `deployment_environment` attribute, not topology), steady-state/canonical
    stable views, and internal-only contexts (Gateway+IAP, ESO IAP projection) where
    develop correctly does not appear. All affected diagrams validated against the
    Mermaid parser.

## [v0.23.0] - 2026-06-27

The optional **`develop` microservices tier** becomes a first-class,
GitHub-Actions-gated feature — **off by default**, engine-neutral (Jenkins **and**
Tekton), and deployed as a deliberately **lean, non-HA tier** so both environments
fit comfortably on the cluster. (Spans this repo + the `jenkins-2026-gitops-config`
repo.)

### Added

- **`develop_track` workflow input (default `false`)** on `Day1.cluster.01-gke`,
  the `Day1.cluster.00-all` umbrella, `Day2.redeploy.02-jenkins`, and
  `Day2.redeploy.03-tekton` — wired to the existing `JENKINS2026_DEVELOP_TRACK_ENABLED`
  flag (durable default `microservices.developTrackEnabled: false`). Turning it on
  provisions a second `microservices-develop` deploy tier alongside `stable`.
- **Engine-neutral develop tier (Jenkins + Tekton).** Jenkins generates
  `<svc>-develop` jobs (04-jenkins + `seed_jobs.groovy`); Tekton seeds develop
  PipelineRuns (`06-tekton-pipelines` + the `env-name=develop` task branches). The
  deploy target is ArgoCD's `microservices-develop` Application (engine-neutral),
  created by `08.5-argocd` appending a `develop` generator to the microservices
  ApplicationSet (values-develop.yaml on the gitops `develop` branch).
- **Lean develop tier (`jenkins-2026-gitops-config`).** The microservices chart's
  `templates/postgres.yaml` is parameterized — `global.postgresInstances` /
  `global.poolerInstances` (default **3**) and `global.postgresBackupEnabled`
  (default **true**) — so **stable is unchanged**. `values-develop.yaml` sets them
  to **1 / 1 / false**: a single CNPG instance (no HA standbys), a single PgBouncer
  pooler, and no Barman/ScheduledBackup (disposable data). Footprint: stable ≈ 12
  CNPG pods vs develop ≈ 4.

### Changed

- **`scripts/01-namespaces.sh` provisions the develop namespace end-to-end when the
  flag is on** (engine-neutral, gated): creates `microservices-develop`; binds
  `edit` for the active engine's SA (jenkins SA, or `tekton-ci` SA); pgAdmin
  secret-reader; `ghcr-credentials` imagePullSecret; and replicates the additive
  `microservices-cnpg-platform` NetworkPolicy into it (CNPG 5432 / API-server 443
  Hazelcast / WI-metadata egress + 9187 metrics ingress).
- **NetworkPolicies**: `observability-policy` (OTLP `4317/4318` ingress) and
  `pgadmin-policy` (egress `5432`) now list `microservices-develop` statically
  (a namespaceSelector for an absent namespace matches nothing, so it is harmless
  when the tier is off).
- **Observability**: the non-OSS collector values (grafana-cloud / managed-azure /
  managed-aws) add `microservices-develop` to the CNPG `:9187` scrape (OSS already
  scrapes all namespaces); ESO mode emits a `ghcr-credentials` ExternalSecret for
  the develop namespace; `down.sh` tears the develop namespace down on teardown.
- **Docs**: `docs/402` (develop tier + lean CNPG + provisioning diagram), `docs/102`
  (the `develop_track` form field), `docs/502` (the parameterized CNPG HA knobs).

> The develop tier is **internal-only** (no public HTTPRoute; `values-develop`
> `ingress.enabled: false`) — reach it via `kubectl -n microservices-develop
> port-forward svc/gateway 8080:8080`. It reports into the same shared
> observability stack, separated by namespace/labels.

## [v0.22.6] - 2026-06-27

### Added

- **The missing "Mental model" `mindmap` in `docs/100`, `docs/101`, `docs/502`,
  `docs/601`** — completing the consistency pass started in v0.22.5 (102). **All
  11 diagram docs** (100, 101, 102, 201, 301, 401, 402, 403, 501, 502, 601) now
  open their newcomers/specialists section with a collapsible mindmap + a
  "Reading it" note.

### Fixed

- **Broken/invisible emoji in `docs/402`**: the `🪢` (U+1FAA2 KNOT, a Unicode 13
  emoji many fonts/renderers lack, so it showed as an empty box) in the "Branch &
  environment mapping" summary is replaced with `🌳` (a universally-rendered
  Unicode 6.0 emoji). A scan of all docs confirms no remaining Unicode-11+ emoji
  or mojibake (`U+FFFD`).

## [v0.22.5] - 2026-06-27

### Added

- **`docs/102-GITHUB_ACTIONS_AUTOMATION.md`: the missing "Mental model"
  `mindmap`** — a consistency fix so 102 matches the other docs (401/402/403,
  201/301/501), which all open their newcomers/specialists section with a
  collapsible mindmap. The mindmap covers the five pillars of the CI automation
  (keyless WIF identity · remote Terraform state · persistent-vs-short-lived
  tiers · DayN lifecycle · five approval gates), with a "Reading it" note.
  Validated against the Mermaid parser.

## [v0.22.4] - 2026-06-27

The final documentation patch in the diagram series: the 401/402/403 treatment
now covers **every** numbered doc with diagrams — `docs/101`, `docs/201`,
`docs/301`, `docs/601` get newcomers/specialists blocks, new diagrams, and
collapsible wrapping.

### Added

- **5 new Mermaid diagrams + 🟢/🔴 newcomers-specialists blocks across
  `docs/101`, `docs/201`, `docs/301`, `docs/601`**:
  - **101-GITHUB_ACTIONS_WORKFLOWS**: a `stateDiagram` of the
    Day0→Day1→Day2→Decom cluster lifecycle and a dependency `flowchart`
    (Day0 prerequisites + the shared `jenkins-2026-gke` concurrency group), plus a
    🟢/🔴 pair on the `DayN.tier.ZZ` naming scheme.
  - **201-ARCHITECTURE**: a system-overview `mindmap` + a 🟢/🔴 pair.
  - **301-OBSERVABILITY**: an observability-model `mindmap` + a 🟢/🔴 pair (the
    six existing diagrams were already collapsible).
  - **601-DEVSECOPS**: a security-scan fan-in `flowchart` (sources → Semgrep /
    CodeQL / Trivy → SARIF / GitHub Code Scanning) + a 🟢/🔴 pair.
  - Each new diagram carries a "Reading it" explanation; all validated against
    the Mermaid parser.

### Changed

- **All previously-bare Mermaid diagrams in `docs/101` and `docs/201` are now
  collapsible (`<details>`)** — completing the render-latency fix begun in
  v0.22.2/v0.22.3. With this release **every Mermaid diagram in the docs is
  wrapped in a `<details>`**. Pre-existing `<details>` were left intact.

## [v0.22.3] - 2026-06-27

A documentation patch extending the 401/402/403 treatment to four more docs:
**newcomers/specialists** explainers, **new Mermaid diagrams**, and every diagram
made **collapsible**.

### Added

- **10 new Mermaid diagrams + 🟢/🔴 newcomers-specialists blocks across
  `docs/100`, `docs/102`, `docs/501`, `docs/502`** (same style as 401/402/403):
  - **100-BOOTSTRAP**: a `stateDiagram` of the root-of-trust lifecycle, plus a
    🟢/🔴 pair.
  - **102-GITHUB_ACTIONS_AUTOMATION**: a `sequenceDiagram` of the **WIF keyless
    auth** (GitHub OIDC → Google STS → impersonate CI SA), a `flowchart` of the
    five approval-gate environments → workflows, plus a 🟢/🔴 pair.
  - **501-PLATFORM_OPERATIONS**: a platform `mindmap`, a Gateway+IAP request-flow
    `sequenceDiagram`, an ArgoCD app-of-apps `flowchart`, a canary
    progressive-delivery `stateDiagram`, plus a top-level 🟢/🔴 pair.
  - **502-MICROSERVICES_GITOPS**: a `classDiagram` of the Helm values model, a
    `sequenceDiagram` of the GitOps deploy loop, a `sequenceDiagram` of the NEG
    synchronization barrier, plus a 🟢/🔴 pair.
  - Each new diagram carries a "Reading it" explanation; all validated against
    the Mermaid parser.

### Changed

- **Every Mermaid diagram in `docs/100`, `docs/102`, `docs/501`, `docs/502` is
  now wrapped in a collapsible `<details>` block** (21 diagrams), so GitHub
  renders each only on expand — the same render-latency fix applied to 401/402/403
  in v0.22.2. Pre-existing `<details>` (e.g. the Argo Rollouts 🟢/🔴, the
  NetworkPolicy-enforcement gotchas) were left intact.

## [v0.22.2] - 2026-06-27

A documentation-rendering patch: every Mermaid diagram in the CI-engine docs is
now **collapsible**, and the Tekton doc gains diagrams matching 401/402 so all
three read homogeneously.

### Changed

- **Every Mermaid diagram in `docs/401`, `docs/402` and `docs/403` is now wrapped
  in a collapsible `<details>` block** (28 diagrams total). GitHub renders a
  Mermaid block only when its `<details>` is expanded, so a page no longer tries
  to render many diagrams at once — which, under load/latency, often failed and
  left the raw diagram source (with an error) on screen. Collapsed-by-default
  also keeps the prose scannable; each diagram still carries its "Reading it"
  explanation directly beneath.

### Added

- **`docs/403-TEKTON.md` gains 5 new diagrams for parity with 401/402** (none of
  the existing diagrams removed): a `mindmap` mental model, a `classDiagram` of
  the Tekton CRD object model (Pipeline / Task / PipelineRun / TaskRun /
  Workspace / Repository), a high-level architecture `flowchart`, a
  `stateDiagram` of the PipelineRun/TaskRun lifecycle, and a `sequenceDiagram` of
  the Pipelines-as-Code `git push → PipelineRun` flow — each with a "Reading it"
  explanation and cross-references to the Jenkins equivalents. All 28 diagrams
  across the three docs were validated against the Mermaid parser.

## [v0.22.1] - 2026-06-27

A documentation + reliability patch on top of v0.22.0: a fix that restores
**pgAdmin → CNPG Postgres** connectivity under Dataplane V2 enforcement, and a
ground-up rewrite of the **Jenkins docs (401/402)** following the same
"newcomers → specialists" structure as 403, with **21 new Mermaid diagrams**.

### Fixed

- **pgAdmin could not reach the CNPG Postgres databases (a connection timeout,
  easily mistaken for a wrong DB password).** The `pgadmin-policy` NetworkPolicy
  selected `app.kubernetes.io/name: pgadmin`, but the pgAdmin chart labels its
  pods `pgadmin4` — so the selector matched nothing and only the DNS-only
  `default-deny` applied, blocking **both** the runtime `:5432` egress to
  Postgres and the `setup-pgpass` init container's `:443` call to the API server
  (so no `.pgpass` was written either, breaking zero-password login). Corrected
  the selector to `pgadmin4` in `infrastructure/networkpolicies.yaml` (applied by
  `scripts/01-namespaces.sh`, not ArgoCD). Surfaced once Dataplane V2 enforcement
  took effect on a cluster rebuild (#353).
- **pgAdmin restarts deadlocked on its ReadWriteOnce PVC.** The Deployment used
  the default RollingUpdate, so a `rollout restart` spawned the new pod before the
  old one released the volume (Multi-Attach). Set `strategy: Recreate` in
  `helm/pgadmin/values.yaml`, and hardened the `setup-pgpass` init container to
  wait up to 600s for the CNPG `*-app` secrets and **fail closed** (retry via
  back-off) instead of starting pgAdmin degraded with no `.pgpass` (#353).

### Documentation

- **`docs/401-JENKINS.md` and `docs/402-PIPELINES_AS_CODE.md` rewritten to the
  403 "newcomers → specialists" pattern** — each gains a `🟢`/`🔴` explainer and
  an *object-model & run-flow* overview, plus **21 new Mermaid diagrams** spanning
  the full range: high- and low-level architecture flowcharts, sequence diagrams
  (OIDC sign-in, agent provisioning over WebSocket, controller boot/JCasC reload,
  the 11-stage build, GitOps deploy), `stateDiagram` (agent + build lifecycles),
  `classDiagram` (the JCasC config model + the shared-library steps), an
  `erDiagram` (the `services.yaml` registry), and `mindmap`s. Every diagram is
  annotated with a rich "Reading it" explanation, and all blocks were validated
  against the Mermaid parser. Also corrected a stale claim (a Google login gets
  the `developer` role, not `authenticated-base`) and the stage count (11, not 10).
- **`docs/502` / `docs/902`**: documented the CNPG application-user password
  retrieval (`kubectl get secret postgres-*-app`) alongside the superuser
  break-glass, and added a pgAdmin-connectivity troubleshooting entry making clear
  the symptom is a network/policy timeout, not the password (#353).

## [v0.22.0] - 2026-06-27

The largest release to date — **91 PRs** (#258–#350) since v0.21.0, plus the
secrets/ArgoCD/decommission hardening that followed. Headlines: **Tekton joins
Jenkins as a selectable CI engine**, a **pluggable secrets backend** (imperative
or GCP Secret Manager + External Secrets Operator), **Dataplane V2** NetworkPolicy
enforcement with WireGuard, **Azure/AWS Managed Grafana** + OSS declarative
alerting brought to full parity, **one-click lifecycle umbrellas** with
per-resource approval environments, and a hardened, finalizer-driven
**decommission** path.

### Added

- **Tekton as a selectable CI engine (`ci.engine: jenkins | tekton`).** A complete
  alternative to Jenkins, GitOps-managed by ArgoCD via the `argocd/tekton`
  app-of-apps: Pipelines (pinned `v1.9.4`, with vendored `release.yaml`), Triggers,
  the IAP-protected Dashboard, and **Pipelines-as-Code** (#258, #261, #262). The
  Jenkins shared library is ported to `tekton/` (Tasks/Pipelines/RBAC) with
  **one-click microservices `PipelineRun`s** (defaulted params) and an opt-in
  `tekton.seedRuns` flag that pre-populates the Dashboard on Day1 (#268, #300,
  #302, #303). `Day2.redeploy.03-tekton` is self-sufficient (runs `09-gateway`)
  (#263); the two engines are **mutually exclusive in both directions** — switching
  retires the other engine's namespace/apps (#267, #270, #286).
- **Pluggable secrets backend (`secrets.backend: imperative | eso`).** Default
  `imperative` (`kubectl create secret`), or `eso` = push to **GCP Secret Manager**
  and let the **External Secrets Operator** sync it in over Workload Identity
  (ClusterSecretStore + ExternalSecrets). Covers all four projection shapes
  (`extract`, `property`, templated `dockerconfigjson`, `basic-auth` with the
  `tekton.dev/git-0` annotation) across the gateway/Tekton/Jenkins secret groups,
  with **clean `eso ↔ imperative` convergence in both directions** (switching away
  orphans the live Secrets and retains the Secret-Manager copies). Additive and
  opt-in — existing deploys are unaffected until the flag is flipped (#350).
- **Dataplane V2 (Cilium/eBPF) with enforced NetworkPolicies** + **WireGuard**
  inter-node pod encryption (both immutable cluster fields). Ships the netpol set
  that keeps enforcement from breaking the platform: the OTel-operator admission
  webhook, Workload-Identity metadata egress, and agent→controller paths (#295,
  #297, #298).
- **Azure & AWS Managed Grafana brought to full parity** with Grafana Cloud / OSS:
  engine-aware dashboards + a dedicated Tekton CI dashboard (#274), Tekton metrics
  (#275), the managed-aws logs pipeline (#278), and **alert provisioning on every
  backend** — Azure/AWS via the Grafana **data-plane API** with the correct token
  audience (#310, #311, #313, #315), and OSS via a **declarative sidecar ConfigMap
  that survives restarts** (#290) — all minting **Service-Account tokens** now that
  Grafana 13 removed API keys (#288).
- **One-click lifecycle umbrellas + per-resource approval environments.**
  `Day1.cluster.00` "Everything up" provisions the whole stack in one click (#336);
  `Decom.infra.00` "Everything" tears down cluster + every backend (#312). Each
  persistent backend/gateway gets its **own GitHub approval environment**
  (`gateway-bootstrap`, `grafana-cloud`, …) rather than sharing `gke-production`
  (#334, #335), and all cluster-touching Day2 workflows now sit behind the
  `gke-production` gate (#271).
- **One-command bootstrap root-of-trust lifecycle** (`scripts/bootstrap.sh
  up`/`down`) — symmetric create/destroy of the WIF trust + Terraform-state bucket
  + CI service account + the permanent public DNS zone, fully documented (#348).
- **CNPG Postgres continuous WAL archiving to GCS** (Barman object-store) backed by
  a dedicated backups service account over Workload Identity (`terraform/gke`
  `pg_backups` SA + bucket IAM, wired through the microservices ApplicationSet).
- **IaC service account for Grafana Cloud's GCP cloud-provider integration**
  (read-only `monitoring.viewer` + `cloudasset.viewer`) (#329).

### Changed

- **ArgoCD pinned to 3.4.x** (chart `9.5.22`, image `v3.4.x`) off the `3.5.0-rc1`
  bug streak, re-enabling the features that rc1 had forced off (this supersedes the
  earlier "auto-track `3.5.x`" stance in #322; move to `3.5.x` only at GA). SSO
  RBAC now matches users **by email** (Google issues no `groups` claim) so SSO
  logins see apps (#273); application-controller memory raised to **3Gi** to stop
  OOM under oss+tekton (#337, #338).
- **Jenkins hardening:** Helm chart pinned to **5.9.29** (#319); plugins pinned and
  bumped to security-fixed versions, including `configuration-as-code`,
  `pipeline-graph-view` and `warnings-ng`, plus 5 CVE bumps (#324, #325); the last
  `:latest` agent images pinned to match Tekton (#340).
- **Observability defaults:** OSS Grafana **13.1.0** (#304); engine-neutral folder
  names (`CI-CD Observability` / Alerts) (#306, #308); **default
  `observability.mode=oss`** with a deterministic single-backend switch (#305).

### Fixed

- **Decommission robustness:** **layered, dependency-safe NEG teardown** in
  `down.sh` — finalizer-wait (L1) → adaptive 10-minute async-GC wait (L2) →
  dependency-ordered force-delete (forwarding-rule → target-proxy → url-map →
  backend-service → NEG, L3) so the VPC delete can't be blocked by a NEG still
  "in use"; finalize-driven namespace teardown (drop the fixed 2-minute timeout)
  (#342); delete all PDBs up front so the node-pool drain can't hang (#343);
  **orphaned PV-disk sweep now retries** while disks detach asynchronously after
  `terraform destroy` (the single-pass sweep raced the detachment and left disks
  billing) (#345); CI SA granted `certificatemanager.owner` (editor lacks
  `.delete`) (#346).
- **Jenkins / JCasC:** empty chart `authorizationStrategy`/`securityRealm` to stop
  the JCasC double-entry crash (#318); build-agent egress to the controller
  (seed-job timeout) (#320); the k6 smoke pod runs in the agent namespace under the
  enforcing NetworkPolicy (#326); poll the `crumbIssuer` API instead of a one-shot
  curl (Day1 exit 52) (#332).
- **Gateway / observability:** `oss-` release-prefix corrected across every OSS
  backend cross-reference (no data in Grafana) (#284–#287); leftover Grafana
  `HTTPRoute` deleted when not in oss mode (#328); managed-aws logs OOM / CloudWatch
  stream conflicts / IAM trust (#278, #281); node-exporter host-port race on
  `oss→grafana-cloud` switch (#299); `oss-kube-prometheus-stack` OutOfSync churn
  (random Grafana admin-password per render) settled via `ignoreDifferences`.
- **ArgoCD sync:** Tekton app-of-apps OutOfSync (chained `ignoreDifferences` +
  Dashboard `ServerSideDiff`) (#269, #289); `tekton/runs` excluded from the PaC app
  (#301).
- **CI plumbing:** removed `concurrency` from the Everything-up umbrella (deadlock)
  (#341); restored executable bits on scripts dropped by Windows edits (#279,
  #296); Dependabot group bump of 9 GitHub Actions (#323).
- **History:** purged the NotebookLM multimedia (infographics/videos/audio) from
  the README, Git LFS, and git history.

> **Migration notes**
> - `ci.engine` and `secrets.backend` default to the prior behaviour
>   (`jenkins` / `imperative`) — both are **opt-in**; existing deployments are
>   unaffected until you flip the flag.
> - **Dataplane V2 + WireGuard are immutable cluster fields** — adopting them on an
>   existing cluster requires a Decom + Day1 (cluster recreate).
> - Re-point any branch-protection required checks / `gh workflow run` calls to the
>   `Day2.redeploy.0{1,2,4}-*` workflow names from v0.21.0 if not already done.

## [v0.21.0] - 2026-06-23

Workflow-naming cleanup: makes the `name:` fields obey the scheme's own
"no action verb — the `DayN.tier` prefix already says the action" rule, renames
the Day2 component tier `deploy` → `redeploy`, and fixes malformed workflow
references left in prose by the v0.19.0 rename.

### Changed

- **Day2 component tier `deploy` → `redeploy`.** These workflows redeploy
  already-deployed components (the initial deploy happens in `Day1`/`scripts/up.sh`),
  so the tier is now `redeploy`. Files renamed: `Day2.deploy.01-argocd` →
  **`Day2.redeploy.01-argocd`**, `Day2.deploy.02-jenkins` →
  **`Day2.redeploy.02-jenkins`**, `Day2.deploy.04-headlamp` →
  **`Day2.redeploy.04-headlamp`**. Controlled vocabulary updated to
  `infra`/`cluster`/`redeploy`/`publish`/`traffic`.
- **Redundant action verbs dropped from every workflow `name:`** so the display
  name is `DayN.tier.ZZ <resource>` (the prefix already conveys the action) —
  e.g. `Day2.publish.03 Publish Azure dashboards` → **`Day2.publish.03 Azure
  dashboards`**, `Day2.deploy.01 Redeploy ArgoCD` → **`Day2.redeploy.01
  ArgoCD`**, `Day0.infra.01 Gateway bootstrap` → **`Day0.infra.01 Gateway`**,
  `Decom.cluster.01 GKE decommission` → **`Decom.cluster.01 GKE`**,
  `Day1.cluster.01 GKE provision` → **`Day1.cluster.01 GKE`**,
  `Day2.traffic.01 Continuous Traffic Simulation` → **`Day2.traffic.01
  Continuous k6 simulation`**. The GitHub Actions UI sort order is unchanged
  (the `DayN.tier.ZZ` prefix still leads every name).

### Fixed

- **Malformed workflow references in prose/comments.** The v0.19.0 rename mapped
  bare old IDs (e.g. `5.2.02`) to the new prefix but left the old verb suffix,
  producing dead references like `Day1.cluster.01-gke-provision`,
  `Decom.cluster.01-gke-decommission`, `Day2.redeploy.02-redeploy-jenkins`,
  `Day0.infra.02-grafana-cloud-bootstrap`, `Day2.publish.03-publish-azure-dashboards`,
  `Day2.traffic.01-traffic-simulation`, etc. across `docs/`, `terraform/*`
  comments and a workflow comment. All now point at the real filenames
  (`Day1.cluster.01-gke`, …). `terraform/gateway-bootstrap` module paths were
  left untouched.

> ⚠️ Re-point any branch-protection required status checks / `gh workflow run`
> calls that referenced `Day2.deploy.0{1,2,4}-*` → `Day2.redeploy.0{1,2,4}-*`.

## [v0.20.0] - 2026-06-23

Adds an ArgoCD redeploy workflow and corrects the `deploy`-tier `ZZ` ordering so
it reflects install/dependency order: ArgoCD is the CD engine installed before
everything it deploys (`scripts/up.sh` runs `08.5-argocd` before `03`/`04`), so
it now sorts first in the tier.

### Added

- **`Day2.deploy.01-argocd` workflow** — redeploys ArgoCD on a running cluster
  without a full reprovision: re-runs `scripts/08.5-argocd.sh` (ArgoCD Helm
  upgrade + OIDC/RBAC + the Jenkins API token, and re-applies the GitOps
  Applications ArgoCD owns: `platform-postgres`, External Secrets, Headlamp, the
  microservices ApplicationSet). Use for an ArgoCD-only change
  (`helm/argocd-values.yaml` or an Application manifest).

### Changed

- **`deploy`-tier `ZZ` reordered to install order.** ArgoCD takes `ZZ=01` (the
  CD engine the rest of the platform deploys through), so the previously-shipped
  `Day2.deploy.01-jenkins` is renamed **`Day2.deploy.02-jenkins`**; Headlamp
  keeps `04`. Final `deploy` tier: `01-argocd`, `02-jenkins`, `04-headlamp`
  (`03-tekton` / `05-pgadmin` reserved for future use). The Jenkins workflow's
  `name:` and all docs/README references were updated; the v0.19.0 CHANGELOG
  entry is left at its historical `Day2.deploy.01-jenkins` name. **Note:**
  re-point any branch-protection required status checks or `gh workflow run`
  calls that referenced `Day2.deploy.01-jenkins`.

## [v0.19.0] - 2026-06-23

Two structural changes: (1) the GitHub Actions workflows are renamed to a
self-documenting `DayN.tier.ZZ-resource` scheme, and (2) the in-cluster OSS
observability stack and the correlated Postgres platform are moved under ArgoCD
GitOps as **app-of-apps** Helm charts. No behavioural change to the
grafana-cloud / managed-azure / managed-aws observability modes.

> ⚠️ **Not yet validated on a live cluster.** Both changes are static-validated
> only (helm template, `bash -n`, YAML/yq parse). Confirm on a fresh
> `Day1.cluster.01-gke` provision before relying on it — in particular the
> pinned `loki` chart `7.0.0` (a major bump from the previously unpinned
> install) against `observability/grafana/values-oss-loki.yaml`.

### Changed

- **Workflow naming → `DayN.tier.ZZ-resource`** (`.github/workflows/`). The 16
  workflows were renamed from the `Y.X.ZZ` numeric scheme (`0.1.01`, `5.2.02`,
  `9.2.04`, …) to a self-documenting `DayN.tier.ZZ-resource` scheme:
  - **`DayN`** = lifecycle phase: `Day0` (persistent bootstrap) · `Day1`
    (cluster) · `Day2` (running-cluster ops) · `Decom` (teardown). `Decom`
    sorts after `Day2`, keeping teardown last.
  - **`tier`** = a brief semantic word from a controlled vocabulary
    (`infra`, `cluster`, `deploy`, `publish`, `traffic`) replacing the old
    middle digit.
  - **`ZZ`** = a per-resource id, stable for the same resource across all
    phases (e.g. `ZZ=03` is always Azure: `Day0.infra.03-azure-grafana` →
    `Day2.publish.03-azure-grafana` → `Decom.infra.03-azure-grafana`).
  - **`-resource`** identifies the resource only — no action verb, since the
    `DayN` prefix already implies bootstrap/publish/teardown.

  The full mapping:

  | Old | New |
  |---|---|
  | `0.1.01-gateway-bootstrap` | `Day0.infra.01-gateway` |
  | `0.1.02-grafana-cloud-bootstrap` | `Day0.infra.02-grafana-cloud` |
  | `0.1.03-azure-bootstrap` | `Day0.infra.03-azure-grafana` |
  | `0.1.04-aws-bootstrap` | `Day0.infra.04-aws-grafana` |
  | `0.2.01-gke-provision` | `Day1.cluster.01-gke` |
  | `5.2.02-redeploy-jenkins` | `Day2.deploy.01-jenkins` |
  | `5.2.03-redeploy-headlamp` | `Day2.deploy.04-headlamp` |
  | `5.1.03-publish-azure-dashboards` | `Day2.publish.03-azure-grafana` |
  | `5.1.04-publish-aws-dashboards` | `Day2.publish.04-aws-grafana` |
  | `5.1.05-publish-grafana-alerts` | `Day2.publish.05-alerts` |
  | `5.9.01-traffic-simulation` | `Day2.traffic.01-k6` |
  | `9.1.01-gke-decommission` | `Decom.cluster.01-gke` |
  | `9.2.01-gateway-decommission` | `Decom.infra.01-gateway` |
  | `9.2.02-grafana-cloud-decommission` | `Decom.infra.02-grafana-cloud` |
  | `9.2.03-azure-decommission` | `Decom.infra.03-azure-grafana` |
  | `9.2.04-aws-decommission` | `Decom.infra.04-aws-grafana` |

  Every workflow's `name:` field was reprefixed to its `DayN.tier.ZZ` value, so
  the **GitHub Actions UI sort order still is the execution order** (the UI
  sorts by `name:`, not filename). The `uses:` `workflow_call` references inside
  `Day1.cluster.01-gke` were repointed at the renamed `Day0.infra.0{2,3,4}`
  files. All references were updated across `README.md`, `docs/101` (full
  rewrite of the naming section + matrices), `docs/102`/`103`/`201`/`301`/`401`/
  `501`/`902`, `CLAUDE.md`, `scripts/` (including two stale `02.99`/`02.04`
  references) and `terraform/*` comments. `CHANGELOG.md` history is left at the
  original filenames (historical record). **Note:** any branch-protection
  *required status checks* or external `gh workflow run <file>` calls that
  referenced the old filenames must be re-pointed at the new names.

- **In-cluster OSS observability stack now GitOps-managed by ArgoCD.** The
  `observability.mode=oss` stack (kube-prometheus-stack = Prometheus + Grafana,
  Loki, Tempo) is deployed by the new `observability-oss` ArgoCD **app-of-apps**
  instead of raw `helm install` in `scripts/03-observability.sh`:
  - `argocd/observability-oss/` is a small Helm chart whose templates emit three
    **multi-source** child `Application`s (`oss-kube-prometheus-stack` /
    `oss-loki` / `oss-tempo`) — each combining the upstream chart with this
    repo's `observability/grafana/values-oss*.yaml` via the `$values` ref. The
    parent `argocd/observability-oss-app.yaml` is templated by the script for
    `repoURL`/`targetRevision` and passes them down as `helm.parameters`.
  - **`scripts/up.sh` now installs ArgoCD (`08.5`) before observability (`03`)**
    so the `Application` CRD exists when `03` applies the app-of-apps. (`08.5`
    only depends on the `jenkins-credentials` Secret from `01-namespaces`.)
  - `03-observability.sh` (oss) now creates the namespace + the companion
    objects the chart consumes and applies the app-of-apps, rather than
    `helm upgrade`-ing the charts. The OTel collectors stay `helm`-managed
    (shared across all four modes).
  - The Jenkins-datasource token and the public Grafana `root_url` move from
    `helm upgrade --set` to **`grafana.envValueFrom`** in `values-oss.yaml`,
    backed by script-managed companion objects: the `grafana-jenkins-ds` Secret
    (`$JENKINS_API_TOKEN`, mirrored from the `jenkins-credentials`
    admin-password) and the `grafana-runtime-config` ConfigMap
    (`GF_SERVER_ROOT_URL`, only when the gateway is enabled). The
    `jenkins-2026-grafana-dashboards` ConfigMap stays script-managed. All three
    are referenced `optional: true`, so a missing object just falls back.
  - Switching `observability.mode` away from `oss` (or `scripts/down.sh`)
    deletes the parent `Application`, and ArgoCD cascade-prunes the charts via
    the `resources-finalizer.argocd.argoproj.io` on each child. `down.sh` does
    this while ArgoCD is still running, before uninstalling ArgoCD.
  - `oss-kube-prometheus-stack` uses `ServerSideApply=true` to avoid the 256KB
    `last-applied-configuration` annotation limit on the Prometheus operator
    CRDs (same rationale as the CNPG app).

### Added

- **`platform-postgres` ArgoCD app-of-apps** (`argocd/platform-postgres/`). The
  previously standalone `cnpg-app.yaml` and `pgadmin-app.yaml` are grouped under
  one parent `Application` — pgAdmin administers the CNPG-provisioned databases,
  so they share a lifecycle and failure domain. The parent renders a Helm chart
  into two children: `cnpg-operator` (chart, preserving the
  `ServerSideDiff`/`ServerSideApply`/`Replace` oversized-CRD handling) and
  `pgadmin` (this repo's `helm/pgadmin`, branch from the parent's
  `helm.parameters`). `scripts/08.5-argocd.sh` applies the parent instead of the
  two separate manifests; `scripts/down.sh` cascade-prunes it. External Secrets
  and Headlamp stay standalone (not correlated).
- **`Day2.publish.01-oss-grafana` workflow** — refreshes the in-cluster OSS
  Grafana on a running cluster without a reprovision: rebuilds the
  `jenkins-2026-grafana-dashboards` ConfigMap, nudges the `observability-oss`
  ArgoCD app to re-sync (for committed chart/value changes) and republishes the
  Grafana alert rules. Forces `JENKINS2026_OBS_MODE=oss` (env-override pattern).
- **Pinned upstream chart versions** for the GitOps-managed stacks
  (CLAUDE.md "pin for reproducibility"): kube-prometheus-stack `87.0.1`, Loki
  `7.0.0`, Tempo `1.24.4` (in `argocd/observability-oss/values.yaml`) and
  CloudNative-PG `0.28.3` (in `argocd/platform-postgres/values.yaml`). These
  match the latest the previously unpinned `helm install` would have pulled.

### Removed

- `argocd/cnpg-app.yaml` and `argocd/pgadmin-app.yaml` — folded into the
  `platform-postgres` app-of-apps chart as `templates/cnpg-operator.yaml` and
  `templates/pgadmin.yaml`.

## [v0.18.1] - 2026-06-23

Fix Grafana Cloud decommission failing with "409 Conflict ... has deletion
protection enabled" — the ephemeral stack can now be torn down by
`9.2.02-grafana-cloud-decommission` as designed.

### Fixed

- **Grafana Cloud stack created with delete protection on**
  (`terraform/grafana-cloud-stack/main.tf`): the `grafana_cloud_stack`
  resource never set `delete_protection`, and the provider defaults it to
  `true`. The stack was therefore created protected and `terraform destroy`
  failed with `409 Conflict ... has deletion protection enabled` (the code
  comment claimed "no delete_protection" but never implemented it). Now sets
  `delete_protection = false` so future stacks are freely destroyable.
- **Decommission workflow could not unstick an already-protected stack**
  (`.github/workflows/9.2.02-grafana-cloud-decommission.yml`): `terraform
  destroy` does not push config changes before deleting, so flipping the flag
  in code alone would still 409 on the existing stack. The job now runs
  `terraform apply` first (reconciling `delete_protection=false` onto the live
  stack) and then `terraform destroy`, guarded so an empty state is not
  re-created.

## [v0.18.0] - 2026-06-22

Fix OTel Java agent injection on fresh deploy — dashboards populate without
manual intervention after the first full provision.

### Fixed

- **Wrong pod label selector in pipeline OTel self-heal** (`vars/microservicesDeploy.groovy`):
  the check used `-l app=<svc>` but pods carry `app.kubernetes.io/name=<svc>`.
  The selector never matched, so the self-heal always printed
  "No running pod — skipping" and silently left the agent uninjected.
  Fixed to `-l app.kubernetes.io/name=<svc>`.
- **`ensure-otel-injection.sh` ran before pods existed** (`scripts/up.sh`):
  on a fresh provision ArgoCD deploys microservices asynchronously after
  `up.sh` finishes, so the guard was always a no-op at that point.
  `up.sh` now waits for ArgoCD `microservices-stable` to reach `Healthy`
  (up to 10 min) before running the injection guard — ensuring the race is
  caught and healed on every fresh deploy regardless of observability mode.

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
