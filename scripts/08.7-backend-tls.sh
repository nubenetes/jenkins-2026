#!/usr/bin/env bash
# Backend TLS (LB→pod re-encryption) - OPT-IN via gateway.backendTls.enabled /
# JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED, default false. See
# docs/504-BACKEND_TLS.md for the full design.
#
# When ACTIVE (flag on AND the cluster serves the BackendTLSPolicy CRD - the
# shared j2026_backend_tls_active gate in lib/common.sh):
#   1. installs cert-manager GitOps-style (argocd/cert-manager-app.yaml, pinned
#      chart per docs/602) and waits for its CRDs + webhook - the same
#      "ArgoCD installs the chart asynchronously" wait pattern as
#      08.6-eso-sync.sh uses for the External Secrets Operator;
#   2. bootstraps a CLUSTER-INTERNAL CA: selfsigned ClusterIssuer -> CA
#      Certificate -> CA ClusterIssuer;
#   3. mints the per-backend server certificates (stage 1: Headlamp) and
#      projects the CA trust bundle as a ConfigMap (key ca.crt) into each
#      TLS-ready backend namespace - the caCertificateRefs target of the
#      BackendTLSPolicies scripts/09-gateway.sh generates.
# When INACTIVE: symmetric retire - removes the certs/trust ConfigMaps and the
# cert-manager Application left by a previous enabled run on this (persistent)
# cluster (09-gateway.sh retires the policies; 08.5-argocd.sh re-renders
# Headlamp back to plain HTTP), so flipping the flag off converges with no
# manual kubectl - the same deterministic-cleanup pattern as the grafana /
# develop-tier blocks in 09-gateway.sh.
#
# Everything here is in-cluster state that dies with the cluster: no external
# identity, no persistent residue - rebuild-safe by construction (docs/104).
# Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

