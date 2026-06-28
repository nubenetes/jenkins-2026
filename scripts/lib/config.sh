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

# --- ci engine (feature flag) ------------------------------------------------

# FEATURE FLAG: JENKINS2026_CI_ENGINE, if set, overrides ci.engine from
# config.yaml (jenkins|tekton) - same "config file is the durable default, env
# var is the ephemeral override" pattern as JENKINS2026_OBS_MODE above. Selects
# which CI engine up.sh/down.sh deploy and which numbered steps run (jenkins ->
# 04-jenkins.sh/06-seed-pipelines.sh; tekton -> 04-tekton.sh/06-tekton-pipelines.sh).
J2026_CI_ENGINE="${JENKINS2026_CI_ENGINE:-$(yq_get '.ci.engine' 'jenkins')}"
export J2026_CI_ENGINE

case "${J2026_CI_ENGINE}" in
  jenkins|tekton) ;;
  *)
    log_error "Unsupported CI engine '${J2026_CI_ENGINE}' (expected jenkins|tekton)."
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
export J2026_SELF_REPO_BRANCH="${JENKINS2026_SELF_REPO_BRANCH:-${GITHUB_REF_NAME:-$(yq_get '.jenkins.selfRepoBranch' 'main')}}"

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
