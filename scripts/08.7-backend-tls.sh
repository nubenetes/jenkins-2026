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

# Namespaces holding a TLS-READY backend (stage 1: Headlamp; stage 2: the
# otel-collector faro receiver in the observability namespace; stage 4: pgAdmin).
# Each entry gets the CA trust ConfigMap when active, and both artifacts retired
# when not. Deduplicated in case two backends ever share a namespace.
tls_backend_namespaces=("${J2026_HEADLAMP_NAMESPACE}" "${J2026_OBS_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}")

# Stage 7: Java Hipster microservices (stable and optionally develop)
tls_backend_namespaces+=("${J2026_MICROSERVICES_NS_STABLE}")
if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
  tls_backend_namespaces+=("${J2026_MICROSERVICES_DEVELOP_NAMESPACE}")
fi

# argocd-server (stage 3) is TLS-ready only for engines whose deploy caller speaks
# TLS (jenkins/githubactions - see j2026_argocd_backend_tls_active). Tracked
# separately so the retire paths clean its cert/trust even when the global flag
# stays on but the engine changed (tekton/argo), and appended to the projection
# list only when active.
ARGOCD_TLS_ACTIVE="$(j2026_argocd_backend_tls_active)"
if [[ "${ARGOCD_TLS_ACTIVE}" == "true" ]]; then
  tls_backend_namespaces+=("${J2026_ARGOCD_NAMESPACE}")
fi

# Grafana (stage 5) is a TLS backend ONLY in observability.mode=oss (in-cluster
# Grafana; the managed backends live off-cluster). Its namespace defaults to the
# observability namespace (already listed above), so add it only when configured
# separately — that keeps the CA trust ConfigMap where the grafana BackendTLSPolicy
# (09) expects it without projecting a duplicate into the shared obs namespace.
if [[ "${J2026_OBS_MODE}" == "oss" && "${J2026_GRAFANA_OSS_NAMESPACE}" != "${J2026_OBS_NAMESPACE}" ]]; then
  tls_backend_namespaces+=("${J2026_GRAFANA_OSS_NAMESPACE}")
fi

# Jenkins (stage 6) is a TLS backend ONLY when it's the active CI engine (the
# controller namespace/Service don't exist otherwise). Tracked like argocd above:
# the retire path below cleans its cert/password Secret unconditionally (covers
# both flag-off and an engine switch away from jenkins), independent of this flag.
JENKINS_TLS_ACTIVE="false"
if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
  JENKINS_TLS_ACTIVE="true"
  tls_backend_namespaces+=("${J2026_JENKINS_NAMESPACE}")
fi

TEKTON_TLS_ACTIVE="false"
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  TEKTON_TLS_ACTIVE="true"
  tls_backend_namespaces+=("${J2026_TEKTON_NAMESPACE}")
fi

ARGOWF_TLS_ACTIVE="false"
if [[ "${J2026_CI_ENGINE}" == "argoworkflows" ]]; then
  ARGOWF_TLS_ACTIVE="true"
  tls_backend_namespaces+=("${J2026_ARGOWF_NAMESPACE}")
fi


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
  # is deleted - drop the server certs so a re-enabled backend can never serve
  # a stale one (and so the plain-HTTP backend doesn't keep a dead mount ref).
  if kubectl get namespace "${J2026_HEADLAMP_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${HEADLAMP_TLS_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_FARO}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_PGADMIN_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_PGADMIN}" -n "${J2026_PGADMIN_NAMESPACE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_GRAFANA_OSS_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_GRAFANA}" -n "${J2026_GRAFANA_OSS_NAMESPACE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
    kubectl delete secret "${J2026_BACKEND_TLS_JENKINS_JKS_PASSWORD_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_MICROSERVICES_NS_STABLE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_MICROSERVICES}" "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}" -n "${J2026_MICROSERVICES_NS_STABLE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_MICROSERVICES_DEVELOP_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_MICROSERVICES}" "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}" -n "${J2026_MICROSERVICES_DEVELOP_NAMESPACE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_TEKTON_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found
  fi
  if kubectl get namespace "${J2026_ARGOWF_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_ARGOWF}" -n "${J2026_ARGOWF_NAMESPACE}" --ignore-not-found
  fi

  # argocd trust bundle + server cert (its namespace is not in the projection list
  # when inactive, so clean it explicitly). 08.5 re-renders argocd-server --insecure.
  if kubectl get namespace "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete secret "${J2026_BACKEND_TLS_SECRET_ARGOCD}" -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found
    kubectl delete configmap "${J2026_BACKEND_TLS_CA_CONFIGMAP}" -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found
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

