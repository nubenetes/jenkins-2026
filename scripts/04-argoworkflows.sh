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
log_step "Retiring Jenkins if present (ci.engine=argoworkflows)"
# Jenkins is a GitOps-managed Application - delete it first so ArgoCD cascade-prunes
# the chart and doesn't re-sync it back. helm_uninstall is a legacy fallback for
# pre-ArgoCD Jenkins installs.
kubectl delete application jenkins -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
helm_uninstall_if_present "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}"
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
  kubectl delete healthcheckpolicy "${J2026_JENKINS_RELEASE}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
fi
# Delete the Jenkins namespace itself — symmetric with 04-jenkins.sh, which deletes the
# alternative-engine namespaces when switching the other way. Clears the orphaned objects
# left once the Jenkins Application is pruned (jenkins-credentials, the JCasC ConfigMaps,
# the IAP secret copies). The shared microservices are GitOps-managed in their own
# namespace, so they survive the engine switch. Idempotent / best-effort.
kubectl delete namespace "${J2026_JENKINS_NAMESPACE}" --ignore-not-found --timeout=3m || true

# Retire Tekton too (the other alternative engine). Delete the app-of-apps while ArgoCD
# is alive so it cascade-prunes the Tekton Pipelines/Triggers/Dashboard controllers and
# the tekton/ pipelines-as-code. Best-effort; a clean argoworkflows install never
# deployed Tekton.
log_step "Retiring Tekton if present (ci.engine=argoworkflows)"
kubectl delete application tekton -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true

# Retire GitHub Actions / ARC too (the fourth engine). Delete the app-of-apps so ArgoCD
# cascade-prunes arc-controller + arc-runner-scale-set, then drop the arc namespaces.
log_step "Retiring GitHub Actions / ARC if present (ci.engine=argoworkflows)"
kubectl delete application githubactions -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
kubectl delete namespace "${J2026_GHA_NAMESPACE}" "${J2026_GHA_RUNNER_NAMESPACE}" --ignore-not-found --wait=false || true

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
