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

# Monitoring-tab Grafana coordinates (docs/505 § Grafana integration). ALL
# THREE keys are ALWAYS written non-empty in EVERY observability.mode - the
# proxy-backend validates its target URL at startup, and this app has already
# been bitten by the empty-string config class (docs/505 § Troubleshooting).
# Live values for oss / grafana-cloud; inert placeholders for managed-azure /
# managed-aws, whose tab is a deep-link InfoCard that never dials the proxy
# (decision record: docs/505 § Why the managed modes are deferred).
read_obs_secret_key() { # <secret> <key> -> value ('' if absent) - 04-jenkins.sh pattern
  kubectl get secret "$1" -n "${J2026_OBS_NAMESPACE}" \
    -o jsonpath="{.data.$2}" 2>/dev/null | base64 -d || true
}
bs_grafana_inert_target="https://grafana.invalid" # RFC 2606: parseable, never resolvable
case "${J2026_OBS_MODE}" in
  oss)
    # In-cluster Service target for the proxy; under backend TLS Grafana's
    # listener flips to HTTPS (values-oss-backend-tls.yaml) and its cert SAN
    # is exactly this FQDN - Node trusts the internal CA via
    # NODE_EXTRA_CA_CERTS, the same trust path the ArgoCD plugin uses.
    if [[ "${BACKEND_TLS_ACTIVE}" == "true" ]]; then
      bs_grafana_proxy_target="https://oss-kube-prometheus-stack-grafana.${J2026_GRAFANA_OSS_NAMESPACE}.svc.cluster.local"
    else
      bs_grafana_proxy_target="http://oss-kube-prometheus-stack-grafana.${J2026_GRAFANA_OSS_NAMESPACE}.svc.cluster.local"
    fi
    if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
      bs_grafana_domain="https://${J2026_GATEWAY_GRAFANA_HOST}"
    else
      bs_grafana_domain="http://localhost:3000"
    fi
    ;;
  grafana-cloud)
    # The stack URL (written into the collector credentials Secret by Day1)
    # doubles as proxy target and link base - the same key 04-jenkins.sh reads
    # for its Grafana banner links.
    bs_grafana_domain="$(read_obs_secret_key "${J2026_GRAFANA_CLOUD_SECRET}" GRAFANA_BASE_URL)"
    bs_grafana_domain="${bs_grafana_domain:-unset}"
    if [[ "${bs_grafana_domain}" != "unset" ]]; then
      bs_grafana_proxy_target="${bs_grafana_domain}"
    else
      bs_grafana_proxy_target="${bs_grafana_inert_target}"
    fi
    ;;
  managed-azure)
    bs_grafana_domain="$(read_obs_secret_key "${J2026_AZURE_MONITOR_SECRET}" GRAFANA_BASE_URL)"
    bs_grafana_domain="${bs_grafana_domain:-unset}"
    bs_grafana_proxy_target="${bs_grafana_inert_target}"
    ;;
  managed-aws)
    bs_grafana_domain="$(read_obs_secret_key "${J2026_AWS_MANAGED_SECRET}" GRAFANA_BASE_URL)"
    bs_grafana_domain="${bs_grafana_domain:-unset}"
    bs_grafana_proxy_target="${bs_grafana_inert_target}"
    ;;
  *)
    bs_grafana_domain="unset"
    bs_grafana_proxy_target="${bs_grafana_inert_target}"
    ;;
esac

kubectl create configmap "${J2026_BACKSTAGE_RUNTIME_CONFIGMAP}" \
  -n "${J2026_BACKSTAGE_NAMESPACE}" \
  --from-literal=APP_BASE_URL="${bs_app_base_url}" \
  --from-literal=CI_ENGINE="${J2026_CI_ENGINE}" \
  --from-literal=CATALOG_BRANCH="${J2026_SELF_REPO_BRANCH}" \
  --from-literal=JENKINS_BASE_URL="${bs_jenkins_url}" \
  --from-literal=ARGOCD_BASE_URL="${bs_argocd_url}" \
  --from-literal=IAP_AUDIENCE="${bs_iap_audience}" \
  --from-literal=BASE_DOMAIN="${J2026_GATEWAY_BASE_DOMAIN}" \
  --from-literal=OBS_MODE="${J2026_OBS_MODE}" \
  --from-literal=GRAFANA_DOMAIN="${bs_grafana_domain}" \
  --from-literal=GRAFANA_PROXY_TARGET="${bs_grafana_proxy_target}" \
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

