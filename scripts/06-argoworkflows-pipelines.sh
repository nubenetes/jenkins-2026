#!/usr/bin/env bash
# Activates the Argo Workflows CI for the microservices. The WorkflowTemplates,
# EventSource/Sensor, RBAC + SA and the runs under argoworkflows/ are GitOps-managed by
# ArgoCD (applied by 04-argoworkflows.sh via the argoworkflows app-of-apps); this script
# does the imperative "activation" ArgoCD can't:
#
#   - Webhook mode (gateway enabled + Argo Events EventSource present): for each service,
#     ensure a GitHub webhook -> the public Argo Events EventSource Service (via the
#     argo-events.<domain> Gateway route). A push then fires the github EventSource, the
#     Sensor submits a Workflow from microservices-pipeline. This is the primary,
#     Git-driven CI model (the Argo Events analogue of Tekton Pipelines-as-Code).
#   - Fallback (gateway disabled / EventSource absent, e.g. local): generate + kick one
#     Workflow per service directly (the seed model).
#
# Idempotent. See docs/405-ARGO_WORKFLOWS.md.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

if [[ "${J2026_CI_ENGINE}" != "argoworkflows" ]]; then
  log_info "ci.engine='${J2026_CI_ENGINE}' (not argoworkflows) - skipping Argo Workflows pipelines."
  exit 0
fi

RUN_NS="${J2026_ARGOWF_RUN_NAMESPACE}"
EVENTS_NS="${J2026_ARGOWF_EVENTS_NAMESPACE}"
SERVICES_YAML="${J2026_ROOT_DIR}/jenkins/pipelines/seed/services.yaml"
GEN_DIR="${J2026_ROOT_DIR}/.generated/argoworkflows"
mkdir -p "${GEN_DIR}"
otlp_endpoint="http://otel-collector-gateway.${J2026_OBS_NAMESPACE}.svc.cluster.local:4317"
registry_host="${J2026_MICROSERVICES_REGISTRY%%/*}"

# --- access-URL annotations (Argo Workflows parity for the Jenkins systemMessage banner) --
# The Argo Workflows Server UI has no system banner, so surface the same engine-neutral
# public URLs (the set 09-gateway.sh exposes, incl. the optional microservices-develop
# tier) as jenkins2026.io/url-* annotations on every Workflow this script seeds — they
# render in the Server UI's run-detail view. Empty/no-op when the gateway is disabled.
pr_ann_pairs=()
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  pr_ann_pairs+=("jenkins2026.io/url-microservices=https://${J2026_GATEWAY_MICROSERVICES_HOST}")
  [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]] \
    && pr_ann_pairs+=("jenkins2026.io/url-microservices-develop=https://${J2026_GATEWAY_MICROSERVICES_DEVELOP_HOST}")
  pr_ann_pairs+=("jenkins2026.io/url-argoworkflows=https://${J2026_GATEWAY_ARGOWF_HOST}")
  pr_ann_pairs+=("jenkins2026.io/url-argocd=https://argocd.${J2026_GATEWAY_BASE_DOMAIN}")
  pr_ann_pairs+=("jenkins2026.io/url-headlamp=https://${J2026_GATEWAY_HEADLAMP_HOST}")
  pr_ann_pairs+=("jenkins2026.io/url-pgadmin=https://${J2026_GATEWAY_PGADMIN_HOST}")
  [[ "${J2026_OBS_MODE}" == "oss" ]] \
    && pr_ann_pairs+=("jenkins2026.io/url-grafana=https://${J2026_GATEWAY_GRAFANA_HOST}")
fi
# Two forms derived once: a JSON object (merged into the committed argoworkflows/runs/*.yaml
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

