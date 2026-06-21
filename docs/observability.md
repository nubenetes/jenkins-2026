# Observability

Every component in this PoC - Jenkins, the 8 Spring Boot microservices, and
the Angular UI - exports OpenTelemetry **traces**, **metrics** and **logs**,
correlated by `trace_id`/`span_id` and common resource attributes
(`service.name`, `service.namespace=jenkins-2026`,
`deployment.environment=stable`).

## Components

### OpenTelemetry Operator ([`observability/otel-operator/`](../observability/otel-operator/))

Installed first (`scripts/02-otel-operator.sh`), via
`open-telemetry/opentelemetry-operator`. Provides the
`Instrumentation` and `OpenTelemetryCollector` CRDs.

### Java auto-instrumentation ([`helm/microservices/templates/instrumentation.yaml`](../helm/microservices/templates/instrumentation.yaml))

The `helm/microservices` chart creates an `Instrumentation` CR (`microservices-java`)
per namespace (`microservices`), pointing at
`otel-collector-gateway.observability.svc.cluster.local:4317`. Each `java`-typed
service's Deployment gets the pod annotation
`instrumentation.opentelemetry.io/inject-java: "true"`
([`deployment.yaml`](../helm/microservices/templates/deployment.yaml)), so the
operator's mutating webhook injects the OTel Java agent automatically - no
code changes to Microservices.

Key settings on the `Instrumentation` CR:

- `OTEL_INSTRUMENTATION_LOGBACK_APPENDER_ENABLED` /
  `..._LOG4J_APPENDER_ENABLED=true` - the Java agent injects `trace_id`/
  `span_id` into every log line's MDC, which is how logs correlate with
  traces (see "Correlation" below).
- `OTEL_RESOURCE_ATTRIBUTES=deployment.environment=stable,service.namespace=jenkins-2026`
- `sampler: parentbased_traceidratio` @ `1.0` (sample everything - this is a
  PoC, not a high-traffic prod cluster).

This template is guarded by
`{{- if .Capabilities.APIVersions.Has "opentelemetry.io/v1alpha1/Instrumentation" }}`,
so `helm template`/`helm lint` and out-of-order installs are safe even if the
operator isn't installed yet.

### Angular RUM ([`resources/angular/otel-web.js`](../resources/angular/otel-web.js))

A small (~100 line) vanilla-JS OTel Web shim, injected into
`microservices-angular`'s `index.html` via an nginx `sub_filter`
([`nginx.conf`](../resources/angular/nginx.conf)). It:

- Emits a "page load" span using the Navigation Timing API.
- Patches `window.fetch` to add a W3C `traceparent` header to every call to
  `/api/*` and emit a matching client span - so a button click in the browser
  becomes the root of the same trace that continues through `api-gateway`
  and the backend microservices.
- Exports spans as OTLP/HTTP JSON via `navigator.sendBeacon` to
  `/otel/v1/traces`, which nginx proxies to
  `otel-collector-gateway.observability.svc.cluster.local:4318`.

### OTel Collector ([`observability/otel-collector/`](../observability/otel-collector/))

Two `open-telemetry/opentelemetry-collector` releases, both with
`fullnameOverride` set so they're reachable at stable Service names
regardless of release name:

- **`otel-collector-gateway`** (Deployment) - receives OTLP/gRPC (4317) and
  OTLP/HTTP (4318, with permissive CORS for the browser RUM beacon) from
  Jenkins, the Java agent, and the Angular UI; batches and forwards to the
  configured backend.
- **`otel-collector-logs`** (DaemonSet) - tails `/var/log/pods/*/*/*.log` on
  every node via the `filelog` receiver (excluding its own and `kube-system`
  logs) and forwards log records to the same backend. This catches anything
  that doesn't go through the Java agent's log bridge (e.g. nginx access
  logs).

### Jenkins ([`jenkins/casc/jcasc-otel.yaml`](../jenkins/casc/jcasc-otel.yaml))

