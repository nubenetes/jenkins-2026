#!/usr/bin/env bash
# Backstage developer portal (backstage.enabled, default true - docs/505):
# deploys the argocd/backstage app-of-apps (CNPG database + the OFFICIAL
# backstage/charts chart running the custom image from backstage/), after
# writing the script-owned runtime ConfigMap the pod's env references and
# patching the ArgoCD plugin credentials into backstage-secrets. Exposure
# (HTTPRoute + IAP + the IAP JWT audience) is 09-gateway.sh's job.
#
# Flag off -> retires the Application (cascade-prunes the chart + the CNPG
# Cluster) and the runtime ConfigMap symmetrically, then no-ops. Idempotent.
#
# Ordering (scripts/up.sh): after 08.5-argocd (Application CRD + the CNPG
# operator wait + argocd-initial-admin-secret), 08.6-eso-sync (backstage-secrets
# materialised in eso mode) and 08.7-backend-tls (the backstage-tls cert must
# exist before the TLS-mode pod can mount it); right before 09-gateway.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

# --- retire path (flag off) ---------------------------------------------------
if [[ "${J2026_BACKSTAGE_ENABLED}" != "true" ]]; then
  log_step "Backstage disabled (backstage.enabled=false) - retiring any leftovers"
  if kubectl get application backstage -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    # Delete while ArgoCD is alive so the resources finalizer cascade-prunes the
    # child app, the chart and the CNPG Cluster (its PVC is reclaimed by CSI).
    kubectl delete application backstage -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false
    log_info "backstage ArgoCD app-of-apps deleted (cascade-prune in progress)."
  fi
  kubectl delete configmap "${J2026_BACKSTAGE_RUNTIME_CONFIGMAP}" \
    -n "${J2026_BACKSTAGE_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  rm -rf "${J2026_ROOT_DIR}/.generated/backstage"
  log_info "Backstage retire complete - nothing else to do."
  exit 0
fi

if ! kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  log_error "ArgoCD Application CRD not found - run scripts/08.5-argocd.sh first."
  exit 1
fi

BACKEND_TLS_ACTIVE="$(j2026_backend_tls_active)"

# --- 1. runtime ConfigMap (must exist BEFORE the pod starts) -------------------
# Script-owned, deliberately a ConfigMap (not part of backstage-secrets) so the
# eso-mode ExternalSecret can never clobber these derived keys - the
# grafana-base-url lesson (docs/505 § eso). backstage/app-config.yaml reads them
# via ${ENV} substitution through helm/backstage/values.yaml extraEnvVars.
log_step "Writing '${J2026_BACKSTAGE_RUNTIME_CONFIGMAP}' ConfigMap in ${J2026_BACKSTAGE_NAMESPACE}"

if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  bs_app_base_url="https://${J2026_GATEWAY_BACKSTAGE_HOST}"
else
  bs_app_base_url="http://localhost:7007"
fi

# The Jenkins plugin dials the controller Service in-cluster. Under backend TLS
# (docs/504 stage 6) the Service's 8080 becomes HTTPS and the plain listener is
# re-exposed on 8082 for in-cluster callers (agents do the same) - keep the
# plugin on plain HTTP either way. Engine-independent value: when the engine
# isn't jenkins the Service simply doesn't exist and the (hidden) tab would
# error if visited - harmless, and it keeps the app-config always-valid.
bs_jenkins_url="http://${J2026_JENKINS_RELEASE}.${J2026_JENKINS_NAMESPACE}.svc.cluster.local:8080"
if [[ "${J2026_CI_ENGINE}" == "jenkins" && "${BACKEND_TLS_ACTIVE}" == "true" ]]; then
  bs_jenkins_url="http://${J2026_JENKINS_RELEASE}.${J2026_JENKINS_NAMESPACE}.svc.cluster.local:8082"
fi

# The ArgoCD plugin dials argocd-server. Under backend TLS (stage 3) the server
# drops --insecure and serves TLS on its pod port - switch to https on the
# Service FQDN (the SAN of the cert-manager-minted argocd-server-tls cert);
# Node trusts the internal CA via NODE_EXTRA_CA_CERTS (values.yaml).
if [[ "${BACKEND_TLS_ACTIVE}" == "true" ]]; then
  bs_argocd_url="https://${J2026_ARGOCD_RELEASE}-server.${J2026_ARGOCD_NAMESPACE}.svc.cluster.local"
else
  bs_argocd_url="http://${J2026_ARGOCD_RELEASE}-server.${J2026_ARGOCD_NAMESPACE}.svc.cluster.local"
fi

