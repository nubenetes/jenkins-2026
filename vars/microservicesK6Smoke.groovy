/**
 * microservicesK6Smoke(namespace: '<ns>', envName: 'stable'|'develop',
 *                   genaiEnabled: true|false,
 *                   // workload (all optional; '' / null → the k6 script default)
 *                   profile: 'smoke'|'load'|'stress'|'soak'|'spike'|'breakpoint',
 *                   vus: '<n>', iterations: '<n>', duration: '<dur>',
 *                   stages: '30s:10,1m:50,30s:0', rps: '<n>', sleep: '<secs>',
 *                   scenarios: 'all'|'gateway-ui,gateway-health,...',
 *                   p95Ms: '<n>', errorRate: '<0..1>', debug: true|false,
 *                   targetUrl: '<external base URL>')
 *
 * Runs jenkins/pipelines/k6/microservices-smoke.js from the 'k6' container of the
 * pod template defined in jenkins/pipelines/Jenkinsfile.microservices-k6-smoke -
 * synthetic traffic against the Microservices Services in `namespace`, to give
 * Grafana fresh traces/metrics/logs to correlate.
 *
 * The default profile (smoke, a few VUs/iterations) is NOT a load test; the
 * load/stress/soak/spike/breakpoint profiles and the fine-grained overrides
 * (VUs, duration, ramping stages, arrival rate, thresholds, think-time, request
 * flows) all flow straight into the K6SIM_* contract the script reads. See
 * docs/302-K6_LOAD_TESTING.md.
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
      "TARGET_URL=${cfg.targetUrl ?: ''}",
      "ENV_NAME=${cfg.envName}",
      "GENAI_SERVICE_ENABLED=${cfg.genaiEnabled}",
      // Workload contract (K6SIM_*). Empty string → the k6 script's own default,
      // so callers only override what they care about. See microservices-smoke.js.
      "K6SIM_PROFILE=${cfg.profile ?: 'smoke'}",
      "K6SIM_VUS=${cfg.vus ?: ''}",
      "K6SIM_ITERATIONS=${cfg.iterations ?: ''}",
      "K6SIM_DURATION=${cfg.duration ?: ''}",
      "K6SIM_STAGES=${cfg.stages ?: ''}",
      "K6SIM_RPS=${cfg.rps ?: ''}",
      "K6SIM_SLEEP=${cfg.sleep ?: ''}",
      "K6SIM_SCENARIOS=${cfg.scenarios ?: ''}",
      "K6SIM_P95_MS=${cfg.p95Ms ?: ''}",
      "K6SIM_ERROR_RATE=${cfg.errorRate ?: ''}",
      "K6SIM_DEBUG=${cfg.debug ?: ''}",
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
          # k6-summary.json is written by the script's handleSummary() (CWD), not
          # --summary-export: k6 2.0's --summary-export flattened schema made the
          # readJSON parser below (printK6Summary) read all-zeros.
          # ci_runner/k6_profile as k6 --tag (metric labels on every series), not
          # resource attrs: Grafana Cloud only promotes a fixed set of resource attrs
          # to labels, so custom ones must be metric tags for the dashboard filters.
          k6 run --tag ci_runner=jenkins --tag "k6_profile=${K6SIM_PROFILE}" \
            -o opentelemetry ${CLOUD_OUT} jenkins/pipelines/k6/microservices-smoke.js
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
 * Jenkinsfile.microservices-k6-smoke) plus a layered human-readable analysis:
 *
 *   1. SUMMARY  - the at-a-glance pass/fail line anyone can read.
 *   2. LATENCY  - full percentile spread (avg/min/med/p90/p95/p99/max) so an
 *                 expert sees the tail, not just p95, and where the budget bites.
 *   3. THROUGHPUT & RELIABILITY - RPS, iterations, dropped iterations, peak VUs,
 *                 bytes in/out, plus connection-level timings (TLS/connect/wait)
 *                 when k6 emits them (external TARGET_URL runs).
 *   4. THRESHOLDS - every configured threshold expression with its PASS/FAIL,
 *                 and a final verdict (PASS / UNSTABLE-thresholds / see-checks).
 *
 * Helpers (numOf/msVal/fmtBytes/...) tolerate the metric being absent so a
 * minimal smoke run and a full breakpoint run both print cleanly.
 */
