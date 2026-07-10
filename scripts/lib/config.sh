#!/usr/bin/env bash
# Loads config/config.yaml via `yq` and exports it as J2026_* environment
# variables consumed by every numbered step script. Sourced (not executed)
# after lib/common.sh:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
#
# FEATURE FLAG: JENKINS2026_PLATFORM, if set, overrides platform.target from
# config.yaml (gke). config/config.yaml is the durable
# default; the env var is the ephemeral override.

require_cmd yq "Install yq (https://github.com/mikefarah/yq) - e.g. 'sudo snap install yq' or download the static binary from the GitHub releases page." || exit 1

J2026_CONFIG_FILE="${J2026_CONFIG_FILE:-${J2026_ROOT_DIR}/config/config.yaml}"
export J2026_CONFIG_FILE

if [[ ! -f "${J2026_CONFIG_FILE}" ]]; then
  log_error "Config file not found: ${J2026_CONFIG_FILE}"
  exit 1
fi

# yq_get <yaml-path> [default]
yq_get() {
  local expr="$1" default="${2:-}" val
  val="$(yq eval "${expr}" "${J2026_CONFIG_FILE}")"
  if [[ "${val}" == "null" || -z "${val}" ]]; then
    printf '%s' "${default}"
  else
    printf '%s' "${val}"
  fi
}

# yq_get_list <yaml-path> - prints one element per line.
yq_get_list() {
  local expr="$1"
  yq eval "${expr}" "${J2026_CONFIG_FILE}"
}

# --- platform (feature flag) -------------------------------------------------

J2026_PLATFORM="${JENKINS2026_PLATFORM:-$(yq_get '.platform.target' 'gke')}"
export J2026_PLATFORM

# Log verbosity (info|debug). common.sh seeds it from JENKINS2026_LOG_LEVEL; here we add
# the config.yaml durable default (logging.level) and validate. Env override wins. See
# log_debug() in common.sh — there is no 'trace'/set -x level by design (secret leakage).
J2026_LOG_LEVEL="${JENKINS2026_LOG_LEVEL:-$(yq_get '.logging.level' 'info')}"
case "${J2026_LOG_LEVEL}" in
  info|debug) ;;
  *) log_warn "Unknown logging.level '${J2026_LOG_LEVEL}' (expected info|debug) — using 'info'."; J2026_LOG_LEVEL=info ;;
esac
export J2026_LOG_LEVEL

if [[ "${J2026_PLATFORM}" != "gke" ]]; then
  log_error "Unsupported platform '${J2026_PLATFORM}' (expected gke)."
  exit 1
fi

export J2026_STORAGE_CLASS="$(yq_get ".platform.gke.storageClassName" '')"
export J2026_INGRESS_CLASS="$(yq_get ".platform.gke.ingressClassName" '')"
export J2026_SERVICE_TYPE="$(yq_get ".platform.gke.serviceType" 'ClusterIP')"
export J2026_USE_ROUTE="false"

# --- node auto-provisioning / ComputeClass (feature flag) --------------------
# GKE NAP — the GA, Google-native equivalent of Karpenter. When enabled, 01-namespaces.sh
# applies the Custom ComputeClass (infrastructure/compute-classes/) and the CI agents
# target it (Spot, scale-to-zero) via the GKE_COMPUTE_CLASS env surfaced through JCasC.
# FEATURE FLAG: JENKINS2026_NODE_AUTOPROVISIONING_ENABLED overrides nodeAutoProvisioning.enabled.
J2026_NODE_AUTOPROVISIONING_ENABLED="${JENKINS2026_NODE_AUTOPROVISIONING_ENABLED:-$(yq_get '.nodeAutoProvisioning.enabled' 'true')}"
export J2026_NODE_AUTOPROVISIONING_ENABLED
case "${J2026_NODE_AUTOPROVISIONING_ENABLED}" in
  true|false) ;;
  *)
    log_error "Invalid nodeAutoProvisioning.enabled '${J2026_NODE_AUTOPROVISIONING_ENABLED}' (expected true|false)."
    exit 1
    ;;
esac
export J2026_NODE_AUTOPROVISIONING_COMPUTE_CLASS="$(yq_get '.nodeAutoProvisioning.computeClass' 'ci-spot')"

# Single source of truth: the SAME flag drives the cluster-level Terraform toggle
# (terraform/gke `enable_node_autoprovisioning`), so cluster NAP, the in-cluster
# ComputeClass, and the agents' targeting can never desync. Anything that sources this
# lib before `terraform apply` (e.g. up.sh) picks it up automatically; test/e2e.sh and
# the Day1 workflow derive the same value straight from config.yaml because they run
# terraform BEFORE sourcing this lib.
export TF_VAR_enable_node_autoprovisioning="${J2026_NODE_AUTOPROVISIONING_ENABLED}"

# --- CI run-pod placement (per-engine feature flags) -------------------------
# Where the build pods run: 'static' (the long-lived jenkins-2026-pool, default — robust,
# no NAP/Spot/quota dependency) or 'ci-spot' (the NAP Spot ComputeClass). Per-engine
# because Jenkins (single agent pod) tolerates Spot preemption far better than Tekton
# (affinity-assistant pins a whole PipelineRun to one node). 04-jenkins.sh / 06-tekton-
# pipelines.sh consume these. FEATURE FLAGS: JENKINS2026_{JENKINS,TEKTON}_RUN_NODE_POOL.
validate_run_node_pool() {
  case "$1" in
    static|ci-spot) ;;
    *) log_error "Invalid $2 '$1' (expected static|ci-spot)."; exit 1 ;;
  esac
}
export J2026_JENKINS_RUN_NODE_POOL="${JENKINS2026_JENKINS_RUN_NODE_POOL:-$(yq_get '.jenkins.runNodePool' 'static')}"
validate_run_node_pool "${J2026_JENKINS_RUN_NODE_POOL}" "jenkins.runNodePool"
export J2026_TEKTON_RUN_NODE_POOL="${JENKINS2026_TEKTON_RUN_NODE_POOL:-$(yq_get '.tekton.runNodePool' 'static')}"
validate_run_node_pool "${J2026_TEKTON_RUN_NODE_POOL}" "tekton.runNodePool"
# GitHub Actions / ARC defaults to ci-spot: each runner is a single ephemeral pod (one
# job then terminated), so a Spot preemption loses at most one re-queued job — unlike
# Tekton's affinity-assistant. This engine IS the NAP Spot scale-to-zero showcase.
export J2026_GITHUBACTIONS_RUN_NODE_POOL="${JENKINS2026_GITHUBACTIONS_RUN_NODE_POOL:-$(yq_get '.githubactions.runNodePool' 'ci-spot')}"
validate_run_node_pool "${J2026_GITHUBACTIONS_RUN_NODE_POOL}" "githubactions.runNodePool"
# Argo Workflows defaults to static: a Workflow's steps share one RWO 'source' workspace
# PVC, so a Spot preemption mid-run loses the whole run (same caveat as Tekton's affinity
# assistant). ci-spot is opt-in.
export J2026_ARGOWORKFLOWS_RUN_NODE_POOL="${JENKINS2026_ARGOWORKFLOWS_RUN_NODE_POOL:-$(yq_get '.argoworkflows.runNodePool' 'static')}"
validate_run_node_pool "${J2026_ARGOWORKFLOWS_RUN_NODE_POOL}" "argoworkflows.runNodePool"