# IAP_AUDIENCE is OWNED by 09-gateway.sh (it resolves the LB backend-service ID
# once the Gateway has programmed it). Preserve any value it already set;
# 'pending' keeps the gcpIap provider config non-empty until then.
bs_iap_audience="$(kubectl get configmap "${J2026_BACKSTAGE_RUNTIME_CONFIGMAP}" \
  -n "${J2026_BACKSTAGE_NAMESPACE}" -o jsonpath='{.data.IAP_AUDIENCE}' 2>/dev/null || true)"
bs_iap_audience="${bs_iap_audience:-pending}"

kubectl create configmap "${J2026_BACKSTAGE_RUNTIME_CONFIGMAP}" \
  -n "${J2026_BACKSTAGE_NAMESPACE}" \
  --from-literal=APP_BASE_URL="${bs_app_base_url}" \
  --from-literal=CI_ENGINE="${J2026_CI_ENGINE}" \
  --from-literal=CATALOG_BRANCH="${J2026_SELF_REPO_BRANCH}" \
  --from-literal=JENKINS_BASE_URL="${bs_jenkins_url}" \
  --from-literal=ARGOCD_BASE_URL="${bs_argocd_url}" \
  --from-literal=IAP_AUDIENCE="${bs_iap_audience}" \
  --from-literal=BASE_DOMAIN="${J2026_GATEWAY_BASE_DOMAIN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- 2. ArgoCD plugin credentials ----------------------------------------------
# Patched onto the LIVE Secret (not seeded by 01) because the value is minted
# in-cluster by ArgoCD at deploy time - exactly like the jenkins-credentials
# argocd-token. In eso mode the ExternalSecret projects with creationPolicy
# Merge (08.6), so this patch survives the periodic re-sync.
log_step "Patching ArgoCD credentials into '${J2026_BACKSTAGE_SECRETS_NAME}'"
argocd_admin_pw="$(kubectl get secret argocd-initial-admin-secret -n "${J2026_ARGOCD_NAMESPACE}" \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
if [[ -n "${argocd_admin_pw}" ]] \
   && kubectl get secret "${J2026_BACKSTAGE_SECRETS_NAME}" -n "${J2026_BACKSTAGE_NAMESPACE}" >/dev/null 2>&1; then
  kubectl patch secret "${J2026_BACKSTAGE_SECRETS_NAME}" -n "${J2026_BACKSTAGE_NAMESPACE}" \
    --type=merge -p "$(cat <<EOF
{"stringData":{"ARGOCD_USERNAME":"admin","ARGOCD_PASSWORD":"${argocd_admin_pw}"}}
EOF
)" >/dev/null
  log_info "ARGOCD_USERNAME/ARGOCD_PASSWORD patched (from argocd-initial-admin-secret)."
else
  log_warn "argocd-initial-admin-secret (or ${J2026_BACKSTAGE_SECRETS_NAME}) not readable - the"
  log_warn "Backstage ArgoCD tab will show auth errors until a re-run patches the credentials."
fi

# --- 3. apply the app-of-apps ---------------------------------------------------
log_step "Configuring Backstage via ArgoCD (app-of-apps: CNPG db + official chart)"
BACKSTAGE_APP_FILE=$(mktemp)
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
# Image coordinates: config.yaml backstage.image.repository split into the
# chart's registry/repository halves; the tag auto-tracks the deploy branch
# (J2026_BACKSTAGE_IMAGE_TAG, see lib/config.sh).
bs_image_registry="${J2026_BACKSTAGE_IMAGE_REPO%%/*}"
bs_image_repository="${J2026_BACKSTAGE_IMAGE_REPO#*/}"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
     s@{{backendTls}}@${BACKEND_TLS_ACTIVE}@g;
     s@{{chartVersion}}@${J2026_BACKSTAGE_CHART_VERSION}@g;
     s@{{imageRegistry}}@${bs_image_registry}@g;
     s@{{imageRepository}}@${bs_image_repository}@g;
     s@{{imageTag}}@${J2026_BACKSTAGE_IMAGE_TAG}@g" \
    "${J2026_ROOT_DIR}/argocd/backstage-app.yaml" > "${BACKSTAGE_APP_FILE}"
kubectl apply -f "${BACKSTAGE_APP_FILE}"
rm "${BACKSTAGE_APP_FILE}"

# Restart an existing deployment so it picks up refreshed secrets/ConfigMap and
# (pullPolicy: Always + moving branch tag) the latest published image - the
# 08-headlamp pattern.
if kubectl get deployment backstage -n "${J2026_BACKSTAGE_NAMESPACE}" >/dev/null 2>&1; then
  log_info "Restarting the Backstage deployment to pick up updated config/secrets/image..."
  kubectl rollout restart deployment/backstage -n "${J2026_BACKSTAGE_NAMESPACE}"
