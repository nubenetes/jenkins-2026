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
source "$(dirname "${BASH_SOURCE[0]}")/lib/secrets.sh"

log_step "Creating namespaces"
# Always-on, engine-neutral namespaces. The shared GKE Gateway (the single
# public-ingress entrypoint for EVERY app) lives in its OWN namespace
# (${J2026_GATEWAY_NAMESPACE}, default 'platform-ingress'), decoupled from any CI
# engine - so switching jenkins<->tekton never touches the ingress, and deleting an
# engine's namespace can't take the Gateway down. The 'jenkins' namespace is created
# below only when ci.engine=jenkins; the tekton-* namespaces only when ci.engine=tekton.
for ns in "${J2026_GATEWAY_NAMESPACE}" "${J2026_OBS_NAMESPACE}" "${J2026_HEADLAMP_NAMESPACE}" "${J2026_MICROSERVICES_NS_STABLE}" "${J2026_ARGOCD_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}"; do
  kubectl_apply_namespace "${ns}"
done

# Tekton control-plane + pipeline-execution namespaces are created up-front (when
# ci.engine=tekton) so the IAP and registry/git Secrets below can land in them
# before 04-tekton.sh installs the components. kubectl_apply_namespace is a no-op
# if the ns already exists (the Tekton release YAML also declares tekton-pipelines).
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  # pipelines-as-code: hosts the PaC controller (its HTTPRoute is created here-ish
  # by 09-gateway.sh, which needs the ns to exist before ArgoCD syncs PaC).
  for ns in "${J2026_TEKTON_NAMESPACE}" "${J2026_TEKTON_PIPELINE_NAMESPACE}" pipelines-as-code; do
    kubectl_apply_namespace "${ns}"
  done
fi

# Jenkins namespace + jenkins-credentials Secret ONLY when ci.engine=jenkins (the
# Jenkins controller is the sole consumer; the shared Gateway now lives in its own
# ${J2026_GATEWAY_NAMESPACE} namespace, so a tekton cluster gets NO jenkins namespace
# at all - and deleting it on a jenkins cluster no longer affects the Gateway).
if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
kubectl_apply_namespace "${J2026_JENKINS_NAMESPACE}"
log_step "Ensuring '${J2026_JENKINS_CREDENTIALS_SECRET}' Secret in ${J2026_JENKINS_NAMESPACE}"
if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
  # eso → seed the create-time/sensitive keys into Secret Manager. admin-password is
  # kept STABLE across runs (sm_keep_or_generate) so Jenkins + grafana-jenkins-ds agree
  # on it. ESO projects these with creationPolicy: Merge (08.6), so the URL keys patched
  # below + the argocd-token patched by 08.5 survive. Merge needs the Secret to exist, so
  # ensure an (empty) base for the merge-patches + ESO to target.
  admin_password="$(sm_keep_or_generate "${J2026_JENKINS_CREDENTIALS_SECRET}" admin-password "${ADMIN_PASSWORD:-$(openssl rand -base64 24 | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c20)}")"
  provision_secret "${J2026_JENKINS_NAMESPACE}" "${J2026_JENKINS_CREDENTIALS_SECRET}" \
    "admin-password=${admin_password}" \
    "grafana-base-url=${GRAFANA_BASE_URL:-}" \
    "registry-username=${REGISTRY_USERNAME:-}" \
    "registry-password=${REGISTRY_PASSWORD:-}" \
    "git-username=${GIT_USERNAME:-}" \
    "git-token=${GIT_TOKEN:-}" \
    "oidc-client-id=${JENKINS_OIDC_CLIENT_ID:-}" \
    "oidc-client-secret=${JENKINS_OIDC_CLIENT_SECRET:-}" \
    "oidc-admin-email=${JENKINS_OIDC_ADMIN_EMAIL:-}"
  kubectl create secret generic "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log_info "Seeded ${J2026_JENKINS_CREDENTIALS_SECRET} into Secret Manager (admin-password stable) — ESO will Merge it."
elif kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
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
{"stringData":{"microservices-url":"${microservices_url}","k6-cloud-token":"${K6_CLOUD_TOKEN:-}","k6-cloud-project-id":"${K6_CLOUD_PROJECT_ID:-}"}}
EOF
)"
fi  # end ci.engine=jenkins (jenkins namespace + credentials)

