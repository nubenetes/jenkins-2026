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
#   managed-aws - two opentelemetry-collector releases exporting to AWS (metrics
#     -> Amazon Managed Service for Prometheus via remote-write with SigV4;
#     traces/logs -> X-Ray/CloudWatch). Visualized in Amazon Managed Grafana.
#     Auth via the GKE->AWS OIDC web-identity role (no access keys).
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
    log_info "Removing the observability-oss app-of-apps + its children (cascade-prune is unreliable for an app-of-apps — a child can be left orphaned, as seen on the CI-engine apps; see lib/common.sh retire_ci_engine)"
    # Delete the parent AND every child Application explicitly (not just the parent),
    # so switching observability.mode away from oss can't leave an orphaned oss-* app.
    for app in observability-oss oss-kube-prometheus-stack oss-loki oss-tempo oss-grafana-dashboards; do
      kubectl delete application "$app" -n argocd --ignore-not-found --wait=false 2>/dev/null || true
    done
  fi
  # The cascade-prune above is asynchronous. The OSS kube-prometheus-stack ships a
  # node-exporter DaemonSet on hostPort 9100 (hostNetwork); k8s-monitoring (grafana
  # -cloud) and the managed-* infra agents run their OWN node-exporter on the same
  # port and FAIL a pre-install validation if the OSS one is still present
  # ("A Node Exporter already appears to be running ... host port conflict"). So on
  # an in-place mode switch we must wait for it to disappear before the caller
  # installs its exporter. Selected by the chart's stable label (robust to the
  # release-name prefix, e.g. oss-kube-prometheus-stack-prometheus-node-exporter).
  local sel="app.kubernetes.io/name=prometheus-node-exporter"
  if [ -n "$(kubectl get ds -n "${J2026_OBS_NAMESPACE}" -l "${sel}" -o name 2>/dev/null)" ]; then
    log_info "Waiting for the OSS node-exporter DaemonSet (hostPort 9100) to be pruned"
    local i=0
    until [ -z "$(kubectl get ds -n "${J2026_OBS_NAMESPACE}" -l "${sel}" -o name 2>/dev/null)" ]; do
      i=$((i + 1)); [ "${i}" -ge 36 ] && break; sleep 5   # up to ~3 min
    done
    # Backstop: if ArgoCD hasn't finished pruning yet (parent app already deleted,
    # so the child won't recreate it), remove the conflicting DaemonSet directly.
    kubectl delete ds -n "${J2026_OBS_NAMESPACE}" -l "${sel}" --ignore-not-found >/dev/null 2>&1 || true
  fi
}