# --- run-pod node placement (argoworkflows.runNodePool: static|ci-spot) ----------
# Patch workflow-controller-configmap.workflowDefaults so EVERY Workflow (seeded,
# webhook-triggered, or UI-created) places its step pods predictably. ArgoCD ignores this
# field (ignoreDifferences in argocd/argoworkflows/templates/workflows.yaml), so this
# imperative patch isn't reverted.
#   static  (default): the long-lived jenkins-2026-pool (app=jenkins-2026, e2-standard-8) —
#           robust, no NAP/Spot/quota dependency. RECOMMENDED: a Workflow's steps share one
#           RWO 'source' workspace PVC bound to a single node, so a small/full node hangs it
#           and a Spot preemption would kill the whole run.
#   ci-spot: the NAP Spot ComputeClass (needs nodeAutoProvisioning.enabled) — cheaper but
#           Spot/quota-dependent (opt-in). See docs/405.
if [[ "${J2026_ARGOWORKFLOWS_RUN_NODE_POOL}" == "ci-spot" && "${J2026_NODE_AUTOPROVISIONING_ENABLED}" == "true" ]]; then
  _cc="${J2026_NODE_AUTOPROVISIONING_COMPUTE_CLASS}"
  argowf_workflow_defaults="$(cat <<EOF
spec:
  serviceAccountName: argoworkflows-ci
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
  argowf_workflow_defaults=$'spec:\n  serviceAccountName: argoworkflows-ci\n  nodeSelector:\n    app: jenkins-2026\n'
  _placement="static pool (app=jenkins-2026)"
fi
log_step "Setting Argo Workflows run-pod placement -> ${_placement}"
if kubectl -n "${J2026_ARGOWF_NAMESPACE}" get configmap workflow-controller-configmap >/dev/null 2>&1; then
  kubectl -n "${J2026_ARGOWF_NAMESPACE}" patch configmap workflow-controller-configmap --type merge \
    -p "$(jq -nc --arg wd "${argowf_workflow_defaults}" '{data:{"workflowDefaults":$wd}}')" >/dev/null
  log_info "workflow-controller-configmap.workflowDefaults set (${_placement})."
else
  log_warn "workflow-controller-configmap not present yet — skipping placement patch (re-run to converge)."
fi

# Wait for ArgoCD to have synced the WorkflowTemplate + the pipeline ServiceAccount.
log_step "Waiting for ArgoCD to sync the Argo Workflows pipelines-as-code into ${RUN_NS}"
timeout 600 bash -c '
  until kubectl -n "'"${RUN_NS}"'" get workflowtemplate microservices-pipeline >/dev/null 2>&1 \
     && kubectl -n "'"${RUN_NS}"'" get serviceaccount argoworkflows-ci >/dev/null 2>&1; do
    sleep 10
  done
' || { log_error "microservices-pipeline WorkflowTemplate / argoworkflows-ci SA not present within 10m - check 'kubectl -n ${J2026_ARGOCD_NAMESPACE} get application argoworkflows-pipeline-as-code'"; exit 1; }

svc_count="$(yq eval '.services | length' "${SERVICES_YAML}")"

# --- decide mode -------------------------------------------------------------
# The webhook trigger needs the public gateway (GitHub must reach the EventSource
# Service) and the Argo Events github EventSource Service running.
WEBHOOK_ENABLED=false
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]] \
   && kubectl -n "${EVENTS_NS}" get svc github-eventsource-svc >/dev/null 2>&1; then
  WEBHOOK_ENABLED=true
fi

# Ensure the argoworkflows-github-webhook secret has a value shared between the cluster
# and the GitHub webhooks. If 01-namespaces created it empty (no
# ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET provided), generate a random one and patch it so
# HMAC validation works. The Argo Events github EventSource reads it via
# webhookSecret: {name: argoworkflows-github-webhook, key: secret}.
ensure_github_webhook_secret() {
  local val
  val="$(kubectl -n "${EVENTS_NS}" get secret argoworkflows-github-webhook -o jsonpath='{.data.secret}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  if [[ -z "${val}" ]]; then
    val="$(openssl rand -hex 20)"
    kubectl -n "${EVENTS_NS}" create secret generic argoworkflows-github-webhook \
      --from-literal=secret="${val}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    log_info "Generated an argoworkflows-github-webhook HMAC secret (none was provided)."
  fi
  printf '%s' "${val}"
}

