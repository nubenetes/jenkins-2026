#!/usr/bin/env bash
# Provision the ACTIVE CI engine's ArgoCD API account + token — the piece a pipeline's
# GitOps "Deploy" stage needs to `argocd app sync`/`app wait` (ARGOCD_AUTH_TOKEN). This is
# the SINGLE source for it, called by:
#   - 08.5-argocd.sh   (Day1, right after ArgoCD is installed + OIDC configured), and
#   - every per-engine Day2.redeploy.* (an engine SWITCH must (re)provision the NEW engine's
#     account+token, exactly like it must refresh Backstage — 08.95; without this the switched
#     pipeline's gitops step runs with an empty --auth-token and dies "Unauthenticated"/exit 20
#     even though the deploy itself converges via ArgoCD auto-sync. Found live 2026-07-17 on a
#     GHA→argoworkflows redeploy). Class: workflow-input-parity (a redeploy that doesn't
#     re-provision a dependent). See docs/507 / docs/101.
#
# Idempotent; requires ArgoCD already installed (argocd-server up). No-op-safe to re-run.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

NS="${J2026_ARGOCD_NAMESPACE}"

if ! kubectl get deployment "${J2026_ARGOCD_RELEASE}-server" -n "${NS}" >/dev/null 2>&1; then
  log_warn "argocd-server not found in ${NS} - ArgoCD not installed yet; skipping CI-account/token provisioning."
  exit 0
fi

# Account name follows the active CI engine (ci.engine).
case "${J2026_CI_ENGINE}" in
  tekton)        CI_ARGOCD_ACCOUNT="tekton" ;;
  githubactions) CI_ARGOCD_ACCOUNT="githubactions" ;;
  argoworkflows) CI_ARGOCD_ACCOUNT="argoworkflows" ;;
  *)             CI_ARGOCD_ACCOUNT="jenkins" ;;
esac

log_step "Provisioning the '${CI_ARGOCD_ACCOUNT}' ArgoCD API account + token (engine=${J2026_CI_ENGINE})"

# 1. Register the local apiKey account (merge — keeps any other engine's account, harmless).
kubectl patch configmap argocd-cm -n "${NS}" --type merge \
  -p "{\"data\": {\"accounts.${CI_ARGOCD_ACCOUNT}\": \"apiKey\"}}" >/dev/null

# 2. Ensure the account has admin RBAC — APPEND to policy.csv, never clobber (preserves the
#    human IAP-admin binding and any other engine's line, unlike a full rebuild).
cur_csv="$(kubectl get configmap argocd-rbac-cm -n "${NS}" -o json 2>/dev/null | jq -r '.data["policy.csv"] // ""')"
acct_line="g, ${CI_ARGOCD_ACCOUNT}, role:admin"
if ! printf '%s\n' "${cur_csv}" | grep -qxF "${acct_line}"; then
  new_csv="${cur_csv:+${cur_csv}$'\n'}${acct_line}"
  kubectl patch configmap argocd-rbac-cm -n "${NS}" --type merge \
    -p "$(jq -nc --arg p "${new_csv}" '{data:{"policy.csv":$p}}')" >/dev/null
  log_info "Added '${acct_line}' to argocd-rbac-cm policy.csv."
fi

# 3. argocd-server must roll to recognise a newly-added LOCAL account (settings auto-reload
#    covers RBAC but not new accounts). Best-effort NEG-aware wait (mirrors 08.5).
log_info "Restarting argocd-server to pick up the '${CI_ARGOCD_ACCOUNT}' account"
kubectl rollout restart deployment "${J2026_ARGOCD_RELEASE}-server" -n "${NS}" >/dev/null 2>&1 || true
wait_neg_backend_rollout "${J2026_ARGOCD_RELEASE}-server" "${NS}" "5m" || \
  log_warn "argocd-server rollout not confirmed (NEG readiness gate?) - continuing; token-gen retries below."

# 4. Generate the API token via a short-lived pod running the argocd CLI in --core mode
#    (talks to the k8s API directly; a temporary cluster-admin binding on the argocd default SA
#    grants the access, deleted immediately after). Image = the running argocd-server's, so the
#    CLI always matches the installed version. Retried; every failure path is a WARN.
ARGOCD_IMG="$(kubectl get deployment "${J2026_ARGOCD_RELEASE}-server" -n "${NS}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
if [[ -z "${ARGOCD_IMG}" ]]; then
  log_warn "Could not resolve the argocd-server image - skipping token generation (pipeline gitops step will lack a token)."
  exit 0
fi

kubectl apply -f - >/dev/null <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: temp-argocd-token-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: default
    namespace: ${NS}
EOF

set +e
RAW_TOKEN=""; EXIT_CODE=1
for attempt in 1 2 3; do
  kubectl delete pod argocd-token-gen -n "${NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl run argocd-token-gen -n "${NS}" --restart=Never --image="${ARGOCD_IMG}" \
    --overrides="{\"spec\":{\"containers\":[{\"name\":\"argocd-token-gen\",\"image\":\"${ARGOCD_IMG}\",\"command\":[\"bash\",\"-c\",\"argocd account generate-token --account ${CI_ARGOCD_ACCOUNT} --core\"],\"resources\":{\"requests\":{\"cpu\":\"50m\",\"memory\":\"128Mi\"},\"limits\":{\"cpu\":\"100m\",\"memory\":\"256Mi\"}}}]}}" >/dev/null 2>&1
  if kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/argocd-token-gen -n "${NS}" --timeout=5m >/dev/null 2>&1; then
    RAW_TOKEN="$(kubectl logs argocd-token-gen -n "${NS}" 2>/dev/null)"; EXIT_CODE=0; break
  fi
  log_warn "ArgoCD token-gen attempt ${attempt}/3 did not Succeed - retrying."
  sleep 5
done
kubectl delete pod argocd-token-gen -n "${NS}" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete clusterrolebinding temp-argocd-token-admin --ignore-not-found=true >/dev/null 2>&1 || true
set -e

TOKEN="$(printf '%s' "${RAW_TOKEN}" | tr -d '\n\r' | xargs 2>/dev/null || true)"
if [[ ${EXIT_CODE} -ne 0 || -z "${TOKEN}" ]]; then
  log_warn "Could not generate an ArgoCD token for '${CI_ARGOCD_ACCOUNT}' - the pipeline's gitops step will lack ARGOCD_AUTH_TOKEN (see docs/507)."
  exit 0
fi

# 5. Store the token where the ACTIVE engine's pipeline reads it (ARGOCD_AUTH_TOKEN).
case "${J2026_CI_ENGINE}" in
  tekton)        tok_secret="tekton-argocd";        tok_ns="${J2026_TEKTON_PIPELINE_NAMESPACE}" ;;
  githubactions) tok_secret="arc-argocd";           tok_ns="${J2026_GHA_RUNNER_NAMESPACE}" ;;
  argoworkflows) tok_secret="argoworkflows-argocd"; tok_ns="${J2026_ARGOWF_RUN_NAMESPACE}" ;;
  *)             tok_secret=""; tok_ns="" ;;
esac
if [[ -n "${tok_secret}" ]]; then
  kubectl create secret generic "${tok_secret}" -n "${tok_ns}" \
    --from-literal=token="${TOKEN}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log_info "Stored the ArgoCD token in '${tok_secret}' (${tok_ns})."
else
  # jenkins path: the token rides jenkins-credentials (handled by 04-jenkins.sh / 08.5); nothing to do here.
  log_info "engine=jenkins - the ArgoCD token is threaded via jenkins-credentials (08.5/04-jenkins), not a standalone secret."
fi
