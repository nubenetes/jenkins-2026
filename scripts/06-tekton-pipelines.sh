#!/usr/bin/env bash
# Activates the Tekton CI for the microservices. The Tasks/Pipelines/Triggers/RBAC
# and the PaC Repository CRs under tekton/ are GitOps-managed by ArgoCD (applied
# by 04-tekton.sh via the tekton app-of-apps); this script does the imperative
# "activation" ArgoCD can't:
#
#   - PaC mode (gateway enabled + PaC controller present): for each service, push
#     a .tekton/<svc>.yaml PipelineRun to its (owned) nubenetes fork and ensure a
#     GitHub webhook -> the public PaC controller. PaC then runs the pipeline on
#     every push/PR. This is the primary, Git-driven CI model.
#   - Fallback (gateway disabled / PaC absent, e.g. local): generate + kick one
#     PipelineRun per service directly (the seed model).
#
# Idempotent. See docs/403-TEKTON.md.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

if [[ "${J2026_CI_ENGINE}" != "tekton" ]]; then
  log_info "ci.engine='${J2026_CI_ENGINE}' (not tekton) - skipping Tekton pipelines."
  exit 0
fi

PIPELINE_NS="${J2026_TEKTON_PIPELINE_NAMESPACE}"
SERVICES_YAML="${J2026_ROOT_DIR}/jenkins/pipelines/seed/services.yaml"
GEN_DIR="${J2026_ROOT_DIR}/.generated/tekton"
mkdir -p "${GEN_DIR}"
otlp_endpoint="http://otel-collector-gateway.${J2026_OBS_NAMESPACE}.svc.cluster.local:4317"
registry_host="${J2026_MICROSERVICES_REGISTRY%%/*}"

# Wait for ArgoCD to have synced the Pipeline + the pipeline ServiceAccount.
log_step "Waiting for ArgoCD to sync the Tekton pipelines-as-code into ${PIPELINE_NS}"
timeout 600 bash -c '
  until kubectl -n "'"${PIPELINE_NS}"'" get pipeline microservices-pipeline >/dev/null 2>&1 \
     && kubectl -n "'"${PIPELINE_NS}"'" get serviceaccount tekton-ci >/dev/null 2>&1; do
    sleep 10
  done
' || { log_error "microservices-pipeline / tekton-ci SA not present within 10m - check 'kubectl -n ${J2026_ARGOCD_NAMESPACE} get application tekton-pipeline-as-code'"; exit 1; }

svc_count="$(yq eval '.services | length' "${SERVICES_YAML}")"

# --- decide mode -------------------------------------------------------------
# PaC needs the public gateway (GitHub must reach the controller) and the PaC
# controller running.
PAC_ENABLED=false
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]] \
   && kubectl -n pipelines-as-code get deploy pipelines-as-code-controller >/dev/null 2>&1; then
  PAC_ENABLED=true
fi

# Ensure the pac-webhook secret has a value shared between the cluster and the
# GitHub webhooks. If 01-namespaces created it empty (PAC_WEBHOOK_SECRET unset),
# generate a random one and patch it so HMAC validation works.
ensure_pac_webhook_secret() {
  local val
  val="$(kubectl -n "${PIPELINE_NS}" get secret pac-webhook -o jsonpath='{.data.webhook\.secret}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  if [[ -z "${val}" ]]; then
    val="$(openssl rand -hex 20)"
    kubectl -n "${PIPELINE_NS}" create secret generic pac-webhook \
      --from-literal=webhook.secret="${val}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    log_info "Generated a pac-webhook HMAC secret (none was provided)."
  fi
  printf '%s' "${val}"
}

# repo_path_from_url <https url> -> owner/repo
repo_path_from_url() { echo "$1" | sed -E 's#^https?://github.com/##; s#\.git$##'; }

