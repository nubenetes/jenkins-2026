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

# Engines are mutually exclusive: selecting Tekton fully retires the other three
# (Jenkins · GitHub Actions/ARC · Argo Workflows) — every ArgoCD app they own,
# their namespaces, and any stuck GKE NEG finalizer — via the shared,
# deadlock-proof helper in lib/common.sh. The GitOps-managed microservices survive
# the switch; only the retired engines' control planes / dashboards go. Idempotent.
retire_ci_engine jenkins
helm_uninstall_if_present "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}"  # legacy pre-ArgoCD Jenkins fallback
retire_ci_engine githubactions
retire_ci_engine argoworkflows

log_step "Applying Tekton app-of-apps via ArgoCD (argocd/tekton-app.yaml)"
TEKTON_APP_FILE="$(mktemp)"
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
     s@{{backendTlsEnabled}}@$(j2026_backend_tls_active)@g" \
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

# Warm the task image caches on every node so TaskRun pods start fast (a TaskRun is
# only Running once all its step images are present; the build pipeline pulls
# maven/kaniko/codeql/... — codeql is multi-GB). Best-effort. Tekton analogue of the
# Jenkins agent-image-prepull DaemonSet.
log_step "Applying Tekton task image pre-pull DaemonSet"
kubectl apply -f "${J2026_ROOT_DIR}/tekton/agent-image-prepull.yaml" || \
  log_warn "Tekton image pre-pull DaemonSet not applied - first TaskRuns on a fresh node will be slower."

# Binary Authorization (docs/507 § Pipeline wiring): annotate the tekton-ci pipeline KSA to
# impersonate the jenkins-2026-binauthz-signer GSA (Workload Identity) so the sign-attest
# step's gcloud can sign+attest. Only affects gcloud calls (the sign step) — the pipeline's
# git/registry/kubectl steps use their own creds, so a KSA impersonating a sign-only GSA
# doesn't disturb them. Analogue of 04-jenkins HOOK 2, but a kubectl annotate instead of a
# helm parameter: the tekton-ci SA is raw ArgoCD-synced YAML (not a chart), and the
# tekton-pipeline-as-code Application ignoreDifferences this exact annotation so selfHeal no
# longer strips it (observed live 2026-07-16: without the ignore, the annotate succeeded but
# was reverted before the sign step ran). Gated on the flag; the WI binding
# (tekton-ci/tekton-ci → signer GSA) is granted by terraform/gke (binauthz_signer_ksas).
if [[ "$(j2026_binary_authorization_active)" == "true" ]]; then
  binauthz_project="$(gcloud config get-value project 2>/dev/null || echo "")"
  if [[ -n "${binauthz_project}" ]]; then
    binauthz_signer="jenkins-2026-binauthz-signer@${binauthz_project}.iam.gserviceaccount.com"
    log_step "Binary Authorization active - annotating the tekton-ci KSA to impersonate ${binauthz_signer} (image signing)"
    kubectl annotate serviceaccount tekton-ci -n "${J2026_TEKTON_PIPELINE_NAMESPACE}" \
      "iam.gke.io/gcp-service-account=${binauthz_signer}" --overwrite 2>/dev/null \
      || log_warn "Could not annotate the tekton-ci KSA - image signing will not authenticate (see docs/507)."
  else
    log_warn "Binary Authorization active but could not resolve the GCP project for the signer-GSA annotation - Tekton image signing will not authenticate (see docs/507)."
  fi
fi

log_info "Tekton deployed via ArgoCD."
log_info "  Apps: kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications -l app.kubernetes.io/part-of=tekton 2>/dev/null || kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications | grep tekton"
log_info "  Pipelines-as-code + per-service runs are applied/kicked by scripts/06-tekton-pipelines.sh (run by up.sh)."
