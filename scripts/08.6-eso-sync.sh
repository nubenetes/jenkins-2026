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
#   2. apply the ExternalSecrets (one per secret×namespace) via the emitters below
#      (plain extract / single-property / dockerconfigjson / basic-auth templates), and
#   3. wait for ESO to materialise the resulting k8s Secret in each namespace,
#      so the downstream steps find it.
#
# Scope: the gateway IAP OAuth secret (+ its single-key client-secret projection);
# the Tekton pipeline creds (tekton-github-webhook-secret, k6-cloud, the registry
# dockerconfigjson, the git basic-auth) when ci.engine=tekton; and ghcr-credentials.
# STILL imperative (generated/multi-writer/in-cluster-minted values that don't fit
# the "value already in Secret Manager" model): jenkins-credentials, headlamp-
# credentials, pac-webhook, grafana-jenkins-ds, tekton-argocd, and the per-mode
# observability backend credentials. See docs/201 § Secrets Management.
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

# NOTE: no blanket gateway early-exit here — the gateway IAP ExternalSecrets are
# guarded by J2026_GATEWAY_BASE_DOMAIN in the emit section below, so the NON-gateway
# secrets (Tekton pipeline creds, ghcr-credentials) still sync when the gateway is off.

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
# admits the ClusterSecretStore/ExternalSecret resources we apply next, and we
# annotate + restart the CONTROLLER below. ArgoCD creates the CRDs and the
# ServiceAccount BEFORE the Deployments, so wait for the controller Deployment to
# actually EXIST first — otherwise the `kubectl rollout restart` below fails with
# "deployments.apps external-secrets not found" and aborts the script (set -e). A
# label-only `rollout status` does NOT cover this: with no matching Deployment yet
# it returns immediately rather than waiting.
log_step "Waiting for the ESO controller Deployment (ArgoCD creates it after the CRDs/SA)"
deadline=$(( SECONDS + 300 ))
until kubectl get deployment external-secrets -n external-secrets >/dev/null 2>&1; do
  if [[ $SECONDS -ge $deadline ]]; then
    log_error "ESO controller Deployment 'external-secrets' never appeared — is the external-secrets ArgoCD app synced?"
    log_error "Check: kubectl get application external-secrets -n argocd; kubectl get deploy -n external-secrets"
    exit 1
  fi
  log_info "  ... waiting for ArgoCD to create the external-secrets Deployment..."
  sleep 5
done
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
GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${GCP_PROJECT}" ]]; then
  log_error "Could not resolve the active gcloud project — required for the ClusterSecretStore projectID + the ESO Workload Identity GSA."
  exit 1
fi
ESO_GSA_EMAIL="eso-secret-reader@${GCP_PROJECT}.iam.gserviceaccount.com"
log_step "Ensuring the ESO controller authenticates as ${ESO_GSA_EMAIL} (Workload Identity)"
kubectl annotate serviceaccount external-secrets -n external-secrets \
  "iam.gke.io/gcp-service-account=${ESO_GSA_EMAIL}" --overwrite
kubectl rollout restart deployment external-secrets -n external-secrets
kubectl rollout status deployment external-secrets -n external-secrets --timeout=3m 2>/dev/null || \
  log_warn "Could not confirm ESO controller restart — continuing (sync wait will catch auth failures)."

log_step "Applying the ClusterSecretStore (gcp-store → Secret Manager via Workload Identity)"
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-store
spec:
  provider:
    gcpsm:
      # ESO's gcpsm provider REQUIRES an explicit projectID — it does NOT fall back
      # to the GKE node's metadata project. Without it the store fails to even build
      # a client: "could not get provider client: unable to find ProjectID in
      # storeSpec" (Ready=False), so nothing ever syncs.
      projectID: ${GCP_PROJECT}
      # auth omitted → Workload Identity: the ESO controller pod runs as the
      # eso-secret-reader GSA (SA annotation + restart above).
      auth: {}
EOF

# --- ExternalSecret emitters --------------------------------------------------
# Each projects a GCP Secret Manager blob into a namespace and records
# "namespace|name" in EMITTED so the single wait pass below covers it. The blobs
# are pushed by scripts/lib/secrets.sh provision_secret (01-namespaces.sh etc.).
EMITTED=()

_es_open() {  # <name> <ns> — ExternalSecret header (through secretStoreRef)
  cat <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${1}
  namespace: ${2}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-store
    kind: ClusterSecretStore
EOF
}

# Project ALL keys of SM blob <key> into Secret <name> (Opaque).
es_extract() {  # <name> <ns> <key>
  kubectl get namespace "${2}" >/dev/null 2>&1 || return 0
  { _es_open "${1}" "${2}"; cat <<EOF
  target:
    name: ${1}
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: ${3}
EOF
  } | kubectl apply -f - >/dev/null
  EMITTED+=("${2}|${1}"); log_step "ExternalSecret ${1} → ${2} (extract ${3})"
}

# Project a SINGLE property of SM blob <key> into a one-key Secret (Opaque).
es_property() {  # <name> <ns> <key> <property> <out-key>
  kubectl get namespace "${2}" >/dev/null 2>&1 || return 0
  { _es_open "${1}" "${2}"; cat <<EOF
  target:
    name: ${1}
    creationPolicy: Owner
  data:
    - secretKey: ${5}
      remoteRef:
        key: ${3}
        property: ${4}
EOF
  } | kubectl apply -f - >/dev/null
  EMITTED+=("${2}|${1}"); log_step "ExternalSecret ${1} → ${2} (property ${3}.${4})"
}

