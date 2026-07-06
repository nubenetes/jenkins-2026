#!/usr/bin/env bash
# Creates the namespaces used by this PoC, the "jenkins-credentials" Secret
# consumed by helm/jenkins/values-common.yaml, and the "headlamp-credentials"
# Secret consumed by helm/headlamp/values.yaml (see scripts/08-headlamp.sh).
# The Jenkins ServiceAccount's "edit" RoleBindings in the microservices
# namespaces are GitOps-managed by the platform-config app
# (argocd/platform-config/templates/rbac-jenkins.yaml). Idempotent.
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

# Optional 'develop' microservices deploy tier (OFF by default; feature flag
# microservices.developTrackEnabled / JENKINS2026_DEVELOP_TRACK_ENABLED). When on,
# provision its namespace up-front so the RBAC/secrets/NetworkPolicies below — and
# ArgoCD's later sync (08.5 appends a 'develop' ApplicationSet generator) — land in
# it. A LEAN, non-HA tier (gitops values-develop.yaml: CNPG single instance, no
# backups) — see docs/402. MS_NAMESPACES drives every per-namespace loop below so
# stable-only behaviour is unchanged when the flag is off (engine-neutral).
MS_NAMESPACES=("${J2026_MICROSERVICES_NS_STABLE}")
if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
  MS_NAMESPACES+=("${J2026_MICROSERVICES_DEVELOP_NAMESPACE}")
  kubectl_apply_namespace "${J2026_MICROSERVICES_DEVELOP_NAMESPACE}"
  log_info "Develop track enabled - provisioning namespace ${J2026_MICROSERVICES_DEVELOP_NAMESPACE} (lean tier)."
fi

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

# GitHub Actions / ARC control-plane (arc-systems) + runner (arc-runners) namespaces
# are created up-front (when ci.engine=githubactions) so the GitHub App + registry
# Secrets below can land in the runner namespace before 04-githubactions.sh syncs the
# AutoscalingRunnerSet — its githubConfigSecret must exist before the runner-set App
# syncs, or registration fails. kubectl_apply_namespace is a no-op if the ns exists.
if [[ "${J2026_CI_ENGINE}" == "githubactions" ]]; then
  for ns in "${J2026_GHA_NAMESPACE}" "${J2026_GHA_RUNNER_NAMESPACE}"; do
    kubectl_apply_namespace "${ns}"
  done
fi

# Argo Workflows control plane (argo) + Argo Events (argo-events) + Workflow execution
# (argo-ci) namespaces are created up-front (when ci.engine=argoworkflows) so the IAP,
# registry/git, and GitHub-webhook Secrets below can land in them before 04-argoworkflows.sh
# installs the controllers. kubectl_apply_namespace is a no-op if the ns already exists.
if [[ "${J2026_CI_ENGINE}" == "argoworkflows" ]]; then
  for ns in "${J2026_ARGOWF_NAMESPACE}" "${J2026_ARGOWF_EVENTS_NAMESPACE}" "${J2026_ARGOWF_RUN_NAMESPACE}"; do
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
  # on it. ESO projects these with creationPolicy: Merge (08.6), so the *04-patched* keys
  # (grafana-base-url, the dashboard uids, k8s-app-link, microservices-url, …) + the
  # argocd-token patched by 08.5 survive — because ESO's Merge only touches the keys it
  # extracts from SM, leaving 04-only keys intact. Merge needs the Secret to exist, so
  # ensure an (empty) base for the merge-patches + ESO to target.
  #
  # grafana-base-url is DELIBERATELY not seeded here (nor in the imperative create below):
  # it is a *derived* URL that 04-jenkins.sh computes per observability.mode and patches
  # into the live Secret. Seeding it into SM would put an EMPTY value there in oss/managed
  # modes (GRAFANA_BASE_URL is only set for grafana-cloud) — and ESO's hourly Merge re-sync
  # would then clobber 04's real URL back to empty, collapsing every Grafana banner
  # deep-link to the Jenkins host (/d/<uid> resolves against the current page). Letting 04
  # be the sole owner is exactly how the other derived URL keys already work.
  admin_password="$(sm_keep_or_generate "${J2026_JENKINS_CREDENTIALS_SECRET}" admin-password "${ADMIN_PASSWORD:-$(openssl rand -base64 24 | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c20)}")"
  provision_secret "${J2026_JENKINS_NAMESPACE}" "${J2026_JENKINS_CREDENTIALS_SECRET}" \
    "admin-password=${admin_password}" \
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

  # grafana-base-url is intentionally omitted — 04-jenkins.sh is its sole owner
  # (derived per observability.mode). See the eso branch above for the full why.
  kubectl create secret generic "${J2026_JENKINS_CREDENTIALS_SECRET}" \
    -n "${J2026_JENKINS_NAMESPACE}" \
    --from-literal=admin-password="${admin_password}" \
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
# Develop tier URL only when the gateway is up AND the lean develop track is
# enabled (the develop HTTPRoute is generated by 09-gateway under the same flag).
microservices_develop_url=""
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  microservices_url="https://${J2026_GATEWAY_MICROSERVICES_HOST}"
  if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
    microservices_develop_url="https://${J2026_GATEWAY_MICROSERVICES_DEVELOP_HOST}"
  fi