# --- ci engine (feature flag) ------------------------------------------------

# FEATURE FLAG: JENKINS2026_CI_ENGINE, if set, overrides ci.engine from
# config.yaml (jenkins|tekton) - same "config file is the durable default, env
# var is the ephemeral override" pattern as JENKINS2026_OBS_MODE above. Selects
# which CI engine up.sh/down.sh deploy and which numbered steps run (jenkins ->
# 04-jenkins.sh/06-seed-pipelines.sh; tekton -> 04-tekton.sh/06-tekton-pipelines.sh;
# githubactions -> 04-githubactions.sh/06-githubactions-pipelines.sh = ARC self-hosted runners).
J2026_CI_ENGINE="${JENKINS2026_CI_ENGINE:-$(yq_get '.ci.engine' 'jenkins')}"
export J2026_CI_ENGINE

case "${J2026_CI_ENGINE}" in
  jenkins|tekton|githubactions|argoworkflows) ;;
  *)
    log_error "Unsupported CI engine '${J2026_CI_ENGINE}' (expected jenkins|tekton|githubactions|argoworkflows)."
    log_error "Set ci.engine in ${J2026_CONFIG_FILE} or export JENKINS2026_CI_ENGINE."
    exit 1
    ;;
esac

# --- secrets backend (feature flag) ------------------------------------------
# FEATURE FLAG: JENKINS2026_SECRETS_BACKEND overrides secrets.backend from
# config.yaml for a single run. imperative (default) = kubectl create secret;
# eso = push to GCP Secret Manager + sync via External Secrets Operator.
J2026_SECRETS_BACKEND="${JENKINS2026_SECRETS_BACKEND:-$(yq_get '.secrets.backend' 'imperative')}"
export J2026_SECRETS_BACKEND
case "${J2026_SECRETS_BACKEND}" in
  imperative|eso) ;;
  *)
    log_error "Unsupported secrets backend '${J2026_SECRETS_BACKEND}' (expected imperative|eso)."
    log_error "Set secrets.backend in ${J2026_CONFIG_FILE} or export JENKINS2026_SECRETS_BACKEND."
    exit 1
    ;;
esac

# --- jenkins -------------------------------------------------------------

export J2026_JENKINS_NAMESPACE="$(yq_get '.jenkins.namespace' 'jenkins')"
export J2026_JENKINS_RELEASE="$(yq_get '.jenkins.releaseName' 'jenkins')"
export J2026_JENKINS_CHART_REPO_NAME="$(yq_get '.jenkins.chart.repoName' 'jenkins')"
export J2026_JENKINS_CHART_REPO_URL="$(yq_get '.jenkins.chart.repoUrl' 'https://charts.jenkins.io')"
export J2026_JENKINS_CHART_NAME="$(yq_get '.jenkins.chart.chartName' 'jenkins/jenkins')"
export J2026_JENKINS_CHART_VERSION="$(yq_get '.jenkins.chart.version' '')"
export J2026_JENKINS_ADMIN_USER="$(yq_get '.jenkins.adminUser' 'admin')"

export J2026_JENKINS_CREDENTIALS_SECRET="$(yq_get '.jenkins.credentialsSecretName' 'jenkins-credentials')"
export J2026_SELF_REPO_URL="$(yq_get '.jenkins.selfRepoUrl' 'https://github.com/nubenetes/jenkins-2026.git')"
# Branch of THIS repo that Jenkins checks out for the shared library + seed job
# (templated into JCasC as {{branchStable}} and the `repo-branch` secret by
# 04-jenkins.sh). Resolution, highest precedence first:
#   1. JENKINS2026_SELF_REPO_BRANCH — explicit ephemeral override (feature-flag pattern).
#   2. GITHUB_REF_NAME — in CI, auto-track the DISPATCHED branch, so a Day1 launched
#      from `develop` exercises develop's library/seed (and `main` from main). This is
#      what lets you validate library/pipeline changes on develop BEFORE the promotion
#      PR, instead of always pulling the pinned default. (GitHub Actions sets this in
#      every step; it is unset locally, so local runs fall through to the config value.)
#   3. jenkins.selfRepoBranch in config.yaml (default 'main') — the local/fallback default.
export J2026_SELF_REPO_BRANCH="${JENKINS2026_SELF_REPO_BRANCH:-${GITHUB_REF_NAME:-$(git branch --show-current 2>/dev/null || yq_get '.jenkins.selfRepoBranch' 'main')}}"

export J2026_JENKINS_OIDC_ADMIN_EMAIL="${JENKINS_OIDC_ADMIN_EMAIL:-}"
if [[ -z "${J2026_JENKINS_OIDC_ADMIN_EMAIL}" ]]; then
  if kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    J2026_JENKINS_OIDC_ADMIN_EMAIL="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.oidc-admin-email}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  fi
fi
export J2026_JENKINS_OIDC_ADMIN_EMAIL


# --- tekton (used when ci.engine == tekton) ----------------------------------

export J2026_TEKTON_NAMESPACE="$(yq_get '.tekton.namespace' 'tekton-pipelines')"
export J2026_TEKTON_PIPELINE_NAMESPACE="$(yq_get '.tekton.pipelineNamespace' 'tekton-ci')"
export J2026_TEKTON_VERSION_PIPELINES="$(yq_get '.tekton.versions.pipelines' 'v1.13.1')"
export J2026_TEKTON_VERSION_TRIGGERS="$(yq_get '.tekton.versions.triggers' 'v0.36.0')"
export J2026_TEKTON_VERSION_DASHBOARD="$(yq_get '.tekton.versions.dashboard' 'v0.69.0')"
export J2026_TEKTON_DASHBOARD_MODE="$(yq_get '.tekton.dashboard.mode' 'full')"
export J2026_TEKTON_DASHBOARD_SERVICE="$(yq_get '.tekton.dashboard.serviceName' 'tekton-dashboard')"
export J2026_TEKTON_DASHBOARD_PORT="$(yq_get '.tekton.dashboard.servicePort' '9097')"
export J2026_TEKTON_REGISTRY_SECRET="$(yq_get '.tekton.registryCredentialsSecretName' 'tekton-registry')"
export J2026_TEKTON_GIT_SECRET="$(yq_get '.tekton.gitCredentialsSecretName' 'tekton-git')"
# FEATURE FLAG: JENKINS2026_TEKTON_SEED_RUNS overrides tekton.seedRuns. When true,
# scripts/06-tekton-pipelines.sh ALSO creates one PipelineRun per service under PaC
# (from tekton/runs/) so the Tekton Dashboard is pre-populated with runnable entries
# (click Rerun) from the first Day1 — at the cost of one build per service per
# provision. Default false: PaC's git-push trigger is the normal path.
export J2026_TEKTON_SEED_RUNS="${JENKINS2026_TEKTON_SEED_RUNS:-$(yq_get '.tekton.seedRuns' 'false')}"