# --- 2a. Wait for the oss observability stack to converge before minting ------
# STRUCTURAL FIX for a live-found race (2026-07-13, docs/505 § Monitoring tab):
# the §2b mint below used to run while oss-kube-prometheus-stack's OWN initial
# ArgoCD sync was still applying. Grafana can be briefly Available (the OLD
# ReplicaSet) while that sync is mid-flight; when it finishes moments later, a
# values/checksum change rolls a NEW Grafana pod - and oss Grafana keeps
# service-account tokens in its EPHEMERAL in-pod SQLite, so the roll silently
# invalidates a token minted seconds earlier (live incident: minted 14:42:29,
# sync's final apply rolled the pod at 14:45:07 - tab 401'd until a manual
# re-mint). Bounded wait (3 min, WARN not fail - the mint below still has its
# own keep-if-valid + re-run heal as a second line of defense) for the
# Application to be Synced+Healthy with no operation in flight, so the mint
# lands on the post-converge pod instead of racing it.
if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  log_step "Waiting for oss-kube-prometheus-stack to converge before minting the Grafana token"
  gf_wait_deadline=$((SECONDS + 180))
  gf_converged="false"
  while [[ ${SECONDS} -lt ${gf_wait_deadline} ]]; do
    gf_app_json="$(kubectl get application oss-kube-prometheus-stack -n "${J2026_ARGOCD_NAMESPACE}" \
      -o json 2>/dev/null || true)"
    if [[ -z "${gf_app_json}" ]]; then
      # Application not applied yet at this point in the run - nothing to
      # converge on (a subsequent 08.95 re-run will catch up).
      break
    fi
    gf_sync_status="$(echo "${gf_app_json}" | jq -r '.status.sync.status // empty')"
    gf_health_status="$(echo "${gf_app_json}" | jq -r '.status.health.status // empty')"
    gf_op_phase="$(echo "${gf_app_json}" | jq -r '.status.operationState.phase // empty')"
    if [[ "${gf_sync_status}" == "Synced" && "${gf_health_status}" == "Healthy" \
          && "${gf_op_phase}" != "Running" ]]; then
      gf_converged="true"
      break
    fi
    sleep 5
  done
  if [[ "${gf_converged}" == "true" ]]; then
    log_info "oss-kube-prometheus-stack Synced+Healthy - safe to mint the Grafana token."
  else
    log_warn "oss-kube-prometheus-stack did not reach Synced+Healthy within 180s -"
    log_warn "minting the Grafana token anyway; a rollout during/after this run may"
    log_warn "still invalidate it (re-run this step or Day2.redeploy.08 to heal)."
  fi
fi

