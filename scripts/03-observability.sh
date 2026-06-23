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

# In oss mode the in-cluster stack (kube-prometheus-stack/Loki/Tempo) is managed
# by the ArgoCD app-of-apps argocd/observability-oss; deleting the parent
# Application cascade-prunes those charts via their resources finalizer. Called
# from every NON-oss branch so a mode switch away from oss retires the stack.
# Safe no-op when ArgoCD/the app is absent.
remove_oss_observability_app() {
  if kubectl get application observability-oss -n argocd >/dev/null 2>&1; then
    log_info "Removing observability-oss ArgoCD app (cascade-prunes the in-cluster OSS stack)"
    kubectl delete application observability-oss -n argocd --ignore-not-found --wait=false
  fi
}

case "${J2026_OBS_MODE}" in
  grafana-cloud)
    log_step "Observability mode: grafana-cloud"

    # Clean in-place switch from oss: retire the in-cluster backends so they
    # don't keep running (and holding PVCs / node-exporter hostPorts) once
    # telemetry is exporting to Grafana Cloud again. The shared
    # otel-collector-{gateway,logs} releases are reconfigured by helm upgrade
    # below, so they must NOT be uninstalled here.
    remove_oss_observability_app
    # Also clean up any legacy helm-managed releases (pre-ArgoCD oss deploys).
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
    kubectl delete deployment "${J2026_OTEL_GATEWAY_RELEASE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found

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
    log_step "Observability mode: oss (in-cluster stack via ArgoCD)"

    # Clean in-place switch from grafana-cloud/managed-*: retire the cloud-only
    # agents before the kube-prometheus-stack node-exporter (hostPort 9100) comes
    # up via ArgoCD. k8s-monitoring/Alloy and managed-* node-exporter also bind
    # hostPort 9100, so they must go first.
    helm_uninstall_if_present pdc-agent "${J2026_OBS_NAMESPACE}"
    helm_uninstall_if_present k8s-monitoring "${J2026_OBS_NAMESPACE}"
    helm_uninstall_if_present kube-state-metrics "${J2026_OBS_NAMESPACE}"
    helm_uninstall_if_present prometheus-node-exporter "${J2026_OBS_NAMESPACE}"

    kubectl_apply_namespace "${J2026_GRAFANA_OSS_NAMESPACE}"

    # Companion inputs consumed by the ArgoCD-managed Grafana (see
    # observability/grafana/values-oss.yaml). Kept script-managed (NOT in the
    # ArgoCD app) so ArgoCD never owns/prunes these per-cluster values; the
    # chart references them via the sidecar / envValueFrom (optional=true, so a
    # missing object just falls back).
    log_step "Creating jenkins-2026-grafana-dashboards ConfigMap in ${J2026_GRAFANA_OSS_NAMESPACE}"
    kubectl create configmap jenkins-2026-grafana-dashboards \
      -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
      --from-file="${J2026_ROOT_DIR}/observability/grafana/dashboards" \
      --dry-run=client -o yaml | kubectl apply -f -

    # The Grafana->Jenkins datasource only makes sense when Jenkins is the CI engine
    # (and the jenkins-credentials Secret exists). Skip it in tekton mode.
    if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
      log_step "Mirroring Jenkins admin password into grafana-jenkins-ds Secret (Jenkins datasource token)"
      JENKINS_ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.admin-password}' | base64 -d)"
      kubectl create secret generic grafana-jenkins-ds \
        -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
        --from-literal=apiToken="${JENKINS_ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    fi

    # Public root_url only when the gateway is enabled; otherwise leave the
    # ConfigMap absent so Grafana falls back to the in-cluster default
    # (values-oss.yaml grafana.ini), matching the previous --set behaviour.
    if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
      log_step "Setting Grafana public root_url -> https://${J2026_GATEWAY_GRAFANA_HOST}"
      kubectl create configmap grafana-runtime-config \
        -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
        --from-literal=root_url="https://${J2026_GATEWAY_GRAFANA_HOST}" \
        --dry-run=client -o yaml | kubectl apply -f -
    else
      kubectl delete configmap grafana-runtime-config -n "${J2026_GRAFANA_OSS_NAMESPACE}" --ignore-not-found
    fi

    # Deploy the in-cluster stack (kube-prometheus-stack/Loki/Tempo) via the
    # ArgoCD app-of-apps. ArgoCD is already installed: scripts/08.5-argocd.sh
    # runs before this script in scripts/up.sh. The parent Application renders
    # argocd/observability-oss/ into the three child Applications, each a
    # multi-source app (upstream chart + this repo's values-oss*.yaml).
    log_step "Applying observability-oss ArgoCD app-of-apps"
    OSS_APP_FILE="$(mktemp)"
    REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
    sed "s@{{repoUrl}}@${REPO_URL}@g;
         s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
        "${J2026_ROOT_DIR}/argocd/observability-oss-app.yaml" > "${OSS_APP_FILE}"
    kubectl apply -f "${OSS_APP_FILE}"
    rm "${OSS_APP_FILE}"

    # The OTel collectors stay script-managed (shared across all four obs modes).
    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Tempo/Prometheus/Loki)"
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete deployment "${J2026_OTEL_GATEWAY_RELEASE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-oss.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Loki)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-oss-logs.yaml"

    # ArgoCD provisions Grafana asynchronously — wait for the Deployment to be
    # created by the sync, then for it to be Ready, before downstream steps
    # (07-grafana-dashboards no-op, 07.5-grafana-alerts) talk to Grafana.
    log_step "Waiting for ArgoCD to provision the OSS observability stack (Grafana)"
    if timeout 300 bash -c "
      until kubectl get deployment kube-prometheus-stack-grafana -n '${J2026_GRAFANA_OSS_NAMESPACE}' >/dev/null 2>&1; do
        sleep 5
      done
    "; then
      wait_for_deployment "kube-prometheus-stack-grafana" "${J2026_GRAFANA_OSS_NAMESPACE}"
    else
      log_warn "kube-prometheus-stack-grafana did not appear within 5m — check 'kubectl -n argocd get applications' (observability-oss / oss-kube-prometheus-stack)."
    fi
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
    remove_oss_observability_app
    # Also clean up any legacy helm-managed releases (pre-ArgoCD oss deploys).
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
    kubectl delete deployment "${J2026_OTEL_GATEWAY_RELEASE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
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
    log_step "Observability mode: managed-aws"

    # Clean in-place switch: AWS backends live outside the cluster, so retire any
    # in-cluster oss backends / cloud agents from a previous mode. The shared
    # otel-collector-{gateway,logs} releases are reconfigured by helm upgrade.
    for r in pdc-agent k8s-monitoring; do
      helm status "$r" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1 && helm uninstall "$r" -n "${J2026_OBS_NAMESPACE}"
    done
    remove_oss_observability_app
    # Also clean up any legacy helm-managed releases (pre-ArgoCD oss deploys).
    helm status kube-prometheus-stack -n "${J2026_GRAFANA_OSS_NAMESPACE}" >/dev/null 2>&1 && \
      helm uninstall kube-prometheus-stack -n "${J2026_GRAFANA_OSS_NAMESPACE}"
    for r in loki tempo; do
      helm status "$r" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1 && helm uninstall "$r" -n "${J2026_OBS_NAMESPACE}"
    done

    if ! kubectl get secret "${J2026_AWS_MANAGED_SECRET}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
      log_error "Secret '${J2026_AWS_MANAGED_SECRET}' not found in namespace '${J2026_OBS_NAMESPACE}'."
      log_error "Copy observability/otel-collector/secret-managed-aws.example.yaml, fill in your"
      log_error "AMP remote-write endpoint / collector IAM role ARN / region / log group, and"
      log_error "'kubectl apply -f' it before re-running. See docs/observability.md."
      exit 1
    fi

    # Kubernetes infra metrics source (scraped by the gateway collector's
    # prometheus receiver -> Amazon Managed Prometheus -> AMG built-in dashboards).
    log_step "Installing kube-state-metrics + node-exporter (Kubernetes infra metrics)"
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update prometheus-community >/dev/null 2>&1 || true
    helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=kube-state-metrics
    helm upgrade --install prometheus-node-exporter prometheus-community/prometheus-node-exporter \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=prometheus-node-exporter

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> AMP / X-Ray / CloudWatch)"
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete deployment "${J2026_OTEL_GATEWAY_RELEASE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-aws.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> CloudWatch Logs)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-aws-logs.yaml"

    wait_for_deployment "otel-collector-gateway" "${J2026_OBS_NAMESPACE}"
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}' (expected grafana-cloud|oss|managed-azure|managed-aws)."
    exit 1
    ;;
esac

log_info "Observability stack ready."