# --- github actions / ARC (used when ci.engine == githubactions) -------------
# Actions Runner Controller: the gha-runner-scale-set-controller + an AutoscalingRunnerSet
# (ephemeral self-hosted runners) installed via the argocd/githubactions app-of-apps.
# No central web UI (runs live in GitHub's Actions tab) -> no Gateway/IAP route.
export J2026_GHA_NAMESPACE="$(yq_get '.githubactions.namespace' 'arc-systems')"
export J2026_GHA_RUNNER_NAMESPACE="$(yq_get '.githubactions.runnerNamespace' 'arc-runners')"
export J2026_GHA_RUNNER_SCALE_SET_NAME="$(yq_get '.githubactions.runnerScaleSetName' 'jenkins-2026-runners')"
export J2026_GHA_CONFIG_URL="$(yq_get '.githubactions.githubConfigUrl' 'https://github.com/nubenetes')"
export J2026_GHA_AUTH_MODE="$(yq_get '.githubactions.authMode' 'app')"
export J2026_GHA_CONTAINER_MODE="$(yq_get '.githubactions.containerMode' 'dind')"
export J2026_GHA_VERSION_ARC="$(yq_get '.githubactions.versions.arc' '0.12.1')"
export J2026_GHA_REGISTRY_SECRET="$(yq_get '.githubactions.registryCredentialsSecretName' 'arc-registry')"
export J2026_GHA_APP_SECRET="$(yq_get '.githubactions.githubAppSecretName' 'arc-github-app')"
# FEATURE FLAG: JENKINS2026_GITHUBACTIONS_SEED_RUNS overrides githubactions.seedRuns. When
# true, 06-githubactions-pipelines.sh ALSO `gh workflow run`s each fork's microservices-ci
# workflow on Day1 (parity with tekton.seedRuns). Default true.
export J2026_GHA_SEED_RUNS="${JENKINS2026_GITHUBACTIONS_SEED_RUNS:-$(yq_get '.githubactions.seedRuns' 'true')}"


# --- argo workflows (used when ci.engine == argoworkflows) -------------------
# Argo Workflows controller+server (argo ns), Argo Events controller+EventBus
# (argo-events ns), and the WorkflowTemplates/EventSource/Sensor that run in the
# execution ns (argo-ci), installed via the argocd/argoworkflows app-of-apps.
# The Server UI is IAP-protected at the Gateway (no native auth), like the Tekton Dashboard.
export J2026_ARGOWF_NAMESPACE="$(yq_get '.argoworkflows.namespace' 'argo')"
export J2026_ARGOWF_EVENTS_NAMESPACE="$(yq_get '.argoworkflows.eventsNamespace' 'argo-events')"
export J2026_ARGOWF_RUN_NAMESPACE="$(yq_get '.argoworkflows.runNamespace' 'argo-ci')"
export J2026_ARGOWF_VERSION_WORKFLOWS="$(yq_get '.argoworkflows.versions.workflows' 'v3.7.15')"
export J2026_ARGOWF_VERSION_EVENTS="$(yq_get '.argoworkflows.versions.events' 'v1.9.4')"
export J2026_ARGOWF_SERVER_SERVICE="$(yq_get '.argoworkflows.server.serviceName' 'argo-server')"
export J2026_ARGOWF_SERVER_PORT="$(yq_get '.argoworkflows.server.servicePort' '2746')"
export J2026_ARGOWF_REGISTRY_SECRET="$(yq_get '.argoworkflows.registryCredentialsSecretName' 'argoworkflows-registry')"
export J2026_ARGOWF_GIT_SECRET="$(yq_get '.argoworkflows.gitCredentialsSecretName' 'argoworkflows-git')"
# FEATURE FLAG: JENKINS2026_ARGOWORKFLOWS_SEED_RUNS overrides argoworkflows.seedRuns. When
# true, 06-argoworkflows-pipelines.sh ALSO submits one Workflow per service (from
# argoworkflows/runs/) so the Server UI is pre-populated (parity with tekton.seedRuns).
export J2026_ARGOWF_SEED_RUNS="${JENKINS2026_ARGOWORKFLOWS_SEED_RUNS:-$(yq_get '.argoworkflows.seedRuns' 'false')}"


# --- observability ---------------------------------------------------------

export J2026_OBS_NAMESPACE="$(yq_get '.observability.namespace' 'observability')"
# FEATURE FLAG: JENKINS2026_OBS_MODE, if set, overrides observability.mode
# from config.yaml (grafana-cloud|oss|managed-azure|managed-aws) - same
# override pattern as JENKINS2026_PLATFORM above.
J2026_OBS_MODE="${JENKINS2026_OBS_MODE:-$(yq_get '.observability.mode' 'grafana-cloud')}"
export J2026_OBS_MODE

# FEATURE FLAG: Grafana Cloud tier — a PROFILE governing the volume-control defaults
# (leanMetrics + logMinSeverity) so the free tier stays under its limits. Only meaningful
# in grafana-cloud mode. Durable default 'free'; override JENKINS2026_GRAFANA_CLOUD_TIER
# or the grafana_cloud_tier GHA dropdown. See docs/301.
J2026_GRAFANA_CLOUD_TIER="${JENKINS2026_GRAFANA_CLOUD_TIER:-$(yq_get '.observability.grafanaCloudTier' 'free')}"
export J2026_GRAFANA_CLOUD_TIER
case "${J2026_GRAFANA_CLOUD_TIER}" in
  free|paid) ;;
  *)
    log_error "Invalid observability.grafanaCloudTier '${J2026_GRAFANA_CLOUD_TIER}' (expected free|paid)."
    exit 1
    ;;
esac