fi

# --- 4. backend-TLS NEG-deadlock guard (mirror 08-headlamp, docs/504) -----------
# Under backend TLS the pod serves HTTPS while the GCP LB defaults to HTTP
# probes - applying the BackendTLSPolicy + HTTPS HealthCheckPolicy BEFORE
# waiting for the rollout breaks the NEG readiness-gate deadlock. 09-gateway.sh
# re-asserts (and retires) the same objects.
if [[ "${BACKEND_TLS_ACTIVE}" == "true" ]]; then
  log_step "Applying backstage BackendTLSPolicy + HTTPS HealthCheckPolicy (rollout-deadlock guard)"
  mkdir -p "${J2026_ROOT_DIR}/.generated/backstage"

  cat >"${J2026_ROOT_DIR}/.generated/backstage/backendtlspolicy-backstage.yaml" <<EOT
apiVersion: gateway.networking.k8s.io/v1
kind: BackendTLSPolicy
metadata:
  name: ${J2026_BACKEND_TLS_POLICY_BACKSTAGE}
  namespace: ${J2026_BACKSTAGE_NAMESPACE}
spec:
  targetRefs:
    - group: ""
      kind: Service
      name: backstage
  validation:
    hostname: backstage.${J2026_BACKSTAGE_NAMESPACE}.svc.cluster.local
    caCertificateRefs:
      - group: ""
        kind: ConfigMap
        name: ${J2026_BACKEND_TLS_CA_CONFIGMAP}
EOT

  cat >"${J2026_ROOT_DIR}/.generated/backstage/healthcheckpolicy-backstage.yaml" <<EOT
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: backstage
  namespace: ${J2026_BACKSTAGE_NAMESPACE}
spec:
  default:
    config:
      type: HTTPS
      httpsHealthCheck:
        requestPath: /.backstage/health/v1/readiness
  targetRef:
    group: ""
    kind: Service
    name: backstage
EOT

  kubectl apply -f "${J2026_ROOT_DIR}/.generated/backstage/backendtlspolicy-backstage.yaml"
  kubectl apply -f "${J2026_ROOT_DIR}/.generated/backstage/healthcheckpolicy-backstage.yaml"
fi

# --- 5. wait (non-fatal - graceful first-run degradation) -----------------------
# The deployment only appears after ArgoCD syncs wave 1 (once the CNPG Cluster
# is Healthy, ~1-2 min on a fresh provision). Bounded existence wait, then the
# non-fatal NEG-aware rollout wait (09 completes the LB half afterwards).
log_step "Waiting for the Backstage deployment (non-fatal)"
_deadline=$(( SECONDS + 300 ))
until kubectl get deployment backstage -n "${J2026_BACKSTAGE_NAMESPACE}" >/dev/null 2>&1; do
  if [[ ${SECONDS} -ge ${_deadline} ]]; then
    log_warn "Deployment backstage not created within 5m (ArgoCD still syncing the db/chart?)."
    log_warn "Non-fatal - check 'kubectl get application backstage backstage-db -n ${J2026_ARGOCD_NAMESPACE}' and re-run."
    break
  fi
  sleep 10
done
if kubectl get deployment backstage -n "${J2026_BACKSTAGE_NAMESPACE}" >/dev/null 2>&1; then
  wait_neg_backend_rollout backstage "${J2026_BACKSTAGE_NAMESPACE}" "5m"
  # ONE-TIME BOOTSTRAP hint (docs/505): the custom image must have been
  # published once (Day2.publish.06-backstage) - GHCR keeps it across rebuilds.
  if kubectl get pods -n "${J2026_BACKSTAGE_NAMESPACE}" -l app.kubernetes.io/name=backstage \
       -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null \
       | grep -qE 'ImagePullBackOff|ErrImagePull'; then
    log_warn "════════════════════════════════════════════════════════════════════════"
    log_warn "Backstage image ${J2026_BACKSTAGE_IMAGE_REPO}:${J2026_BACKSTAGE_IMAGE_TAG} is not pullable."
    log_warn "Run the one-time 'Day2.publish.06-backstage' workflow (branch '${J2026_BACKSTAGE_IMAGE_TAG}')"
    log_warn "to build+push it - the image persists across cluster rebuilds. Then re-run"
    log_warn "this step (or Day2.redeploy.08-backstage). Everything else is already wired."
    log_warn "════════════════════════════════════════════════════════════════════════"
  fi
fi

log_info "Backstage configured. 09-gateway.sh exposes it at https://${J2026_GATEWAY_BACKSTAGE_HOST}"
log_info "(IAP-protected; the IAP JWT audience is resolved+patched there too)."