The `opentelemetry` plugin exports one span per pipeline run / stage / step
as `service.name=jenkins` to the same gateway - so a Microservices deploy's CI
trace and the resulting application traces share the same backend (and, with
matching timestamps, the same dashboards).

## Correlation, end to end

1. A browser request to `microservices-angular` gets a `traceparent` header from
   `otel-web.js` and is proxied to `api-gateway`.
2. The OTel Java agent on `api-gateway` (and every downstream service)
   continues that trace, and injects `trace_id=<...> span_id=<...>` into
   every log line via the Logback/Log4j2 MDC bridge.
3. **Logs -> Traces**: the Loki datasource's `derivedFields` match `trace_id=(\w+)` in log lines and link straight to that trace in Tempo.
   - **OSS**: Pre-configured in [`observability/grafana/values-oss.yaml`](../observability/grafana/values-oss.yaml).
   - **Grafana Cloud**: Log-to-trace links are **pre-configured by default**. Your Loki datasource (**`grafanacloud-<stack-slug>-logs`**) already contains derived fields that match `trace_id=...` and link them to Tempo. Because these datasources are system-managed, they appear as "Read Only" in the UI and do not require manual intervention.
4. **Other Cloud Datasources**: Your stack may also include system-managed sources like:
   - **`grafanacloud-<stack-slug>-alert-state-history`**: Historical alert transitions.
   - **`grafanacloud-<stack-slug>-usage-insights`**: Billing and series volume details.
5. **Metrics -> Traces**: Micrometer/OTel HTTP server metrics
   (`http_server_duration_milliseconds_*`) carry **exemplars** pointing at a
   sampled `trace_id`; the Prometheus/Mimir datasource's
   `exemplarTraceIdDestinations` links a latency spike straight to an example
   trace. (Note: Grafana Cloud usually requires this to be enabled in the
   Prometheus datasource settings as well).
5. **Traces -> Logs/Metrics**: the Tempo datasource's `tracesToLogsV2` /
   `tracesToMetrics` / `serviceMap` link a trace back to the logs and RED
   metrics for each `service.name` span in it.
6. **CI -> App**: a Jenkins pipeline's "Deploy to Kubernetes" stage span
   (service.name=jenkins) and the first requests served by the newly deployed
   pod (service.name=<microservices-service>) appear in the same time window /
   dashboards, with `service.namespace=jenkins-2026` common to both.

## Dashboards ([`observability/grafana/dashboards/`](../observability/grafana/dashboards/))

Three dashboards, portable across Grafana Cloud and OSS via `datasource`
template variables (`DS_PROMETHEUS`/`DS_LOKI`/`DS_TEMPO`):

- **`jenkins-overview.json`** - active/queued builds, executor utilization,
  pipeline completion rate by result (success/failure/aborted) and duration
  percentiles (from the Jenkins OTel plugin's `ci_pipeline_run_*` /
  `jenkins_*` metrics), plus Jenkins pod logs and traces.
- **`microservices-overview.json`** - per-service HTTP request rate, 5xx rate,
  p95 latency and JVM heap usage for the `stable` environment, plus traces and pod logs.