# Mint one per-backend server cert (Secret <secret> in <ns>, signed by the
# internal CA). SAN = the Service FQDN, because the BackendTLSPolicy 09-gateway.sh
# generates sends exactly that hostname as SNI and validates the cert against it
# - keep the two in sync. Also emits the short `.svc` form as a convenience SAN.
mint_server_cert() {
  local secret="$1" ns="$2" fqdn="$3" jks_password_secret="${4:-}" pkcs12_password_secret="${5:-}"
  local short="${fqdn%.cluster.local}" # e.g. headlamp.headlamp.svc
  # 01-namespaces.sh creates these namespaces on Day1; ensure they exist for a
  # standalone run of this script.
  kubectl get namespace "${ns}" >/dev/null 2>&1 || kubectl create namespace "${ns}"
  cat >"${GENERATED_DIR}/certificate-${secret}.yaml" <<EOT
# Generated by scripts/08.7-backend-tls.sh - do not edit by hand, do not commit.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${secret}
  namespace: ${ns}
spec:
  secretName: ${secret}
  # No commonName: X.509 caps it at 64 bytes and some FQDNs (e.g. the OSS
  # kube-prometheus-stack Grafana Service name + namespace) exceed that; SAN
  # (dnsNames) is what SNI/BackendTLSPolicy validation actually checks.
  dnsNames:
    - ${fqdn}
    - ${short}
  usages:
    - digital signature
    - key encipherment
    - server auth
  issuerRef:
    name: ${J2026_BACKEND_TLS_CA_ISSUER}
    kind: ClusterIssuer
    group: cert-manager.io
EOT
  # Jenkins only (stage 6): also emit a JKS keystore into the same Secret
  # (key keystore.jks), encrypted with the password in jks_password_secret - the
  # chart's controller.httpsKeyStore.jenkinsHttpsJksSecretName/PasswordSecretName
  # (values-backend-tls.yaml) read the same two Secrets.
  if [[ -n "${jks_password_secret}" ]]; then
    cat >>"${GENERATED_DIR}/certificate-${secret}.yaml" <<EOT
  keystores:
    jks:
      create: true
      passwordSecretRef:
        name: ${jks_password_secret}
        key: password
EOT
  fi
  # Microservices gateway only (stage 7): also emit a PKCS12 keystore into the same
  # Secret (key keystore.p12), encrypted with the password in pkcs12_password_secret.
  if [[ -n "${pkcs12_password_secret}" ]]; then
    cat >>"${GENERATED_DIR}/certificate-${secret}.yaml" <<EOT
  keystores:
    pkcs12:
      create: true
      passwordSecretRef:
        name: ${pkcs12_password_secret}
        key: password
EOT
  fi
  kubectl apply -f "${GENERATED_DIR}/certificate-${secret}.yaml"
  kubectl wait certificate "${secret}" -n "${ns}" --for=condition=Ready --timeout=180s
}

log_step "Minting the per-backend server certificates (SAN = Service FQDN)"
# Stage 1: Headlamp (admin UI, headlamp namespace).
mint_server_cert "${HEADLAMP_TLS_SECRET}" "${J2026_HEADLAMP_NAMESPACE}" \
  "${J2026_HEADLAMP_RELEASE}.${J2026_HEADLAMP_NAMESPACE}.svc.cluster.local"
# Stage 2: the otel-collector faro (RUM) receiver. One cert for the shared
# otel-collector-gateway Service (fullnameOverride, identical across obs modes);
# 03-observability.sh layers values-backend-tls.yaml so the faro receiver serves
# it on port 8027.
mint_server_cert "${J2026_BACKEND_TLS_SECRET_FARO}" "${J2026_OBS_NAMESPACE}" \
  "otel-collector-gateway.${J2026_OBS_NAMESPACE}.svc.cluster.local"
# Stage 4: pgAdmin (the platform-postgres admin UI). One cert for its runix-chart
# Service (${J2026_PGADMIN_RELEASE}-pgadmin4); the pgadmin child app layers
# helm/pgadmin/values-backend-tls.yaml (threaded by 08.5) so pgAdmin serves it on
# pod port 8443. Always active with the global flag (engine- and obs-mode-neutral).
mint_server_cert "${J2026_BACKEND_TLS_SECRET_PGADMIN}" "${J2026_PGADMIN_NAMESPACE}" \
  "${J2026_PGADMIN_RELEASE}-pgadmin4.${J2026_PGADMIN_NAMESPACE}.svc.cluster.local"
