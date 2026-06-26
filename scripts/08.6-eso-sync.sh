#!/usr/bin/env bash
# =============================================================================
# scripts/08.6-eso-sync.sh — wire up External Secrets Operator (eso mode only)
# =============================================================================
# Runs right AFTER 08.5-argocd.sh (which installs the ESO operator) and BEFORE the
# secret consumers (04-jenkins/tekton, 08-headlamp, 09-gateway). It is a NO-OP
# unless secrets.backend=eso.
#
# In eso mode, 01-namespaces.sh already pushed the secret VALUE to GCP Secret
# Manager (see scripts/lib/secrets.sh). Here we:
#   1. apply the ClusterSecretStore (gcp-store) that authenticates to Secret
#      Manager via Workload Identity (keyless),
#   2. apply an ExternalSecret per namespace that needs `gateway-iap-oauth`, and
#   3. wait for ESO to materialise the resulting k8s Secret in each namespace,
#      so the downstream steps find it.
#
# Scope (stage 1): the gateway IAP OAuth secret. jenkins-credentials (generated
# admin password), headlamp-credentials, and the per-mode observability
# credentials remain on their current path; see docs/201 § Secrets Management for
# the staged rollout.
# =============================================================================
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/secrets.sh"  # gcp_console_secret_url

# Active backend = explicit override → cluster detection → config default (so a
# standalone Day2 redeploy on an eso cluster syncs even without secrets_backend).
ACTIVE_SECRETS_BACKEND="$(j2026_active_secrets_backend)"
if [[ "${ACTIVE_SECRETS_BACKEND}" != "eso" ]]; then
  log_info "secrets.backend=${ACTIVE_SECRETS_BACKEND} (not eso) — skipping External Secrets sync."
  exit 0
fi

# Gateway disabled => no IAP secret to sync.
if [[ -z "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  log_info "gateway.baseDomain empty — no IAP secret to sync."
  exit 0
fi

log_step "Waiting for the External Secrets Operator (CRDs + controller) to be ready"
# ESO is installed ASYNCHRONOUSLY by ArgoCD (argocd/external-secrets-app.yaml,
# applied but NOT waited on by 08.5). Its CRDs only appear after ArgoCD's first
# sync of the chart, so we must wait for them to be registered + established
# BEFORE applying any ClusterSecretStore/ExternalSecret below — otherwise kubectl
# fails with: no matches for kind "ClusterSecretStore" in version
# "external-secrets.io/v1beta1".
eso_crds=(clustersecretstores.external-secrets.io externalsecrets.external-secrets.io)
deadline=$(( SECONDS + 300 ))
until kubectl get crd "${eso_crds[@]}" >/dev/null 2>&1; do
  if [[ $SECONDS -ge $deadline ]]; then
    log_error "External Secrets CRDs never appeared — is the external-secrets ArgoCD app synced?"
    log_error "Check: kubectl get application external-secrets -n argocd"
    exit 1
  fi
  log_info "  ... waiting for ArgoCD to install the External Secrets CRDs..."
  sleep 5
done
kubectl wait --for=condition=established --timeout=120s "${eso_crds[@]/#/crd/}"

# Controller + webhook deployments must also be ready: the ESO validating webhook
# admits the ClusterSecretStore/ExternalSecret resources we apply next.
kubectl rollout status deployment -n external-secrets \
  -l app.kubernetes.io/instance=external-secrets --timeout=5m 2>/dev/null || \
  log_warn "Could not confirm ESO rollout via label — continuing (apply will retry)."

# The ESO CONTROLLER is what reads Secret Manager, so it must run with the Workload
# Identity annotation mapping its KSA to the eso-secret-reader GSA (terraform/gke
# grants that GSA secretmanager.secretAccessor + binds it to this KSA). ArgoCD sets
# the same annotation from the chart (argocd/external-secrets-app.yaml) — we set it
# here too for immediacy (same value → no drift) and RESTART the controller: a pod
# created BEFORE the annotation existed won't adopt it (a pod's GCP identity is
# fixed at creation), which is exactly what happens on an idempotent re-run over an
# existing cluster. Without this the ExternalSecrets never sync (auth failure) and
# the wait below times out.
ESO_GSA_EMAIL="eso-secret-reader@$(gcloud config get-value project 2>/dev/null).iam.gserviceaccount.com"
log_step "Ensuring the ESO controller authenticates as ${ESO_GSA_EMAIL} (Workload Identity)"
kubectl annotate serviceaccount external-secrets -n external-secrets \
  "iam.gke.io/gcp-service-account=${ESO_GSA_EMAIL}" --overwrite
kubectl rollout restart deployment external-secrets -n external-secrets
kubectl rollout status deployment external-secrets -n external-secrets --timeout=3m 2>/dev/null || \
  log_warn "Could not confirm ESO controller restart — continuing (sync wait will catch auth failures)."

log_step "Applying the ClusterSecretStore (gcp-store → Secret Manager via Workload Identity)"
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-store
spec:
  provider:
    gcpsm:
      # projectID omitted → defaults to the hosting GKE node's project.
      # auth omitted → Workload Identity (the node SA needs roles/secretmanager.secretAccessor).
      auth: {}
EOF

# Namespaces that hold the gateway IAP secret — must match 01-namespaces.sh.
iap_namespaces=("${J2026_HEADLAMP_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}")
[[ "${J2026_OBS_MODE}" == "oss" ]] && iap_namespaces+=("${J2026_GRAFANA_OSS_NAMESPACE}")
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  iap_namespaces+=("${J2026_TEKTON_NAMESPACE}")
else
  iap_namespaces+=("${J2026_JENKINS_NAMESPACE}")
fi

for ns in "${iap_namespaces[@]}"; do
  kubectl get namespace "${ns}" >/dev/null 2>&1 || continue
  log_step "ExternalSecret ${J2026_GATEWAY_IAP_SECRET} → ${ns}"
  kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${J2026_GATEWAY_IAP_SECRET}
  namespace: ${ns}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-store
    kind: ClusterSecretStore
  target:
    name: ${J2026_GATEWAY_IAP_SECRET}
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: ${J2026_GATEWAY_IAP_SECRET}
EOF
done

log_step "Waiting for ESO to materialise the Secrets"
for ns in "${iap_namespaces[@]}"; do
  kubectl get namespace "${ns}" >/dev/null 2>&1 || continue
  deadline=$(( SECONDS + 120 ))
  until kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${ns}" >/dev/null 2>&1; do
    if [[ $SECONDS -ge $deadline ]]; then
      log_error "Timed out waiting for ESO to create ${J2026_GATEWAY_IAP_SECRET} in ${ns}."
      log_error "Check: kubectl describe externalsecret ${J2026_GATEWAY_IAP_SECRET} -n ${ns}"
      log_error "Source secret: $(gcp_console_secret_url "${J2026_GATEWAY_IAP_SECRET}")"
      exit 1
    fi
    sleep 3
  done
  log_info "OK: ${J2026_GATEWAY_IAP_SECRET} synced into ${ns}."
done

log_info "External Secrets sync complete."