- **`k6-smoke-overview.json`** (uid `jenkins2026-k6-smoke-overview`) - the
  `microservices-k6-smoke` run's own
  iterations, checks pass rate, `http_req_failed` rate and
  `http_req_duration` p95 (scoped to the `stable` environment, with thresholds
  matching `jenkins/pipelines/k6/microservices-smoke.js`), plus the traces and
  Microservices pod logs generated by that run. Linked directly from the build
  console - see [k6 observability smoke test](#k6-observability-smoke-test)
  below.

## OTel injection race

The OTel Operator injects the Java agent into a microservices pod via a
**mutating webhook** at pod-admission time, only if the `Instrumentation` CR
(`microservices-java`) is already in its cache. That webhook (`mpod.kb.io`) has
`failurePolicy: Ignore` by design, so a pod admitted **before** the CR/webhook
is ready starts **without** the agent and silently emits no metrics/traces -
the dashboards then look empty (only `service.name=jenkins` has data, since
Jenkins emits via its OTel plugin, not the agent). The static
`OTEL_RESOURCE_ATTRIBUTES` env on the pod is set by the Helm chart and does
**not** mean the agent is loaded - check `JAVA_TOOL_OPTIONS` for `-javaagent`
(or the `opentelemetry-auto-instrumentation-java` init container).

Guards against it:

- [`scripts/02-otel-operator.sh`](../scripts/02-otel-operator.sh) waits for the
  webhook to actually be serving (its caBundle populated) before proceeding.
- [`scripts/ensure-otel-injection.sh`](../scripts/ensure-otel-injection.sh) is
  an idempotent verify-and-heal: it `rollout restart`s any running microservices
  Deployment whose pods lack the agent. `scripts/up.sh` calls it; run it any
  time the dashboards look empty.
- [`test/smoke-test.sh`](../test/smoke-test.sh) asserts the agent is injected on
  every running microservices Deployment, so a regression fails the pipeline.

For a fully GitOps-native guarantee, order the `Instrumentation` CR ahead of the
Deployments in the GitOps repo (ArgoCD `sync-wave: "-1"` on the CR, or a
PostSync hook that restarts the Deployments).

## k6 observability smoke test

[`microservices-k6-smoke`](../jenkins/pipelines/Jenkinsfile.microservices-k6-smoke) (generated by `seed_jobs.groovy`
alongside the per-service pipelines, see
[`docs/pipelines-as-code.md`](pipelines-as-code.md#k6-observability-smoke-test-microservices-k6-smoke))
send a small amount of synthetic traffic - a few k6 virtual users
(`K6_VUS`, default 4) running a few iterations in total (`K6_ITERATIONS`,
default 12) - through every Microservices Service in `TARGET_NAMESPACE`
(`microservices`). This is **not** a load/stress test; the
goal is purely to give Grafana something fresh to correlate end to end,
on demand, without waiting for real users.

[`jenkins/pipelines/k6/microservices-smoke.js`](../jenkins/pipelines/k6/microservices-smoke.js)
runs a simulated user flow per iteration:

- Gateway UI landing page: `GET /`
- Gateway health check: `GET /management/health`
- Direct Microservice health check (if in-cluster): `GET /management/health` on `jhipstersamplemicroservice` port 8081.
- Microservice health check via Gateway proxy routing (Option A verification): `GET /services/jhipstersamplemicroservice/management/health`.

Every request in an iteration carries the **same generated W3C
`traceparent` header**. Because the `Instrumentation` CR enables the
`tracecontext` propagator with `parentbased_traceidratio` @ `1.0` (see
above), every service the iteration touches continues that
trace - so one k6 iteration produces one Tempo trace spanning the gateway,
the backend microservice, and their databases, with each service's logs/metrics
correlated to it. The k6 script logs each iteration's `trace_id` to the Jenkins build console,
ready to paste into Tempo's trace search.

[`vars/microservicesK6Smoke.groovy`](../vars/microservicesK6Smoke.groovy) also runs
`k6 run -o opentelemetry`, pointing k6's own client-side request metrics at
`otel-collector-gateway.observability.svc.cluster.local:4317` with
`service.namespace=jenkins-2026,deployment.environment=stable` -
the same resource attributes as the Microservices services - so the test run's
own RED metrics land in the same Grafana Cloud stack alongside everything
else.

### Build output: summary + Grafana link

Once `k6 run` finishes (pass, threshold-`UNSTABLE`, or error),
`microservicesK6Smoke` prints to the build console:

1. The raw `k6-summary.json` (also archived as a build artifact).
2. A short pass/fail analysis - `checks` passed/total, `http_req_failed` rate
   vs its `rate<0.05` threshold, `http_req_duration` avg/p95 vs its
   `p(95)<3000ms` threshold, and total iterations.
3. A link to the **`k6-smoke-overview.json`** Grafana dashboard (see
   [Dashboards](#dashboards-observabilitygrafanadashboards) above), scoped to
   this run's `deployment_environment` and time window (+/-5m, so the
   dashboard's `rate()`/`histogram_quantile()` panels have data to render).

## observability.mode

### `grafana-cloud` (default)

`scripts/03-observability.sh` installs only the two collector releases,
exporting via `otlphttp` to Grafana Cloud's OTLP gateway. Either way, it
requires a `grafana-cloud-credentials` Secret carrying
`GRAFANA_CLOUD_OTLP_ENDPOINT`/`GRAFANA_CLOUD_OTLP_AUTH` (the OTLP gateway URL
and `base64(instanceID:apiKey)` Basic-auth header), plus optionally
`GRAFANA_BASE_URL`/`GRAFANA_API_KEY` (a Grafana Cloud service account token
with dashboard-write scope), used both by `scripts/07-grafana-dashboards.sh`
to import the dashboards via `gcx`, and by Jenkins (`GRAFANA_BASE_URL` is
surfaced to the controller via `jenkins-credentials`/`grafana-base-url`, see
`helm/jenkins/values-common.yaml`) to build the `k6-smoke-overview.json`
dashboard link in `microservicesK6Smoke`'s build output. Two ways to provide it:

- **GitHub Actions (automated)**: follow README.md "GitHub Actions
  automation" step 5 once - it provisions a persistent Grafana Cloud stack
  via [`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack).
  From then on, every `02.01-gke-provision`/`02.99-gke-decommission` run applies
  [`terraform/grafana-cloud-token`](../terraform/grafana-cloud-token) to
  mint/revoke a scoped OTLP access policy token and dashboard service account
  token, and writes them into `grafana-cloud-credentials` automatically - no
  manual secret needed.
- **Local / `test/e2e.sh` (manual)**: copy
  [`observability/otel-collector/secret.example.yaml`](../observability/otel-collector/secret.example.yaml)
  to `secret.yaml`, fill in your stack's OTLP endpoint and
  `base64(instanceID:apiKey)` Basic-auth header (Grafana Cloud Portal ->
  **OpenTelemetry** -> **Configuration Details**), and `kubectl apply -f` it
  before running `scripts/up.sh` (or re-run
  `03-observability.sh`/`07-grafana-dashboards.sh` afterwards).

### `oss`

`scripts/03-observability.sh` additionally installs, all in the
`observability` namespace:

- `prometheus-community/kube-prometheus-stack` -
  [`values-oss.yaml`](../observability/grafana/values-oss.yaml) - Prometheus
  (with `--web.enable-remote-write-receiver` for the collector's
  `prometheusremotewrite` exporter) + Grafana (image pinned to `13.0.2`),
  pre-provisioned with Loki and Tempo datasources (derived fields / exemplars
  / service graph as described above) and the `jenkins-2026` dashboards via a
  ConfigMap + the Grafana sidecar. When the public gateway is enabled, this
  Grafana is exposed at `https://grafana.<baseDomain>` behind IAP (same edge
  pattern as Jenkins/Headlamp - see
  [Public access](../README.md#public-access-gke-gateway-api--iap)); its
  `server.root_url` is set accordingly by `scripts/03-observability.sh`.
- `grafana/loki` -
  [`values-oss-loki.yaml`](../observability/grafana/values-oss-loki.yaml) -
  single-binary, filesystem storage, native OTLP log ingestion.
- `grafana/tempo` -
  [`values-oss-tempo.yaml`](../observability/grafana/values-oss-tempo.yaml) -
  single-binary, OTLP receiver, metrics-generator feeding RED metrics/service
  graph back into Prometheus via remote-write.
- The two collector releases use
  [`values-oss.yaml`](../observability/otel-collector/values-oss.yaml) /
  [`values-oss-logs.yaml`](../observability/otel-collector/values-oss-logs.yaml)
  (exporters: `otlp/tempo`, `otlphttp/loki`, `prometheusremotewrite`) instead
  of the Grafana Cloud variants. The gateway collector also runs a
  `k8sobjects` receiver that ships Kubernetes **Events** to Loki, for parity
  with grafana-cloud mode's k8s-monitoring `clusterEvents` preset.

> **Switching modes in place:** re-running the deploy after changing
> `observability.mode` is clean - `scripts/03-observability.sh` uninstalls the
> releases belonging to the mode you're leaving (cloud-only `pdc-agent` /
> `k8s-monitoring` when switching to `oss`; the in-cluster
> `kube-prometheus-stack` / `loki` / `tempo` when switching back to
> `grafana-cloud`) before installing the new stack. The shared
> `otel-collector-{gateway,logs}` releases are reconfigured via `helm upgrade`.

### `managed-azure`

Unlike Grafana Cloud, **Azure Managed Grafana is only a visualization
frontend** - it reads from Azure Monitor datasources, it does not ingest OTLP.
So in this mode the collectors export to Azure Monitor's backends and Azure
Managed Grafana renders from them:

- **traces + logs** → Azure Monitor / Application Insights, via the
  collector-contrib `azuremonitor` exporter (connection string from the
  `azure-monitor-credentials` Secret).
- **metrics** → Azure Monitor managed Prometheus, via the
  `prometheusremotewrite` exporter authenticated to Microsoft Entra with the
  `oauth2client` extension (service-principal client-credentials, scope
  `https://monitor.azure.com/.default`).

`scripts/03-observability.sh` installs the two collector releases with
[`values-managed-azure.yaml`](../observability/otel-collector/values-managed-azure.yaml)
/ [`values-managed-azure-logs.yaml`](../observability/otel-collector/values-managed-azure-logs.yaml),
after retiring any in-cluster `oss` backends / `grafana-cloud` agents left from
a previous mode. It requires the `azure-monitor-credentials` Secret - copy
[`secret-managed-azure.example.yaml`](../observability/otel-collector/secret-managed-azure.example.yaml),
fill it in, and apply it first.

`scripts/07-grafana-dashboards.sh` publishes the
[managed-azure dashboard variants](../observability/grafana/dashboards-azure)
to Azure Managed Grafana via its Grafana HTTP API. Those variants keep the
metric panels (Azure Monitor managed Prometheus is PromQL-compatible) and
rewrite the log/trace panels to Azure Monitor Logs/Traces, with the
Application Insights resource selected at runtime via an account-agnostic
`${appinsights}` Azure Resource Graph template variable (no hardcoded IDs).

The Azure resources themselves are provisioned by
[`terraform/azure-managed-grafana/`](../terraform/azure-managed-grafana),
applied **once** by the `01.03 Azure managed-grafana bootstrap` workflow (GCS
remote state, same bucket as `terraform/gke`). It creates the Azure Managed
Grafana instance, the Azure Monitor workspace + Data Collection Endpoint/Rule
for managed Prometheus, Application Insights + Log Analytics, the Entra service
principal the collector authenticates with, and the role assignments.

Secrets handling is **key-less and repo-clean**: the bootstrap workflow logs in
to Azure with **GitHub OIDC** (a federated credential on an Entra app - no
stored client secret), and only *identifiers*
(`AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID`/
`AZURE_GRAFANA_ADMIN_OBJECT_IDS`) are GitHub secrets. The actual backend
credentials (connection string, managed-Prometheus endpoint, the collector's
service-principal secret) live only in the GCS Terraform state;
`02.01-gke-provision.yml` (managed-azure) reads them straight from those outputs
to build the `azure-monitor-credentials` Secret. Nothing sensitive is written
to the repo or duplicated as a GitHub secret. See README.md "GitHub Actions
automation" step 6.

**Kubernetes infrastructure metrics** (parity with grafana-cloud's
k8s-monitoring/Alloy): `03-observability.sh` deploys `kube-state-metrics` +
`prometheus-node-exporter`, and the gateway collector's `prometheus` receiver
scrapes the standard job set - **cadvisor + kubelet** (via the API server proxy
with the collector's ServiceAccount token), **node**, **kube-state-metrics** -
all stamped with a `cluster` label and remote-written to Azure Monitor managed
Prometheus. These feed **Azure Managed Grafana's built-in Kubernetes dashboards**
(Compute Resources / Kubelet / Node Exporter / USE Method), which AMG
auto-provisions from the Azure Monitor workspace integration - so there are no
infra dashboards to maintain in this repo (the Azure-native equivalent of the
kube-prometheus-stack dashboards `oss` ships).

**Correlation** is App-Insights-native, not Loki/Tempo: the OTel `trace_id`
becomes the App Insights **`operation_Id`**, shared by `traces` (logs),
`requests`/`dependencies` (spans). The dashboards query the App Insights
**resource** (so the classic `traces`/`requests`/`dependencies` schema, NOT the
workspace `App*` schema). Both the log and trace panels carry a data link on
the `operation_Id` column that sets the `operation_id` dashboard variable, so
clicking it filters BOTH panels to that one trace's logs + spans - the
managed-azure equivalent of grafana-cloud's derived-fields / traces-to-logs
click-through. Metric→trace exemplars are not wired (Azure-managed-Prometheus
limitation).

> **Note.** The managed-azure pipeline is integration-verified end to end
> (metrics/logs/traces confirmed in Azure Monitor; dashboard queries validated
> through Grafana's query engine against the live App Insights classic schema).
> Compute stays on GKE; only the
> observability backend changes.

### `managed-aws`

The AWS analogue of `managed-azure` - Amazon Managed Grafana is a frontend, so
telemetry goes to AWS backends and AMG reads them:

- **metrics** → **Amazon Managed Service for Prometheus** (remote-write, **SigV4**).
- **traces** → **AWS X-Ray** (`awsxray` exporter).
- **logs** → **CloudWatch Logs** (`awscloudwatchlogs`).

`03-observability.sh` installs the two collector releases with
[`values-managed-aws.yaml`](../observability/otel-collector/values-managed-aws.yaml)
/ [`-logs.yaml`](../observability/otel-collector/values-managed-aws-logs.yaml)
(plus `kube-state-metrics` + `node-exporter`, scraped alongside cadvisor/kubelet
into AMP for the AMG built-in Kubernetes dashboards). It requires the
`aws-managed-credentials` Secret - in CI `02.01` builds it from the
[`terraform/aws-managed-grafana`](../terraform/aws-managed-grafana) GCS-state
outputs (the module is applied once by **01.04 AWS bootstrap**).

**Key-less auth (no access keys anywhere):** the collector's ServiceAccount is
federated to an IAM role via the **GKE cluster's OIDC issuer** +
`AssumeRoleWithWebIdentity` (a projected SA token, audience `sts.amazonaws.com`).
The bootstrap workflow likewise uses **GitHub OIDC → AWS**. Only identifiers
(`AWS_BOOTSTRAP_ROLE_ARN`/`AWS_REGION`/`GKE_OIDC_ISSUER_URL`) are GitHub secrets.

**Dashboards.** AMG reads from AWS datasources, so `07-grafana-dashboards.sh`
publishes the [`dashboards-aws/`](../observability/grafana/dashboards-aws)
variants (metric panels unchanged; Loki -> CloudWatch Logs, Tempo -> X-Ray).
AMG has no static API key, so the script stays keyless: it mints a short-lived
workspace **service-account token** (`aws grafana
create-workspace-service-account-token`, 15 min, deleted on exit), ensures the
AMP/CloudWatch/X-Ray datasources exist (authenticated by the workspace IAM role),
substitutes their uids and imports. All get-or-create / overwrite, so it is
idempotent across decommission + re-provision - see
[`dashboards-aws/README.md`](../observability/grafana/dashboards-aws/README.md).

> **What this PoC ships vs. follow-ups.** Collector wiring, mode plumbing,
> credentials template/Secret wiring, dashboards + publish, the Terraform module
> and the bootstrap/decommission workflows are in place and **validated**
> (`terraform validate`, `helm template`) but **not applied** - bring an AWS
> account (with IAM Identity Center for AMG's AWS_SSO auth), run **01.04**, and
> grant your SSO users Admin on the Grafana workspace (see
> [README "Logging in to Amazon Managed Grafana"](../README.md#logging-in-to-amazon-managed-grafana-managed-aws)).
> Compute stays on GKE; only the observability backend changes.