# Tier-derived defaults for the two volume knobs. The tier only shapes them in
# grafana-cloud mode; other backends are neutral (lean off, severity info).
if [[ "${J2026_OBS_MODE}" == "grafana-cloud" && "${J2026_GRAFANA_CLOUD_TIER}" == "free" ]]; then
  _lean_default="true";  _sev_default="warn"
elif [[ "${J2026_OBS_MODE}" == "grafana-cloud" && "${J2026_GRAFANA_CLOUD_TIER}" == "paid" ]]; then
  _lean_default="false"; _sev_default="trace"
else
  _lean_default="false"; _sev_default="info"
fi

# FEATURE FLAG: lean metrics — when true, scripts/03-observability.sh (grafana-cloud mode)
# disables the k8s-monitoring/Alloy CLUSTER INFRA metrics (cadvisor / kube-state /
# node-exporter), the high-cardinality series the custom jenkins2026-* dashboards don't use
# (app/CNPG/Tekton metrics via the otel-collector are UNAFFECTED). Precedence:
# env JENKINS2026_OBS_LEAN_METRICS > explicit config (true|false) > 'auto'/unset = tier
# default. 'auto' is honoured from EITHER layer (the GHA dropdown passes 'auto' to mean
# "derive from tier" — emitting an empty string via a ${{ }} ternary isn't reliable).
_lean_raw="${JENKINS2026_OBS_LEAN_METRICS:-$(yq_get '.observability.leanMetrics' 'auto')}"
[[ "${_lean_raw}" == "auto" || -z "${_lean_raw}" ]] && _lean_raw="${_lean_default}"
export J2026_OBS_LEAN_METRICS="${_lean_raw}"

# FEATURE FLAG: minimum log severity. The otel-collector-logs DaemonSet gets a `filter`
# processor (injected by 03-observability.sh) that drops structured log records below this
# level, trimming every Grafana logs panel across all four obs modes. Precedence:
# env JENKINS2026_LOG_MIN_SEVERITY > explicit config (a level) > 'auto'/unset = tier
# default. 'auto' is honoured from EITHER layer (same reason as leanMetrics above).
_sev_raw="${JENKINS2026_LOG_MIN_SEVERITY:-$(yq_get '.observability.logMinSeverity' 'auto')}"
[[ "${_sev_raw}" == "auto" || -z "${_sev_raw}" ]] && _sev_raw="${_sev_default}"
J2026_LOG_MIN_SEVERITY="${_sev_raw}"
export J2026_LOG_MIN_SEVERITY
case "${J2026_LOG_MIN_SEVERITY}" in
  trace|debug|info|warn|error) ;;
  *)
    log_error "Invalid logMinSeverity '${J2026_LOG_MIN_SEVERITY}' (expected trace|debug|info|warn|error; or 'auto' in config)."
    log_error "Set observability.logMinSeverity/grafanaCloudTier in ${J2026_CONFIG_FILE} or export JENKINS2026_LOG_MIN_SEVERITY."
    exit 1
    ;;
esac

case "${J2026_OBS_MODE}" in
  grafana-cloud|oss|managed-azure|managed-aws) ;;
  *)
    log_error "Unsupported observability mode '${J2026_OBS_MODE}' (expected grafana-cloud|oss|managed-azure|managed-aws)."
    log_error "Set observability.mode in ${J2026_CONFIG_FILE} or export JENKINS2026_OBS_MODE."
    exit 1
    ;;
esac

# For the managed-* modes, the cloud provider is the suffix (azure|aws). Empty
# for grafana-cloud/oss. Lets scripts branch on provider without re-parsing.
case "${J2026_OBS_MODE}" in
  managed-*) J2026_OBS_MANAGED_PROVIDER="${J2026_OBS_MODE#managed-}" ;;
  *)         J2026_OBS_MANAGED_PROVIDER="" ;;
esac
export J2026_OBS_MANAGED_PROVIDER

export J2026_OTEL_OPERATOR_REPO_NAME="$(yq_get '.observability.otelOperator.chart.repoName' 'open-telemetry')"
export J2026_OTEL_OPERATOR_REPO_URL="$(yq_get '.observability.otelOperator.chart.repoUrl' 'https://open-telemetry.github.io/opentelemetry-helm-charts')"
export J2026_OTEL_OPERATOR_CHART="$(yq_get '.observability.otelOperator.chart.chartName' 'open-telemetry/opentelemetry-operator')"
export J2026_OTEL_OPERATOR_CHART_VERSION="$(yq_get '.observability.otelOperator.chart.version' '')"
export J2026_OTEL_OPERATOR_RELEASE="$(yq_get '.observability.otelOperator.releaseName' 'otel-operator')"

export J2026_OTEL_COLLECTOR_CHART="$(yq_get '.observability.otelCollector.chart.chartName' 'open-telemetry/opentelemetry-collector')"
export J2026_OTEL_COLLECTOR_CHART_VERSION="$(yq_get '.observability.otelCollector.chart.version' '')"
export J2026_OTEL_GATEWAY_RELEASE="$(yq_get '.observability.otelCollector.gatewayReleaseName' 'otel-collector-gateway')"
export J2026_OTEL_LOGS_RELEASE="$(yq_get '.observability.otelCollector.logsReleaseName' 'otel-collector-logs')"
export J2026_GRAFANA_CLOUD_SECRET="$(yq_get '.observability.otelCollector.grafanaCloudSecretName' 'grafana-cloud-credentials')"

export J2026_GRAFANA_CHART_REPO_NAME="$(yq_get '.observability.grafana.chart.repoName' 'grafana')"
export J2026_GRAFANA_CHART_REPO_URL="$(yq_get '.observability.grafana.chart.repoUrl' 'https://grafana.github.io/helm-charts')"
export J2026_GRAFANA_OSS_NAMESPACE="$(yq_get '.observability.grafana.ossNamespace' "${J2026_OBS_NAMESPACE}")"

# Managed (Azure/AWS) provider credential Secret names. Only consumed by the
# matching observability.mode=managed-* branch in 03-observability.sh.
export J2026_AZURE_MONITOR_SECRET="$(yq_get '.observability.managed.azure.credentialsSecretName' 'azure-monitor-credentials')"
export J2026_AWS_MANAGED_SECRET="$(yq_get '.observability.managed.aws.credentialsSecretName' 'aws-managed-credentials')"

