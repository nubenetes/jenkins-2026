#!/usr/bin/env bash
# 06-githubactions-pipelines.sh — activate the GitHub Actions / ARC pipelines.
# The analogue of 06-tekton-pipelines.sh: renders .github/workflows/microservices-ci.yml
# (from jenkins/pipelines/seed/microservices-ci.yml.tmpl) into each owned microservices fork,
# reading the SAME jenkins/pipelines/seed/services.yaml registry. Simpler than the Tekton
# version — ARC's GitHub App handles webhook dispatch, so there is no hook-creation loop.
# Idempotent (diff-then-push). See docs/404-GITHUB_ACTIONS.md.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

[[ "${J2026_CI_ENGINE}" != "githubactions" ]] && { log_info "ci.engine='${J2026_CI_ENGINE}' - skipping (06-githubactions)."; exit 0; }

SERVICES_YAML="${J2026_ROOT_DIR}/jenkins/pipelines/seed/services.yaml"
TEMPLATE="${J2026_ROOT_DIR}/jenkins/pipelines/seed/microservices-ci.yml.tmpl"
[[ -f "${SERVICES_YAML}" && -f "${TEMPLATE}" ]] || { log_error "Missing services.yaml or microservices-ci.yml.tmpl"; exit 1; }

# --- wait for ArgoCD to sync the AutoscalingRunnerSet ------------------------
log_step "Waiting for the ARC AutoscalingRunnerSet '${J2026_GHA_RUNNER_SCALE_SET_NAME}' to register"
deadline=$(( $(date +%s) + 600 ))
until kubectl get autoscalingrunnerset "${J2026_GHA_RUNNER_SCALE_SET_NAME}" -n "${J2026_GHA_RUNNER_NAMESPACE}" >/dev/null 2>&1; do
  [[ "$(date +%s)" -ge "${deadline}" ]] && { log_warn "AutoscalingRunnerSet not present yet — continuing (re-run to converge)."; break; }
  sleep 10
done

# --- static opt-out: pin runner pods to the static pool ----------------------
# Default placement (ci-spot) is baked into the runner-set chart values; only the static
# opt-out is patched at runtime (the runner-set child App ignores this field via ignoreDifferences).
if [[ "${J2026_GITHUBACTIONS_RUN_NODE_POOL}" == "static" ]]; then
  log_step "Pinning ARC runner pods to the static pool (githubactions.runNodePool=static)"
  kubectl patch autoscalingrunnerset "${J2026_GHA_RUNNER_SCALE_SET_NAME}" -n "${J2026_GHA_RUNNER_NAMESPACE}" --type merge \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"app":"jenkins-2026"}}}}}' >/dev/null 2>&1 \
    || log_warn "Could not patch runner nodeSelector to static (CR not ready?)."
fi

# --- render the workflow into each owned fork --------------------------------
git_user="${GIT_USERNAME:-nubenetes-ci}"
[[ -z "${GIT_TOKEN:-}" ]] && { log_warn "GIT_TOKEN unset - cannot push .github/workflows/ to the forks. Skipping render."; exit 0; }
repo_path_from_url() { echo "$1" | sed -E 's#^https?://github.com/##; s#\.git$##'; }

# branches list: drop develop when the develop track is off.
branches="main"
[[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED:-false}" == "true" ]] && branches="main, develop"

svc_count="$(yq eval '.services | length' "${SERVICES_YAML}")"
log_step "Rendering microservices-ci.yml into ${svc_count} fork(s)"
rendered=0
for i in $(seq 0 $((svc_count - 1))); do
  name="$(yq eval ".services[${i}].name" "${SERVICES_YAML}")"
  type="$(yq eval ".services[${i}].type // \"java\"" "${SERVICES_YAML}")"
  repo="$(yq eval ".services[${i}].repoUrl" "${SERVICES_YAML}")"
  module="$(yq eval ".services[${i}].module // \"\"" "${SERVICES_YAML}")"
  port="$(yq eval ".services[${i}].port" "${SERVICES_YAML}")"
  health="$(yq eval ".services[${i}].healthPath" "${SERVICES_YAML}")"
  repo_path="$(repo_path_from_url "${repo}")"
  work="$(mktemp -d)"

  if ! git clone --depth 1 "https://${git_user}:${GIT_TOKEN}@github.com/${repo_path}.git" "${work}" >/dev/null 2>&1; then
    log_warn "Could not clone ${repo_path} (not an owned fork?) — skipping ${name}."; rm -rf "${work}"; continue
  fi
  mkdir -p "${work}/.github/workflows"
  sed -e "s@{{runnerLabel}}@${J2026_GHA_RUNNER_SCALE_SET_NAME}@g" \
      -e "s@{{svcName}}@${name}@g" \
      -e "s@{{svcType}}@${type}@g" \
      -e "s@{{svcModule}}@${module}@g" \
      -e "s@{{svcPort}}@${port}@g" \
      -e "s@{{svcHealth}}@${health}@g" \
      -e "s@{{registry}}@${J2026_MICROSERVICES_REGISTRY}@g" \
      -e "s@{{nsStable}}@${J2026_MICROSERVICES_NS_STABLE}@g" \
      -e "s@{{nsDevelop}}@${J2026_MICROSERVICES_DEVELOP_NAMESPACE}@g" \
      -e "s@{{obsNamespace}}@${J2026_OBS_NAMESPACE}@g" \
      -e "s@{{argocdNamespace}}@${J2026_ARGOCD_NAMESPACE}@g" \
      -e "s@{{selfRepoBranch}}@${J2026_SELF_REPO_BRANCH}@g" \
      -e "s@{{branches}}@${branches}@g" \
      "${TEMPLATE}" > "${work}/.github/workflows/microservices-ci.yml"

  ( cd "${work}"
    git config user.email "githubactions@nubenetes.com"; git config user.name "jenkins-2026 CI bootstrap"
    git add .github/workflows/microservices-ci.yml
    if git diff --cached --quiet; then
      log_info "  ${name}: workflow already up to date."
    else
      git commit -m "ci: render microservices-ci.yml (ARC self-hosted runners) [jenkins-2026]" >/dev/null
      # NOTE: GIT_TOKEN must carry the `workflow` scope or this push is rejected.
      if git push origin HEAD >/dev/null 2>&1; then log_info "  ${name}: workflow pushed."; rendered=$((rendered+1));
      else log_warn "  ${name}: push of .github/workflows/ rejected — GIT_TOKEN needs the 'workflow' scope."; fi
    fi
    # Optional seed run so the Actions tab is populated from Day1 (parity with tekton.seedRuns).
    if [[ "${J2026_GHA_SEED_RUNS}" == "true" ]] && command -v gh >/dev/null 2>&1; then
      GH_TOKEN="${GIT_TOKEN}" gh workflow run microservices-ci.yml --repo "${repo_path}" --ref main >/dev/null 2>&1 \
        && log_info "  ${name}: seed run dispatched." || true
    fi
  )
  rm -rf "${work}"
done
log_info "GitHub Actions pipelines activated: ${rendered} workflow(s) rendered/updated across ${svc_count} fork(s)."
