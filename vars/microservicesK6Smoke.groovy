/**
 * microservicesK6Smoke(namespace: '<ns>', envName: 'stable'|'develop',
 *                   genaiEnabled: true|false, vus: '<n>', iterations: '<n>')
 *
 * Runs jenkins/pipelines/k6/microservices-smoke.js from the 'k6' container of the
 * pod template defined in jenkins/pipelines/Jenkinsfile.microservices-k6-smoke -
 * a small amount of synthetic traffic (a few VUs/iterations, NOT a load test)
 * against the Microservices Services in `namespace`, to give Grafana Cloud fresh
 * traces/metrics/logs to correlate.
 *
 * k6's own request metrics are exported (-o opentelemetry) to the same
 * otel-collector-gateway used by the OTel Java auto-instrumentation
 * (helm/microservices/templates/instrumentation.yaml) and this Jenkins pipeline's
 * own spans (jenkins/casc/jcasc-otel.yaml), tagged with the same
 * service.namespace=jenkins-2026 and deployment.environment=<envName> resource
 * attributes so everything groups together in Grafana.
 *
 * k6 exits 99 when a threshold (e.g. the p(95) latency budget in
 * microservices-smoke.js) is crossed but the run itself completed cleanly - this
 * is a smoke test feeding Grafana fresh telemetry, not a load-test gate, so
 * that's reported as UNSTABLE rather than failing the build. Any other
 * non-zero exit (script/runtime error) still fails the build.
 *
 * Either way, once k6-summary.json exists this prints a short pass/fail
 * analysis of it plus a link to the "jenkins-2026 / k6 Observability Smoke
 * Test" Grafana dashboard (observability/grafana/dashboards/k6-smoke-overview.json,
 * imported by scripts/07-grafana-dashboards.sh) scoped to this run's
 * deployment_environment and time window.
 */
def call(Map cfg) {
  container('k6') {
    withEnv([
      "TARGET_NAMESPACE=${cfg.namespace}",
      "GENAI_SERVICE_ENABLED=${cfg.genaiEnabled}",
      "K6_VUS=${cfg.vus}",
      "K6_ITERATIONS=${cfg.iterations}",
      "K6_OTEL_SERVICE_NAME=k6-microservices-smoke",
      "K6_OTEL_GRPC_EXPORTER_ENDPOINT=otel-collector-gateway.observability.svc.cluster.local:4317",
      "K6_OTEL_GRPC_EXPORTER_INSECURE=true",
      "K6_OTEL_EXPORT_INTERVAL=2s",
      "OTEL_RESOURCE_ATTRIBUTES=service.namespace=jenkins-2026,deployment.environment=${cfg.envName}",
      // Optional Grafana Cloud k6 (the k6-app) streaming; empty -> skipped.
      // Injected into the controller env from the jenkins-credentials Secret
      // (helm/jenkins/values-common.yaml containerEnv, populated by 04-jenkins.sh).
      "K6_CLOUD_TOKEN=${env.K6_CLOUD_TOKEN ?: ''}",
      "K6_CLOUD_PROJECT_ID=${env.K6_CLOUD_PROJECT_ID ?: ''}",
    ]) {
      def exitCode = sh(
        script: '''
          set -eu
          # Stream results to Grafana Cloud k6 (/a/k6-app) when a token + project
          # id are present; otherwise just OTLP + summary, as before.
          CLOUD_OUT=""
          if [ -n "${K6_CLOUD_TOKEN:-}" ] && [ -n "${K6_CLOUD_PROJECT_ID:-}" ]; then
            CLOUD_OUT="--out cloud"
          fi
          k6 run -o opentelemetry ${CLOUD_OUT} --summary-export=k6-summary.json jenkins/pipelines/k6/microservices-smoke.js
        ''',
        returnStatus: true
      )

      if (fileExists('k6-summary.json')) {
        printK6Summary()
        printGrafanaLink(cfg.envName)
      }

      if (exitCode == 99) {
        unstable('k6 thresholds were not met - see k6-summary.json and Grafana for details')
      } else if (exitCode != 0) {
        error("k6 run failed with exit code ${exitCode}")
      }
    }
  }
}