# --- grafana LLM app (feature flag, oss mode only) ----------------------------
# FEATURE FLAG: JENKINS2026_OBS_LLM_ENABLED overrides observability.llm.enabled
# for a single run - same durable-default/ephemeral-override pattern as
# JENKINS2026_OBS_MODE. When true (and observability.mode=oss), the
# grafana-llm-app plugin is provisioned in the in-cluster Grafana, wired to
# Vertex AI via the LiteLLM gateway + Workload Identity (keyless, no new public
# surface). grafana-cloud -> no-op (native assistant); managed-* -> no-op by
# decision (docs/301 § Grafana LLM app - the plugin has no keyless path to the
# managed clouds). Consumed by scripts/08.8-grafana-llm.sh (apply/retire),
# 03-observability.sh, and exported to Terraform below.
J2026_OBS_LLM_ENABLED="${JENKINS2026_OBS_LLM_ENABLED:-$(yq_get '.observability.llm.enabled' 'false')}"
export J2026_OBS_LLM_ENABLED
case "${J2026_OBS_LLM_ENABLED}" in
  true|false) ;;
  *)
    log_error "Invalid observability.llm.enabled '${J2026_OBS_LLM_ENABLED}' (expected true|false)."
    log_error "Set observability.llm.enabled in ${J2026_CONFIG_FILE} or export JENKINS2026_OBS_LLM_ENABLED."
    exit 1
    ;;
esac

# Single source of truth for the cloud-side trust chain: the SAME flag drives
# the Terraform toggle (terraform/gke grafana-llm GSA + WI binding), so the
# in-cluster wiring and the cloud IAM can never desync - same pattern as
# TF_VAR_enable_node_autoprovisioning.
export TF_VAR_observability_llm_enabled="${J2026_OBS_LLM_ENABLED}"

# oss mode (Vertex AI via LiteLLM). The GSA/KSA names are the WI-binding key -
# keep in sync with terraform/gke/variables.tf if renamed.
export J2026_OBS_LLM_GSA="$(yq_get '.observability.llm.gcp.googleServiceAccount' 'grafana-llm-gsa')"
export J2026_OBS_LLM_KSA="$(yq_get '.observability.llm.gcp.kubernetesServiceAccount' 'grafana-llm-sa')"
export J2026_OBS_LLM_VERTEX_LOCATION="$(yq_get '.observability.llm.gcp.vertexLocation' 'global')"
export J2026_OBS_LLM_MODEL_BASE="$(yq_get '.observability.llm.gcp.models.base' 'gemini-3.5-flash')"
export J2026_OBS_LLM_MODEL_LARGE="$(yq_get '.observability.llm.gcp.models.large' 'gemini-3.1-pro-preview')"
export J2026_OBS_LLM_LITELLM_IMAGE="$(yq_get '.observability.llm.litellm.image' 'ghcr.io/berriai/litellm')"
export J2026_OBS_LLM_LITELLM_VERSION="$(yq_get '.observability.llm.litellm.version' 'v1.91.1')"
export J2026_OBS_LLM_LITELLM_SERVICE="$(yq_get '.observability.llm.litellm.serviceName' 'litellm-service')"
export J2026_OBS_LLM_LITELLM_PORT="$(yq_get '.observability.llm.litellm.servicePort' '4000')"
# The GSA/KSA identity names + namespace also flow into terraform/gke (the
# Workload Identity binding is keyed on them), so a rename in config.yaml can
# never silently diverge from the cloud-side binding - same single-source
# doctrine as TF_VAR_observability_llm_enabled above.
export TF_VAR_grafana_llm_gsa_account_id="${J2026_OBS_LLM_GSA}"
export TF_VAR_grafana_llm_ksa_namespace="${J2026_OBS_NAMESPACE}"
export TF_VAR_grafana_llm_ksa_name="${J2026_OBS_LLM_KSA}"

# --- grafana Assistant (feature flag, oss mode only, SaaS-hybrid) -------------
# FEATURE FLAG: JENKINS2026_OBS_ASSISTANT_ENABLED overrides
# observability.assistant.enabled. The official grafana-assistant-app chat;
# oss-only, connects to a Grafana Cloud stack (SaaS-hybrid - prompts leave the
# cluster, unlike the keyless LLM app). No GCP resources. Consumed by
# 03-observability.sh (plugin overlay) + 08.9-grafana-assistant.sh (the
# grafana-assistant-credentials Secret built from the connection GitHub secrets).
J2026_OBS_ASSISTANT_ENABLED="${JENKINS2026_OBS_ASSISTANT_ENABLED:-$(yq_get '.observability.assistant.enabled' 'false')}"
export J2026_OBS_ASSISTANT_ENABLED
case "${J2026_OBS_ASSISTANT_ENABLED}" in
  true|false) ;;
  *)
    log_error "Invalid observability.assistant.enabled '${J2026_OBS_ASSISTANT_ENABLED}' (expected true|false)."
    log_error "Set observability.assistant.enabled in ${J2026_CONFIG_FILE} or export JENKINS2026_OBS_ASSISTANT_ENABLED."
    exit 1
    ;;
esac
export J2026_OBS_ASSISTANT_PLUGIN_ID="$(yq_get '.observability.assistant.pluginId' 'grafana-assistant-app')"
export J2026_OBS_ASSISTANT_PLUGIN_VERSION="$(yq_get '.observability.assistant.pluginVersion' '2.0.31')"
# Both-on caveat: the Assistant and LLM-app overlays both set grafana.plugins (a
# Helm list = replace-on-merge), so enabling BOTH installs only the Assistant
# plugin. They are alternative chat approaches (SaaS Assistant vs keyless LLM app)
# - warn rather than fail, since the rest of each feature is independent.
if [[ "${J2026_OBS_ASSISTANT_ENABLED}" == "true" && "${J2026_OBS_LLM_ENABLED}" == "true" ]]; then
  log_warn "Both observability.assistant.enabled and observability.llm.enabled are true: their grafana.plugins overlays don't merge, so only grafana-assistant-app installs (the LLM app's ✨-features plugin is dropped). Enable one chat approach - see docs/301."
fi

# --- headlamp ----------------------------------------------------------------

export J2026_HEADLAMP_NAMESPACE="$(yq_get '.headlamp.namespace' 'headlamp')"
export J2026_HEADLAMP_RELEASE="$(yq_get '.headlamp.releaseName' 'headlamp')"
export J2026_HEADLAMP_CHART_REPO_NAME="$(yq_get '.headlamp.chart.repoName' 'headlamp')"
export J2026_HEADLAMP_CHART_REPO_URL="$(yq_get '.headlamp.chart.repoUrl' 'https://kubernetes-sigs.github.io/headlamp/')"
export J2026_HEADLAMP_CHART_NAME="$(yq_get '.headlamp.chart.chartName' 'headlamp/headlamp')"
export J2026_HEADLAMP_CHART_VERSION="$(yq_get '.headlamp.chart.version' '')"
export J2026_HEADLAMP_CREDENTIALS_SECRET="$(yq_get '.headlamp.credentialsSecretName' 'headlamp-credentials')"
export J2026_HEADLAMP_OIDC_ISSUER_URL="$(yq_get '.headlamp.oidc.issuerURL' 'https://accounts.google.com')"
export J2026_HEADLAMP_OIDC_SCOPES="$(yq_get '.headlamp.oidc.scopes' 'openid email profile')"