log_step "Ensuring '${J2026_HEADLAMP_CREDENTIALS_SECRET}' Secret in ${J2026_HEADLAMP_NAMESPACE}"
if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
  # eso → all 6 keys are deterministic (env client id/secret + config-derived OIDC
  # settings) and single-writer, so push the whole blob; ESO projects it (Owner, 08.6).
  provision_secret "${J2026_HEADLAMP_NAMESPACE}" "${J2026_HEADLAMP_CREDENTIALS_SECRET}" \
    "OIDC_CLIENT_ID=${HEADLAMP_OIDC_CLIENT_ID:-}" \
    "OIDC_CLIENT_SECRET=${HEADLAMP_OIDC_CLIENT_SECRET:-}" \
    "OIDC_ISSUER_URL=${J2026_HEADLAMP_OIDC_ISSUER_URL}" \
    "OIDC_SCOPES=${J2026_HEADLAMP_OIDC_SCOPES}" \
    "OIDC_CALLBACK_URL=${J2026_HEADLAMP_OIDC_CALLBACK_URL}" \
    "OIDC_USE_ACCESS_TOKEN=false"
elif kubectl get secret "${J2026_HEADLAMP_CREDENTIALS_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" >/dev/null 2>&1; then
  log_info "Secret already exists - leaving OIDC_CLIENT_ID/OIDC_CLIENT_SECRET untouched."
  log_info "(to rotate the OIDC client secret, delete the secret and re-run this script)"
  log_info "Refreshing non-sensitive OIDC config keys (issuer/scopes/callback/useAccessToken)."
  kubectl patch secret "${J2026_HEADLAMP_CREDENTIALS_SECRET}" -n "${J2026_HEADLAMP_NAMESPACE}" \
    --type=merge -p "$(cat <<EOF
{"stringData":{
  "OIDC_ISSUER_URL":"${J2026_HEADLAMP_OIDC_ISSUER_URL}",
  "OIDC_SCOPES":"${J2026_HEADLAMP_OIDC_SCOPES}",
  "OIDC_CALLBACK_URL":"${J2026_HEADLAMP_OIDC_CALLBACK_URL}",
  "OIDC_USE_ACCESS_TOKEN":"false"
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
    --from-literal=OIDC_USE_ACCESS_TOKEN="false"

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
  # the same client ID/secret must exist in each backend's namespace. The OSS
  # Grafana (observability.mode=oss) is IAP-protected too, so its namespace
  # needs the secret as well - only in oss mode, where Grafana runs in-cluster.
  iap_namespaces=("${J2026_HEADLAMP_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}")
  if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
    iap_namespaces+=("${J2026_GRAFANA_OSS_NAMESPACE}")
  fi
  # The IAP-protected CI backend is engine-specific: the Tekton Dashboard
  # (ci.engine=tekton) or Jenkins (ci.engine=jenkins) - its GCPBackendPolicy lives
  # in that engine's namespace, so only that one gets the IAP secret (the jenkins
  # namespace doesn't exist in tekton mode).
  if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
    iap_namespaces+=("${J2026_TEKTON_NAMESPACE}")
  else
    iap_namespaces+=("${J2026_JENKINS_NAMESPACE}")
  fi
  if [[ "${J2026_SECRETS_BACKEND}" == "eso" ]]; then
    # ESO mode: push the value once to GCP Secret Manager. The per-namespace
    # ExternalSecrets in infrastructure/secrets/eso-bootstrap.yaml project it into
    # each iap_namespaces member; scripts/08.6-eso-sync.sh applies them and waits
    # for the resulting Secrets to materialise before the consumers run.
    provision_secret "${iap_namespaces[*]}" "${J2026_GATEWAY_IAP_SECRET}" \
      "client_id=${IAP_OAUTH_CLIENT_ID:-}" \
      "client_secret=${IAP_OAUTH_CLIENT_SECRET:-}"
  else
    for ns in "${iap_namespaces[@]}"; do
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
fi

# Tekton pipeline credentials (ci.engine=tekton). The pipeline ServiceAccount
# (created by 04-tekton.sh in the pipeline namespace) references these for
# ghcr.io push/pull (Jib/Kaniko) and git push to the gitops repo. Same
# REGISTRY_*/GIT_* env the Jenkins path consumes; falls back to reading them
# from the jenkins-credentials Secret. The git Secret is annotated for
# tekton.dev/git-0 so Tekton's credential initializer wires it into PipelineRuns.
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  log_step "Ensuring Tekton pipeline credentials in ${J2026_TEKTON_PIPELINE_NAMESPACE}"
  tk_reg_user="${REGISTRY_USERNAME:-}"
  tk_reg_pass="${REGISTRY_PASSWORD:-}"
  tk_git_user="${GIT_USERNAME:-}"
  tk_git_token="${GIT_TOKEN:-}"
  if kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    [[ -z "${tk_reg_user}" ]]  && tk_reg_user="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-username}' 2>/dev/null | base64 -d || true)"
    [[ -z "${tk_reg_pass}" ]]  && tk_reg_pass="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-password}' 2>/dev/null | base64 -d || true)"
    [[ -z "${tk_git_user}" ]]  && tk_git_user="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.git-username}' 2>/dev/null | base64 -d || true)"
    [[ -z "${tk_git_token}" ]] && tk_git_token="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.git-token}' 2>/dev/null | base64 -d || true)"
  fi
  tk_reg_host="${J2026_MICROSERVICES_REGISTRY%%/*}"
  if [[ -n "${tk_reg_user}" && -n "${tk_reg_pass}" ]]; then
    tk_reg_auth="$(printf '%s:%s' "${tk_reg_user}" "${tk_reg_pass}" | base64 -w0)"
    tk_dockercfg="$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
      "${tk_reg_host}" "${tk_reg_user}" "${tk_reg_pass}" "${tk_reg_auth}")"
  else
    log_warn "REGISTRY_USERNAME/REGISTRY_PASSWORD not set - Tekton image push will fail until configured."
    tk_dockercfg='{"auths":{}}'
  fi
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    # eso → store the raw creds in Secret Manager; the ExternalSecret (08.6)
    # rebuilds the dockerconfigjson via its target.template from these keys.
    provision_secret "${J2026_TEKTON_PIPELINE_NAMESPACE}" "${J2026_TEKTON_REGISTRY_SECRET}" \
      "username=${tk_reg_user}" "password=${tk_reg_pass}" "registry=${tk_reg_host}"
  else
    kubectl create secret generic "${J2026_TEKTON_REGISTRY_SECRET}" \
      -n "${J2026_TEKTON_PIPELINE_NAMESPACE}" \
      --type=kubernetes.io/dockerconfigjson \
      --from-literal=.dockerconfigjson="${tk_dockercfg}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  if [[ -z "${tk_git_token}" ]]; then
    log_warn "GIT_TOKEN not set - Tekton git push (GitOps deploy) and SARIF upload will fail until configured."
  fi
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    # eso → store username/password; the ExternalSecret (08.6) emits a basic-auth
    # Secret with the tekton.dev/git-0 annotation via its target.template.
    provision_secret "${J2026_TEKTON_PIPELINE_NAMESPACE}" "${J2026_TEKTON_GIT_SECRET}" \
      "username=${tk_git_user:-git}" "password=${tk_git_token}"
  else
    kubectl create secret generic "${J2026_TEKTON_GIT_SECRET}" \
      -n "${J2026_TEKTON_PIPELINE_NAMESPACE}" \
      --type=kubernetes.io/basic-auth \
      --from-literal=username="${tk_git_user:-git}" \
      --from-literal=password="${tk_git_token}" \
      --dry-run=client -o yaml \
      | kubectl annotate --local -f - tekton.dev/git-0=https://github.com -o yaml \
      | kubectl apply -f -
  fi

  # GitHub HMAC secret for the Triggers EventListener (tekton/triggers/). Optional
  # (the upstream JHipster repos aren't owned, so push webhooks can't target them);
  # created empty unless TEKTON_GITHUB_WEBHOOK_SECRET is provided, so the
  # EventListener's github interceptor reference resolves either way.
  # eso → push to Secret Manager (08.6 projects it back); imperative → kubectl
  # upsert. provision_secret branches on the active backend internally.
  provision_secret "${J2026_TEKTON_PIPELINE_NAMESPACE}" tekton-github-webhook-secret \
    "secretToken=${TEKTON_GITHUB_WEBHOOK_SECRET:-}"

  # PaC (Pipelines-as-Code) webhook HMAC secret, referenced by the Repository
  # CRs (tekton/pac/) and shared with the GitHub repo webhooks created by
  # 06-tekton-pipelines.sh. Optional - empty unless PAC_WEBHOOK_SECRET is set.
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    # eso → seed the HMAC into Secret Manager, generated-if-absent and kept STABLE
    # (06-tekton-pipelines shares it with the GitHub webhooks); ESO projects it (Owner).
    pac_secret="$(sm_keep_or_generate pac-webhook webhook.secret "${PAC_WEBHOOK_SECRET:-$(openssl rand -hex 20)}")"
    provision_secret "${J2026_TEKTON_PIPELINE_NAMESPACE}" pac-webhook "webhook.secret=${pac_secret}"
  else
    kubectl create secret generic pac-webhook \
      -n "${J2026_TEKTON_PIPELINE_NAMESPACE}" \
      --from-literal=webhook.secret="${PAC_WEBHOOK_SECRET:-}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  # Optional Grafana Cloud k6 (the k6-app) streaming for the k6-smoke Task. Created
  # empty unless K6_CLOUD_TOKEN is set, so the Task's optional secretKeyRef resolves
  # either way; the cloud output (--out cloud) only activates when both are present.
  provision_secret "${J2026_TEKTON_PIPELINE_NAMESPACE}" k6-cloud \
    "token=${K6_CLOUD_TOKEN:-}" \
    "project-id=${K6_CLOUD_PROJECT_ID:-}" \
    "grafana-base-url=${GRAFANA_BASE_URL:-}"
fi

# Jenkins SA 'edit' binding only when ci.engine=jenkins (no jenkins SA/namespace in
# tekton mode; the tekton-ci SA gets its own edit binding via tekton/rbac).
if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
log_step "Granting Jenkins ServiceAccount 'edit' in microservices namespaces"
for ns in "${J2026_MICROSERVICES_NS_STABLE}"; do
  kubectl create rolebinding jenkins-edit \
    --clusterrole=edit \
    --serviceaccount="${J2026_JENKINS_NAMESPACE}:jenkins" \
    -n "${ns}" \
    --dry-run=client -o yaml | kubectl apply -f -
done
fi

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
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    # eso → store the raw creds in Secret Manager; the ExternalSecret (08.6)
    # rebuilds the dockerconfigjson via its target.template from these keys.
    provision_secret "${ns}" ghcr-credentials \
      "username=${REGISTRY_USERNAME:-}" "password=${REGISTRY_PASSWORD:-}" "registry=${registry_host}"
  else
    kubectl create secret generic ghcr-credentials \
      -n "${ns}" \
      --type=kubernetes.io/dockerconfigjson \
      --from-literal=.dockerconfigjson="${dockerconfigjson}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
done

log_step "Applying ResourceQuotas to limit scaling and costs"

# 1. Jenkins Namespace Quota (only when ci.engine=jenkins - no jenkins ns otherwise)
if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
kubectl apply -f - -n "${J2026_JENKINS_NAMESPACE}" <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: jenkins-quota
spec:
  hard:
    requests.cpu: "16.0"
    requests.memory: 32.0Gi
    limits.cpu: "60.0"
    limits.memory: 64.0Gi
EOF
fi

# 2. Observability Namespace Quota
# The in-cluster footprint is far larger in observability.mode=oss (the whole
# stack runs locally: Prometheus, Loki, Tempo, Grafana, plus the OTel
# collectors) than in the cloud/managed modes (collectors only), so size the
# quota per mode - the small cap would otherwise reject the oss stack's pods
# (exceeded quota: limits.cpu).
if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  obs_requests_cpu="6.0";  obs_requests_mem="12.0Gi"
  obs_limits_cpu="12.0";   obs_limits_mem="20.0Gi"
else
  obs_requests_cpu="3.0";  obs_requests_mem="6.0Gi"
  obs_limits_cpu="6.0";    obs_limits_mem="10.0Gi"
fi
kubectl apply -f - -n "${J2026_OBS_NAMESPACE}" <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: observability-quota
spec:
  hard:
    requests.cpu: "${obs_requests_cpu}"
    requests.memory: ${obs_requests_mem}
    limits.cpu: "${obs_limits_cpu}"
    limits.memory: ${obs_limits_mem}
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

limitrange_ns=("${J2026_OBS_NAMESPACE}" "${J2026_HEADLAMP_NAMESPACE}" "${J2026_ARGOCD_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}")
[[ "${J2026_CI_ENGINE}" == "jenkins" ]] && limitrange_ns+=("${J2026_JENKINS_NAMESPACE}")
for ns in "${limitrange_ns[@]}"; do
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

log_step "Applying NetworkPolicies for platform namespaces"
kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies.yaml"
# Jenkins-namespace NetworkPolicies only when ci.engine=jenkins (no jenkins ns in
# tekton mode - applying them there fails with 'namespaces "jenkins" not found').
if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
  kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies-jenkins.yaml"
fi
# Tekton-namespace baseline only when ci.engine=tekton (no tekton-ci ns otherwise).
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies-tekton.yaml"
fi

log_info "Namespaces ready."

