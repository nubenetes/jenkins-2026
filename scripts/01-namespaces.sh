#!/usr/bin/env bash
# Creates the namespaces used by this PoC, the "jenkins-credentials" Secret
# consumed by helm/jenkins/values-common.yaml, the "headlamp-credentials"
# Secret consumed by helm/headlamp/values.yaml (see scripts/08-headlamp.sh),
# and grants the Jenkins controller's ServiceAccount "edit" access in both
# microservices namespaces so pipelines can `helm upgrade`/`kubectl apply` their
# deployments. Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

log_step "Creating namespaces"
for ns in "${J2026_JENKINS_NAMESPACE}" "${J2026_OBS_NAMESPACE}" "${J2026_HEADLAMP_NAMESPACE}" "${J2026_MICROSERVICES_NS_STABLE}" "${J2026_ARGOCD_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}"; do
  kubectl_apply_namespace "${ns}"
done

log_step "Ensuring '${J2026_JENKINS_CREDENTIALS_SECRET}' Secret in ${J2026_JENKINS_NAMESPACE}"
if kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
  log_info "Secret already exists - leaving it untouched."
  log_info "(to rotate the admin password, delete the secret and re-run this script)"
else
  # ADMIN_PASSWORD can be supplied via env for
  # reproducible demos; otherwise a random one is generated and printed once
  # below. `openssl rand` writes a fixed-size, finite stream (unlike
  # `/dev/urandom | head`, which makes `tr` die with SIGPIPE -> exit 141
  # under `set -o pipefail`).
  admin_password="${ADMIN_PASSWORD:-$(openssl rand -base64 24 | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c20)}"

  if [[ -z "${JENKINS_OIDC_CLIENT_ID:-}" || -z "${JENKINS_OIDC_CLIENT_SECRET:-}" ]]; then
    log_warn "JENKINS_OIDC_CLIENT_ID/JENKINS_OIDC_CLIENT_SECRET not set - Jenkins will"
    log_warn "deploy but \"Sign in with Google\" won't work until configured. The"
    log_warn "escape-hatch admin login (above) still works. See README.md \"Jenkins\"."
  fi

  kubectl create secret generic "${J2026_JENKINS_CREDENTIALS_SECRET}" \
    -n "${J2026_JENKINS_NAMESPACE}" \
    --from-literal=admin-password="${admin_password}" \
    --from-literal=grafana-base-url="${GRAFANA_BASE_URL:-}" \
    --from-literal=registry-username="${REGISTRY_USERNAME:-}" \
    --from-literal=registry-password="${REGISTRY_PASSWORD:-}" \
    --from-literal=git-username="${GIT_USERNAME:-}" \
    --from-literal=git-token="${GIT_TOKEN:-}" \
    --from-literal=oidc-client-id="${JENKINS_OIDC_CLIENT_ID:-}" \
    --from-literal=oidc-client-secret="${JENKINS_OIDC_CLIENT_SECRET:-}" \
    --from-literal=oidc-admin-email="${JENKINS_OIDC_ADMIN_EMAIL:-}"

  log_info "Created. Jenkins admin login: ${J2026_JENKINS_ADMIN_USER} / ${admin_password}"
  log_warn "Save this password now - it is not printed again on subsequent runs."
fi

log_step "Refreshing Microservices URLs in '${J2026_JENKINS_CREDENTIALS_SECRET}' Secret"
# Non-sensitive, so refreshed on every run (unlike the admin
# password above) - tracks gateway.baseDomain even if it changes after the
# secret was first created. Empty if the Gateway feature is disabled. Surfaced
# in the Jenkins systemMessage banner by jcasc-base.yaml (MICROSERVICES_URL).
microservices_url=""
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  microservices_url="https://${J2026_GATEWAY_MICROSERVICES_HOST}"
fi
kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
  --type=merge -p "$(cat <<EOF
{"stringData":{"microservices-url":"${microservices_url}"}}
EOF
)"