# FEATURE FLAG: JENKINS2026_HEADLAMP_ADMIN_EMAILS, if set, overrides
# headlamp.adminEmails from config.yaml - same "config file is the durable
# default, env var is the ephemeral override" pattern as JENKINS2026_PLATFORM
# above. Comma-separated Google account emails granted cluster-admin via
# Headlamp (see README.md "Headlamp"). Never put real emails in config.yaml.
export J2026_HEADLAMP_ADMIN_EMAILS="${JENKINS2026_HEADLAMP_ADMIN_EMAILS:-$(yq_get '.headlamp.adminEmails' '')}"

# --- pgadmin -----------------------------------------------------------------

export J2026_PGADMIN_NAMESPACE="$(yq_get '.pgadmin.namespace' 'pgadmin')"
export J2026_PGADMIN_RELEASE="$(yq_get '.pgadmin.releaseName' 'pgadmin')"

# --- gateway (public access via GKE Gateway API + IAP) -----------------------


# FEATURE FLAG: JENKINS2026_BASE_DOMAIN, if set (including to ""), overrides
# gateway.baseDomain from config.yaml - same "config file is the durable
# default, env var is the ephemeral override" pattern as JENKINS2026_PLATFORM
# above. An empty value disables the gateway entirely (scripts/09-gateway.sh
# becomes a no-op) - e.g. before terraform/gateway-bootstrap has been run.
# Note: uses "${VAR-default}" (no colon) so that JENKINS2026_BASE_DOMAIN=""
# (explicitly set to empty) is honored as "disabled", distinct from unset.
export J2026_GATEWAY_BASE_DOMAIN="${JENKINS2026_BASE_DOMAIN-$(yq_get '.gateway.baseDomain' '')}"
export J2026_GATEWAY_STATIC_IP_NAME="$(yq_get '.gateway.staticIPName' 'jenkins-2026-gateway-ip')"
export J2026_GATEWAY_CERTMAP_NAME="$(yq_get '.gateway.certMapName' 'jenkins-2026-cert-map')"
export J2026_GATEWAY_IAP_SECRET="$(yq_get '.gateway.iapCredentialsSecretName' 'gateway-iap-oauth')"

# FEATURE FLAG: JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED overrides
# gateway.backendTls.enabled from config.yaml for a single run - same
# durable-default/ephemeral-override pattern as JENKINS2026_BASE_DOMAIN above.
# When true, 08.7-backend-tls.sh installs cert-manager + the cluster-internal
# CA and mints the per-backend server certs, 08.5-argocd.sh layers the TLS
# overlay onto the TLS-ready backends (stage 1: Headlamp), and 09-gateway.sh
# attaches the BackendTLSPolicy + HTTPS HealthCheckPolicy so the L7 LB
# re-encrypts AND validates the LB→pod hop. Consumers never read this raw -
# they gate on j2026_backend_tls_active (lib/common.sh: this flag AND the
# BackendTLSPolicy CRD being served). See docs/504-BACKEND_TLS.md.
J2026_GATEWAY_BACKEND_TLS_ENABLED="${JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED:-$(yq_get '.gateway.backendTls.enabled' 'false')}"
export J2026_GATEWAY_BACKEND_TLS_ENABLED
case "${J2026_GATEWAY_BACKEND_TLS_ENABLED}" in
  true|false) ;;
  *)
    log_error "Invalid gateway.backendTls.enabled '${J2026_GATEWAY_BACKEND_TLS_ENABLED}' (expected true|false)."
    log_error "Set gateway.backendTls.enabled in ${J2026_CONFIG_FILE} or export JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED."
    exit 1
    ;;
esac

# Fixed names of the backend-TLS resources created by scripts/08.7-backend-tls.sh
# and scripts/09-gateway.sh. Shared with scripts/down.sh for the same reason as
# the Gateway names below (Decom deletes by fixed name from a fresh checkout).
export J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE="cert-manager"
export J2026_BACKEND_TLS_SELFSIGNED_ISSUER="jenkins-2026-selfsigned"
# The CA ClusterIssuer; its CA Certificate + Secret (in the cert-manager
# namespace) deliberately share this name.
export J2026_BACKEND_TLS_CA_ISSUER="jenkins-2026-internal-ca"
# Per-backend-namespace CA trust bundle ConfigMap (key ca.crt) that the
# BackendTLSPolicies' caCertificateRefs validate against.
export J2026_BACKEND_TLS_CA_CONFIGMAP="jenkins-2026-backend-tls-ca"
export J2026_BACKEND_TLS_POLICY_HEADLAMP="headlamp-backend-tls"
# Stage-2 TLS backend: the otel-collector faro (RUM) receiver. Server-cert Secret
# 08.7 mints (must match secretName in observability/otel-collector/
# values-backend-tls.yaml) + the BackendTLSPolicy 09-gateway.sh attaches. The
# collector Service is otel-collector-gateway (fullnameOverride, every obs mode).
export J2026_BACKEND_TLS_SECRET_FARO="faro-tls"
export J2026_BACKEND_TLS_POLICY_FARO="faro-backend-tls"
# Stage-3 TLS backend: argocd-server (the ArgoCD UI). argocd-server watches the
# argocd-server-tls Secret and serves it when not --insecure (08.5 drops --insecure
# under j2026_argocd_backend_tls_active). 09-gateway.sh attaches the BackendTLSPolicy.
export J2026_BACKEND_TLS_SECRET_ARGOCD="argocd-server-tls"
export J2026_BACKEND_TLS_POLICY_ARGOCD="argocd-backend-tls"
# Stage-4 TLS backend: pgAdmin (the platform-postgres admin UI). Server-cert Secret
# 08.7 mints (must match the secretName the pgadmin-tls extraSecretMounts reference
# in helm/pgadmin/values-backend-tls.yaml) + the BackendTLSPolicy 09-gateway.sh
# attaches. pgAdmin serves TLS on its pod port 8443 (PGADMIN_ENABLE_TLS +
# PGADMIN_LISTEN_PORT, non-privileged since the pod runs as UID 5050); the Service
# is ${J2026_PGADMIN_RELEASE}-pgadmin4 (runix chart fullname).
export J2026_BACKEND_TLS_SECRET_PGADMIN="pgadmin-tls"
export J2026_BACKEND_TLS_POLICY_PGADMIN="pgadmin-backend-tls"
# Stage-5 TLS backend: the in-cluster OSS Grafana (observability.mode=oss ONLY —
# doubly conditional: the flag AND oss mode; the managed backends live off-cluster).
# Server-cert Secret 08.7-backend-tls.sh mints (must match the secretName in
# observability/grafana/values-oss-backend-tls.yaml, layered by the observability-oss
# app-of-apps) + the BackendTLSPolicy 09-gateway.sh attaches. Grafana serves TLS on its
# pod port (named `grafana`, 3000) via grafana.ini server.protocol=https; the Service is
# oss-kube-prometheus-stack-grafana (the kube-prometheus-stack subchart fullname).
export J2026_BACKEND_TLS_SECRET_GRAFANA="grafana-tls"
export J2026_BACKEND_TLS_POLICY_GRAFANA="grafana-backend-tls"
# Stage-6 TLS backend: Jenkins (ci.engine=jenkins ONLY - the controller Service
# doesn't exist otherwise). Highest blast radius of the six stages: build agents
# and (oss mode) Grafana's Jenkins datasource dial the Service directly in plain
# HTTP, so the chart's native controller.httpsKeyStore feature is used instead of
# a plain cert (see helm/jenkins/values-backend-tls.yaml) - it moves the pod's
# plain-HTTP listener + probes to httpPort 8081 while the Service's existing port
# (8080) becomes HTTPS, and controller.extraPorts re-exposes the plain port on the
# Service as 8082 (->pod 8081; a distinct number to avoid a containerPort collision)
# so in-cluster callers (agents) keep dialing plain HTTP on a different port than
# the LB. The JKS keystore needs a password Secret cert-manager reads via
# passwordSecretRef (it doesn't create one) - 08.7-backend-tls.sh generates it
# once (create-if-absent).
export J2026_BACKEND_TLS_SECRET_JENKINS="jenkins-tls"
export J2026_BACKEND_TLS_JENKINS_JKS_PASSWORD_SECRET="jenkins-https-jks-password"
export J2026_BACKEND_TLS_POLICY_JENKINS="jenkins-backend-tls"
# Tekton Dashboard Backend TLS
export J2026_BACKEND_TLS_SECRET_TEKTON="tekton-dashboard-tls"
export J2026_BACKEND_TLS_POLICY_TEKTON="tekton-dashboard-backend-tls"
# Argo Workflows Server Backend TLS
export J2026_BACKEND_TLS_SECRET_ARGOWF="argo-server-tls"
export J2026_BACKEND_TLS_POLICY_ARGOWF="argo-server-backend-tls"
# Stage-7 TLS backend: microservices gateway.
export J2026_BACKEND_TLS_SECRET_MICROSERVICES="gateway-tls"
export J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET="gateway-tls-password"
export J2026_BACKEND_TLS_POLICY_MICROSERVICES="microservices-gateway-backend-tls"


