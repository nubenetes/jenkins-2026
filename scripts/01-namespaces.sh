#!/usr/bin/env bash
# Creates the namespaces used by this PoC, the "jenkins-credentials" Secret
# consumed by helm/jenkins/values-common.yaml, and grants the Jenkins
# controller's ServiceAccount "edit" access in both PetClinic namespaces so
# pipelines can `helm upgrade`/`kubectl apply` their deployments. Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

log_step "Creating namespaces"
for ns in "${J2026_JENKINS_NAMESPACE}" "${J2026_OBS_NAMESPACE}" "${J2026_PETCLINIC_NS_STABLE}" "${J2026_PETCLINIC_NS_DEVELOP}" "${J2026_PETCLINIC_NS_PAC_DEV}"; do
  kubectl_apply_namespace "${ns}"
done

log_step "Ensuring '${J2026_JENKINS_CREDENTIALS_SECRET}' Secret in ${J2026_JENKINS_NAMESPACE}"
if kubectl get secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" >/dev/null 2>&1; then
  log_info "Secret already exists - leaving it untouched."
  log_info "(to rotate the admin/platform-engineer passwords, delete the secret and re-run this script)"
else
  # ADMIN_PASSWORD/PLATFORM_ENGINEER_PASSWORD can be supplied via env for
  # reproducible demos; otherwise random ones are generated and printed once
  # below. `openssl rand` writes a fixed-size, finite stream (unlike
  # `/dev/urandom | head`, which makes `tr` die with SIGPIPE -> exit 141
  # under `set -o pipefail`).
  admin_password="${ADMIN_PASSWORD:-$(openssl rand -base64 24 | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c20)}"
  platform_engineer_password="${PLATFORM_ENGINEER_PASSWORD:-$(openssl rand -base64 24 | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c20)}"

  kubectl create secret generic "${J2026_JENKINS_CREDENTIALS_SECRET}" \
    -n "${J2026_JENKINS_NAMESPACE}" \
    --from-literal=admin-password="${admin_password}" \
    --from-literal=platform-engineer-password="${platform_engineer_password}" \
    --from-literal=otel-logs-backend-url="${OTEL_LOGS_BACKEND_URL:-}" \
    --from-literal=grafana-base-url="${GRAFANA_BASE_URL:-}" \
    --from-literal=grafana-traces-dashboard-uid="${GRAFANA_TRACES_DASHBOARD_UID:-}" \
    --from-literal=registry-username="${REGISTRY_USERNAME:-}" \
    --from-literal=registry-password="${REGISTRY_PASSWORD:-}" \
    --from-literal=git-username="${GIT_USERNAME:-}" \
    --from-literal=git-token="${GIT_TOKEN:-}"

  log_info "Created. Jenkins admin login: ${J2026_JENKINS_ADMIN_USER} / ${admin_password}"
  log_info "Created. Jenkins platform-engineer login (pac-dev/* pipelines-as-code sandbox): ${J2026_PLATFORM_ENGINEER_USER} / ${platform_engineer_password}"
  log_warn "Save these passwords now - they are not printed again on subsequent runs."
fi

log_step "Granting Jenkins ServiceAccount 'edit' in PetClinic namespaces"
for ns in "${J2026_PETCLINIC_NS_STABLE}" "${J2026_PETCLINIC_NS_DEVELOP}" "${J2026_PETCLINIC_NS_PAC_DEV}"; do
  kubectl create rolebinding jenkins-edit \
    --clusterrole=edit \
    --serviceaccount="${J2026_JENKINS_NAMESPACE}:jenkins" \
    -n "${ns}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

# 'ghcr-credentials' imagePullSecret (helm/petclinic values-*.yaml
# imagePullSecret) - same REGISTRY_USERNAME/REGISTRY_PASSWORD the
# "container-registry" Jenkins credential (jenkins/casc/jcasc-base.yaml) uses
# to push images, since pipelines push to PETCLINIC_REGISTRY as private
# packages by default. Without these env vars, an empty-auths secret is
# created so the Deployments still reference a valid secret name and fall
# back to anonymous pulls (fine for public images).
log_step "Ensuring 'ghcr-credentials' imagePullSecret in PetClinic namespaces"
registry_host="${J2026_PETCLINIC_REGISTRY%%/*}"
if [[ -n "${REGISTRY_USERNAME:-}" && -n "${REGISTRY_PASSWORD:-}" ]]; then
  registry_auth="$(printf '%s:%s' "${REGISTRY_USERNAME}" "${REGISTRY_PASSWORD}" | base64 -w0)"
  dockerconfigjson="$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
    "${registry_host}" "${REGISTRY_USERNAME}" "${REGISTRY_PASSWORD}" "${registry_auth}")"
else
  dockerconfigjson='{"auths":{}}'
fi
for ns in "${J2026_PETCLINIC_NS_STABLE}" "${J2026_PETCLINIC_NS_DEVELOP}" "${J2026_PETCLINIC_NS_PAC_DEV}"; do
  kubectl create secret generic ghcr-credentials \
    -n "${ns}" \
    --type=kubernetes.io/dockerconfigjson \
    --from-literal=.dockerconfigjson="${dockerconfigjson}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

log_info "Namespaces ready."