log_step "Ensuring '${J2026_HEADLAMP_CREDENTIALS_SECRET}' Secret in ${J2026_HEADLAMP_NAMESPACE}"
if kubectl get secret "${J2026_HEADLAMP_CREDENTIALS_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" >/dev/null 2>&1; then
  log_info "Secret already exists - leaving OIDC_CLIENT_ID/OIDC_CLIENT_SECRET untouched."
  log_info "(to rotate the OIDC client secret, delete the secret and re-run this script)"
  log_info "Refreshing non-sensitive OIDC config keys (issuer/scopes/callback/useAccessToken)."
  kubectl patch secret "${J2026_HEADLAMP_CREDENTIALS_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" \
    --type=merge -p "$(cat <<EOF
{"stringData":{
  "OIDC_ISSUER_URL":"${J2026_HEADLAMP_OIDC_ISSUER_URL}",
  "OIDC_SCOPES":"${J2026_HEADLAMP_OIDC_SCOPES}",
  "OIDC_CALLBACK_URL":"${J2026_HEADLAMP_OIDC_CALLBACK_URL}",
  "OIDC_USE_ACCESS_TOKEN":"true"
}}
EOF
)"
else
  if [[ -z "${HEADLAMP_OIDC_CLIENT_ID:-}" || -z "${HEADLAMP_OIDC_CLIENT_SECRET:-}" ]]; then
    log_warn "HEADLAMP_OIDC_CLIENT_ID/HEADLAMP_OIDC_CLIENT_SECRET not set - Headlamp will"
    log_warn "deploy but Google login won't work until configured. See README.md \"Headlamp\"."
  fi
  # Keys match the env vars helm/headlamp/values.yaml config.oidc.externalSecret
  # expects (envFrom on this Secret).
  kubectl create secret generic "${J2026_HEADLAMP_CREDENTIALS_SECRET}" \
    -n "${J2026_HEADLAMP_NAMESPACE}" \
    --from-literal=OIDC_CLIENT_ID="${HEADLAMP_OIDC_CLIENT_ID:-}" \
    --from-literal=OIDC_CLIENT_SECRET="${HEADLAMP_OIDC_CLIENT_SECRET:-}" \
    --from-literal=OIDC_ISSUER_URL="${J2026_HEADLAMP_OIDC_ISSUER_URL}" \
    --from-literal=OIDC_SCOPES="${J2026_HEADLAMP_OIDC_SCOPES}" \
    --from-literal=OIDC_CALLBACK_URL="${J2026_HEADLAMP_OIDC_CALLBACK_URL}" \
    --from-literal=OIDC_USE_ACCESS_TOKEN="true"

  log_info "Created."
fi

log_step "Ensuring '${J2026_GATEWAY_IAP_SECRET}' Secret for Gateway IAP"
if [[ -z "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  log_info "gateway.baseDomain / JENKINS2026_BASE_DOMAIN is empty - gateway disabled, skipping."
else
  if [[ -z "${IAP_OAUTH_CLIENT_ID:-}" || -z "${IAP_OAUTH_CLIENT_SECRET:-}" ]]; then
    log_warn "IAP_OAUTH_CLIENT_ID/IAP_OAUTH_CLIENT_SECRET not set - the Jenkins and"
    log_warn "Headlamp GCPBackendPolicies will deploy but IAP won't work until"
    log_warn "configured. See README.md \"Public access (GKE Gateway API + IAP)\"."
  fi
  # GCPBackendPolicy's oauth2ClientSecret is a namespaced Secret reference, so
  # the same client ID/secret must exist in each backend's namespace.
  for ns in "${J2026_JENKINS_NAMESPACE}" "${J2026_HEADLAMP_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}"; do
    if kubectl get secret "${J2026_GATEWAY_IAP_SECRET}" -n "${ns}" >/dev/null 2>&1; then
      log_info "Secret already exists in ${ns} - leaving it untouched."
    else
      kubectl create secret generic "${J2026_GATEWAY_IAP_SECRET}" \
        -n "${ns}" \
        --from-literal=client_id="${IAP_OAUTH_CLIENT_ID:-}" \
        --from-literal=client_secret="${IAP_OAUTH_CLIENT_SECRET:-}"
      log_info "Created in ${ns}."
    fi
  done
fi

log_step "Granting Jenkins ServiceAccount 'edit' in microservices namespaces"
for ns in "${J2026_MICROSERVICES_NS_STABLE}"; do
  kubectl create rolebinding jenkins-edit \
    --clusterrole=edit \
    --serviceaccount="${J2026_JENKINS_NAMESPACE}:jenkins" \
    -n "${ns}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

log_step "Granting pgAdmin ServiceAccount read access to Postgres user secrets in microservices namespace"
# Create a Role that only allows reading the specific database user secrets
kubectl apply -f - -n "${J2026_MICROSERVICES_NS_STABLE}" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pgadmin-secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames:
  - postgres-gateway-app
  - postgres-jhipstersamplemicroservice-app
  verbs: ["get", "list"]
EOF

# Bind this Role to pgAdmin's ServiceAccount (pgadmin) in the pgadmin namespace
kubectl create rolebinding pgadmin-secret-reader-binding \
  --role=pgadmin-secret-reader \
  --serviceaccount="${J2026_PGADMIN_NAMESPACE}:pgadmin" \
  -n "${J2026_MICROSERVICES_NS_STABLE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# 'ghcr-credentials' imagePullSecret (helm/microservices values-*.yaml
# imagePullSecret) - same REGISTRY_USERNAME/REGISTRY_PASSWORD the
# "container-registry" Jenkins credential (jenkins/casc/jcasc-base.yaml) uses
# to push images, since pipelines push to MICROSERVICES_REGISTRY as private
# packages by default. Without these env vars, an empty-auths secret is
# created so the Deployments still reference a valid secret name and fall
# back to anonymous pulls (fine for public images).
log_step "Ensuring 'ghcr-credentials' imagePullSecret in microservices namespaces"
registry_host="${J2026_MICROSERVICES_REGISTRY%%/*}"

# Fallback: try to read from jenkins-credentials secret in jenkins namespace
if [[ -z "${REGISTRY_USERNAME:-}" || -z "${REGISTRY_PASSWORD:-}" ]]; then
  if kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    log_info "Reading registry credentials from secret ${J2026_JENKINS_CREDENTIALS_SECRET}..."
    REGISTRY_USERNAME="${REGISTRY_USERNAME:-$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-username}' | base64 -d)}"
    REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-password}' | base64 -d)}"
  fi
fi

if [[ -n "${REGISTRY_USERNAME:-}" && -n "${REGISTRY_PASSWORD:-}" ]]; then
  registry_auth="$(printf '%s:%s' "${REGISTRY_USERNAME}" "${REGISTRY_PASSWORD}" | base64 -w0)"
  dockerconfigjson="$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
    "${registry_host}" "${REGISTRY_USERNAME}" "${REGISTRY_PASSWORD}" "${registry_auth}")"