# repo_path_from_url <https url> -> owner/repo
repo_path_from_url() { echo "$1" | sed -E 's#^https?://github.com/##; s#\.git$##'; }

if [[ "${WEBHOOK_ENABLED}" == "true" ]]; then
  [[ -z "${GIT_TOKEN:-}" ]] && { log_error "GIT_TOKEN unset - cannot create webhooks for the Argo Events EventSource."; exit 1; }
  webhook_secret="$(ensure_github_webhook_secret)"
  # The github EventSource serves its handler at /push (spec.github.*.webhook.endpoint) and the
  # argo-events Gateway route forwards the full path, so the hook URL MUST include /push — a hook
  # to the bare host lands on '/', which the EventSource 404s.
  webhook_url="https://${J2026_GATEWAY_ARGOEVENTS_HOST}/push"
  log_step "Activating git-push webhooks on the forks (webhook -> ${webhook_url})"

  for i in $(seq 0 $((svc_count - 1))); do
    name="$(yq eval ".services[${i}].name" "${SERVICES_YAML}")"
    repo="$(yq eval ".services[${i}].repoUrl" "${SERVICES_YAML}")"
    repo_path="$(repo_path_from_url "${repo}")"

    # Reconcile the fork's hooks. GitHub allows many, and a CI-engine switch leaves the previous
    # engine's hook behind (e.g. Tekton's pac.<domain>) 404ing forever, while an older run may
    # have left a /push-less argo-events hook. Prune any hook pointing at THIS project's base
    # domain that isn't the desired URL, then ensure the desired one exists (hooks to unrelated
    # hosts are left untouched). Makes an engine switch self-heal on the fork side too.
    hooks_json="$(curl -fsS -H "Authorization: token ${GIT_TOKEN}" \
      "https://api.github.com/repos/${repo_path}/hooks" 2>/dev/null || echo '[]')"
    have_desired=false
    while IFS=$'\t' read -r hid hurl; do
      [[ -z "${hid}" ]] && continue
      if [[ "${hurl}" == "${webhook_url}" ]]; then have_desired=true; continue; fi
      if [[ "${hurl}" == *".${J2026_GATEWAY_BASE_DOMAIN}"* ]]; then
        curl -fsS -X DELETE -H "Authorization: token ${GIT_TOKEN}" \
          "https://api.github.com/repos/${repo_path}/hooks/${hid}" >/dev/null 2>&1 \
          && log_info "  pruned stale webhook on ${repo_path} (${hurl})" || true
      fi
    done < <(printf '%s' "${hooks_json}" | jq -r '.[] | "\(.id)\t\(.config.url)"' 2>/dev/null)

    if [[ "${have_desired}" == "true" ]]; then
      log_info "  webhook already present on ${repo_path}"
    else
      # Build the JSON with jq so a secret/URL containing special characters is escaped
      # correctly. A printf-built body produces invalid JSON when the value has a quote/
      # backslash/newline -> GitHub rejects it with HTTP 400 ("Problems parsing JSON"),
      # which is the most common cause of a failed hook create here. One POST only;
      # capture HTTP code + body to report WHY on error.
      hook_payload="$(jq -nc --arg url "${webhook_url}" --arg secret "${webhook_secret}" \
        '{name:"web",active:true,events:["push","pull_request"],config:{url:$url,content_type:"json",insecure_ssl:"0",secret:$secret}}')"
      hook_resp="$(curl -sS -w $'\n%{http_code}' -X POST \
        -H "Authorization: token ${GIT_TOKEN}" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo_path}/hooks" -d "${hook_payload}" 2>/dev/null)"
      hook_code="${hook_resp##*$'\n'}"; hook_body="${hook_resp%$'\n'*}"
      if [[ "${hook_code}" =~ ^2 ]]; then
        log_info "  webhook created on ${repo_path}"
      else
        hook_msg="$(printf '%s' "${hook_body}" | jq -r '.message // empty' 2>/dev/null || true)"
        log_warn "  could not create webhook on ${repo_path} (HTTP ${hook_code}: ${hook_msg:-see GitHub}). The Argo Events Sensor still runs IF a webhook to ${webhook_url} already exists; otherwise add one in the fork's Settings -> Webhooks (content-type=json, events: push + pull_request, secret = the argoworkflows-github-webhook value)."
      fi
    fi
  done
  log_info "Git-push webhooks activated. Pushes/PRs to the forks now fire the github EventSource; the microservices Sensor submits a Workflow from microservices-pipeline; watch the Argo Workflows UI."
  # Opt-in (argoworkflows.seedRuns / JENKINS2026_ARGOWORKFLOWS_SEED_RUNS): also kick one
  # run per service now from the same argoworkflows/runs/ manifests used for manual
  # one-click, so the Argo Workflows UI is pre-populated with runnable entries (Resubmit)
  # from the first Day1. Costs one build per service; the git-push webhook remains the
  # default.
  if [[ "${J2026_ARGOWF_SEED_RUNS}" == "true" ]]; then
    log_step "argoworkflows.seedRuns=true - seeding Workflows from argoworkflows/runs/ (one build per service)"
    for rf in "${J2026_ROOT_DIR}"/argoworkflows/runs/*.yaml; do
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
      # Merge the access-URL annotations in (no-op without a gateway) so the seeded runs
      # carry the same banner-parity URLs as the webhook/fallback ones.
      src="${rf}"
      if [[ "${pr_ann_json}" != "{}" ]]; then
        src="${GEN_DIR}/seed-$(basename "${rf}")"
        # `*` (deep-merge) not `+`: map addition isn't supported on older yq (the local
        # v4.16), while `*` merges maps on every yq v4 and keeps existing keys.
        yq eval ".metadata.annotations = ((.metadata.annotations // {}) * ${pr_ann_json})" "${rf}" > "${src}"
      fi
      # Retry: the first create right after 04-argoworkflows synced the Argo Workflows
      # admission webhook can hit it mid-warm-up (the webhook validates every Workflow),
      # so a single attempt occasionally flakes on the first file.
      seeded=false
      for attempt in 1 2 3; do
        if kubectl create -f "${src}" >/dev/null 2>&1; then seeded=true; break; fi
        sleep 5
      done
      if [[ "${seeded}" == "true" ]]; then
        log_info "  seeded $(basename "${rf}")"
      else
        log_warn "  could not seed $(basename "${rf}") after 3 tries (Argo Workflows admission webhook warming up? namespace ${RUN_NS} / SA argoworkflows-ci)"
      fi
    done
  fi
  exit 0
fi

# --- fallback: seed model (no gateway/EventSource) - kick one Workflow per service --
envs=(stable)
[[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]] && envs+=(develop)
log_step "Webhook trigger not enabled (no gateway) - generating Workflows for ${svc_count} service(s) directly"
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
    run_file="${GEN_DIR}/workflow-${name}-${env}.yaml"
    cat >"${run_file}" <<EOT
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: ${name}-${env}-
  namespace: ${RUN_NS}${pr_ann_meta}
  labels: {jenkins2026.io/service: "${name}", jenkins2026.io/env: "${env}"}
spec:
  serviceAccountName: argoworkflows-ci
  workflowTemplateRef: {name: microservices-pipeline}
  arguments:
    parameters:
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
EOT
    if kubectl create -f "${run_file}" >/dev/null 2>&1; then
      log_info "  kicked Workflow for ${name} (${env})"; ((created++)) || true
    else
      log_warn "  failed to create Workflow for ${name} (${env})"
    fi
  done
done
log_info "${created} Workflow(s) kicked. Track with: kubectl get workflow -n ${RUN_NS}"