fi
kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
  --type=merge -p "$(cat <<EOF
{"stringData":{"microservices-url":"${microservices_url}","microservices-develop-url":"${microservices_develop_url}","k6-cloud-token":"${K6_CLOUD_TOKEN:-}","k6-cloud-project-id":"${K6_CLOUD_PROJECT_ID:-}"}}
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
  # ArgoCD is IAP-fronted too (defense-in-depth; its Dex authproxy connector trusts
  # the IAP identity header — docs/504/501), and is always deployed, so unconditional.
  iap_namespaces=("${J2026_HEADLAMP_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}" "${J2026_ARGOCD_NAMESPACE}")
  if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
    iap_namespaces+=("${J2026_GRAFANA_OSS_NAMESPACE}")
  fi
  # The IAP-protected CI backend is engine-specific: the Tekton Dashboard
  # (ci.engine=tekton) or Jenkins (ci.engine=jenkins) - its GCPBackendPolicy lives
  # in that engine's namespace, so only that one gets the IAP secret (the jenkins
  # namespace doesn't exist in tekton mode). ci.engine=githubactions has NO
  # IAP-protected CI backend (runs live in GitHub's Actions tab, no in-cluster
  # dashboard), so neither engine namespace is added - an explicit elif, not an
  # else, so githubactions doesn't fall through to the jenkins branch.
  if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
    iap_namespaces+=("${J2026_TEKTON_NAMESPACE}")
  elif [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
    iap_namespaces+=("${J2026_JENKINS_NAMESPACE}")
  elif [[ "${J2026_CI_ENGINE}" == "argoworkflows" ]]; then
    # The Argo Workflows Server UI (argo ns) has no native auth → IAP-protected, like
    # the Tekton Dashboard. (The argo-events webhook receiver is public, no IAP.)
    iap_namespaces+=("${J2026_ARGOWF_NAMESPACE}")
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

# GitHub Actions / ARC pipeline credentials (ci.engine=githubactions). The
# AutoscalingRunnerSet authenticates to GitHub via a GitHub App (recommended) or a
# PAT fallback read from arc-github-app; the ephemeral runner pods pull their image
# (and the dind sidecar) from ghcr.io via arc-registry (referenced as an
# imagePullSecret in the runner pod template). Both land in the runner namespace
# BEFORE 04-githubactions.sh syncs the runner-set, whose githubConfigSecret must
# already exist. provision_secret branches on imperative|eso internally.
if [[ "${J2026_CI_ENGINE}" == "githubactions" ]]; then
  log_step "Ensuring ARC credentials in ${J2026_GHA_RUNNER_NAMESPACE}"
  if [[ "${J2026_GHA_AUTH_MODE}" == "app" && -n "${ARC_GITHUB_APP_ID:-}" && -n "${ARC_GITHUB_APP_PRIVATE_KEY:-}" ]]; then
    provision_secret "${J2026_GHA_RUNNER_NAMESPACE}" "${J2026_GHA_APP_SECRET}" \
      "github_app_id=${ARC_GITHUB_APP_ID}" \
      "github_app_installation_id=${ARC_GITHUB_APP_INSTALLATION_ID:-}" \
      "github_app_private_key=${ARC_GITHUB_APP_PRIVATE_KEY}"
  else
    log_warn "ARC_GITHUB_APP_* unset (or authMode != app) - registering ARC runners via the GIT_TOKEN PAT (github_token)."
    provision_secret "${J2026_GHA_RUNNER_NAMESPACE}" "${J2026_GHA_APP_SECRET}" \
      "github_token=${GIT_TOKEN:-}"
  fi

  # GHCR pull (imagePullSecret) — same REGISTRY_*/jenkins-credentials fallback as the
  # tekton-registry block, emitted as a dockerconfigjson Secret (imperative) or raw
  # creds in Secret Manager rebuilt by the ExternalSecret template (eso).
  gha_reg_user="${REGISTRY_USERNAME:-}"
  gha_reg_pass="${REGISTRY_PASSWORD:-}"
  if [[ ( -z "${gha_reg_user}" || -z "${gha_reg_pass}" ) ]] \
     && kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    [[ -z "${gha_reg_user}" ]] && gha_reg_user="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-username}' 2>/dev/null | base64 -d || true)"
    [[ -z "${gha_reg_pass}" ]] && gha_reg_pass="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-password}' 2>/dev/null | base64 -d || true)"
  fi
  gha_reg_host="${J2026_MICROSERVICES_REGISTRY%%/*}"
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    provision_secret "${J2026_GHA_RUNNER_NAMESPACE}" "${J2026_GHA_REGISTRY_SECRET}" \
      "username=${gha_reg_user}" "password=${gha_reg_pass}" "registry=${gha_reg_host}"
  else
    if [[ -n "${gha_reg_user}" && -n "${gha_reg_pass}" ]]; then
      gha_reg_auth="$(printf '%s:%s' "${gha_reg_user}" "${gha_reg_pass}" | base64 -w0)"
      gha_dockercfg="$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
        "${gha_reg_host}" "${gha_reg_user}" "${gha_reg_pass}" "${gha_reg_auth}")"
    else
      log_warn "REGISTRY_USERNAME/REGISTRY_PASSWORD not set - ARC runner image pull falls back to anonymous."
      gha_dockercfg='{"auths":{}}'
    fi
    kubectl create secret generic "${J2026_GHA_REGISTRY_SECRET}" \
      -n "${J2026_GHA_RUNNER_NAMESPACE}" \
      --type=kubernetes.io/dockerconfigjson \
      --from-literal=.dockerconfigjson="${gha_dockercfg}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  # Optional Grafana Cloud k6 streaming for the workflow's k6 step (parity with the
  # tekton k6-cloud Secret). Created empty unless K6_CLOUD_TOKEN is set.
  provision_secret "${J2026_GHA_RUNNER_NAMESPACE}" k6-cloud \
    "token=${K6_CLOUD_TOKEN:-}" \
    "project-id=${K6_CLOUD_PROJECT_ID:-}" \
    "grafana-base-url=${GRAFANA_BASE_URL:-}"