else
  dockerconfigjson='{"auths":{}}'
fi
for ns in "${J2026_MICROSERVICES_NS_STABLE}"; do
  kubectl create secret generic ghcr-credentials \
    -n "${ns}" \
    --type=kubernetes.io/dockerconfigjson \
    --from-literal=.dockerconfigjson="${dockerconfigjson}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

log_step "Applying ResourceQuotas to limit scaling and costs"

# 1. Jenkins Namespace Quota
kubectl apply -f - -n "${J2026_JENKINS_NAMESPACE}" <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: jenkins-quota
spec:
  hard:
    requests.cpu: "3.0"
    requests.memory: 8.0Gi
    limits.cpu: "14"
    limits.memory: 16.0Gi
EOF

# 2. Observability Namespace Quota
kubectl apply -f - -n "${J2026_OBS_NAMESPACE}" <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: observability-quota
spec:
  hard:
    requests.cpu: "1.5"
    requests.memory: 3.0Gi
    limits.cpu: "3.5"
    limits.memory: 5.0Gi
EOF

# 3. Headlamp Namespace Quota
kubectl apply -f - -n "${J2026_HEADLAMP_NAMESPACE}" <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: headlamp-quota
spec:
  hard:
    requests.cpu: "200m"
    requests.memory: 256Mi
    limits.cpu: "500m"
    limits.memory: 512Mi
EOF

# 4. ArgoCD Namespace Quota
kubectl apply -f - -n "${J2026_ARGOCD_NAMESPACE}" <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: argocd-quota
spec:
  hard:
    requests.cpu: "1.5"
    requests.memory: 3.0Gi
    limits.cpu: "5"
    limits.memory: 8.0Gi
EOF

# 5. pgAdmin Namespace Quota
kubectl apply -f - -n "${J2026_PGADMIN_NAMESPACE}" <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pgadmin-quota
spec:
  hard:
    requests.cpu: "300m"
    requests.memory: 512Mi
    limits.cpu: "1.0"
    limits.memory: 1.0Gi
EOF



log_step "Applying LimitRanges to supply default requests/limits"

for ns in "${J2026_JENKINS_NAMESPACE}" "${J2026_OBS_NAMESPACE}" "${J2026_HEADLAMP_NAMESPACE}" "${J2026_ARGOCD_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}"; do
  kubectl apply -f - -n "${ns}" <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: namespace-limit-range
spec:
  limits:
  - default:
      cpu: 200m
      memory: 256Mi
    defaultRequest:
      cpu: 50m
      memory: 128Mi
    type: Container
EOF
done

log_info "Namespaces ready."