/**
 * Prints the raw k6-summary.json (also archived as a build artifact by
 * Jenkinsfile.microservices-k6-smoke) plus a short human-readable pass/fail
 * breakdown of the metrics that matter most for this smoke test.
 */
def printK6Summary() {
  echo '--- k6-summary.json ---'
  echo readFile('k6-summary.json')

  def metrics = readJSON(file: 'k6-summary.json').metrics ?: [:]

  def lines = ['--- k6 run analysis ---']

  def checks = metrics.checks
  if (checks?.values != null) {
    def passes = (checks.values.passes ?: 0) as Number
    def fails = (checks.values.fails ?: 0) as Number
    def rate = (checks.values.rate ?: 0) as Number
    lines << "checks:            ${passes}/${passes + fails} passed (${String.format('%.1f', rate * 100)}%)"
  }

  def httpReqFailed = metrics.http_req_failed
  if (httpReqFailed?.values != null) {
    def rate = (httpReqFailed.values.rate ?: 0) as Number
    lines << "http_req_failed:   ${String.format('%.2f', rate * 100)}% failed (threshold rate<0.05: ${thresholdStatus(httpReqFailed)})"
  }

  def httpReqDuration = metrics.http_req_duration
  if (httpReqDuration?.values != null) {
    def p95 = (httpReqDuration.values['p(95)'] ?: 0) as Number
    def avg = (httpReqDuration.values.avg ?: 0) as Number
    lines << "http_req_duration: avg=${String.format('%.0f', avg)}ms, p95=${String.format('%.0f', p95)}ms (threshold p(95)<3000ms: ${thresholdStatus(httpReqDuration)})"
  }

  def iterations = metrics.iterations
  if (iterations?.values != null) {
    def count = (iterations.values.count ?: 0) as Number
    def rate = (iterations.values.rate ?: 0) as Number
    lines << "iterations:        ${count} (${String.format('%.2f', rate)}/s)"
  }

  echo lines.join('\n')
}

/**
 * @return "PASS"/"FAIL" if metric.thresholds has at least one threshold and
 * all of them are ok, "FAIL" if any failed, or "n/a" if there are none.
 */
def thresholdStatus(metric) {
  def thresholds = metric.thresholds ?: [:]
  if (thresholds.isEmpty()) {
    return 'n/a'
  }
  return thresholds.values().every { it.ok } ? 'PASS' : 'FAIL'
}

/**
 * Prints a link to the "jenkins-2026 / k6 Observability Smoke Test" Grafana
 * dashboard (uid jenkins2026-k6-smoke-overview), scoped to this run's
 * deployment_environment and padded +/-5m around the build's time window so
 * the dashboard's rate()/histogram_quantile() panels have enough lookback to
 * render this run's data points.
 */
def printGrafanaLink(String envName) {
  def baseUrl = env.GRAFANA_BASE_URL
  if (!baseUrl) {
    echo 'GRAFANA_BASE_URL not configured - skipping Grafana dashboard link.'
    return
  }

  def padMillis = 5 * 60 * 1000
  def from = currentBuild.startTimeInMillis - padMillis
  def to = System.currentTimeMillis() + padMillis

  def url = "${baseUrl}/d/jenkins2026-k6-smoke-overview/jenkins-2026-k6-observability-smoke-test" +
    "?orgId=1&var-deployment_environment=${envName}&from=${from}&to=${to}"

  echo "View this run in Grafana: ${url}"

  // When Grafana Cloud k6 streaming is enabled, also surface the native k6-app URL.
  def projectId = env.K6_CLOUD_PROJECT_ID
  if (projectId?.trim()) {
    echo "View this run in Grafana Cloud k6: ${baseUrl}/a/k6-app/projects/${projectId}"
  }
}
