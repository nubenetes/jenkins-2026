#!/usr/bin/env bash
# 04-githubactions.sh — install the GitHub Actions / ARC CI engine (ci.engine=githubactions).
# The analogue of 04-tekton.sh / 04-jenkins.sh: applies the argocd/githubactions app-of-apps
# (gha-runner-scale-set-controller + the AutoscalingRunnerSet of ephemeral self-hosted
# runners), retiring the sibling engines first. Idempotent. See docs/405-GITHUB_ACTIONS.md.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

[[ "${J2026_CI_ENGINE}" != "githubactions" ]] && { log_info "ci.engine='${J2026_CI_ENGINE}' - skipping ARC (04-githubactions)."; exit 0; }

# --- retire the sibling CI engines (githubactions has THREE: jenkins, tekton, argoworkflows) ---
# Fully remove each — every ArgoCD app they own, their namespaces (incl. the
# jenkins/tekton dashboard routes + IAP policies that live in those namespaces),
# and any stuck GKE NEG finalizer — via the shared, deadlock-proof helper in
# lib/common.sh. githubactions itself has no in-cluster UI route. Idempotent.
retire_ci_engine jenkins
helm_uninstall_if_present "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}" 2>/dev/null || true  # legacy pre-ArgoCD Jenkins fallback
retire_ci_engine tekton
retire_ci_engine argoworkflows

# --- apply the ARC app-of-apps via ArgoCD ------------------------------------
log_step "Applying ARC app-of-apps via ArgoCD (argocd/githubactions-app.yaml)"
GHA_APP_FILE="$(mktemp)"
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed -e "s@{{repoUrl}}@${REPO_URL}@g" \
    -e "s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g" \
    -e "s@{{runNodePool}}@${J2026_GITHUBACTIONS_RUN_NODE_POOL}@g" \
    -e "s@{{nodeAutoProvisioningEnabled}}@${J2026_NODE_AUTOPROVISIONING_ENABLED:-true}@g" \
    "${J2026_ROOT_DIR}/argocd/githubactions-app.yaml" > "${GHA_APP_FILE}"
kubectl apply -f "${GHA_APP_FILE}"
rm -f "${GHA_APP_FILE}"

# --- wait for the controller + the runner scale set to register --------------
log_step "Waiting for the ARC controller to come up (ArgoCD sync)"
deadline=$(( $(date +%s) + 600 ))
ctrl=""
while [[ -z "${ctrl}" && "$(date +%s)" -lt "${deadline}" ]]; do
  ctrl="$(kubectl get deploy -n "${J2026_GHA_NAMESPACE}" -l app.kubernetes.io/part-of=gha-rs-controller -o name 2>/dev/null | head -n1)"
  [[ -z "${ctrl}" ]] && sleep 10
done
if [[ -n "${ctrl}" ]]; then
  kubectl rollout status "${ctrl}" -n "${J2026_GHA_NAMESPACE}" --timeout=10m \
    || log_warn "ARC controller not Available yet — check 'kubectl -n ${J2026_ARGOCD_NAMESPACE} get applications | grep arc-'."
  # ARC's controller backs off after auth failures and does NOT re-read the arc-github-app
  # Secret when it changes. So when 01-namespaces (re)builds that Secret with new creds — e.g.
  # adding the GitHub App key on a re-run after a first run fell back to the GIT_TOKEN PAT — a
  # long-running controller keeps the stale creds, 403s on registration, and never creates the
  # listener. Roll it so the fresh pod re-reads the current Secret. Cheap, idempotent.
  log_step "Restarting the ARC controller so it re-reads the current arc-github-app Secret"
  kubectl rollout restart "${ctrl}" -n "${J2026_GHA_NAMESPACE}" >/dev/null 2>&1 || true
  kubectl rollout status "${ctrl}" -n "${J2026_GHA_NAMESPACE}" --timeout=5m 2>/dev/null || true
else
  log_warn "ARC controller Deployment not found yet (ArgoCD still syncing the OCI charts?) — re-run to converge."
fi

# At minRunners=0 there is no runner pod to wait on; wait on the AutoscalingRunnerSet CR.
kubectl wait --for=jsonpath='{.status.state}'=running \
  autoscalingrunnerset/"${J2026_GHA_RUNNER_SCALE_SET_NAME}" -n "${J2026_GHA_RUNNER_NAMESPACE}" --timeout=5m 2>/dev/null \
  || log_warn "RunnerScaleSet '${J2026_GHA_RUNNER_SCALE_SET_NAME}' not yet registered — check the listener pod logs in ${J2026_GHA_NAMESPACE} (GitHub App creds / OCI pull)."

# --- runner ServiceAccount (+ Binary Authorization signing wiring) -----------
# In dind containerMode the gha-runner-scale-set chart creates NO runner ServiceAccount, so the
# runner pod template (argocd/githubactions/templates/runner-scale-set.yaml) pins
# serviceAccountName: arc-runner-scale-set and we create that KSA here so the pods always
# schedule. Created UNCONDITIONALLY (not gated) — a runner needs no RBAC in dind (the ArgoCD-sync
# workflow step uses the arc-argocd token Secret, not this SA), and an unannotated SA behaves
# like default. Idempotent.
log_step "Ensuring the arc-runner-scale-set runner ServiceAccount in ${J2026_GHA_RUNNER_NAMESPACE}"
kubectl create serviceaccount arc-runner-scale-set -n "${J2026_GHA_RUNNER_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 \
  || log_warn "Could not ensure the arc-runner-scale-set KSA in ${J2026_GHA_RUNNER_NAMESPACE} — runner pods may fail to schedule."

# Binary Authorization (docs/507 § Pipeline wiring): annotate that KSA to impersonate the
# jenkins-2026-binauthz-signer GSA via Workload Identity, so the rendered microservices-ci.yml's
# sign-attest gcloud (which runs INSIDE the ephemeral runner pod) can sign+attest. terraform binds
# the GSA to arc-runners/arc-runner-scale-set (binauthz_signer_ksas); this is the KSA-side half.
# Analogue of 04-tekton.sh, but WITHOUT an ArgoCD ignoreDifferences: this SA is script-created
# (not part of any ArgoCD app), so selfHeal never strips the annotation. Gated on the flag; only
# affects the gcloud sign step (the runner's git/registry/argocd steps use their own creds).
if [[ "$(j2026_binary_authorization_active)" == "true" ]]; then
  binauthz_project="$(gcloud config get-value project 2>/dev/null || echo "")"
  if [[ -n "${binauthz_project}" ]]; then
    binauthz_signer="jenkins-2026-binauthz-signer@${binauthz_project}.iam.gserviceaccount.com"
    log_step "Binary Authorization active - annotating the arc-runner-scale-set KSA to impersonate ${binauthz_signer} (image signing)"
    kubectl annotate serviceaccount arc-runner-scale-set -n "${J2026_GHA_RUNNER_NAMESPACE}" \
      "iam.gke.io/gcp-service-account=${binauthz_signer}" --overwrite >/dev/null 2>&1 \
      || log_warn "Could not annotate the arc-runner-scale-set KSA - GHA image signing will not authenticate (see docs/507)."
  else
    log_warn "Binary Authorization active but could not resolve the GCP project for the signer-GSA annotation - GHA image signing will not authenticate (see docs/507)."
  fi
fi

log_info "ARC installed (ci.engine=githubactions). Runners register as '${J2026_GHA_RUNNER_SCALE_SET_NAME}' against ${J2026_GHA_CONFIG_URL}."
