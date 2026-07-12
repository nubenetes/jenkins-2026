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
# Idempotent. See docs/404-TEKTON.md.
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

# --- access-URL annotations (Tekton parity for the Jenkins systemMessage banner) --
# Tekton's Dashboard has no system banner, so surface the same engine-neutral public
# URLs (the set 09-gateway.sh exposes, incl. the optional microservices-develop tier)
# as jenkins2026.io/url-* annotations on every PipelineRun this script seeds — they
# render in the Dashboard's run-detail view. Empty/no-op when the gateway is disabled.
pr_ann_pairs=()
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  pr_ann_pairs+=("jenkins2026.io/url-microservices=https://${J2026_GATEWAY_MICROSERVICES_HOST}")
  [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]] \
    && pr_ann_pairs+=("jenkins2026.io/url-microservices-develop=https://${J2026_GATEWAY_MICROSERVICES_DEVELOP_HOST}")
  pr_ann_pairs+=("jenkins2026.io/url-tekton-dashboard=https://${J2026_GATEWAY_TEKTON_HOST}")
  pr_ann_pairs+=("jenkins2026.io/url-argocd=https://argocd.${J2026_GATEWAY_BASE_DOMAIN}")
  pr_ann_pairs+=("jenkins2026.io/url-headlamp=https://${J2026_GATEWAY_HEADLAMP_HOST}")
  pr_ann_pairs+=("jenkins2026.io/url-pgadmin=https://${J2026_GATEWAY_PGADMIN_HOST}")
  [[ "${J2026_OBS_MODE}" == "oss" ]] \
    && pr_ann_pairs+=("jenkins2026.io/url-grafana=https://${J2026_GATEWAY_GRAFANA_HOST}")