# Stage 5: the in-cluster OSS Grafana, ONLY in observability.mode=oss (doubly
# conditional — the managed backends live off-cluster). One cert for the
# kube-prometheus-stack Grafana Service (oss-kube-prometheus-stack-grafana); the
# observability-oss app-of-apps layers observability/grafana/values-oss-backend-tls.yaml
# (threaded by 03-observability.sh) so Grafana serves it on pod port 3000. 08.7 runs
# BEFORE 03 in up.sh, so the Secret exists before ArgoCD rolls Grafana with the overlay.
if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  mint_server_cert "${J2026_BACKEND_TLS_SECRET_GRAFANA}" "${J2026_GRAFANA_OSS_NAMESPACE}" \
    "oss-kube-prometheus-stack-grafana.${J2026_GRAFANA_OSS_NAMESPACE}.svc.cluster.local"
elif kubectl get namespace "${J2026_GRAFANA_OSS_NAMESPACE}" >/dev/null 2>&1; then
  # backend TLS globally on but obs mode isn't oss: retire any grafana cert left by a
  # prior oss run so nothing stale lingers (09 drops the BackendTLSPolicy; the non-oss
  # Grafana backend is off-cluster and never served this cert).
  kubectl delete secret "${J2026_BACKEND_TLS_SECRET_GRAFANA}" -n "${J2026_GRAFANA_OSS_NAMESPACE}" --ignore-not-found
fi
# Stage 3: argocd-server, ONLY for engines whose deploy caller speaks TLS
# (jenkins/githubactions). argocd-server watches the argocd-server-tls Secret.
if [[ "${ARGOCD_TLS_ACTIVE}" == "true" ]]; then
  mint_server_cert "${J2026_BACKEND_TLS_SECRET_ARGOCD}" "${J2026_ARGOCD_NAMESPACE}" \
    "argocd-server.${J2026_ARGOCD_NAMESPACE}.svc.cluster.local"
  # argocd-server hot-reloads the TLS Secret, but 08.5 (which drops --insecure) runs
  # BEFORE this script, so the server may have come up with a self-signed cert before
  # argocd-server-tls existed. Restart it so it deterministically serves the
  # cert-manager cert the LB (09) validates against.
  if kubectl get deployment argocd-server -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    log_step "Restarting argocd-server to load the cert-manager server certificate"
    kubectl rollout restart deployment argocd-server -n "${J2026_ARGOCD_NAMESPACE}" || \
      log_warn "Could not restart argocd-server - it should hot-reload argocd-server-tls on its own."
  fi
elif kubectl get namespace "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  # backend TLS on globally but argocd's engine gate is off (tekton/argo): retire any
  # argocd cert/trust from a prior jenkins/gha run so 09 drops the BackendTLSPolicy and
  # argocd-server (re-rendered --insecure by 08.5) stays plaintext for those callers.
  kubectl delete secret "${J2026_BACKEND_TLS_SECRET_ARGOCD}" -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found
  kubectl delete configmap "${J2026_BACKEND_TLS_CA_CONFIGMAP}" -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found
fi
# Stage 6: Jenkins, ONLY when it's the active CI engine (the controller
# namespace/Service don't exist otherwise). Unlike every other stage, the
# controller needs a JKS keystore (chart controller.httpsKeyStore), not a plain
# PEM cert - cert-manager encrypts it with a password from an existing Secret
# (passwordSecretRef; it does not create one), so mint that Secret first,
# once (create-if-absent: the password only protects a keystore that already
# lives inside an RBAC-protected, in-cluster-only, ephemeral-per-cluster Secret -
# regenerating it on every run would force a needless keystore re-issue).
if [[ "${JENKINS_TLS_ACTIVE}" == "true" ]]; then
  kubectl get namespace "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${J2026_JENKINS_NAMESPACE}"
  if ! kubectl get secret "${J2026_BACKEND_TLS_JENKINS_JKS_PASSWORD_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    log_step "Generating the Jenkins HTTPS keystore password (one-time, in-cluster only)"
    kubectl create secret generic "${J2026_BACKEND_TLS_JENKINS_JKS_PASSWORD_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
      --from-literal=password="$(openssl rand -base64 24)"
  fi
  mint_server_cert "${J2026_BACKEND_TLS_SECRET_JENKINS}" "${J2026_JENKINS_NAMESPACE}" \
    "${J2026_JENKINS_RELEASE}.${J2026_JENKINS_NAMESPACE}.svc.cluster.local" \
    "${J2026_BACKEND_TLS_JENKINS_JKS_PASSWORD_SECRET}"
