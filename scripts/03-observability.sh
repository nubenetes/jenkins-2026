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
#   managed-azure - two opentelemetry-collector releases exporting to Azure
#     Monitor (traces/logs -> Application Insights via the azuremonitor
#     exporter; metrics -> Azure Monitor managed Prometheus via remote-write +
#     Entra auth). Visualized in Azure Managed Grafana. Requires the
#     "${J2026_AZURE_MONITOR_SECRET}" Secret - see
#     observability/otel-collector/secret-managed-azure.example.yaml.
#
#   managed-aws - documented stub; no resources created (planned).
#
# Requires scripts/02-otel-operator.sh to have run first (CRDs).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

case "${J2026_OBS_MODE}" in
  grafana-cloud)
    log_step "Observability mode: grafana-cloud"

    # Clean in-place switch from oss: retire the in-cluster backends so they
    # don't keep running (and holding PVCs / node-exporter hostPorts) once
    # telemetry is exporting to Grafana Cloud again. The shared
    # otel-collector-{gateway,logs} releases are reconfigured by helm upgrade
    # below, so they must NOT be uninstalled here.
    helm_uninstall_if_present kube-prometheus-stack "${J2026_GRAFANA_OSS_NAMESPACE}"
    helm_uninstall_if_present loki "${J2026_OBS_NAMESPACE}"
    helm_uninstall_if_present tempo "${J2026_OBS_NAMESPACE}"
    # managed-azure's in-cluster infra-metrics agents.
    helm_uninstall_if_present kube-state-metrics "${J2026_OBS_NAMESPACE}"
    helm_uninstall_if_present prometheus-node-exporter "${J2026_OBS_NAMESPACE}"

    if ! kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_error "Secret '${J2026_GRAFANA_CLOUD_SECRET}' not found in namespace '${J2026_OBS_NAMESPACE}'."
      log_error "Copy observability/otel-collector/secret.example.yaml, fill in your Grafana Cloud"
      log_error "OTLP endpoint + Basic-auth header, and 'kubectl apply -f' it before re-running."
      exit 1
    fi

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Grafana Cloud)"
    # Resolve field manager conflicts (SSA) by removing the ConfigMap if it was previously
    # managed by kubectl instead of Helm.
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found

    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-grafana-cloud.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Grafana Cloud)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-grafana-cloud-logs.yaml"

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
        --set resources.requests.cpu=50m \
        --set resources.requests.memory=64Mi \
        --set resources.limits.cpu=200m \
        --set resources.limits.memory=128Mi
    else
      log_warn "GRAFANA_PDC_TOKEN not set - skipping pdc-agent installation."
    fi

    log_step "Installing k8s-monitoring (Kubernetes metrics + events -> Grafana Cloud)"
    OTLP_ENDPOINT="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_CLOUD_OTLP_ENDPOINT}' | base64 -d)"
    OTLP_AUTH_DECODED="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_CLOUD_OTLP_AUTH}' | base64 -d | base64 -d)"

    OTLP_USERNAME="${OTLP_AUTH_DECODED%%:*}"
    OTLP_PASSWORD="${OTLP_AUTH_DECODED#*:}"

    GENERATED_OBS_DIR="${J2026_ROOT_DIR}/.generated/observability"
    mkdir -p "${GENERATED_OBS_DIR}"

    cat >"${GENERATED_OBS_DIR}/k8s-monitoring-values.yaml" <<EOT
# Generated by scripts/03-observability.sh - do not edit by hand
cluster:
  name: "${J2026_CLUSTER_NAME:-jenkins-2026}"

destinations:
  grafanaCloudOtlp:
    type: otlp
    url: "${OTLP_ENDPOINT}"
    protocol: http
    auth:
      type: basic
      username: "${OTLP_USERNAME}"
      password: "${OTLP_PASSWORD}"

# Disable pod log collection since our otel-collector-logs DaemonSet handles it
podLogsViaLoki:
  enabled: false
podLogsViaOpenTelemetry:
  enabled: false

# Enable node/pod/container metrics and events
clusterMetrics:
  enabled: true
hostMetrics:
  enabled: true
clusterEvents:
  enabled: true

# Deploy telemetry backing services
telemetryServices:
  kube-state-metrics:
    deploy: true
  node-exporter:
    deploy: true

# Define the Alloy collector instance
collectors:
  alloy:
    enabled: true
    presets:
      - clustered
      - statefulset