# Fixed names of the Gateway/HTTPRoute/GCPBackendPolicy resources created by
# scripts/09-gateway.sh. Shared with scripts/down.sh so the two stay in sync:
# down.sh deletes these by name/namespace from a fresh checkout in
# Decom.cluster.01-gke.yml, where .generated/gateway/ (created by
# 09-gateway.sh on a different runner) doesn't exist.
export J2026_GATEWAY_NAME="jenkins-2026-gateway"
# Engine-neutral namespace that hosts the shared Gateway object (the public-ingress
# entrypoint for every app). Always created by 01-namespaces.sh, independent of
# ci.engine - so switching jenkins<->tekton never touches the ingress. HTTPRoutes
# live in each app's own namespace and attach cross-namespace (Gateway
# allowedRoutes.namespaces.from: All).
export J2026_GATEWAY_NAMESPACE="$(yq_get '.gateway.namespace' 'platform-ingress')"
export J2026_GATEWAY_HTTPROUTE_JENKINS="jenkins"
export J2026_GATEWAY_HTTPROUTE_MICROSERVICES="microservices"
export J2026_GATEWAY_HTTPROUTE_MICROSERVICES_DEVELOP="microservices-develop"
export J2026_GATEWAY_HTTPROUTE_HEADLAMP="headlamp"
export J2026_GATEWAY_HTTPROUTE_PGADMIN="pgadmin"
export J2026_GATEWAY_HTTPROUTE_FARO="faro"
# Grafana is only exposed in observability.mode=oss (in-cluster Grafana).
export J2026_GATEWAY_HTTPROUTE_GRAFANA="grafana"
# Tekton Dashboard is only exposed when ci.engine=tekton.
export J2026_GATEWAY_HTTPROUTE_TEKTON="tekton"
# PaC controller webhook endpoint (ci.engine=tekton; public, no IAP).
export J2026_GATEWAY_HTTPROUTE_PAC="pac"
export J2026_GATEWAY_IAP_POLICY_JENKINS="jenkins-iap"
export J2026_GATEWAY_IAP_POLICY_ARGOCD="argocd-iap"
export J2026_GATEWAY_IAP_POLICY_HEADLAMP="headlamp-iap"
export J2026_GATEWAY_IAP_POLICY_PGADMIN="pgadmin-iap"
export J2026_GATEWAY_IAP_POLICY_GRAFANA="grafana-iap"
export J2026_GATEWAY_IAP_POLICY_TEKTON="tekton-iap"

J2026_GATEWAY_HOST_JENKINS="$(yq_get '.gateway.hosts.jenkins' 'jenkins')"
J2026_GATEWAY_HOST_MICROSERVICES="$(yq_get '.gateway.hosts.microservices' 'microservices')"
J2026_GATEWAY_HOST_MICROSERVICES_DEVELOP="$(yq_get '.gateway.hosts.microservicesDevelop' 'microservices-develop')"
J2026_GATEWAY_HOST_HEADLAMP="$(yq_get '.gateway.hosts.headlamp' 'headlamp')"
J2026_GATEWAY_HOST_PGADMIN="$(yq_get '.gateway.hosts.pgadmin' 'pgadmin')"
J2026_GATEWAY_HOST_FARO="$(yq_get '.gateway.hosts.faro' 'faro')"
J2026_GATEWAY_HOST_GRAFANA="$(yq_get '.gateway.hosts.grafana' 'grafana')"
J2026_GATEWAY_HOST_TEKTON="$(yq_get '.gateway.hosts.tekton' 'tekton')"
J2026_GATEWAY_HOST_PAC="$(yq_get '.gateway.hosts.pac' 'pac')"
export J2026_GATEWAY_JENKINS_HOST="${J2026_GATEWAY_HOST_JENKINS}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_MICROSERVICES_HOST="${J2026_GATEWAY_HOST_MICROSERVICES}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_MICROSERVICES_DEVELOP_HOST="${J2026_GATEWAY_HOST_MICROSERVICES_DEVELOP}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_HEADLAMP_HOST="${J2026_GATEWAY_HOST_HEADLAMP}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_PGADMIN_HOST="${J2026_GATEWAY_HOST_PGADMIN}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_FARO_HOST="${J2026_GATEWAY_HOST_FARO}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_GRAFANA_HOST="${J2026_GATEWAY_HOST_GRAFANA}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_TEKTON_HOST="${J2026_GATEWAY_HOST_TEKTON}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_PAC_HOST="${J2026_GATEWAY_HOST_PAC}.${J2026_GATEWAY_BASE_DOMAIN}"