if [[ -z "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  log_info "gateway.baseDomain / JENKINS2026_BASE_DOMAIN is empty - gateway disabled, backend TLS not applicable, skipping."
  exit 0
fi

if [[ "${J2026_PLATFORM}" != "gke" ]]; then
  log_info "platform.target='${J2026_PLATFORM}' - BackendTLSPolicy is GKE-specific, skipping."
  exit 0
fi

GENERATED_DIR="${J2026_ROOT_DIR}/.generated/backend-tls"

# Server-cert Secret name for the stage-1 backend. Must match secretName in
# helm/headlamp/values-backend-tls.yaml (the overlay 08.5-argocd.sh layers on).
HEADLAMP_TLS_SECRET="headlamp-tls"

# Namespaces holding a TLS-READY backend (stage 1: Headlamp). Each entry gets
# the CA trust ConfigMap when active, and both artifacts retired when not.
tls_backend_namespaces=("${J2026_HEADLAMP_NAMESPACE}")

if [[ "$(j2026_backend_tls_active)" != "true" ]]; then
  # --- retire: deterministic cleanup of a previous enabled run ---------------
  # (Flag off - the default - or the CRD is absent. A cluster that never had
  # the feature on hits only cheap --ignore-not-found no-ops here.)
  rm -rf "${GENERATED_DIR}"
  if kubectl get application cert-manager -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    log_step "Retiring backend TLS (backendTls inactive): cert-manager app + certs + trust bundles"
    # Delete while ArgoCD is alive so the resources-finalizer cascade-prunes
    # the chart. crds.keep=false in the app means the cert-manager CRDs go
    # too, garbage-collecting every Certificate/ClusterIssuer with them.
    # --wait=false keeps the run moving; ArgoCD finishes the prune async.
    kubectl delete application cert-manager -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
  fi
  for ns in "${tls_backend_namespaces[@]}"; do
    kubectl get namespace "${ns}" >/dev/null 2>&1 || continue
    kubectl delete configmap "${J2026_BACKEND_TLS_CA_CONFIGMAP}" -n "${ns}" --ignore-not-found
  done
  # cert-manager deliberately leaves issued Secrets behind when a Certificate
  # is deleted - drop the server cert so a re-enabled backend can never serve
  # a stale one (and so the plain-HTTP Headlamp doesn't keep a dead mount ref).
  if kubectl get namespace "${J2026_HEADLAMP_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${HEADLAMP_TLS_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" --ignore-not-found
  fi
  log_info "Backend TLS is off (gateway.backendTls.enabled=false is the default) - nothing more to do."
  exit 0
fi

# --- 1. cert-manager via ArgoCD ----------------------------------------------

log_step "Installing cert-manager via ArgoCD (backend TLS enabled)"
kubectl apply -f "${J2026_ROOT_DIR}/argocd/cert-manager-app.yaml"

# cert-manager is installed ASYNCHRONOUSLY by ArgoCD (exactly like the ESO
# chart in 08.6-eso-sync.sh): its CRDs only appear after the first sync, and
# the webhook must be admitting before the Issuer/Certificate CRs below can be
# applied - otherwise kubectl fails with 'no matches for kind "ClusterIssuer"'.
log_step "Waiting for the cert-manager CRDs + webhook"
cm_crds=(certificates.cert-manager.io clusterissuers.cert-manager.io)
deadline=$(( SECONDS + 300 ))
until kubectl get crd "${cm_crds[@]}" >/dev/null 2>&1; do
  if [[ $SECONDS -ge $deadline ]]; then
    log_error "cert-manager CRDs never appeared - is the cert-manager ArgoCD app synced?"
    log_error "Check: kubectl get application cert-manager -n ${J2026_ARGOCD_NAMESPACE}"
    exit 1
  fi
  log_info "  ... waiting for ArgoCD to install the cert-manager CRDs..."
  sleep 5
done
kubectl wait --for=condition=established --timeout=120s "${cm_crds[@]/#/crd/}"

# The webhook Deployment must EXIST before rollout status can wait on it
# (ArgoCD creates the CRDs before the Deployments - same race as the ESO
# controller in 08.6).
deadline=$(( SECONDS + 300 ))
until kubectl get deployment cert-manager-webhook -n "${J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1; do
  if [[ $SECONDS -ge $deadline ]]; then
    log_error "cert-manager-webhook Deployment never appeared - is the cert-manager ArgoCD app synced?"
    log_error "Check: kubectl get application cert-manager -n ${J2026_ARGOCD_NAMESPACE}; kubectl get deploy -n ${J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE}"
    exit 1
  fi
  log_info "  ... waiting for ArgoCD to create the cert-manager Deployments..."
  sleep 5
done
kubectl rollout status deployment -n "${J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE}" \
  -l app.kubernetes.io/instance=cert-manager --timeout=5m 2>/dev/null || \
  log_warn "Could not confirm the cert-manager rollout via label - continuing (the applies below retry)."

# --- 2. cluster-internal CA ----------------------------------------------------

mkdir -p "${GENERATED_DIR}"
log_step "Bootstrapping the cluster-internal CA (selfsigned root -> CA ClusterIssuer)"
cat >"${GENERATED_DIR}/ca.yaml" <<EOT
# Generated by scripts/08.7-backend-tls.sh from config/config.yaml - do not
# edit by hand, do not commit (see .gitignore).
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${J2026_BACKEND_TLS_SELFSIGNED_ISSUER}
spec:
  selfSigned: {}
---
# The root CA lives and dies with the (ephemeral) cluster: 10y >> any cluster
# lifetime, a rebuild simply mints a fresh CA, and nothing OUTSIDE the cluster
# ever trusts it (only the per-namespace trust ConfigMaps projected below).
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${J2026_BACKEND_TLS_CA_ISSUER}
  namespace: ${J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE}
spec:
  isCA: true
  commonName: jenkins-2026 internal CA
  secretName: ${J2026_BACKEND_TLS_CA_ISSUER}
  duration: 87600h # 10y
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: ${J2026_BACKEND_TLS_SELFSIGNED_ISSUER}
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${J2026_BACKEND_TLS_CA_ISSUER}
spec:
  ca:
    secretName: ${J2026_BACKEND_TLS_CA_ISSUER}
EOT
# The webhook can still reject the very first applies while its own serving
# cert warms up - bounded retry instead of failing the provision on a race.
deadline=$(( SECONDS + 180 ))
until kubectl apply -f "${GENERATED_DIR}/ca.yaml" >/dev/null 2>&1; do
  if [[ $SECONDS -ge $deadline ]]; then
    log_error "cert-manager webhook kept rejecting the CA bootstrap manifests:"
    kubectl apply -f "${GENERATED_DIR}/ca.yaml" || true # surface the real error
    exit 1
  fi
  log_info "  ... cert-manager webhook not admitting yet, retrying..."
  sleep 5
done
kubectl wait certificate "${J2026_BACKEND_TLS_CA_ISSUER}" \
  -n "${J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE}" --for=condition=Ready --timeout=180s

# --- 3. per-backend server certs + CA trust bundles ---------------------------

log_step "Minting the Headlamp server certificate (stage-1 TLS backend)"
# 01-namespaces.sh creates the headlamp namespace on Day1; ensure it exists for
# a standalone run of this script.
kubectl get namespace "${J2026_HEADLAMP_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${J2026_HEADLAMP_NAMESPACE}"
cat >"${GENERATED_DIR}/certificate-headlamp.yaml" <<EOT
# Generated by scripts/08.7-backend-tls.sh - do not edit by hand, do not
# commit. SAN = the Service FQDN, because the BackendTLSPolicy 09-gateway.sh
# generates sends exactly that hostname as SNI and validates the cert against
# it - keep the two in sync.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${HEADLAMP_TLS_SECRET}
  namespace: ${J2026_HEADLAMP_NAMESPACE}
spec:
  secretName: ${HEADLAMP_TLS_SECRET}
  commonName: ${J2026_HEADLAMP_RELEASE}.${J2026_HEADLAMP_NAMESPACE}.svc.cluster.local
  dnsNames:
    - ${J2026_HEADLAMP_RELEASE}.${J2026_HEADLAMP_NAMESPACE}.svc.cluster.local
    - ${J2026_HEADLAMP_RELEASE}.${J2026_HEADLAMP_NAMESPACE}.svc
  usages:
    - digital signature
    - key encipherment
    - server auth
  issuerRef:
    name: ${J2026_BACKEND_TLS_CA_ISSUER}
    kind: ClusterIssuer
    group: cert-manager.io
EOT
kubectl apply -f "${GENERATED_DIR}/certificate-headlamp.yaml"
kubectl wait certificate "${HEADLAMP_TLS_SECRET}" \
  -n "${J2026_HEADLAMP_NAMESPACE}" --for=condition=Ready --timeout=180s

log_step "Projecting the CA trust bundle into the TLS-ready backend namespaces"
# tls.crt of the (self-signed) CA Secret IS the trust anchor the LB validates
# against. Re-projected on every run (dry-run | apply - the same idempotent
# projection idiom as 09-gateway.sh's IAP client-secret), so a rotated CA
# converges without manual steps.
ca_pem="$(kubectl get secret "${J2026_BACKEND_TLS_CA_ISSUER}" \
  -n "${J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE}" -o jsonpath='{.data.tls\.crt}' | base64 -d)"
if [[ -z "${ca_pem}" ]]; then
  log_error "CA secret '${J2026_BACKEND_TLS_CA_ISSUER}' has no tls.crt - cannot project the trust bundle."
  exit 1
fi
for ns in "${tls_backend_namespaces[@]}"; do
  kubectl create configmap "${J2026_BACKEND_TLS_CA_CONFIGMAP}" -n "${ns}" \
    --from-literal=ca.crt="${ca_pem}" --dry-run=client -o yaml | kubectl apply -f -
done

log_info "Backend TLS ready: cert-manager installed, internal CA bootstrapped, headlamp cert minted."
log_info "  (08.5-argocd.sh layers the Headlamp TLS overlay; 09-gateway.sh attaches the BackendTLSPolicy.)"