fi
# Two forms derived once: a JSON object (merged into the committed tekton/runs/*.yaml
# via yq) and a pre-indented YAML block (embedded under metadata: in the generated
# heredocs). Both are empty/no-ops without a gateway.
pr_ann_json="{}"
pr_ann_yaml=""    # lines indented 4 spaces, to sit under a `  annotations:` key
pr_ann_meta=""    # a full `\n  annotations:<lines>` block, or empty
if (( ${#pr_ann_pairs[@]} > 0 )); then
  pr_ann_json="$(printf '%s\n' "${pr_ann_pairs[@]}" \
    | jq -Rn '[inputs | split("=") | {(.[0]): (.[1:] | join("="))}] | add')"
  for kv in "${pr_ann_pairs[@]}"; do
    pr_ann_yaml+=$'\n'"    ${kv%%=*}: \"${kv#*=}\""
  done
  pr_ann_meta=$'\n  annotations:'"${pr_ann_yaml}"
fi

# --- run-pod node placement (tekton.runNodePool: static|ci-spot) ----------------
# Patch config-defaults.default-pod-template so EVERY PipelineRun (seeded, PaC-triggered,
# or Dashboard-created) places its pods — and the affinity assistant they're co-scheduled
# around — predictably. ArgoCD ignores this field (ignoreDifferences in
# argocd/tekton/templates/pipelines.yaml), so this imperative patch isn't reverted.
#   static  (default): the long-lived jenkins-2026-pool (app=jenkins-2026, e2-standard-8) —
#           robust, no NAP/Spot/quota dependency. RECOMMENDED: the affinity assistant pins a
#           whole RWO-workspace run to one node, so a small/full node hangs it and a Spot
#           preemption would kill the whole run.
#   ci-spot: the NAP Spot ComputeClass (needs nodeAutoProvisioning.enabled) — cheaper but
#           Spot/quota-dependent (opt-in). See docs/404.
if [[ "${J2026_TEKTON_RUN_NODE_POOL}" == "ci-spot" && "${J2026_NODE_AUTOPROVISIONING_ENABLED}" == "true" ]]; then
  _cc="${J2026_NODE_AUTOPROVISIONING_COMPUTE_CLASS}"
  tekton_pod_template="$(cat <<EOF
nodeSelector:
  cloud.google.com/compute-class: ${_cc}
tolerations:
  - key: cloud.google.com/compute-class
    operator: Equal
    value: ${_cc}
    effect: NoSchedule
  - key: cloud.google.com/gke-spot
    operator: Equal
    value: "true"
    effect: NoSchedule
EOF
)"
  _placement="ci-spot ComputeClass (${_cc})"
else
  tekton_pod_template=$'nodeSelector:\n  app: jenkins-2026\n'
  _placement="static pool (app=jenkins-2026)"
fi
log_step "Setting Tekton run-pod placement -> ${_placement}"
if kubectl -n "${J2026_TEKTON_NAMESPACE}" get configmap config-defaults >/dev/null 2>&1; then
  kubectl -n "${J2026_TEKTON_NAMESPACE}" patch configmap config-defaults --type merge \
    -p "$(jq -nc --arg pt "${tekton_pod_template}" '{data:{"default-pod-template":$pt}}')" >/dev/null
  log_info "config-defaults.default-pod-template set (${_placement})."
else
  log_warn "config-defaults not present yet — skipping placement patch (re-run to converge)."
fi

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

    # 1) Reconcile the fork's hooks. GitHub allows many, and a CI-engine switch leaves the
    #    previous engine's hook behind (e.g. argo-events' argo-events.<domain>/push) 404ing
    #    forever. Prune any hook pointing at THIS project's base domain that isn't the desired
    #    PaC URL, then ensure the desired one exists (hooks to unrelated hosts are left
    #    untouched). Makes an engine switch self-heal on the fork side too.
    hooks_json="$(curl -fsS -H "Authorization: token ${GIT_TOKEN}" \
      "https://api.github.com/repos/${repo_path}/hooks" 2>/dev/null || echo '[]')"
    have_desired=false
    while IFS=$'\t' read -r hid hurl; do
      [[ -z "${hid}" ]] && continue
      if [[ "${hurl}" == "${pac_url}" ]]; then have_desired=true; continue; fi
      if [[ "${hurl}" == *".${J2026_GATEWAY_BASE_DOMAIN}"* ]]; then
        curl -fsS -X DELETE -H "Authorization: token ${GIT_TOKEN}" \
          "https://api.github.com/repos/${repo_path}/hooks/${hid}" >/dev/null 2>&1 \
          && log_info "  pruned stale webhook on ${repo_path} (${hurl})" || true
      fi
    done < <(printf '%s' "${hooks_json}" | jq -r '.[] | "\(.id)\t\(.config.url)"' 2>/dev/null)

    if [[ "${have_desired}" == "true" ]]; then
      # Reconcile-to-current (docs/104): the fork hook PERSISTS across cluster
      # rebuilds while the in-cluster HMAC regenerates (or gets clobbered -
      # found live 2026-07-12: a 01 re-run without PAC_WEBHOOK_SECRET reset the
      # secret to "" while this hook kept signing with the old value, and PaC
      # hard-rejects deliveries on an empty/mismatched secret). Re-assert the
      # current value on the existing hook instead of trusting it.
      hid="$(printf '%s' "${hooks_json}" | jq -r --arg url "${pac_url}" \
        '.[] | select(.config.url==$url) | .id' 2>/dev/null | head -1)"
      hook_patch="$(jq -nc --arg url "${pac_url}" --arg secret "${webhook_secret}" \
        '{config:{url:$url,content_type:"json",insecure_ssl:"0",secret:$secret}}')"
      if curl -fsS -X PATCH -H "Authorization: token ${GIT_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo_path}/hooks/${hid}" \
        -d "${hook_patch}" >/dev/null 2>&1; then
        log_info "  webhook already present on ${repo_path} - HMAC re-asserted"
      else
        log_warn "  webhook present on ${repo_path} but the HMAC re-assert failed - if PaC logs show 'could not validate payload', update the hook secret in the fork's Settings -> Webhooks to the pac-webhook value"
      fi
    else
      # Build the JSON with yq env() so a secret/URL containing special characters
      # is escaped correctly. A printf-built body produces invalid JSON when the
      # value has a quote/backslash/newline -> GitHub rejects it with HTTP 400
      # ("Problems parsing JSON"), which is the most common cause of a failed hook
      # create here. One POST only; capture HTTP code + body to report WHY on error.
      hook_payload="$(jq -nc --arg url "${pac_url}" --arg secret "${webhook_secret}" \
        '{name:"web",active:true,events:["push","pull_request"],config:{url:$url,content_type:"json",insecure_ssl:"0",secret:$secret}}')"
      hook_resp="$(curl -sS -w $'\n%{http_code}' -X POST \
        -H "Authorization: token ${GIT_TOKEN}" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo_path}/hooks" -d "${hook_payload}" 2>/dev/null)"
      hook_code="${hook_resp##*$'\n'}"; hook_body="${hook_resp%$'\n'*}"
      if [[ "${hook_code}" =~ ^2 ]]; then
        log_info "  webhook created on ${repo_path}"
      else
        hook_msg="$(printf '%s' "${hook_body}" | jq -r '.message // empty' 2>/dev/null || true)"
        log_warn "  could not create webhook on ${repo_path} (HTTP ${hook_code}: ${hook_msg:-see GitHub}). PaC still runs via the committed .tekton/${name}.yaml IF a webhook to ${pac_url} already exists; otherwise add one in the fork's Settings -> Webhooks (content-type=json, events: push + pull_request, secret = the pac-webhook value)."
      fi
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
  # Backstage's Kubernetes-backend fetch rides app.kubernetes.io/name (docs/505,
  # same contract as tekton/runs/*.yaml + the TriggerTemplate): PaC preserves
  # authored labels and only adds its own pipelinesascode.tekton.dev/* set.
  labels:
    jenkins2026.io/service: ${name}
    jenkins2026.io/env: stable
    app.kubernetes.io/name: ${name}
  annotations:
    pipelinesascode.tekton.dev/on-event: "[push, pull_request]"
    pipelinesascode.tekton.dev/on-target-branch: "[main]"
    pipelinesascode.tekton.dev/max-keep-runs: "5"${pr_ann_yaml}
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
  # Opt-in (tekton.seedRuns / JENKINS2026_TEKTON_SEED_RUNS): also kick one run per
  # service now from the same tekton/runs/ manifests used for manual one-click, so
  # the Dashboard is pre-populated with runnable entries (Rerun) from the first
  # Day1. Costs one build per service; PaC's git-push trigger remains the default.
  if [[ "${J2026_TEKTON_SEED_RUNS}" == "true" ]]; then
    log_step "tekton.seedRuns=true - seeding PipelineRuns from tekton/runs/ (one build per service)"
    for rf in "${J2026_ROOT_DIR}"/tekton/runs/*.yaml; do
      [[ -f "${rf}" ]] || continue
      # Gate develop-tier runs behind the develop-track feature flag — parity with the
      # Jenkins seed, which only generates *-develop jobs when developTrackEnabled. Any
      # run labelled jenkins2026.io/env=develop (the *-develop service runs + the k6
      # develop run) is skipped when the track is off; stable runs always seed.
      run_env="$(yq eval '.metadata.labels."jenkins2026.io/env" // "stable"' "${rf}" 2>/dev/null)"
      if [[ "${run_env}" == "develop" && "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" != "true" ]]; then
        log_info "  skipping $(basename "${rf}") (develop track disabled)"
        continue
      fi
      # Merge the access-URL annotations in (no-op without a gateway) so the seeded
      # runs carry the same banner-parity URLs as the PaC/fallback ones.
      src="${rf}"
      if [[ "${pr_ann_json}" != "{}" ]]; then
        src="${GEN_DIR}/seed-$(basename "${rf}")"
        # `*` (deep-merge) not `+`: map addition isn't supported on older yq (the
        # local v4.16), while `*` merges maps on every yq v4 and keeps existing keys.
        yq eval ".metadata.annotations = ((.metadata.annotations // {}) * ${pr_ann_json})" "${rf}" > "${src}"
      fi
      # Retry: the first create right after 04-tekton restarted the Tekton
      # admission webhook can hit it mid-warm-up (the webhook validates every
      # PipelineRun), so a single attempt occasionally flakes on the first file.
      seeded=false
      for attempt in 1 2 3; do
        if kubectl create -f "${src}" >/dev/null 2>&1; then seeded=true; break; fi
        sleep 5
      done
      if [[ "${seeded}" == "true" ]]; then
        log_info "  seeded $(basename "${rf}")"
      else
        log_warn "  could not seed $(basename "${rf}") after 3 tries (Tekton admission webhook warming up? namespace tekton-ci / SA tekton-ci)"
      fi
    done
  fi
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
  namespace: ${PIPELINE_NS}${pr_ann_meta}
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