# Argo Workflows Server UI (IAP-protected) + Argo Events webhook receiver (public, no
# IAP) — only used when ci.engine=argoworkflows.
export J2026_GATEWAY_HTTPROUTE_ARGOWF="argoworkflows"
export J2026_GATEWAY_HTTPROUTE_ARGOEVENTS="argo-events"
export J2026_GATEWAY_IAP_POLICY_ARGOWF="argoworkflows-iap"
J2026_GATEWAY_HOST_ARGOWF="$(yq_get '.gateway.hosts.argoworkflows' 'argo')"
J2026_GATEWAY_HOST_ARGOEVENTS="$(yq_get '.gateway.hosts.argoevents' 'argo-events')"
export J2026_GATEWAY_ARGOWF_HOST="${J2026_GATEWAY_HOST_ARGOWF}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_ARGOEVENTS_HOST="${J2026_GATEWAY_HOST_ARGOEVENTS}.${J2026_GATEWAY_BASE_DOMAIN}"


# Headlamp's OIDC redirect URI: the public gateway URL if the gateway is
# enabled, else the kubectl port-forward default. Override with
# JENKINS2026_HEADLAMP_OIDC_CALLBACK_URL if neither fits. Must be registered
# as an authorized redirect URI on the Headlamp Google OAuth client - see
# README.md "Headlamp" and "Public access (GKE Gateway API + IAP)".
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  J2026_HEADLAMP_OIDC_CALLBACK_URL_DEFAULT="https://${J2026_GATEWAY_HEADLAMP_HOST}/oidc-callback"
else
  J2026_HEADLAMP_OIDC_CALLBACK_URL_DEFAULT="http://localhost:8080/oidc-callback"
fi
export J2026_HEADLAMP_OIDC_CALLBACK_URL="${JENKINS2026_HEADLAMP_OIDC_CALLBACK_URL:-${J2026_HEADLAMP_OIDC_CALLBACK_URL_DEFAULT}}"

# Jenkins' own root URL (jenkins.casc.defaults' unclassified.location.url via
# controller.jenkinsUrl, see scripts/04-jenkins.sh): the public gateway URL if
# the gateway is enabled, else the kubectl port-forward default. The oic-auth
# plugin derives its Google OAuth redirect_uri
# (<location.url>/securityRealm/finishLogin) from this - it must be https and
# match an authorized redirect URI on the Jenkins OAuth client (see
# README.md "Google login (OpenID Connect)"), which an unset/cluster-internal
# location.url cannot satisfy.
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  J2026_JENKINS_URL_DEFAULT="https://${J2026_GATEWAY_JENKINS_HOST}/"
else
  J2026_JENKINS_URL_DEFAULT="http://localhost:8080/"
fi
export J2026_JENKINS_URL="${JENKINS2026_JENKINS_URL:-${J2026_JENKINS_URL_DEFAULT}}"

# --- microservices ------------------------------------------------------------

export J2026_MICROSERVICES_NS_STABLE="$(yq_get '.microservices.namespaces.stable' 'microservices')"

export J2026_MICROSERVICES_GIT_ORG="$(yq_get '.microservices.git.org' 'nubenetes')"
export J2026_MICROSERVICES_GIT_REPO="$(yq_get '.microservices.git.repo' 'jenkins-2026')"
export J2026_MICROSERVICES_GIT_URL="$(yq_get '.microservices.git.url' '')"

export J2026_MICROSERVICES_BRANCH_STABLE="$(yq_get '.microservices.branches.stable' 'main')"

export J2026_MICROSERVICES_REGISTRY="$(yq_get '.microservices.registry' 'ghcr.io/nubenetes/jenkins-2026-microservices')"

# Space-separated list of service names.
J2026_MICROSERVICES_SERVICES="$(yq_get_list '.microservices.services[].name' | tr '\n' ' ')"
export J2026_MICROSERVICES_SERVICES="${J2026_MICROSERVICES_SERVICES% }"

# FEATURE FLAG: JENKINS2026_GENAI_SERVICE_ENABLED.
export J2026_MICROSERVICES_GENAI_SERVICE_ENABLED="${JENKINS2026_GENAI_SERVICE_ENABLED:-$(yq_get '.microservices.genaiServiceEnabled' 'false')}"

# FEATURE FLAG: JENKINS2026_DEVELOP_TRACK_ENABLED. Optional second deploy tier
# (microservices-develop namespace + values-develop.yaml, tracking the gitops
# 'develop' branch). OFF by default - it roughly doubles the microservices
# footprint. Consumed by 08.5-argocd.sh (adds the develop ApplicationSet
# generator element) and surfaced to the seed job as the env var of the same
# name (04-jenkins.sh) so it generates the parallel '<svc>-develop' jobs.
export J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED="${JENKINS2026_DEVELOP_TRACK_ENABLED:-$(yq_get '.microservices.developTrackEnabled' 'false')}"
export J2026_MICROSERVICES_DEVELOP_NAMESPACE="$(yq_get '.microservices.namespaces.develop' 'microservices-develop')"

# --- argocd -----------------------------------------------------------------

export J2026_ARGOCD_NAMESPACE="$(yq_get '.argocd.namespace' 'argocd')"
export J2026_ARGOCD_RELEASE="$(yq_get '.argocd.releaseName' 'argocd')"
export J2026_ARGOCD_VERSION="$(yq_get '.argocd.version' 'v3.4.4')"
export J2026_ARGOCD_VERSION_CONSTRAINT="$(yq_get '.argocd.version_constraint' '3.4.x')"
# argo-cd Helm chart version pinned to the 3.4.x line (chart 9.5.x ships ArgoCD 3.4.x).
export J2026_ARGOCD_CHART_VERSION="$(yq_get '.argocd.chartVersion' '9.5.22')"

# Branch of the gitops-config repo that the develop tier's ArgoCD app tracks.
# Used by 08.5-argocd.sh as the 'branch' of the develop ApplicationSet generator
# element (only added when J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED=true).
export J2026_SELF_REPO_DEV_BRANCH="$(yq_get '.microservices.branches.develop' 'develop')"
