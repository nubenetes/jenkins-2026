#!/usr/bin/env bash
# Installs the OTel Collector pipeline (and, in OSS mode, the Grafana/Loki/
# Tempo/Prometheus stack) according to observability.mode in config.yaml:
#
#   grafana-cloud (default) - two opentelemetry-collector releases (gateway +
#     logs DaemonSet) export traces/metrics/logs to Grafana Cloud's OTLP
#     gateway. Requires the "${J2026_GRAFANA_CLOUD_SECRET}" Secret - see
#     observability/otel-collector/secret.example.yaml.
#
#   oss - installs kube-prometheus-stack + Loki + Tempo in-cluster, then two
#     opentelemetry-collector releases pointed at them.
#
#   managed - documented stub (docs/platforms.md); no resources created.
#
# Requires scripts/02-otel-operator.sh to have run first (CRDs).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

case "${J2026_OBS_MODE}" in
  grafana-cloud)
    log_step "Observability mode: grafana-cloud"

    if ! kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_error "Secret '${J2026_GRAFANA_CLOUD_SECRET}' not found in namespace '${J2026_OBS_NAMESPACE}'."
      log_error "Copy observability/otel-collector/secret.example.yaml, fill in your Grafana Cloud"
      log_error "OTLP endpoint + Basic-auth header, and 'kubectl apply -f' it before re-running."
      exit 1
    fi

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Grafana Cloud)"
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-grafana-cloud.yaml" \
      --wait --timeout 5m --debug

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Grafana Cloud)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-grafana-cloud-logs.yaml" \
      --wait --timeout 5m --debug

    log_step "Installing pdc-agent (Private Data Source Connect)"
    GRAFANA_PDC_TOKEN="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_PDC_TOKEN}' | base64 -d)"
    GRAFANA_PDC_CLUSTER="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_PDC_CLUSTER}' | base64 -d)"
    GRAFANA_STACK_ID="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_STACK_ID}' | base64 -d)"

    if [[ -n "${GRAFANA_PDC_TOKEN}" ]]; then
      helm upgrade --install pdc-agent grafana/pdc-agent \
        --namespace "${J2026_OBS_NAMESPACE}" \
        --set cluster="${GRAFANA_PDC_CLUSTER}" \
        --set hostedGrafanaId="${GRAFANA_STACK_ID}" \
        --set insecureTokenValue="${GRAFANA_PDC_TOKEN}" \
        --wait --timeout 5m
    else
      log_warn "GRAFANA_PDC_TOKEN not set - skipping pdc-agent installation."
    fi
    ;;

  oss)
    log_step "Observability mode: oss"

    log_step "Creating jenkins-2026-grafana-dashboards ConfigMap in ${J2026_GRAFANA_OSS_NAMESPACE}"
    kubectl_apply_namespace "${J2026_GRAFANA_OSS_NAMESPACE}"
    kubectl create configmap jenkins-2026-grafana-dashboards \
      -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
      --from-file="${J2026_ROOT_DIR}/observability/grafana/dashboards" \
      --dry-run=client -o yaml | kubectl apply -f -

    log_step "Installing kube-prometheus-stack (Prometheus + Grafana)"
    JENKINS_ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.admin-password}' | base64 -d)"
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      --namespace "${J2026_GRAFANA_OSS_NAMESPACE}" \
      --create-namespace \
      -f "${J2026_ROOT_DIR}/observability/grafana/values-oss.yaml" \
      --set "grafana.additionalDataSources[3].secureJsonData.apiToken=${JENKINS_ADMIN_PASSWORD}" \
      --wait --timeout 15m --debug

    log_step "Installing Loki"
    helm upgrade --install loki "${J2026_GRAFANA_CHART_REPO_NAME}/loki" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/grafana/values-oss-loki.yaml" \
      --wait --timeout 5m --debug

    log_step "Installing Tempo"
    helm upgrade --install tempo "${J2026_GRAFANA_CHART_REPO_NAME}/tempo" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/grafana/values-oss-tempo.yaml" \
      --wait --timeout 5m --debug

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Tempo/Prometheus/Loki)"
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-oss.yaml" \
      --wait --timeout 5m --debug

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Loki)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-oss-logs.yaml" \
      --wait --timeout 5m --debug
    ;;

  managed)
    log_step "Observability mode: managed (stub)"
    log_warn "observability.mode=managed is documented in docs/platforms.md but does not"
    log_warn "install anything - point OTEL_EXPORTER_OTLP_ENDPOINT at your managed Grafana"
    log_warn "stack's OTLP gateway and create '${J2026_GRAFANA_CLOUD_SECRET}' accordingly."
    exit 0
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}' (expected grafana-cloud|oss|managed)."
    exit 1
    ;;
esac

log_info "Observability stack ready."
