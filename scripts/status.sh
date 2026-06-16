#!/usr/bin/env bash
# Prints rollout status for every component installed by up.sh, plus
# port-forward commands for the Jenkins UI and (in oss mode) Grafana.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

log_step "Platform=${J2026_PLATFORM} Observability=${J2026_OBS_MODE}"

log_step "Jenkins (namespace: ${J2026_JENKINS_NAMESPACE})"
kubectl get statefulset,svc -n "${J2026_JENKINS_NAMESPACE}" -l "app.kubernetes.io/instance=${J2026_JENKINS_RELEASE}" 2>/dev/null \
  || log_warn "Jenkins not found - run scripts/04-jenkins.sh"

log_step "Observability (namespace: ${J2026_OBS_NAMESPACE})"
kubectl get pods -n "${J2026_OBS_NAMESPACE}" 2>/dev/null || log_warn "Namespace ${J2026_OBS_NAMESPACE} not found"
if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  kubectl get pods -n "${J2026_GRAFANA_OSS_NAMESPACE}" -l "app.kubernetes.io/name=grafana" 2>/dev/null
fi

log_step "Microservices - stable (namespace: ${J2026_MICROSERVICES_NS_STABLE})"
kubectl get deploy,pods -n "${J2026_MICROSERVICES_NS_STABLE}" 2>/dev/null || log_warn "Namespace ${J2026_MICROSERVICES_NS_STABLE} not found"

log_step "ArgoCD (namespace: ${J2026_ARGOCD_NAMESPACE})"
kubectl get pods -n "${J2026_ARGOCD_NAMESPACE}" 2>/dev/null || log_warn "Namespace ${J2026_ARGOCD_NAMESPACE} not found"
if kubectl get applications -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  kubectl get applications -n "${J2026_ARGOCD_NAMESPACE}"
fi

echo
log_step "Useful endpoints"
log_info "Jenkins UI:   kubectl -n ${J2026_JENKINS_NAMESPACE} port-forward svc/${J2026_JENKINS_RELEASE} 8080:8080  (login: ${J2026_JENKINS_ADMIN_USER} / see '${J2026_JENKINS_CREDENTIALS_SECRET}' secret)"
log_info "ArgoCD UI:    kubectl -n ${J2026_ARGOCD_NAMESPACE} port-forward svc/${J2026_ARGOCD_RELEASE}-server 8081:443 (login: admin / see argocd-initial-admin-secret secret)"
log_info "Microservices UI (stable):  kubectl -n ${J2026_MICROSERVICES_NS_STABLE} port-forward svc/microservices-angular 8082:8080"
if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  log_info "Grafana:      kubectl -n ${J2026_GRAFANA_OSS_NAMESPACE} port-forward svc/kube-prometheus-stack-grafana 3000:80  (login: admin / see kube-prometheus-stack-grafana secret)"
fi