EOT

    helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true

    helm upgrade --install k8s-monitoring grafana/k8s-monitoring \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${GENERATED_OBS_DIR}/k8s-monitoring-values.yaml"

    wait_for_deployment "otel-collector-gateway" "${J2026_OBS_NAMESPACE}"
    ;;

  oss)
    log_step "Observability mode: oss"

    # Clean in-place switch from grafana-cloud: retire the cloud-only agents
    # before installing kube-prometheus-stack. k8s-monitoring/Alloy ships its
    # own node-exporter DaemonSet on hostPort 9100, which would clash with the
    # one kube-prometheus-stack deploys - and both keep exporting to Grafana
    # Cloud otherwise. Must run before the kube-prometheus-stack install below.
    helm_uninstall_if_present pdc-agent "${J2026_OBS_NAMESPACE}"
    helm_uninstall_if_present k8s-monitoring "${J2026_OBS_NAMESPACE}"
    # managed-azure's node-exporter binds hostPort 9100 - the same as the one
    # kube-prometheus-stack installs below, so it must go first.
    helm_uninstall_if_present kube-state-metrics "${J2026_OBS_NAMESPACE}"
    helm_uninstall_if_present prometheus-node-exporter "${J2026_OBS_NAMESPACE}"

    log_step "Creating jenkins-2026-grafana-dashboards ConfigMap in ${J2026_GRAFANA_OSS_NAMESPACE}"
    kubectl_apply_namespace "${J2026_GRAFANA_OSS_NAMESPACE}"
    kubectl create configmap jenkins-2026-grafana-dashboards \
      -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
      --from-file="${J2026_ROOT_DIR}/observability/grafana/dashboards" \
      --dry-run=client -o yaml | kubectl apply -f -

    log_step "Installing kube-prometheus-stack (Prometheus + Grafana)"
    JENKINS_ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.admin-password}' | base64 -d)"

    # When the public gateway is enabled, Grafana must know its public URL so
    # redirects/links resolve to https://grafana.<baseDomain> instead of the
    # in-cluster default (see observability/grafana/values-oss.yaml grafana.ini
    # and scripts/09-gateway.sh, which creates the HTTPRoute + IAP policy).
    GRAFANA_SET_ARGS=()
    if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
      GRAFANA_SET_ARGS+=(--set "grafana.grafana\.ini.server.root_url=https://${J2026_GATEWAY_GRAFANA_HOST}")
    fi

    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      --namespace "${J2026_GRAFANA_OSS_NAMESPACE}" \
      --create-namespace \
      -f "${J2026_ROOT_DIR}/observability/grafana/values-oss.yaml" \
      --set "grafana.additionalDataSources[3].secureJsonData.apiToken=${JENKINS_ADMIN_PASSWORD}" \
      "${GRAFANA_SET_ARGS[@]}"

    log_step "Installing Loki"
    helm upgrade --install loki "${J2026_GRAFANA_CHART_REPO_NAME}/loki" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/grafana/values-oss-loki.yaml"

    log_step "Installing Tempo"
    helm upgrade --install tempo "${J2026_GRAFANA_CHART_REPO_NAME}/tempo" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/grafana/values-oss-tempo.yaml"

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Tempo/Prometheus/Loki)"
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-oss.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Loki)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-oss-logs.yaml"

    wait_for_deployment "kube-prometheus-stack-grafana" "${J2026_GRAFANA_OSS_NAMESPACE}"
    wait_for_deployment "otel-collector-gateway" "${J2026_OBS_NAMESPACE}"
    ;;

  managed-azure)
    log_step "Observability mode: managed-azure"

    # Clean in-place switch: Azure Managed Grafana + Azure Monitor live outside
    # the cluster, so retire any in-cluster backends / cloud agents left over
    # from a previous oss or grafana-cloud deploy. The shared
    # otel-collector-{gateway,logs} releases are reconfigured by helm upgrade.
    for r in pdc-agent k8s-monitoring; do
      helm status "$r" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1 && helm uninstall "$r" -n "${J2026_OBS_NAMESPACE}"
    done
    helm status kube-prometheus-stack -n "${J2026_GRAFANA_OSS_NAMESPACE}" >/dev/null 2>&1 && \
      helm uninstall kube-prometheus-stack -n "${J2026_GRAFANA_OSS_NAMESPACE}"
    for r in loki tempo; do
      helm status "$r" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1 && helm uninstall "$r" -n "${J2026_OBS_NAMESPACE}"
    done

    if ! kubectl get secret "${J2026_AZURE_MONITOR_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_error "Secret '${J2026_AZURE_MONITOR_SECRET}' not found in namespace '${J2026_OBS_NAMESPACE}'."
      log_error "Copy observability/otel-collector/secret-managed-azure.example.yaml, fill in your"
      log_error "Azure Monitor connection string / managed-Prometheus endpoint / Entra service"
      log_error "principal, and 'kubectl apply -f' it before re-running. See docs/observability.md."
      exit 1
    fi

    # Kubernetes infra metrics source (scraped by the gateway collector's
    # prometheus receiver -> Azure Monitor managed Prometheus). Parity with
    # grafana-cloud's k8s-monitoring/Alloy. fullnameOverride pins predictable
    # Service names that values-managed-azure.yaml's scrape_configs target.
    log_step "Installing kube-state-metrics + node-exporter (Kubernetes infra metrics)"
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update prometheus-community >/dev/null 2>&1 || true
    helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=kube-state-metrics
    helm upgrade --install prometheus-node-exporter prometheus-community/prometheus-node-exporter \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=prometheus-node-exporter

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Azure Monitor)"
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-azure.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Azure Monitor)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-azure-logs.yaml"

    wait_for_deployment "otel-collector-gateway" "${J2026_OBS_NAMESPACE}"
    ;;

  managed-aws)
    log_step "Observability mode: managed-aws (stub)"
    log_warn "observability.mode=managed-aws is not implemented yet - planned: export to"
    log_warn "Amazon Managed Service for Prometheus (remote-write) + X-Ray/CloudWatch, with"
    log_warn "Amazon Managed Grafana as the frontend. Use grafana-cloud, oss, or managed-azure"
    log_warn "for now. See docs/observability.md \"managed-aws\"."
    exit 0
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}' (expected grafana-cloud|oss|managed-azure|managed-aws)."
    exit 1
    ;;
esac

log_info "Observability stack ready."