# --- 2b. Grafana Viewer token for the Monitoring tab (oss only) -----------------
# The '/grafana/api' proxy endpoint sends 'Authorization: Bearer ${GRAFANA_TOKEN}'
# (backstage/app-config.yaml). grafana-cloud threads a Terraform-minted stack
# token through Day1 into 01-namespaces.sh; the managed modes never call the
# proxy (deep-link card - decision record in docs/505). oss has no Terraform
# hand to mint one, so mint it HERE against the in-cluster Grafana API - curl
# exec'd INSIDE the Grafana container (localhost:3000: no Service, DNS or
# NetworkPolicy dependency), admin creds from the kube-prometheus-stack Secret.
# KEEP-IF-VALID (docs/104 reconcile-to-current): an existing token that still
# answers /api/search is left alone; otherwise mint a fresh Viewer token
# (pruning this script's older ones - bounded growth) and PATCH it into
# backstage-secrets - the ARGOCD_* pattern, surviving the eso Merge re-sync.
# Every failure path is a WARN, not an exit: the portal deploys fine and the
# Monitoring tab 401s until a re-run heals it (Day2.redeploy.08 suffices).
if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  log_step "Ensuring the oss Grafana Viewer token for the Backstage Monitoring tab"
  gf_ns="${J2026_GRAFANA_OSS_NAMESPACE}"
  gf_deploy="oss-kube-prometheus-stack-grafana"
  # Grafana's listener under backend TLS is HTTPS with SERVICE-FQDN SANs only
  # (mint_server_cert in 08.7) - loopback isn't in them, hence -k here. The
  # PROXY's trust story is unaffected (it dials the FQDN, Node validates
  # against the internal CA); this exec is a localhost control-plane call.
  gf_url="http://localhost:3000"
  gf_curl_opts=""
  if [[ "${BACKEND_TLS_ACTIVE}" == "true" ]]; then
    gf_url="https://localhost:3000"
    gf_curl_opts="-k"
  fi
  gf_curl() { # curl inside the grafana container; args appended verbatim
    # shellcheck disable=SC2086 # gf_curl_opts is deliberately word-split
    kubectl exec -n "${gf_ns}" "deploy/${gf_deploy}" -c grafana -- \
      curl -s ${gf_curl_opts} --max-time 10 "$@" 2>/dev/null
  }
  gf_avail="$(kubectl get deployment "${gf_deploy}" -n "${gf_ns}" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  if [[ "${gf_avail:-0}" -ge 1 ]]; then
    gf_existing_token="$(kubectl get secret "${J2026_BACKSTAGE_SECRETS_NAME}" -n "${J2026_BACKSTAGE_NAMESPACE}" \
      -o jsonpath='{.data.GRAFANA_TOKEN}' 2>/dev/null | base64 -d || true)"
    gf_token_ok="false"
    if [[ -n "${gf_existing_token}" && "${gf_existing_token}" != "unset" ]]; then
      gf_code="$(gf_curl -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${gf_existing_token}" \
        "${gf_url}/api/search?limit=1" || true)"
      [[ "${gf_code}" == "200" ]] && gf_token_ok="true"
    fi
    if [[ "${gf_token_ok}" == "true" ]]; then
      log_info "Existing GRAFANA_TOKEN still valid against Grafana - keeping it."
    else
      gf_admin_user="$(kubectl get secret "${gf_deploy}" -n "${gf_ns}" \
        -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d || true)"
      gf_admin_pw="$(kubectl get secret "${gf_deploy}" -n "${gf_ns}" \
        -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)"
      gf_new_token=""
      if [[ -n "${gf_admin_user}" && -n "${gf_admin_pw}" ]]; then
        gf_api() { gf_curl -u "${gf_admin_user}:${gf_admin_pw}" "$@"; }
        # Service account 'backstage' (Viewer): find-or-create, idempotent.
        gf_sa_id="$(gf_api "${gf_url}/api/serviceaccounts/search?query=backstage" \
          | jq -r '.serviceAccounts[]? | select(.name=="backstage") | .id' 2>/dev/null | head -n1 || true)"
        if [[ -z "${gf_sa_id}" ]]; then
          gf_sa_id="$(gf_api -X POST -H 'Content-Type: application/json' \
            -d '{"name":"backstage","role":"Viewer"}' \
            "${gf_url}/api/serviceaccounts" | jq -r '.id // empty' 2>/dev/null || true)"
        fi
        if [[ -n "${gf_sa_id}" ]]; then
          # Prune this integration's older tokens (invalid/rotated ones).
          for gf_tid in $(gf_api "${gf_url}/api/serviceaccounts/${gf_sa_id}/tokens" \
              | jq -r '.[]? | select(.name | startswith("backstage-")) | .id' 2>/dev/null || true); do
            gf_api -X DELETE "${gf_url}/api/serviceaccounts/${gf_sa_id}/tokens/${gf_tid}" >/dev/null || true
          done
          gf_new_token="$(gf_api -X POST -H 'Content-Type: application/json' \
            -d "{\"name\":\"backstage-$(date +%s)\"}" \
            "${gf_url}/api/serviceaccounts/${gf_sa_id}/tokens" | jq -r '.key // empty' 2>/dev/null || true)"
        fi
      fi
      if [[ -n "${gf_new_token}" ]] \
         && kubectl get secret "${J2026_BACKSTAGE_SECRETS_NAME}" -n "${J2026_BACKSTAGE_NAMESPACE}" >/dev/null 2>&1; then
        kubectl patch secret "${J2026_BACKSTAGE_SECRETS_NAME}" -n "${J2026_BACKSTAGE_NAMESPACE}" \
          --type=merge -p "$(cat <<EOF
{"stringData":{"GRAFANA_TOKEN":"${gf_new_token}"}}
EOF
)" >/dev/null
        log_info "Minted a fresh Grafana Viewer token (service account 'backstage') and patched it in."
      else
        log_warn "Could not mint/patch a Grafana token (Grafana API or ${J2026_BACKSTAGE_SECRETS_NAME} unavailable) -"
        log_warn "the Monitoring tab will show 401s until a re-run of this step heals it."
      fi
    fi
  else
    log_warn "Grafana deployment '${gf_deploy}' not Available in ${gf_ns} - skipping the token mint."
    log_warn "The Monitoring tab will 401 until a re-run (Day2.redeploy.08) once Grafana is up."
  fi
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
     s@{{ciEngine}}@${J2026_CI_ENGINE}@g;
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
    log_warn "Non-fatal - check 'kubectl get application backstage backstage-chart -n ${J2026_ARGOCD_NAMESPACE}' and re-run."
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
