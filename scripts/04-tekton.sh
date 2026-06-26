#!/usr/bin/env bash
# Deploys the Tekton CI engine (ci.engine=tekton) as the alternative to Jenkins,
# GitOps-managed by ArgoCD - the same app-of-apps pattern as observability-oss /
# platform-postgres. This script applies the parent Application
# (argocd/tekton-app.yaml), which renders child Applications for:
#   - Tekton Pipelines  (argocd/tekton/components/pipelines, pinned release)
#   - Tekton Triggers   (argocd/tekton/components/triggers)
#   - Tekton Dashboard  (argocd/tekton/components/dashboard, read-write)
#   - the pipelines-as-code under tekton/ (Tasks/Pipelines/Triggers/RBAC + SA)
# then waits for the control plane to come up. The pinned component versions live
# in argocd/tekton/components/*/kustomization.yaml (kustomize remote resources);
# the credential Secrets are created imperatively by 01-namespaces.sh / 08.5-argocd.sh
# (they hold env-sourced secrets and can't be GitOps-managed). The per-service
# PipelineRuns are kicked by 06-tekton-pipelines.sh.
#
# Requires ArgoCD (08.5-argocd.sh runs before this in up.sh). The Dashboard has
# no native auth - it is exposed behind Google IAP at the Gateway (09-gateway.sh).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

if [[ "${J2026_CI_ENGINE}" != "tekton" ]]; then
  log_info "ci.engine='${J2026_CI_ENGINE}' (not tekton) - skipping Tekton install."
  exit 0
fi

TEKTON_NS="${J2026_TEKTON_NAMESPACE}"

# Engines are mutually exclusive: selecting Tekton retires Jenkins if it is
# present (switching engines on a running cluster, or a stale leftover), and a
# clean install never deploys Jenkins in the first place (up.sh branches on
# ci.engine). Same "retire the mode we're switching away from" pattern as
# 03-observability.sh / helm_uninstall_if_present. The shared microservices are
# GitOps-managed (ArgoCD), so they survive the switch - only the Jenkins
# controller and its gateway routing are removed. Idempotent / best-effort.
log_step "Retiring Jenkins if present (ci.engine=tekton)"
# Jenkins is a GitOps-managed Application - delete it first so ArgoCD
# cascade-prunes the chart and doesn't re-sync it back. helm_uninstall is a
# legacy fallback for pre-ArgoCD Jenkins installs.
kubectl delete application jenkins -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
helm_uninstall_if_present "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}"
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
  kubectl delete healthcheckpolicy "${J2026_JENKINS_RELEASE}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
fi
# Delete the Jenkins namespace itself — symmetric with 04-jenkins.sh, which deletes the
# tekton namespaces when switching the other way. Clears the orphaned objects left once
# the Jenkins Application is pruned (jenkins-credentials, the JCasC ConfigMaps, the IAP
# secret copies). The shared microservices are GitOps-managed in their own namespace, so
# they survive the engine switch. Idempotent / best-effort.
kubectl delete namespace "${J2026_JENKINS_NAMESPACE}" --ignore-not-found --timeout=3m || true

log_step "Applying Tekton app-of-apps via ArgoCD (argocd/tekton-app.yaml)"
TEKTON_APP_FILE="$(mktemp)"
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
    "${J2026_ROOT_DIR}/argocd/tekton-app.yaml" > "${TEKTON_APP_FILE}"
kubectl apply -f "${TEKTON_APP_FILE}"
rm -f "${TEKTON_APP_FILE}"

# ArgoCD syncs the children asynchronously (sync waves: pipelines -> triggers/
# dashboard -> pipelines-as-code). Wait for the control-plane Deployments to
# appear and become Available. wait_for_deployment first waits for existence.
log_step "Waiting for the Tekton control plane to come up (ArgoCD sync)"
for deploy in tekton-pipelines-controller tekton-pipelines-webhook \
              tekton-triggers-controller "${J2026_TEKTON_DASHBOARD_SERVICE}"; do
  wait_for_deployment "${deploy}" "${TEKTON_NS}" "10m" \
    || log_warn "${deploy} not Available yet - check 'kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications' (tekton-*)."
done

# NOTE: the first-sync race between ArgoCD applying the Tekton config-* ConfigMaps
# and tekton-pipelines-webhook issuing its serving cert (config.webhook.pipeline.
# tekton.dev → "tls: unrecognized name" / x509) is now **self-healed by ArgoCD**:
# the tekton-pipelines Application carries syncPolicy.retry (auto-retry with
# backoff) and no longer uses Replace=true (which used to re-trigger the webhook /
# blank the caBundle on every sync). So no manual/script webhook restart is needed
# here anymore — the sync converges on its own once the webhook is up. If you ever
# need to force it by hand: `kubectl -n ${TEKTON_NS} rollout restart deploy/tekton-pipelines-webhook`.

log_info "Tekton deployed via ArgoCD."
log_info "  Apps: kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications -l app.kubernetes.io/part-of=tekton 2>/dev/null || kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications | grep tekton"
log_info "  Pipelines-as-code + per-service runs are applied/kicked by scripts/06-tekton-pipelines.sh (run by up.sh)."