fi

# Argo Workflows pipeline credentials (ci.engine=argoworkflows). The Workflow
# ServiceAccount (argoworkflows-ci, created by the GitOps pac in argo-ci) references
# these for ghcr.io push/pull (Jib/Kaniko) and git push to the gitops repo - same
# REGISTRY_*/GIT_* env the Jenkins path consumes, with a jenkins-credentials fallback.
# Unlike Tekton, the git Secret is a PLAIN basic-auth (no tekton.dev/git-0 annotation -
# the fetch-source/gitops-deploy templates read creds from env, not a credential
# initializer). The GitHub HMAC Secret lives in the EVENTS namespace (argo-events),
# where the EventSource consumes it.
if [[ "${J2026_CI_ENGINE}" == "argoworkflows" ]]; then
  log_step "Ensuring Argo Workflows pipeline credentials in ${J2026_ARGOWF_RUN_NAMESPACE}"
  awf_reg_user="${REGISTRY_USERNAME:-}"
  awf_reg_pass="${REGISTRY_PASSWORD:-}"
  awf_git_user="${GIT_USERNAME:-}"
  awf_git_token="${GIT_TOKEN:-}"
  if kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
    [[ -z "${awf_reg_user}" ]]  && awf_reg_user="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-username}' 2>/dev/null | base64 -d || true)"
    [[ -z "${awf_reg_pass}" ]]  && awf_reg_pass="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.registry-password}' 2>/dev/null | base64 -d || true)"
    [[ -z "${awf_git_user}" ]]  && awf_git_user="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.git-username}' 2>/dev/null | base64 -d || true)"
    [[ -z "${awf_git_token}" ]] && awf_git_token="$(kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" -o jsonpath='{.data.git-token}' 2>/dev/null | base64 -d || true)"
  fi
  awf_reg_host="${J2026_MICROSERVICES_REGISTRY%%/*}"
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    provision_secret "${J2026_ARGOWF_RUN_NAMESPACE}" "${J2026_ARGOWF_REGISTRY_SECRET}" \
      "username=${awf_reg_user}" "password=${awf_reg_pass}" "registry=${awf_reg_host}"
  else
    if [[ -n "${awf_reg_user}" && -n "${awf_reg_pass}" ]]; then
      awf_reg_auth="$(printf '%s:%s' "${awf_reg_user}" "${awf_reg_pass}" | base64 -w0)"
      awf_dockercfg="$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
        "${awf_reg_host}" "${awf_reg_user}" "${awf_reg_pass}" "${awf_reg_auth}")"
    else
      log_warn "REGISTRY_USERNAME/REGISTRY_PASSWORD not set - Argo Workflows image push will fail until configured."
      awf_dockercfg='{"auths":{}}'
    fi
    kubectl create secret generic "${J2026_ARGOWF_REGISTRY_SECRET}" \
      -n "${J2026_ARGOWF_RUN_NAMESPACE}" \
      --type=kubernetes.io/dockerconfigjson \
      --from-literal=.dockerconfigjson="${awf_dockercfg}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  if [[ -z "${awf_git_token}" ]]; then
    log_warn "GIT_TOKEN not set - Argo Workflows git push (GitOps deploy) and SARIF upload will fail until configured."
  fi
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    provision_secret "${J2026_ARGOWF_RUN_NAMESPACE}" "${J2026_ARGOWF_GIT_SECRET}" \
      "username=${awf_git_user:-git}" "password=${awf_git_token}"
  else
    kubectl create secret generic "${J2026_ARGOWF_GIT_SECRET}" \
      -n "${J2026_ARGOWF_RUN_NAMESPACE}" \
      --type=kubernetes.io/basic-auth \
      --from-literal=username="${awf_git_user:-git}" \
      --from-literal=password="${awf_git_token}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  # GitHub HMAC secret for the Argo Events EventSource (argoworkflows/events/eventsource.yaml,
  # in argo-events). Optional; generated-if-absent and kept STABLE so 06-argoworkflows-pipelines
  # shares it with the GitHub webhooks. Reuses ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET / PAC_WEBHOOK_SECRET.
  if [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
    awf_webhook="$(sm_keep_or_generate argoworkflows-github-webhook secret "${ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET:-${PAC_WEBHOOK_SECRET:-$(openssl rand -hex 20)}}")"
    provision_secret "${J2026_ARGOWF_EVENTS_NAMESPACE}" argoworkflows-github-webhook "secret=${awf_webhook}"
  else
    kubectl create secret generic argoworkflows-github-webhook \
      -n "${J2026_ARGOWF_EVENTS_NAMESPACE}" \
      --from-literal=secret="${ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET:-${PAC_WEBHOOK_SECRET:-}}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  # Optional Grafana Cloud k6 streaming for the k6 Workflow step (parity with tekton k6-cloud).
  provision_secret "${J2026_ARGOWF_RUN_NAMESPACE}" k6-cloud \
    "token=${K6_CLOUD_TOKEN:-}" \
    "project-id=${K6_CLOUD_PROJECT_ID:-}" \
    "grafana-base-url=${GRAFANA_BASE_URL:-}"
fi

# Static platform RBAC (Jenkins/Tekton SA 'edit' bindings + the pgAdmin
# secret-reader Role/binding) is now GitOps-owned by the ArgoCD `platform-config`
# app (argocd/platform-config/, planted by 08.5-argocd.sh) — it's timing-insensitive
# (its consumers, the CI pipelines and pgAdmin, run long after ArgoCD syncs). The
# NetworkPolicies + ResourceQuotas/LimitRanges below stay here on purpose: they must
# land BEFORE workloads for Dataplane V2 enforcement timing. See argocd/README.md.

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
for ns in "${MS_NAMESPACES[@]}"; do
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
    requests.cpu: "500m"
    requests.memory: 512Mi
    limits.cpu: "1.0"
    limits.memory: 1.0Gi
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
# Develop tier: the additive 'microservices-cnpg-platform' policy hardcodes
# namespace: microservices (stable). Replicate it into the develop namespace so its
# pods get the same CNPG (5432) / API-server (443, Hazelcast) / WI-metadata egress +
# 9187 metrics ingress. (The OTLP ingress allow in observability-policy and pgAdmin's
# egress already list microservices-develop statically — see networkpolicies.yaml.)
if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
  yq eval 'select(.metadata.name == "microservices-cnpg-platform") | .metadata.namespace = env(J2026_MICROSERVICES_DEVELOP_NAMESPACE)' \
    "${J2026_ROOT_DIR}/infrastructure/networkpolicies.yaml" | kubectl apply -f -
fi
# Jenkins-namespace NetworkPolicies only when ci.engine=jenkins (no jenkins ns in
# tekton mode - applying them there fails with 'namespaces "jenkins" not found').
if [[ "${J2026_CI_ENGINE}" == "jenkins" ]]; then
  kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies-jenkins.yaml"
fi
# Tekton-namespace baseline only when ci.engine=tekton (no tekton-ci ns otherwise).
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies-tekton.yaml"
fi
# ARC runner-namespace baseline only when ci.engine=githubactions (no arc-runners ns
# otherwise). Egress to GitHub/GHCR (runner registration + image pull), the OTel
# collector (build/k6 spans), the API server, and the microservices namespaces.
if [[ "${J2026_CI_ENGINE}" == "githubactions" ]]; then
  kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies-githubactions.yaml"
fi
# Argo Workflows execution-namespace (argo-ci) baseline only when ci.engine=argoworkflows.
# Egress to GitHub/GHCR, the OTel collector (4317), the API server, and microservices.
if [[ "${J2026_CI_ENGINE}" == "argoworkflows" ]]; then
  kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies-argoworkflows.yaml"
fi

# Node Auto-Provisioning (NAP): apply the Custom ComputeClass that backs Spot,
# scale-to-zero CI-agent nodes (the GKE-native equivalent of a Karpenter NodePool). NAP
# itself is enabled at the cluster level by terraform/gke; this just registers the class
# Pods select via `cloud.google.com/compute-class`. NON-FATAL by design: no platform pod
# depends on it, so a transient ComputeClass API hiccup (e.g. the CRD not yet reconciled
# on a brand-new cluster) must never fail the provision. The class is cluster-scoped, so
# it's only meaningful on GKE.
if [[ "${J2026_PLATFORM}" == "gke" && "${J2026_NODE_AUTOPROVISIONING_ENABLED}" == "true" ]]; then
  log_step "Applying Node Auto-Provisioning ComputeClass (${J2026_NODE_AUTOPROVISIONING_COMPUTE_CLASS})"
  if kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/compute-classes/"; then
    log_info "ComputeClass '${J2026_NODE_AUTOPROVISIONING_COMPUTE_CLASS}' applied — CI agents will provision Spot nodes on demand."
  else
    log_warn "ComputeClass apply failed (NAP may not be ready yet). Continuing — this is non-fatal; re-run Day1 to converge."
  fi
fi

# GKE NEG finalizer self-heal: GKE's NEG controller has a known issue where if a Service
# is deleted and recreated (or updated) with the same name, the old ServiceNetworkEndpointGroup
# (svcneg) gets stuck in "Terminating" (Pending deletion) because the finalizer is blocked.
# Clean up any stuck terminating svcnegs by removing their finalizers.
if [[ "${J2026_PLATFORM}" == "gke" ]] && kubectl get crd servicenetworkendpointgroups.networking.gke.io >/dev/null 2>&1; then
  log_step "Self-heal: cleaning up stuck terminating GKE ServiceNetworkEndpointGroups"
  stuck_negs=$(kubectl get svcneg -A -o jsonpath="{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.namespace}/{.metadata.name}{' '}{end}")
  for neg in ${stuck_negs}; do
    ns="${neg%/*}"
    name="${neg#*/}"
    log_warn "Clearing finalizer from stuck GKE svcneg: ${ns}/${name}"
    kubectl patch svcneg "${name}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":null}}' || true
  done
fi

log_info "Namespaces ready."