if [[ "${PAC_ENABLED}" == "true" ]]; then
  [[ -z "${GIT_TOKEN:-}" ]] && { log_error "GIT_TOKEN unset - cannot push .tekton/ or create webhooks for PaC."; exit 1; }
  webhook_secret="$(ensure_pac_webhook_secret)"
  pac_url="https://${J2026_GATEWAY_PAC_HOST}"
  git_user="${GIT_USERNAME:-git}"
  log_step "Activating Pipelines-as-Code on the forks (webhook -> ${pac_url})"

  for i in $(seq 0 $((svc_count - 1))); do
    name="$(yq eval ".services[${i}].name" "${SERVICES_YAML}")"
    type="$(yq eval ".services[${i}].type // \"java\"" "${SERVICES_YAML}")"
    repo="$(yq eval ".services[${i}].repoUrl" "${SERVICES_YAML}")"
    module="$(yq eval ".services[${i}].module // \"\"" "${SERVICES_YAML}")"
    port="$(yq eval ".services[${i}].port" "${SERVICES_YAML}")"
    health="$(yq eval ".services[${i}].healthPath" "${SERVICES_YAML}")"
    repo_path="$(repo_path_from_url "${repo}")"

    # 1) Ensure the GitHub webhook (idempotent: skip if one already targets pac_url).
    existing="$(curl -fsS -H "Authorization: token ${GIT_TOKEN}" \
      "https://api.github.com/repos/${repo_path}/hooks" 2>/dev/null \
      | yq -p=json -o=tsv '.[].config.url' 2>/dev/null | grep -Fx "${pac_url}" || true)"
    if [[ -z "${existing}" ]]; then
      hook_payload="$(printf '{"name":"web","active":true,"events":["push","pull_request"],"config":{"url":"%s","content_type":"json","insecure_ssl":"0","secret":"%s"}}' "${pac_url}" "${webhook_secret}")"
      curl -fsS -X POST -H "Authorization: token ${GIT_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo_path}/hooks" \
        -d "${hook_payload}" \
        >/dev/null && log_info "  webhook created on ${repo_path}" \
        || log_warn "  could not create webhook on ${repo_path}"
    else
      log_info "  webhook already present on ${repo_path}"
    fi

    # 2) Push .tekton/<name>.yaml to the fork (triggers the first PaC run).
    work="$(mktemp -d)"
    if git clone --depth 1 "https://${git_user}:${GIT_TOKEN}@github.com/${repo_path}.git" "${work}" >/dev/null 2>&1; then
      mkdir -p "${work}/.tekton"
      cat >"${work}/.tekton/${name}.yaml" <<EOT
# Managed by jenkins-2026 (scripts/06-tekton-pipelines.sh). Tekton Pipelines-as-Code
# runs this on push/PR to main; it references the in-cluster microservices-pipeline.
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: ${name}
  annotations:
    pipelinesascode.tekton.dev/on-event: "[push, pull_request]"
    pipelinesascode.tekton.dev/on-target-branch: "[main]"
    pipelinesascode.tekton.dev/max-keep-runs: "5"
spec:
  taskRunTemplate:
    serviceAccountName: tekton-ci
  # Resolve the in-cluster Pipeline via the cluster resolver. A bare
  # 'pipelineRef: {name: ...}' makes Pipelines-as-Code try to fetch the Pipeline
  # from the git repo (it's not in .tekton/) and fail with "cannot find referenced
  # pipeline". The cluster resolver defers resolution to Tekton at runtime, reading
  # microservices-pipeline (and its Tasks) from the ${J2026_TEKTON_PIPELINE_NAMESPACE} namespace.
  pipelineRef:
    resolver: cluster
    params:
      - {name: kind, value: pipeline}
      - {name: name, value: microservices-pipeline}
      - {name: namespace, value: ${J2026_TEKTON_PIPELINE_NAMESPACE}}
  params:
    - {name: service-name, value: "${name}"}
    - {name: service-type, value: "${type}"}
    - {name: git-repo-url, value: "${repo}"}
    - {name: git-branch, value: "{{ source_branch }}"}
    - {name: module-path, value: "${module}"}
    - {name: target-namespace, value: "${J2026_MICROSERVICES_NS_STABLE}"}
    - {name: env-name, value: "stable"}
    - {name: port, value: "${port}"}
    - {name: health-path, value: "${health}"}
    - {name: image, value: "${J2026_MICROSERVICES_REGISTRY}/${name}:{{ revision }}"}
    - {name: registry-host, value: "${registry_host}"}
    - {name: self-repo-url, value: "${J2026_SELF_REPO_URL}"}
    - {name: self-repo-branch, value: "${J2026_SELF_REPO_BRANCH}"}
    - {name: otlp-endpoint, value: "${otlp_endpoint}"}
  workspaces:
    - name: source
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources: {requests: {storage: 4Gi}}
    - name: dockerconfig
      secret:
        secretName: ${J2026_TEKTON_REGISTRY_SECRET}
        items: [{key: .dockerconfigjson, path: config.json}]