# Renders an otel-collector "-logs" values file into a temp copy with the configurable
# minimum-log-severity `filter` processor injected, and echoes the path (use with
# `helm -f`). The filelog operators (static, in the values files) parse the level token
# and set the record severity, so this filter is a clean numeric `severity_number`
# comparison — it drops records below J2026_LOG_MIN_SEVERITY while the
# `!= SEVERITY_NUMBER_UNSPECIFIED` guard keeps anything whose level couldn't be parsed
# (no accidental blackout). 'trace' = no filtering: the original file is returned
# unchanged. All log output goes to stderr so stdout stays a clean path for $(...).
otel_logs_values_with_filter() {
  local src="$1"
  if [[ "${J2026_LOG_MIN_SEVERITY}" == "trace" ]]; then
    printf '%s' "${src}"
    return 0
  fi
  local enum
  case "${J2026_LOG_MIN_SEVERITY}" in
    debug) enum="SEVERITY_NUMBER_DEBUG" ;;
    info)  enum="SEVERITY_NUMBER_INFO" ;;
    warn)  enum="SEVERITY_NUMBER_WARN" ;;
    error) enum="SEVERITY_NUMBER_ERROR" ;;
  esac
  local cond="severity_number != SEVERITY_NUMBER_UNSPECIFIED and severity_number < ${enum}"
  local dst
  dst="$(mktemp --suffix=-otel-logs.yaml)"
  COND="${cond}" yq eval '
    .config.processors["filter/severity"].error_mode = "ignore" |
    .config.processors["filter/severity"].logs.log_record = [strenv(COND)] |
    .config.service.pipelines.logs.processors += ["filter/severity"]
  ' "${src}" > "${dst}"
  log_info "otel-collector-logs: dropping log severities < ${J2026_LOG_MIN_SEVERITY}" >&2
  printf '%s' "${dst}"
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
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-grafana-cloud.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Grafana Cloud)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "$(otel_logs_values_with_filter "${J2026_ROOT_DIR}/observability/otel-collector/values-grafana-cloud-logs.yaml")"

    log_step "Installing pdc-agent (Private Data Source Connect)"
    GRAFANA_PDC_TOKEN="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_PDC_TOKEN}' | base64 -d)"
    GRAFANA_PDC_CLUSTER="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_PDC_CLUSTER}' | base64 -d)"
    GRAFANA_STACK_ID="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_STACK_ID}' | base64 -d)"

    if [[ -n "${GRAFANA_PDC_TOKEN}" ]]; then
      helm upgrade --install pdc-agent grafana/pdc-agent \
        --version=0.2.0 \
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

    # Lean metrics (observability.leanMetrics / JENKINS2026_OBS_LEAN_METRICS): trim the
    # high-cardinality CLUSTER INFRA metrics to stay under the Grafana Cloud free-tier 15k
    # active-series cap (e.g. while validating the develop tier). App/CNPG/Tekton metrics go
    # via the otel-collector and are untouched. clusterEvents stays on — it ships to Loki
    # (logs), ~0 metric series, and keeps the Alloy collector with at least one active feature.
    #
    # LEAN ≠ "all cluster metrics off". We keep a deliberately TINY node-inventory slice so the
    # "CI-CD / Node Auto-Provisioning (Spot)" dashboard works even on the free tier: only
    # kube-state-metrics, and within it only `kube_node_info`, `kube_node_spec_taint` and
    # `kube_node_status_condition` (≈ a handful of series per node — ~30-50 total here, vs the
    # 15k cap). Everything expensive — cadvisor (per-container), kubelet, node-exporter (host)
    # — stays OFF. The dashboard derives Spot/ComputeClass membership from the node TAINTS
    # (`kube_node_spec_taint{key="cloud.google.com/gke-spot"|".../compute-class"}`), which KSM
    # exposes by DEFAULT — not from node LABELS (`kube_node_labels`), whose `label_*` dimensions
    # would need a KSM `--metric-labels-allowlist` we deliberately don't set. KSM is still
    # DEPLOYED in lean mode (it produces those node metrics); node-exporter is not. See
    # docs/301 (§ leanMetrics) and docs/runbooks/nap-spot-provisioning.md.
    if [[ "${J2026_OBS_LEAN_METRICS}" == "true" ]]; then
      km_host_metrics=false
      km_deploy_ksm=true
      km_deploy_node_exporter=false
      km_cluster_metrics_block=$(cat <<'KMEOF'
clusterMetrics:
  enabled: true
  # Drop every high-cardinality source; keep only the node-inventory slice (kube-state-metrics
  # restricted to the three kube_node_* metrics below).
  kubelet:
    enabled: false
  kubeletResource:
    enabled: false
  kubeletProbes:
    enabled: false
  cadvisor:
    enabled: false
  apiServer:
    enabled: false
  kubeControllerManager:
    enabled: false
  kubeDNS:
    enabled: false
  kubeProxy:
    enabled: false
  kubeScheduler:
    enabled: false
  kube-state-metrics:
    enabled: true
    metricsTuning:
      # Replace KSM's default allow-list with ONLY the node-inventory metrics the NAP
      # dashboard needs. kube_node_spec_taint carries the gke-spot / compute-class taints;
      # kube_node_labels carries the node labels KSM is configured to expose — notably
      # `label_node_kubernetes_io_instance_type` (the machine type), which is the only
      # cluster-wide source of a node's machine type for STATIC pool nodes (NAP node names
      # embed it, e.g. nap-e2-standard-2-…, but static `jenkins-2026-pool-…` names don't).
      # KSM already exposes node.kubernetes.io/instance-type via the chart's default
      # --metric-labels-allowlist, so no KSM/chart change is needed — we only have to keep
      # the metric through this scrape. Still ~1 series per node → negligible vs the 15k cap.
      useDefaultAllowList: false
      includeMetrics:
        - kube_node_info
        - kube_node_labels
        - kube_node_spec_taint
        - kube_node_status_condition
KMEOF
)
      log_warn "observability.leanMetrics=true → k8s-monitoring trimmed to a NODE-INVENTORY slice only (kube_node_* for the NAP/Spot dashboard); cadvisor/kubelet/node-exporter DISABLED to cut Grafana Cloud active series. App/CNPG/Tekton metrics unaffected; 'K8s Compute' built-in views stay empty."
    else
      km_host_metrics=true
      km_deploy_ksm=true
      km_deploy_node_exporter=true
      km_cluster_metrics_block=$'clusterMetrics:\n  enabled: true'
    fi

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

