/**
 * petclinicK6Smoke(namespace: '<ns>', envName: 'stable'|'develop',
 *                   genaiEnabled: true|false, vus: '<n>', iterations: '<n>')
 *
 * Runs jenkins/pipelines/k6/petclinic-smoke.js from the 'k6' container of the
 * pod template defined in jenkins/pipelines/Jenkinsfile.petclinic-k6-smoke -
 * a small amount of synthetic traffic (a few VUs/iterations, NOT a load test)
 * against the PetClinic Services in `namespace`, to give Grafana Cloud fresh
 * traces/metrics/logs to correlate.
 *
 * k6's own request metrics are exported (-o opentelemetry) to the same
 * otel-collector-gateway used by the OTel Java auto-instrumentation
 * (helm/petclinic/templates/instrumentation.yaml) and this Jenkins pipeline's
 * own spans (jenkins/casc/jcasc-otel.yaml), tagged with the same
 * service.namespace=jenkins-2026 and deployment.environment=<envName> resource
 * attributes so everything groups together in Grafana.
 */
def call(Map cfg) {
  container('k6') {
    withEnv([
      "TARGET_NAMESPACE=${cfg.namespace}",
      "GENAI_SERVICE_ENABLED=${cfg.genaiEnabled}",
      "K6_VUS=${cfg.vus}",
      "K6_ITERATIONS=${cfg.iterations}",
      "K6_OTEL_SERVICE_NAME=k6-petclinic-smoke",
      "K6_OTEL_GRPC_EXPORTER_ENDPOINT=otel-collector-gateway.observability.svc.cluster.local:4317",
      "K6_OTEL_GRPC_EXPORTER_INSECURE=true",
      "OTEL_RESOURCE_ATTRIBUTES=service.namespace=jenkins-2026,deployment.environment=${cfg.envName}",
    ]) {
      sh """
        set -eux
        k6 run -o opentelemetry --summary-export=k6-summary.json jenkins/pipelines/k6/petclinic-smoke.js
      """
    }
  }
}
