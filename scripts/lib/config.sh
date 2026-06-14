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
# 02.99-gke-decommission.yml, where .generated/gateway/ (created by
# 09-gateway.sh on a different runner) doesn't exist.
export J2026_GATEWAY_NAME="jenkins-2026-gateway"
export J2026_GATEWAY_HTTPROUTE_JENKINS="jenkins"
export J2026_GATEWAY_HTTPROUTE_PETCLINIC="petclinic"
export J2026_GATEWAY_HTTPROUTE_HEADLAMP="headlamp"
export J2026_GATEWAY_IAP_POLICY_JENKINS="jenkins-iap"
export J2026_GATEWAY_IAP_POLICY_HEADLAMP="headlamp-iap"

J2026_GATEWAY_HOST_JENKINS="$(yq_get '.gateway.hosts.jenkins' 'jenkins')"
J2026_GATEWAY_HOST_PETCLINIC="$(yq_get '.gateway.hosts.petclinic' 'petclinic')"
J2026_GATEWAY_HOST_HEADLAMP="$(yq_get '.gateway.hosts.headlamp' 'headlamp')"
export J2026_GATEWAY_JENKINS_HOST="${J2026_GATEWAY_HOST_JENKINS}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_PETCLINIC_HOST="${J2026_GATEWAY_HOST_PETCLINIC}.${J2026_GATEWAY_BASE_DOMAIN}"
export J2026_GATEWAY_HEADLAMP_HOST="${J2026_GATEWAY_HOST_HEADLAMP}.${J2026_GATEWAY_BASE_DOMAIN}"

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

# --- petclinic ---------------------------------------------------------------

export J2026_PETCLINIC_NS_STABLE="$(yq_get '.petclinic.namespaces.stable' 'petclinic')"
export J2026_PETCLINIC_NS_DEVELOP="$(yq_get '.petclinic.namespaces.develop' 'petclinic-develop')"

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

# FEATURE FLAG: JENKINS2026_GENAI_SERVICE_ENABLED, if set, overrides
# petclinic.genaiServiceEnabled from config.yaml - same override pattern as
# JENKINS2026_PLATFORM above. Gates whether seed-jobs enables the
# genai-service pipeline jobs (see jenkins/pipelines/seed/seed_jobs.groovy).
export J2026_PETCLINIC_GENAI_SERVICE_ENABLED="${JENKINS2026_GENAI_SERVICE_ENABLED:-$(yq_get '.petclinic.genaiServiceEnabled' 'false')}"