# Cluster metrics (cluster infra metrics gated by observability.leanMetrics): full set when
# lean is off, a tiny node-inventory slice when lean is on — see the leanMetrics logic above.
${km_cluster_metrics_block}
hostMetrics:
  enabled: ${km_host_metrics}
clusterEvents:
  enabled: true

# Deploy telemetry backing services. kube-state-metrics stays DEPLOYED even in lean mode (it
# produces the node-inventory metrics the NAP/Spot dashboard reads); node-exporter is lean-gated.
telemetryServices:
  kube-state-metrics:
    deploy: ${km_deploy_ksm}
  node-exporter:
    deploy: ${km_deploy_node_exporter}

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
      --version=4.1.6 \
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
    # The jenkins-2026-grafana-dashboards ConfigMap is now GitOps-managed by the
    # oss-grafana-dashboards child app of the observability-oss app-of-apps
    # (rendered from observability/grafana/dashboards/ — a small Helm chart that
    # drops the off-engine CI overview based on ciEngine). It used to be built
    # here with `kubectl create configmap`; ArgoCD owns it now, so it auto-syncs
    # on commit and needs no Day2.publish re-run. The ciEngine value flows to the
    # app-of-apps via the {{ciEngine}} parameter substituted above.

    # The Grafana->Jenkins datasource only makes sense when Jenkins is the CI engine
    # (and the jenkins-credentials Secret exists). Skip it in tekton mode.
    if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
      if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
        # eso → grafana-jenkins-ds is ESO-managed: a property projection of the
        # jenkins-credentials Secret Manager blob's admin-password into key apiToken
        # (08.6), so it follows the same stable password. Skip the imperative mirror.
        log_info "grafana-jenkins-ds is ESO-managed (jenkins-credentials.admin-password → apiToken) — skipping imperative mirror."
      else
        log_step "Mirroring Jenkins admin password into grafana-jenkins-ds Secret (Jenkins datasource token)"
        JENKINS_ADMIN_PASSWORD="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.admin-password}' | base64 -d)"
        kubectl create secret generic grafana-jenkins-ds \
          -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
          --from-literal=apiToken="${JENKINS_ADMIN_PASSWORD}" \
          --dry-run=client -o yaml | kubectl apply -f -
      fi
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
         s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
         s@{{ciEngine}}@${J2026_CI_ENGINE}@g" \
        "${J2026_ROOT_DIR}/argocd/observability-oss-app.yaml" > "${OSS_APP_FILE}"
    kubectl apply -f "${OSS_APP_FILE}"
    rm "${OSS_APP_FILE}"

    # The OTel collectors stay script-managed (shared across all four obs modes).
    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Tempo/Prometheus/Loki)"
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete deployment "${J2026_OTEL_GATEWAY_RELEASE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-oss.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Loki)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "$(otel_logs_values_with_filter "${J2026_ROOT_DIR}/observability/otel-collector/values-oss-logs.yaml")"

    # ArgoCD provisions Grafana asynchronously — wait for the Deployment to be
    # created by the sync, then for it to be Ready, before downstream steps
    # (07-grafana-dashboards no-op, 07.5-grafana-alerts) talk to Grafana.
    log_step "Waiting for ArgoCD to provision the OSS observability stack (Grafana)"
    if timeout 300 bash -c "
      until kubectl get deployment oss-kube-prometheus-stack-grafana -n '${J2026_GRAFANA_OSS_NAMESPACE}' >/dev/null 2>&1; do
        sleep 5
      done
    "; then
      wait_for_deployment "oss-kube-prometheus-stack-grafana" "${J2026_GRAFANA_OSS_NAMESPACE}"
    else
      log_warn "oss-kube-prometheus-stack-grafana did not appear within 5m — check 'kubectl -n argocd get applications' (observability-oss / oss-kube-prometheus-stack)."
    fi
    wait_for_deployment "otel-collector-gateway" "${J2026_OBS_NAMESPACE}"

    # In oss mode the in-cluster Prometheus scrapes CloudNativePG metrics (cnpg_*)
    # via the PodMonitor that the CNPG operator creates per Cluster — but ONLY when
    # the PodMonitor CRD exists at reconcile time. A Cluster created before the CRD
    # (e.g. switching obs mode TO oss on a running cluster that previously ran
    # grafana-cloud/managed-* — which have no in-cluster prometheus-operator, hence
    # no PodMonitor CRD) is left without a PodMonitor and the operator won't retry
    # until it reconciles, so that tier's Postgres silently never appears in Grafana.
    # kube-prometheus-stack (synced above) provides the CRD now, so nudge the CNPG
    # operator to reconcile and create any missing PodMonitors. No-op on fresh
    # deploys (CRD precedes Cluster creation → PodMonitor already there). Idempotent:
    # only restarts when a CNPG-Cluster namespace is actually missing its PodMonitor.
    if kubectl get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1; then
      cnpg_dep_ns="$(kubectl get deploy -A -l app.kubernetes.io/name=cloudnative-pg \
        -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
      cnpg_dep_name="$(kubectl get deploy -A -l app.kubernetes.io/name=cloudnative-pg \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      if [[ -n "${cnpg_dep_name}" ]]; then
        missing_pm=0
        for cl_ns in $(kubectl get cluster.postgresql.cnpg.io -A \
          -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u); do
          if [[ "$(kubectl get podmonitor -n "${cl_ns}" --no-headers 2>/dev/null | wc -l)" -eq 0 ]]; then
            missing_pm=1
          fi
        done
        if [[ "${missing_pm}" -eq 1 ]]; then
          log_step "Nudging CNPG operator to create missing PodMonitors (oss Prometheus scrape)"
          kubectl rollout restart "deploy/${cnpg_dep_name}" -n "${cnpg_dep_ns}" || true
          kubectl rollout status "deploy/${cnpg_dep_name}" -n "${cnpg_dep_ns}" --timeout=120s || true
        fi
      fi
    fi
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
    # Expose the node instance-type label on kube_node_labels (KSM drops node labels by
    # default) so the NAP/Spot dashboard can show each node's MACHINE TYPE — including the
    # static-pool nodes, whose names (unlike NAP's nap-<type>-…) don't embed it. These are the
    # same node labels the grafana-cloud KSM exposes via the k8s-monitoring chart default. The
    # escaped comma (\,) keeps the two-label list as ONE --set value instead of two.
    helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=kube-state-metrics \
      --set 'metricLabelsAllowlist[0]=nodes=[node.kubernetes.io/instance-type\,beta.kubernetes.io/instance-type]'
    helm upgrade --install prometheus-node-exporter prometheus-community/prometheus-node-exporter \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=prometheus-node-exporter

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> Azure Monitor)"
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete deployment "${J2026_OTEL_GATEWAY_RELEASE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-azure.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> Azure Monitor)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "$(otel_logs_values_with_filter "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-azure-logs.yaml")"

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
    # Expose the node instance-type label on kube_node_labels (KSM drops node labels by
    # default) so the NAP/Spot dashboard can show each node's MACHINE TYPE — including the
    # static-pool nodes, whose names (unlike NAP's nap-<type>-…) don't embed it. These are the
    # same node labels the grafana-cloud KSM exposes via the k8s-monitoring chart default. The
    # escaped comma (\,) keeps the two-label list as ONE --set value instead of two.
    helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=kube-state-metrics \
      --set 'metricLabelsAllowlist[0]=nodes=[node.kubernetes.io/instance-type\,beta.kubernetes.io/instance-type]'
    helm upgrade --install prometheus-node-exporter prometheus-community/prometheus-node-exporter \
      --namespace "${J2026_OBS_NAMESPACE}" \
      --set fullnameOverride=prometheus-node-exporter

    log_step "Installing ${J2026_OTEL_GATEWAY_RELEASE} (OTLP gateway -> AMP / X-Ray / CloudWatch)"
    kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete deployment "${J2026_OTEL_GATEWAY_RELEASE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    helm upgrade --install "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-aws.yaml"

    log_step "Installing ${J2026_OTEL_LOGS_RELEASE} (node log DaemonSet -> CloudWatch Logs)"
    helm upgrade --install "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OTEL_COLLECTOR_CHART}" \
      ${J2026_OTEL_COLLECTOR_CHART_VERSION:+--version=${J2026_OTEL_COLLECTOR_CHART_VERSION}} \
      --namespace "${J2026_OBS_NAMESPACE}" \
      -f "$(otel_logs_values_with_filter "${J2026_ROOT_DIR}/observability/otel-collector/values-managed-aws-logs.yaml")"

    wait_for_deployment "otel-collector-gateway" "${J2026_OBS_NAMESPACE}"
    ;;

  *)
    log_error "Unknown observability.mode '${J2026_OBS_MODE}' (expected grafana-cloud|oss|managed-azure|managed-aws)."
    exit 1
    ;;
esac

log_info "Observability stack ready."