EOT
      ( cd "${work}"
        git config user.email "tekton@nubenetes.com"; git config user.name "jenkins-2026 CI"
        git add .tekton/"${name}.yaml"
        if ! git diff --cached --quiet; then
          git commit -q -m "ci(tekton): add/update .tekton/${name}.yaml (Pipelines-as-Code)"
          git push -q origin HEAD && log_info "  pushed .tekton/${name}.yaml to ${repo_path}"
        else
          log_info "  .tekton/${name}.yaml already up to date on ${repo_path}"
        fi ) || log_warn "  could not push .tekton/ to ${repo_path}"
    else
      log_warn "  could not clone ${repo_path} to add .tekton/"
    fi
    rm -rf "${work}"
  done
  log_info "PaC activated. Pushes/PRs to the forks now run microservices-pipeline; watch the Tekton Dashboard."
  exit 0
fi

# --- fallback: seed model (no gateway/PaC) - kick one PipelineRun per service --
envs=(stable)
[[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]] && envs+=(develop)
log_step "PaC not enabled (no gateway) - generating PipelineRuns for ${svc_count} service(s) directly"
created=0
for i in $(seq 0 $((svc_count - 1))); do
  name="$(yq eval ".services[${i}].name" "${SERVICES_YAML}")"
  type="$(yq eval ".services[${i}].type // \"java\"" "${SERVICES_YAML}")"
  repo="$(yq eval ".services[${i}].repoUrl" "${SERVICES_YAML}")"
  module="$(yq eval ".services[${i}].module // \"\"" "${SERVICES_YAML}")"
  port="$(yq eval ".services[${i}].port" "${SERVICES_YAML}")"
  health="$(yq eval ".services[${i}].healthPath" "${SERVICES_YAML}")"
  for env in "${envs[@]}"; do
    if [[ "${env}" == "stable" ]]; then
      ns="${J2026_MICROSERVICES_NS_STABLE}"; src_branch="${J2026_MICROSERVICES_BRANCH_STABLE}"
    else
      ns="${J2026_MICROSERVICES_DEVELOP_NAMESPACE}"; src_branch="main"
    fi
    run_file="${GEN_DIR}/pipelinerun-${name}-${env}.yaml"
    cat >"${run_file}" <<EOT
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ${name}-${env}-
  namespace: ${PIPELINE_NS}
  labels: {jenkins2026.io/service: "${name}", jenkins2026.io/env: "${env}"}
spec:
  taskRunTemplate: {serviceAccountName: tekton-ci}
  pipelineRef: {name: microservices-pipeline}
  params:
    - {name: service-name, value: "${name}"}
    - {name: service-type, value: "${type}"}
    - {name: git-repo-url, value: "${repo}"}
    - {name: git-branch, value: "${src_branch}"}
    - {name: module-path, value: "${module}"}
    - {name: target-namespace, value: "${ns}"}
    - {name: env-name, value: "${env}"}
    - {name: port, value: "${port}"}
    - {name: health-path, value: "${health}"}
    - {name: image, value: "${J2026_MICROSERVICES_REGISTRY}/${name}:${src_branch}"}
    - {name: registry-host, value: "${registry_host}"}
    - {name: self-repo-url, value: "${J2026_SELF_REPO_URL}"}
    - {name: self-repo-branch, value: "${J2026_SELF_REPO_BRANCH}"}
    - {name: otlp-endpoint, value: "${otlp_endpoint}"}
  workspaces:
    - name: source
      volumeClaimTemplate:
        spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: 4Gi}}}
    - name: dockerconfig
      secret:
        secretName: ${J2026_TEKTON_REGISTRY_SECRET}
        items: [{key: .dockerconfigjson, path: config.json}]
EOT
    if kubectl create -f "${run_file}" >/dev/null 2>&1; then
      log_info "  kicked PipelineRun for ${name} (${env})"; ((created++)) || true
    else
      log_warn "  failed to create PipelineRun for ${name} (${env})"
    fi
  done
done
log_info "${created} PipelineRun(s) kicked. Track with: kubectl get pipelinerun -n ${PIPELINE_NS}"
