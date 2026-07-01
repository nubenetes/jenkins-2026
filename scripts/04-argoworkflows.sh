#!/usr/bin/env bash
# Deploys the Argo Workflows CI engine (ci.engine=argoworkflows) as the alternative
# to Jenkins/Tekton, GitOps-managed by ArgoCD - the same app-of-apps pattern as
# observability-oss / platform-postgres / tekton. This script applies the parent
# Application (argocd/argoworkflows-app.yaml), which renders child Applications for:
#   - Argo Workflows  (argocd/argoworkflows/components/workflows: controller + server)
#   - Argo Events     (argocd/argoworkflows/components/events: controllers + EventBus)
#   - the pipelines-as-code under argoworkflows/ (WorkflowTemplates/EventSource/Sensor/RBAC + SA)
# then waits for the control plane to come up. The pinned component versions live in
# argocd/argoworkflows/components/*/ (vendored upstream release.yaml); the credential
# Secrets are created imperatively by 01-namespaces.sh / 08.5-argocd.sh (they hold
# env-sourced secrets and can't be GitOps-managed). The per-service Workflows are
# kicked by 06-argoworkflows-pipelines.sh.
#
# Requires ArgoCD (08.5-argocd.sh runs before this in up.sh). The Argo Workflows
# Server UI has no native auth - it is exposed behind Google IAP at the Gateway
# (09-gateway.sh), exactly like the Tekton Dashboard.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

if [[ "${J2026_CI_ENGINE}" != "argoworkflows" ]]; then
  log_info "ci.engine='${J2026_CI_ENGINE}' (not argoworkflows) - skipping Argo Workflows install."
  exit 0
fi

ARGOWF_NS="${J2026_ARGOWF_NAMESPACE}"

# Engines are mutually exclusive: selecting Argo Workflows retires Jenkins AND Tekton
# if they are present (switching engines on a running cluster, or a stale leftover),
# and a clean install never deploys either in the first place (up.sh branches on
# ci.engine). Same "retire the mode we're switching away from" pattern as
# 03-observability.sh / 04-tekton.sh / helm_uninstall_if_present. The shared
# microservices are GitOps-managed (ArgoCD), so they survive the switch - only the
# Jenkins/Tekton controllers and their gateway routing are removed. Idempotent /
# best-effort.
# Engines are mutually exclusive: selecting Argo Workflows fully retires the other
# three (Jenkins · Tekton · GitHub Actions/ARC) — every ArgoCD app they own, their
# namespaces, and any stuck GKE NEG finalizer — via the shared, deadlock-proof
# helper in lib/common.sh. The GitOps-managed microservices survive; only the
# retired engines' control planes / dashboards go. Idempotent.
retire_ci_engine jenkins
helm_uninstall_if_present "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}"  # legacy pre-ArgoCD Jenkins fallback
retire_ci_engine tekton
retire_ci_engine githubactions

log_step "Applying Argo Workflows app-of-apps via ArgoCD (argocd/argoworkflows-app.yaml)"
ARGOWF_APP_FILE="$(mktemp)"
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
    "${J2026_ROOT_DIR}/argocd/argoworkflows-app.yaml" > "${ARGOWF_APP_FILE}"
kubectl apply -f "${ARGOWF_APP_FILE}"
rm -f "${ARGOWF_APP_FILE}"

# ArgoCD syncs the children asynchronously (sync waves: workflows -> events ->
# pipelines-as-code). Wait for the control-plane Deployments to appear and become
# Available. wait_for_deployment first waits for existence.
log_step "Waiting for the Argo Workflows control plane to come up (ArgoCD sync)"
for deploy in workflow-controller argo-server; do
  wait_for_deployment "${deploy}" "${ARGOWF_NS}" "10m" \
    || log_warn "${deploy} not Available yet - check 'kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications' (argoworkflows-*)."
done

# Argo Events v1.9.x ships a SINGLE unified controller-manager Deployment in the events
# namespace (the eventbus/eventsource/sensor controllers are consolidated into it — the
# separate per-CR Deployments of older releases no longer exist). Wait for just that one;
# waiting on the retired names would block 10m each for nothing.
log_step "Waiting for the Argo Events controller to come up (ArgoCD sync)"
wait_for_deployment "controller-manager" "${J2026_ARGOWF_EVENTS_NAMESPACE}" "10m" \
  || log_warn "controller-manager not Available yet - check 'kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications' (argo-events)."

# Warm the workflow-step image caches on every node so Workflow pods start fast (a
# Workflow step is only Running once its image is present; the build pipeline pulls
# maven/kaniko/codeql/... — codeql is multi-GB). Best-effort. Argo Workflows analogue of
# the Tekton/Jenkins agent-image-prepull DaemonSet.
log_step "Applying Argo Workflows step image pre-pull DaemonSet"
kubectl apply -f "${J2026_ROOT_DIR}/argoworkflows/agent-image-prepull.yaml" || \
  log_warn "Argo Workflows image pre-pull DaemonSet not applied - first Workflows on a fresh node will be slower."

log_info "Argo Workflows deployed via ArgoCD."
log_info "  Apps: kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications -l app.kubernetes.io/part-of=argoworkflows 2>/dev/null || kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications | grep argoworkflows"
log_info "  Pipelines-as-code + per-service runs are applied/kicked by scripts/06-argoworkflows-pipelines.sh (run by up.sh)."