elif kubectl get namespace "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
  # backend TLS on globally but ci.engine isn't jenkins: retire any jenkins cert/password
  # left by a prior jenkins run so 09 drops the BackendTLSPolicy and a re-enabled jenkins
  # engine never starts from a stale keystore.
  kubectl delete secret "${J2026_BACKEND_TLS_SECRET_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
  kubectl delete secret "${J2026_BACKEND_TLS_JENKINS_JKS_PASSWORD_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found
fi

# Stage 6.1: Tekton Dashboard, ONLY when it's the active CI engine.
if [[ "${TEKTON_TLS_ACTIVE}" == "true" ]]; then
  kubectl get namespace "${J2026_TEKTON_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${J2026_TEKTON_NAMESPACE}"
  mint_server_cert "${J2026_BACKEND_TLS_SECRET_TEKTON}" "${J2026_TEKTON_NAMESPACE}" \
    "${J2026_TEKTON_DASHBOARD_SERVICE}.${J2026_TEKTON_NAMESPACE}.svc.cluster.local"
elif kubectl get namespace "${J2026_TEKTON_NAMESPACE}" >/dev/null 2>&1; then
  # retire leftover certs
  kubectl delete secret "${J2026_BACKEND_TLS_SECRET_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found
fi

# Stage 6.2: Argo Workflows Server, ONLY when it's the active CI engine.
if [[ "${ARGOWF_TLS_ACTIVE}" == "true" ]]; then
  kubectl get namespace "${J2026_ARGOWF_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${J2026_ARGOWF_NAMESPACE}"
  mint_server_cert "${J2026_BACKEND_TLS_SECRET_ARGOWF}" "${J2026_ARGOWF_NAMESPACE}" \
    "${J2026_ARGOWF_SERVER_SERVICE}.${J2026_ARGOWF_NAMESPACE}.svc.cluster.local"
elif kubectl get namespace "${J2026_ARGOWF_NAMESPACE}" >/dev/null 2>&1; then
  # retire leftover certs
  kubectl delete secret "${J2026_BACKEND_TLS_SECRET_ARGOWF}" -n "${J2026_ARGOWF_NAMESPACE}" --ignore-not-found
fi

# Stage 7: Java Hipster microservices gateway.

# Stable tier
stable_ns="${J2026_MICROSERVICES_NS_STABLE}"
kubectl get namespace "${stable_ns}" >/dev/null 2>&1 || kubectl create namespace "${stable_ns}"
if ! kubectl get secret "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}" -n "${stable_ns}" >/dev/null 2>&1; then
  log_step "Generating the microservices gateway HTTPS keystore password (one-time, stable)"
  kubectl create secret generic "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}" -n "${stable_ns}" \
    --from-literal=password="$(openssl rand -base64 24)"
fi
mint_server_cert "${J2026_BACKEND_TLS_SECRET_MICROSERVICES}" "${stable_ns}" \
  "gateway.${stable_ns}.svc.cluster.local" "" "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}"

# Develop tier
if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
  dev_ns="${J2026_MICROSERVICES_DEVELOP_NAMESPACE}"
  kubectl get namespace "${dev_ns}" >/dev/null 2>&1 || kubectl create namespace "${dev_ns}"
  if ! kubectl get secret "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}" -n "${dev_ns}" >/dev/null 2>&1; then
    log_step "Generating the microservices gateway HTTPS keystore password (one-time, develop)"
    kubectl create secret generic "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}" -n "${dev_ns}" \
      --from-literal=password="$(openssl rand -base64 24)"
  fi
  mint_server_cert "${J2026_BACKEND_TLS_SECRET_MICROSERVICES}" "${dev_ns}" \
    "gateway.${dev_ns}.svc.cluster.local" "" "${J2026_BACKEND_TLS_MICROSERVICES_PASSWORD_SECRET}"
fi

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

log_info "Backend TLS ready: cert-manager installed, internal CA bootstrapped, headlamp + faro + pgadmin$([[ "${J2026_OBS_MODE}" == "oss" ]] && echo " + grafana")$([[ "${JENKINS_TLS_ACTIVE}" == "true" ]] && echo " + jenkins") certs minted."
log_info "  (08.5-argocd.sh layers the Headlamp + pgAdmin TLS overlays; 03-observability.sh layers the faro + oss-Grafana overlays;"
log_info "   04-jenkins.sh layers the Jenkins TLS overlay; 09-gateway.sh attaches the BackendTLSPolicies.)"
