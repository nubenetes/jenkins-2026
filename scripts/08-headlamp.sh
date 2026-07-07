#!/usr/bin/env bash
# Installs Headlamp (kubernetes-sigs/headlamp) - a web UI for managing this
# cluster - into ${J2026_HEADLAMP_NAMESPACE}, wired to Google OIDC login via
# the "${J2026_HEADLAMP_CREDENTIALS_SECRET}" Secret (created by
# scripts/01-namespaces.sh), and grants cluster-admin to every email in
# J2026_HEADLAMP_ADMIN_EMAILS via a ClusterRoleBinding. See README.md
# "Headlamp" for the access model, OAuth client setup and caveats. Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

# If deployment exists, restart it to pick up any potentially updated secrets.
if kubectl get deployment/"${J2026_HEADLAMP_RELEASE}" -n "${J2026_HEADLAMP_NAMESPACE}" >/dev/null 2>&1; then
  log_info "Restarting Headlamp deployment to pick up updated secrets..."
  kubectl rollout restart deployment/"${J2026_HEADLAMP_RELEASE}" -n "${J2026_HEADLAMP_NAMESPACE}"
fi

# GKE Gateway NEG health check deadlock fix (docs/504): GKE container-native load
# balancing (NEG) requires the pod to be HEALTHY in the GCP Load Balancer to satisfy
# the pod's `cloud.google.com/load-balancer-neg-ready` readiness gate during a rollout.
# But when Backend TLS is active, the pod serves HTTPS while the GCP LB defaults to
# HTTP probes (causing TLS handshake errors / connection refused), creating a deadlock.
# Applying the BackendTLSPolicy and HealthCheckPolicy (HTTPS) BEFORE waiting for the
# deployment rollout breaks this deadlock and lets the pods go healthy.
if [[ "$(j2026_backend_tls_active)" == "true" ]]; then
  log_step "Applying headlamp BackendTLSPolicy + HTTPS HealthCheckPolicy to prevent rollout deadlock"
  mkdir -p "${J2026_ROOT_DIR}/.generated/headlamp"
  
  cat >"${J2026_ROOT_DIR}/.generated/headlamp/backendtlspolicy-headlamp.yaml" <<EOT
apiVersion: gateway.networking.k8s.io/v1
kind: BackendTLSPolicy
metadata:
  name: ${J2026_BACKEND_TLS_POLICY_HEADLAMP}
  namespace: ${J2026_HEADLAMP_NAMESPACE}
spec:
  targetRefs:
    - group: ""
      kind: Service
      name: ${J2026_HEADLAMP_RELEASE}
  validation:
    hostname: ${J2026_HEADLAMP_RELEASE}.${J2026_HEADLAMP_NAMESPACE}.svc.cluster.local
    caCertificateRefs:
      - group: ""
        kind: ConfigMap
        name: ${J2026_BACKEND_TLS_CA_CONFIGMAP}
EOT

  cat >"${J2026_ROOT_DIR}/.generated/headlamp/healthcheckpolicy-headlamp.yaml" <<EOT
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: ${J2026_HEADLAMP_RELEASE}
  namespace: ${J2026_HEADLAMP_NAMESPACE}
spec:
  default:
    config:
      type: HTTPS
      httpsHealthCheck:
        requestPath: /
  targetRef:
    group: ""
    kind: Service
    name: ${J2026_HEADLAMP_RELEASE}
EOT

  kubectl apply -f "${J2026_ROOT_DIR}/.generated/headlamp/backendtlspolicy-headlamp.yaml"
  kubectl apply -f "${J2026_ROOT_DIR}/.generated/headlamp/healthcheckpolicy-headlamp.yaml"
fi

# Headlamp is a GKE NEG backend fronted by the Gateway/IAP, so its rollout wait can
# deadlock on a HealthCheckPolicy protocol mismatch until 09-gateway.sh reconciles it -
# and 09 runs AFTER this script. The bite is the DISABLE (backend_tls true->off) switch:
# the unconditional restart above brings up a plain-HTTP headlamp, but the HTTPS-HC
# reorder above is gated on backend TLS being ACTIVE, so a STALE HTTPS HealthCheckPolicy
# from the prior enabled run lingers and fails the NEG health check until 09 deletes it.
# wait_for_deployment would hard-fail AND self-heal by restarting (resetting the NEG,
# thrashing the rollout). Use the non-fatal, no-restart NEG-aware wait; 09 makes the pod
# NEG-healthy. Same class as the argocd-server fix (docs/504 § backend-TLS idempotency).
wait_neg_backend_rollout "${J2026_HEADLAMP_RELEASE}" "${J2026_HEADLAMP_NAMESPACE}" "5m"

log_step "Granting cluster-admin to Headlamp admin emails"
if [[ -z "${J2026_HEADLAMP_ADMIN_EMAILS}" ]]; then
  log_info "headlamp.adminEmails / JENKINS2026_HEADLAMP_ADMIN_EMAILS is empty - no ClusterRoleBindings created."
  log_info "See README.md \"Headlamp\" to grant your Google account access."
else
  IFS=',' read -ra admin_emails <<<"${J2026_HEADLAMP_ADMIN_EMAILS}"
  for email in "${admin_emails[@]}"; do
    email="$(echo "${email}" | xargs)" # trim whitespace
    [[ -z "${email}" ]] && continue
    # Sanitize email into a valid resource name (RFC 1123): lowercase,
    # '@'/'.'/'+' -> '-'.
    binding_name="headlamp-admin-$(echo "${email}" | tr '[:upper:]' '[:lower:]' | tr '@.+' '-')"
    log_info "ClusterRoleBinding ${binding_name} -> User ${email} (cluster-admin)"
    kubectl create clusterrolebinding "${binding_name}" \
      --clusterrole=cluster-admin \
      --user="${email}" \
      --dry-run=client -o yaml | kubectl apply -f -
  done
fi

log_info "Headlamp ready. Forward the UI with:"
log_info "  kubectl -n ${J2026_HEADLAMP_NAMESPACE} port-forward svc/${J2026_HEADLAMP_RELEASE} 8080:80"
log_info "Then open http://localhost:8080 and sign in with Google."
