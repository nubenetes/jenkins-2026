# Observability

Every component in this PoC - Jenkins, the 8 Spring Boot microservices, and
the Angular UI - exports OpenTelemetry **traces**, **metrics** and **logs**,
correlated by `trace_id`/`span_id` and common resource attributes
(`service.name`, `service.namespace=jenkins-2026`,
`deployment.environment=stable|develop`).

## Components

### OpenTelemetry Operator ([`observability/otel-operator/`](../observability/otel-operator/))

Installed first (`scripts/02-otel-operator.sh`), via
`open-telemetry/opentelemetry-operator`. Provides the
`Instrumentation` and `OpenTelemetryCollector` CRDs.

### Java auto-instrumentation ([`helm/petclinic/templates/instrumentation.yaml`](../helm/petclinic/templates/instrumentation.yaml))

The `helm/petclinic` chart creates an `Instrumentation` CR (`petclinic-java`)
per namespace (`petclinic`/`petclinic-develop`), pointing at
`otel-collector-gateway.observability.svc.cluster.local:4317`. Each `java`-typed
service's Deployment gets the pod annotation
`instrumentation.opentelemetry.io/inject-java: "true"`
([`deployment.yaml`](../helm/petclinic/templates/deployment.yaml)), so the
operator's mutating webhook injects the OTel Java agent automatically - no
code changes to PetClinic.

Key settings on the `Instrumentation` CR:

- `OTEL_INSTRUMENTATION_LOGBACK_APPENDER_ENABLED` /
  `..._LOG4J_APPENDER_ENABLED=true` - the Java agent injects `trace_id`/
  `span_id` into every log line's MDC, which is how logs correlate with
  traces (see "Correlation" below).
- `OTEL_RESOURCE_ATTRIBUTES=deployment.environment=<stable|develop>,service.namespace=jenkins-2026`
- `sampler: parentbased_traceidratio` @ `1.0` (sample everything - this is a
  PoC, not a high-traffic prod cluster).

This template is guarded by
`{{- if .Capabilities.APIVersions.Has "opentelemetry.io/v1alpha1/Instrumentation" }}`,
so `helm template`/`helm lint` and out-of-order installs are safe even if the
operator isn't installed yet.

### Angular RUM ([`resources/angular/otel-web.js`](../resources/angular/otel-web.js))

A small (~100 line) vanilla-JS OTel Web shim, injected into
`petclinic-angular`'s `index.html` via an nginx `sub_filter`
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
as `service.name=jenkins` to the same gateway - so a PetClinic deploy's CI
trace and the resulting application traces share the same backend (and, with
matching timestamps, the same dashboards).

## Correlation, end to end

1. A browser request to `petclinic-angular` gets a `traceparent` header from
   `otel-web.js` and is proxied to `api-gateway`.
2. The OTel Java agent on `api-gateway` (and every downstream service)
   continues that trace, and injects `trace_id=<...> span_id=<...>` into
   every log line via the Logback/Log4j2 MDC bridge.
3. **Logs -> Traces**: the Loki datasource's `derivedFields` (Grafana Cloud:
   configured manually in the Grafana Cloud Logs datasource; OSS:
   [`observability/grafana/values-oss.yaml`](../observability/grafana/values-oss.yaml))
   match `trace_id=(\w+)` in log lines and link straight to that trace in
   Tempo.
4. **Metrics -> Traces**: Micrometer/OTel HTTP server metrics
   (`http_server_duration_milliseconds_*`) carry **exemplars** pointing at a
   sampled `trace_id`; the Prometheus/Mimir datasource's
   `exemplarTraceIdDestinations` links a latency spike straight to an example
   trace.
5. **Traces -> Logs/Metrics**: the Tempo datasource's `tracesToLogsV2` /
   `tracesToMetrics` / `serviceMap` link a trace back to the logs and RED
   metrics for each `service.name` span in it.
6. **CI -> App**: a Jenkins pipeline's "Deploy to Kubernetes" stage span
   (service.name=jenkins) and the first requests served by the newly deployed
   pod (service.name=<petclinic-service>) appear in the same time window /
   dashboards, with `service.namespace=jenkins-2026` common to both.

## Dashboards ([`observability/grafana/dashboards/`](../observability/grafana/dashboards/))

Two dashboards, portable across Grafana Cloud and OSS via `datasource`
template variables (`DS_PROMETHEUS`/`DS_LOKI`/`DS_TEMPO`):

- **`jenkins-overview.json`** - active/queued builds, executor utilization,
  pipeline completion rate by result (success/failure/aborted) and duration
  percentiles (from the Jenkins OTel plugin's `ci_pipeline_run_*` /
  `jenkins_*` metrics), plus Jenkins pod logs and traces.
- **`petclinic-overview.json`** - per-service HTTP request rate, 5xx rate,
  p95 latency and JVM heap usage (filterable by `stable`/`develop`
  environment), plus traces and pod logs for the selected environment.

## observability.mode

### `grafana-cloud` (default)

`scripts/03-observability.sh` installs only the two collector releases,
exporting via `otlphttp` to Grafana Cloud's OTLP gateway. Requires a
`grafana-cloud-credentials` Secret - copy
[`observability/otel-collector/secret.example.yaml`](../observability/otel-collector/secret.example.yaml),
fill in your stack's OTLP endpoint and `base64(instanceID:apiKey)` Basic-auth
header (Grafana Cloud Portal -> **OpenTelemetry** -> **Configuration
Details**), and `kubectl apply -f` it before running `scripts/up.sh` (or
re-run `03-observability.sh`/`07-grafana-dashboards.sh` afterwards). The same
secret optionally carries `GRAFANA_BASE_URL`/`GRAFANA_API_KEY` (a Grafana
Cloud service account token with dashboard-write scope), used by
`scripts/07-grafana-dashboards.sh` to import the two dashboards via the HTTP
API, and `GRAFANA_TRACES_DASHBOARD_UID`/`OTEL_LOGS_BACKEND_URL`, surfaced as
links on Jenkins build pages by `jcasc-otel.yaml`.

### `oss`

`scripts/03-observability.sh` additionally installs, all in the
`observability` namespace:

- `prometheus-community/kube-prometheus-stack` -
  [`values-oss.yaml`](../observability/grafana/values-oss.yaml) - Prometheus
  (with `--web.enable-remote-write-receiver` for the collector's
  `prometheusremotewrite` exporter) + Grafana, pre-provisioned with Loki and
  Tempo datasources (derived fields / exemplars / service graph as described
  above) and the two `jenkins-2026` dashboards via a ConfigMap + the Grafana
  sidecar.
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
  of the Grafana Cloud variants.

### `managed`

A documented stub (see [`platforms.md`](platforms.md)) for "bring your own"
managed Grafana (e.g. Amazon Managed Grafana, Azure Managed Grafana). Point
`OTEL_EXPORTER_OTLP_ENDPOINT` / the `grafana-cloud-credentials` Secret at that
stack's OTLP gateway; `03-observability.sh`/`07-grafana-dashboards.sh` exit
without creating resources.