def printK6Summary() {
  echo '--- k6-summary.json ---'
  echo readFile('k6-summary.json')

  def metrics = readJSON(file: 'k6-summary.json').metrics ?: [:]

  // ---- 1. SUMMARY (basic, at-a-glance) -------------------------------------
  def lines = ['', '========== k6 run analysis ==========', '--- SUMMARY ---']

  def checks = metrics.checks
  if (checks?.values != null) {
    def passes = numOf(checks.values.passes)
    def fails = numOf(checks.values.fails)
    def rate = numOf(checks.values.rate)
    lines << "checks:            ${passes as int}/${(passes + fails) as int} passed (${pct(rate)})${fails > 0 ? '  <-- ' + (fails as int) + ' FAILED' : ''}"
  }

  def httpReqFailed = metrics.http_req_failed
  if (httpReqFailed?.values != null) {
    lines << "http_req_failed:   ${pct(numOf(httpReqFailed.values.rate))} failed   [${thresholdStatus(httpReqFailed)}]"
  }

  def reqs = metrics.http_reqs
  if (reqs?.values != null) {
    lines << "http_reqs:         ${numOf(reqs.values.count) as int} total (${String.format('%.2f', numOf(reqs.values.rate))} req/s)"
  }

  // ---- 2. LATENCY (expert: full percentile spread) -------------------------
  def dur = metrics.http_req_duration
  if (dur?.values != null) {
    lines << ''
    lines << '--- LATENCY (http_req_duration, ms)  [' + thresholdStatus(dur) + '] ---'
    lines << "  avg=${ms(dur.values.avg)}  min=${ms(dur.values.min)}  med=${ms(dur.values.med)}"
    lines << "  p90=${ms(dur.values['p(90)'])}  p95=${ms(dur.values['p(95)'])}  p99=${ms(dur.values['p(99)'])}  max=${ms(dur.values.max)}"
    // Connection-level breakdown (only meaningful for external TARGET_URL runs).
    def waiting = metrics.http_req_waiting
    if (waiting?.values != null) {
      lines << "  server (waiting/TTFB) avg=${ms(waiting.values.avg)}  p95=${ms(waiting.values['p(95)'])}" +
               connDetail(metrics)
    }
  }

  // ---- 3. THROUGHPUT & RELIABILITY -----------------------------------------
  def iterations = metrics.iterations
  def vusMax = metrics.vus_max
  def dropped = metrics.dropped_iterations
  def dataRecv = metrics.data_received
  def dataSent = metrics.data_sent
  if (iterations?.values != null || dataRecv?.values != null) {
    lines << ''
    lines << '--- THROUGHPUT & RELIABILITY ---'
    if (iterations?.values != null) {
      lines << "  iterations:      ${numOf(iterations.values.count) as int} (${String.format('%.2f', numOf(iterations.values.rate))}/s)"
    }
    if (dropped?.values != null && numOf(dropped.values.count) > 0) {
      lines << "  dropped iters:   ${numOf(dropped.values.count) as int}  <-- arrival-rate executor could not keep up (under-provisioned VUs)"
    }
    if (vusMax?.values != null) {
      lines << "  peak VUs:        ${numOf(vusMax.values.value ?: vusMax.values.max) as int}"
    }
    if (dataRecv?.values != null) {
      lines << "  data received:   ${fmtBytes(numOf(dataRecv.values.count))} (${fmtBytes(numOf(dataRecv.values.rate))}/s)"
    }
    if (dataSent?.values != null) {
      lines << "  data sent:       ${fmtBytes(numOf(dataSent.values.count))} (${fmtBytes(numOf(dataSent.values.rate))}/s)"
    }
  }

  // ---- 4. THRESHOLDS table + verdict ---------------------------------------
  lines << ''
  lines << '--- THRESHOLDS ---'
  def anyThreshold = false
  def allOk = true
  metrics.each { name, m ->
    def th = m?.thresholds
    if (th instanceof Map && !th.isEmpty()) {
      th.each { expr, res ->
        anyThreshold = true
        def ok = (res instanceof Map) ? (res.ok != false) : (res != false)
        if (!ok) { allOk = false }
        lines << "  [${ok ? 'PASS' : 'FAIL'}] ${name}: ${expr}"
      }
    }
  }
  if (!anyThreshold) { lines << '  (none configured)' }

  def checksFailed = checks?.values != null && numOf(checks.values.fails) > 0
  def verdict = !allOk ? 'UNSTABLE - one or more thresholds breached (k6 exit 99)'
              : checksFailed ? 'PASS on thresholds, but some functional checks FAILED - inspect SUMMARY'
              : 'PASS - thresholds met and all checks green'
  lines << ''
  lines << "VERDICT: ${verdict}"
  lines << '====================================='

  echo lines.join('\n')
}

// ---- formatting helpers (null-tolerant) ------------------------------------
// numOf returns a primitive double on purpose: when a rate is exactly 0 or 1
// (e.g. http_req_failed rate=1 when 100% of requests fail), k6's JSON encodes it
// as an integer (`1`), and String.format('%.2f', <Integer>) throws
// IllegalFormatConversionException — which crashed printK6Summary() and turned an
// UNSTABLE threshold breach into a hard build FAILURE that hid the real cause.
def numOf(v) { (v ?: 0) as double }
def pct(Number rate) { "${String.format('%.2f', (rate as double) * 100)}%" }
def ms(v) { "${String.format('%.0f', numOf(v))}" }
def fmtBytes(Number n) {
  double d = (n ?: 0) as double
  if (d >= 1024 * 1024) return "${String.format('%.1f', d / (1024 * 1024))} MB"
  if (d >= 1024) return "${String.format('%.1f', d / 1024)} KB"
  return "${d as int} B"
}
def connDetail(Map metrics) {
  def parts = []
  def conn = metrics.http_req_connecting
  def tls = metrics.http_req_tls_handshaking
  if (conn?.values != null) parts << "connect avg=${ms(conn.values.avg)}"
  if (tls?.values != null && numOf(tls.values.avg) > 0) parts << "tls avg=${ms(tls.values.avg)}"
  return parts ? "  (${parts.join(', ')})" : ''
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