# Build a kubernetes.io/dockerconfigjson Secret from username/password/registry
# keys of SM blob <key> (empty-auths when no username — matches the imperative path).
es_dockerconfig() {  # <name> <ns> <key>
  kubectl get namespace "${2}" >/dev/null 2>&1 || return 0
  { _es_open "${1}" "${2}"; cat <<EOF
  target:
    name: ${1}
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      engineVersion: v2
      data:
        .dockerconfigjson: |
          {{- if .username -}}
          {"auths":{"{{ .registry }}":{"username":"{{ .username }}","password":"{{ .password }}","auth":"{{ printf "%s:%s" .username .password | b64enc }}"}}}
          {{- else -}}
          {"auths":{}}
          {{- end -}}
  data:
    - secretKey: username
      remoteRef: { key: ${3}, property: username }
    - secretKey: password
      remoteRef: { key: ${3}, property: password }
    - secretKey: registry
      remoteRef: { key: ${3}, property: registry }
EOF
  } | kubectl apply -f - >/dev/null
  EMITTED+=("${2}|${1}"); log_step "ExternalSecret ${1} → ${2} (dockerconfigjson)"
}

# Build a kubernetes.io/basic-auth Secret (+ tekton.dev/git-0 annotation) from
# username/password keys of SM blob <key>.
es_basicauth() {  # <name> <ns> <key> <git-host>
  kubectl get namespace "${2}" >/dev/null 2>&1 || return 0
  { _es_open "${1}" "${2}"; cat <<EOF
  target:
    name: ${1}
    creationPolicy: Owner
    template:
      type: kubernetes.io/basic-auth
      engineVersion: v2
      metadata:
        annotations:
          tekton.dev/git-0: ${4}
      data:
        username: "{{ .username }}"
        password: "{{ .password }}"
  data:
    - secretKey: username
      remoteRef: { key: ${3}, property: username }
    - secretKey: password
      remoteRef: { key: ${3}, property: password }
EOF
  } | kubectl apply -f - >/dev/null
  EMITTED+=("${2}|${1}"); log_step "ExternalSecret ${1} → ${2} (basic-auth)"
}

# --- emit: gateway IAP secrets (only when the gateway is enabled) -------------
# Namespace membership must match 01-namespaces.sh / 09-gateway.sh.
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  iap_namespaces=("${J2026_HEADLAMP_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}")
  [[ "${J2026_OBS_MODE}" == "oss" ]] && iap_namespaces+=("${J2026_GRAFANA_OSS_NAMESPACE}")
  if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
    iap_namespaces+=("${J2026_TEKTON_NAMESPACE}")
  else
    iap_namespaces+=("${J2026_JENKINS_NAMESPACE}")
  fi
  for ns in "${iap_namespaces[@]}"; do
    es_extract  "${J2026_GATEWAY_IAP_SECRET}" "${ns}" "${J2026_GATEWAY_IAP_SECRET}"
    # the GCPBackendPolicy oauth2ClientSecret ref wants a single-key Secret.
    es_property "${J2026_GATEWAY_IAP_SECRET}-client-secret" "${ns}" \
      "${J2026_GATEWAY_IAP_SECRET}" "client_secret" "client_secret"
  done
fi

# --- emit: Tekton pipeline secrets (only when ci.engine=tekton) ---------------
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  tns="${J2026_TEKTON_PIPELINE_NAMESPACE}"
  es_extract      "tekton-github-webhook-secret"   "${tns}" "tekton-github-webhook-secret"
  es_extract      "k6-cloud"                        "${tns}" "k6-cloud"
  es_dockerconfig "${J2026_TEKTON_REGISTRY_SECRET}" "${tns}" "${J2026_TEKTON_REGISTRY_SECRET}"
  es_basicauth    "${J2026_TEKTON_GIT_SECRET}"      "${tns}" "${J2026_TEKTON_GIT_SECRET}" "https://github.com"
fi

# --- emit: microservices image pull secret (always) --------------------------
es_dockerconfig "ghcr-credentials" "${J2026_MICROSERVICES_NS_STABLE}" "ghcr-credentials"

# --- wait: every emitted Secret must materialise -----------------------------
log_step "Waiting for ESO to materialise the Secrets"
for pair in "${EMITTED[@]}"; do
  ns="${pair%%|*}"; name="${pair#*|}"
  deadline=$(( SECONDS + 120 ))
  until kubectl get secret "${name}" -n "${ns}" >/dev/null 2>&1; do
    if [[ $SECONDS -ge $deadline ]]; then
      log_error "Timed out waiting for ESO to create ${name} in ${ns}."
      log_error "Source secret: $(gcp_console_secret_url "${name}")"
      # Usual culprits: Workload Identity auth on the controller, or the JSON keys
      # in Secret Manager not matching the extract/property/template references.
      log_error "--- ExternalSecret status (${ns}) ---"
      kubectl get externalsecret "${name}" -n "${ns}" \
        -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' 2>/dev/null || true
      kubectl describe externalsecret "${name}" -n "${ns}" 2>/dev/null | grep -A20 -iE '^Events:' || true
      log_error "--- ClusterSecretStore gcp-store status ---"
      kubectl get clustersecretstore gcp-store \
        -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' 2>/dev/null || true
      log_error "--- ESO controller SA + logs (auth) ---"
      kubectl get serviceaccount external-secrets -n external-secrets \
        -o jsonpath='WI annotation: {.metadata.annotations.iam\.gke\.io/gcp-service-account}{"\n"}' 2>/dev/null || true
      kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets \
        --tail=40 --since=5m 2>/dev/null | grep -iE 'error|denied|forbid|token|identity' | tail -20 || true
      exit 1
    fi
    sleep 3
  done
  log_info "OK: ${name} synced into ${ns}."
done

log_info "External Secrets sync complete."
