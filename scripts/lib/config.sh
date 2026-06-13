#!/usr/bin/env bash
# Loads config/config.yaml via `yq` and exports it as J2026_* environment
# variables consumed by every numbered step script. Sourced (not executed)
# after lib/common.sh:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
#
# FEATURE FLAG: JENKINS2026_PLATFORM, if set, overrides platform.target from
# config.yaml (gke|eks|aks|openshift). config/config.yaml is the durable
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

case "${J2026_PLATFORM}" in
  gke|eks|aks|openshift) ;;
  *)
    log_error "Unsupported platform '${J2026_PLATFORM}' (expected gke|eks|aks|openshift)."
    log_error "Set platform.target in ${J2026_CONFIG_FILE} or export JENKINS2026_PLATFORM."
    exit 1
    ;;
esac

export J2026_STORAGE_CLASS="$(yq_get ".platform.${J2026_PLATFORM}.storageClassName" '')"
export J2026_INGRESS_CLASS="$(yq_get ".platform.${J2026_PLATFORM}.ingressClassName" '')"
export J2026_SERVICE_TYPE="$(yq_get ".platform.${J2026_PLATFORM}.serviceType" 'ClusterIP')"
export J2026_USE_ROUTE="$(yq_get ".platform.${J2026_PLATFORM}.useRoute" 'false')"

# --- jenkins -------------------------------------------------------------

export J2026_JENKINS_NAMESPACE="$(yq_get '.jenkins.namespace' 'jenkins')"
export J2026_JENKINS_RELEASE="$(yq_get '.jenkins.releaseName' 'jenkins')"
export J2026_JENKINS_CHART_REPO_NAME="$(yq_get '.jenkins.chart.repoName' 'jenkins')"
export J2026_JENKINS_CHART_REPO_URL="$(yq_get '.jenkins.chart.repoUrl' 'https://charts.jenkins.io')"
export J2026_JENKINS_CHART_NAME="$(yq_get '.jenkins.chart.chartName' 'jenkins/jenkins')"
export J2026_JENKINS_CHART_VERSION="$(yq_get '.jenkins.chart.version' '')"
export J2026_JENKINS_ADMIN_USER="$(yq_get '.jenkins.adminUser' 'admin')"
export J2026_PLATFORM_ENGINEER_USER="$(yq_get '.jenkins.platformEngineerUser' 'platform-engineer')"
export J2026_JENKINS_CREDENTIALS_SECRET="$(yq_get '.jenkins.credentialsSecretName' 'jenkins-credentials')"
export J2026_SELF_REPO_URL="$(yq_get '.jenkins.selfRepoUrl' 'https://github.com/nubenetes/jenkins-2026.git')"
export J2026_SELF_REPO_BRANCH="$(yq_get '.jenkins.selfRepoBranch' 'main')"
export J2026_SELF_REPO_DEV_BRANCH="$(yq_get '.jenkins.selfRepoDevBranch' 'develop')"

# --- observability ---------------------------------------------------------

export J2026_OBS_NAMESPACE="$(yq_get '.observability.namespace' 'observability')"
# FEATURE FLAG: JENKINS2026_OBS_MODE, if set, overrides observability.mode
# from config.yaml (grafana-cloud|oss|managed) - same override pattern as
# JENKINS2026_PLATFORM above.
J2026_OBS_MODE="${JENKINS2026_OBS_MODE:-$(yq_get '.observability.mode' 'grafana-cloud')}"
export J2026_OBS_MODE

case "${J2026_OBS_MODE}" in
  grafana-cloud|oss|managed) ;;
  *)
    log_error "Unsupported observability mode '${J2026_OBS_MODE}' (expected grafana-cloud|oss|managed)."
    log_error "Set observability.mode in ${J2026_CONFIG_FILE} or export JENKINS2026_OBS_MODE."
    exit 1
    ;;
esac

export J2026_OTEL_OPERATOR_REPO_NAME="$(yq_get '.observability.otelOperator.chart.repoName' 'open-telemetry')"
export J2026_OTEL_OPERATOR_REPO_URL="$(yq_get '.observability.otelOperator.chart.repoUrl' 'https://open-telemetry.github.io/opentelemetry-helm-charts')"
export J2026_OTEL_OPERATOR_CHART="$(yq_get '.observability.otelOperator.chart.chartName' 'open-telemetry/opentelemetry-operator')"
export J2026_OTEL_OPERATOR_RELEASE="$(yq_get '.observability.otelOperator.releaseName' 'otel-operator')"

export J2026_OTEL_COLLECTOR_CHART="$(yq_get '.observability.otelCollector.chart.chartName' 'open-telemetry/opentelemetry-collector')"
export J2026_OTEL_GATEWAY_RELEASE="$(yq_get '.observability.otelCollector.gatewayReleaseName' 'otel-collector-gateway')"
export J2026_OTEL_LOGS_RELEASE="$(yq_get '.observability.otelCollector.logsReleaseName' 'otel-collector-logs')"
export J2026_GRAFANA_CLOUD_SECRET="$(yq_get '.observability.otelCollector.grafanaCloudSecretName' 'grafana-cloud-credentials')"

export J2026_GRAFANA_CHART_REPO_NAME="$(yq_get '.observability.grafana.chart.repoName' 'grafana')"
export J2026_GRAFANA_CHART_REPO_URL="$(yq_get '.observability.grafana.chart.repoUrl' 'https://grafana.github.io/helm-charts')"
export J2026_GRAFANA_OSS_NAMESPACE="$(yq_get '.observability.grafana.ossNamespace' "${J2026_OBS_NAMESPACE}")"

# --- petclinic ---------------------------------------------------------------

export J2026_PETCLINIC_NS_STABLE="$(yq_get '.petclinic.namespaces.stable' 'petclinic')"
export J2026_PETCLINIC_NS_DEVELOP="$(yq_get '.petclinic.namespaces.develop' 'petclinic-develop')"
export J2026_PETCLINIC_NS_PAC_DEV="$(yq_get '.petclinic.namespaces.pacDev' 'petclinic-pac-dev')"

export J2026_PETCLINIC_GIT_ORG="$(yq_get '.petclinic.git.org' 'spring-petclinic')"
export J2026_PETCLINIC_BACKEND_REPO="$(yq_get '.petclinic.git.backendRepo' 'spring-petclinic-microservices')"
export J2026_PETCLINIC_FRONTEND_REPO="$(yq_get '.petclinic.git.frontendRepo' 'spring-petclinic-angular')"
export J2026_PETCLINIC_BACKEND_URL="$(yq_get '.petclinic.git.backendUrl' '')"
export J2026_PETCLINIC_FRONTEND_URL="$(yq_get '.petclinic.git.frontendUrl' '')"

export J2026_PETCLINIC_BRANCH_STABLE="$(yq_get '.petclinic.branches.stable' 'master')"
export J2026_PETCLINIC_BRANCH_DEVELOP="$(yq_get '.petclinic.branches.develop' 'develop')"

export J2026_PETCLINIC_REGISTRY="$(yq_get '.petclinic.registry' 'ghcr.io/nubenetes/jenkins-2026-petclinic')"

# Space-separated list of service names, e.g. "config-server discovery-server ...".
J2026_PETCLINIC_SERVICES="$(yq_get_list '.petclinic.services[].name' | tr '\n' ' ')"
export J2026_PETCLINIC_SERVICES="${J2026_PETCLINIC_SERVICES% }"
