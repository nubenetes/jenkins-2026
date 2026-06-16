#!/usr/bin/env bash
# Verifies local tooling + cluster connectivity, and registers the Helm repos
# used by every other step. Safe to re-run.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

log_step "Checking required CLI tools"
missing=0
for bin in kubectl helm yq git; do
  require_cmd "${bin}" || missing=1
done
if ! command -v gh >/dev/null 2>&1; then
  log_warn "'gh' (GitHub CLI) not found - only needed by scripts that push this repo to GitHub."
fi
if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

log_step "Checking cluster connectivity"
if ! kubectl version >/dev/null 2>&1; then
  log_error "kubectl cannot reach a cluster. Set KUBECONFIG / current-context first."
  exit 1
fi
# Capture output before piping to `head`: `kubectl cluster-info | head -n1`
# lets `head` close the pipe early, so kubectl gets SIGPIPE -> exit 141 under
# `set -o pipefail`.
cluster_info="$(kubectl cluster-info)"
head -n1 <<< "${cluster_info}"
log_info "Current context: $(kubectl config current-context)"

log_step "Resolved configuration"
log_info "Platform target : ${J2026_PLATFORM} (config/config.yaml, override with JENKINS2026_PLATFORM)"
log_info "Observability   : ${J2026_OBS_MODE}"
log_info "Jenkins ns      : ${J2026_JENKINS_NAMESPACE}"
log_info "Microservices ns    : ${J2026_MICROSERVICES_NS_STABLE}"
log_info "Microservices svcs  : ${J2026_MICROSERVICES_SERVICES}"

if [[ "${J2026_PLATFORM}" == "openshift" ]]; then
  if ! kubectl api-resources --api-group=route.openshift.io 2>/dev/null | grep -q routes; then
    log_warn "platform=openshift but the route.openshift.io API group was not found on this cluster."
  fi
fi

log_step "Adding/updating Helm repositories"
helm repo add "${J2026_JENKINS_CHART_REPO_NAME}" "${J2026_JENKINS_CHART_REPO_URL}"
helm repo add "${J2026_OTEL_OPERATOR_REPO_NAME}" "${J2026_OTEL_OPERATOR_REPO_URL}"
helm repo add "${J2026_GRAFANA_CHART_REPO_NAME}" "${J2026_GRAFANA_CHART_REPO_URL}"
helm repo add "${J2026_HEADLAMP_CHART_REPO_NAME}" "${J2026_HEADLAMP_CHART_REPO_URL}"
helm repo add argo https://argoproj.github.io/argo-helm
# kube-prometheus-stack, used only when observability.mode == oss.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

log_info "Prereqs OK."
