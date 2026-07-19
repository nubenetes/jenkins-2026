#!/usr/bin/env bash
# 06-githubactions-pipelines.sh — activate the GitHub Actions / ARC pipelines.
# The analogue of 06-tekton-pipelines.sh: renders .github/workflows/microservices-ci.yml
# (from jenkins/pipelines/seed/microservices-ci.yml.tmpl) into each owned microservices fork,
# reading the SAME jenkins/pipelines/seed/services.yaml registry. Simpler than the Tekton
# version — ARC's GitHub App handles webhook dispatch, so there is no hook-CREATION loop;
# it still PRUNES the previous engine's stale base-domain hooks from the forks (engine-switch
# parity with the tekton/argoworkflows 06 scripts).
# Idempotent (diff-then-push). See docs/405-GITHUB_ACTIONS.md.
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

  # Prune the PREVIOUS engine's webhooks from the fork (engine-switch parity
  # with 06-tekton/06-argoworkflows, which prune foreign base-domain hooks and
  # ensure their own; found live 2026-07-12: a tekton→argoworkflows→githubactions
  # switch day left an argo-events.<domain>/push hook 404ing on every push).
  # GHA is the no-hook engine (ARC's GitHub App handles dispatch), so here the
  # desired set is EMPTY: delete every hook pointing at this project's base
  # domain; hooks to unrelated hosts are left untouched.
  hooks_json="$(curl -fsS -H "Authorization: token ${GIT_TOKEN}" \
    "https://api.github.com/repos/${repo_path}/hooks" 2>/dev/null || echo '[]')"
  while IFS=$'\t' read -r hid hurl; do
    [[ -z "${hid}" ]] && continue
    if [[ "${hurl}" == *".${J2026_GATEWAY_BASE_DOMAIN}"* ]]; then
      curl -fsS -X DELETE -H "Authorization: token ${GIT_TOKEN}" \
        "https://api.github.com/repos/${repo_path}/hooks/${hid}" >/dev/null 2>&1 \
        && log_info "  pruned stale webhook on ${repo_path} (${hurl})" || true
    fi
  done < <(printf '%s' "${hooks_json}" | jq -r '.[] | "\(.id)\t\(.config.url)"' 2>/dev/null)

  work="$(mktemp -d)"

  if ! git clone --depth 1 "https://${git_user}:${GIT_TOKEN}@github.com/${repo_path}.git" "${work}" >/dev/null 2>&1; then
    log_warn "Could not clone ${repo_path} (not an owned fork?) — skipping ${name}."; rm -rf "${work}"; continue
  fi
  mkdir -p "${work}/.github/workflows"
  # Binary Authorization (docs/507): render the flag + project into the workflow env so the
  # sign step self-gates and the script can derive the attestor. Empty project is fine when
  # the flag is off (the step no-ops before using it). Same source as 04-jenkins.sh HOOK 1.
  binauthz_enabled="${J2026_BINARY_AUTHORIZATION_ENABLED:-false}"
  binauthz_project="$(gcloud config get-value project 2>/dev/null || echo "")"
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
      -e "s@{{binauthzEnabled}}@${binauthz_enabled}@g" \
      -e "s@{{projectId}}@${binauthz_project}@g" \
      "${TEMPLATE}" > "${work}/.github/workflows/microservices-ci.yml"

  ( cd "${work}"
    git config user.email "githubactions@nubenetes.com"; git config user.name "jenkins-2026 CI bootstrap"
    git add .github/workflows/microservices-ci.yml
    if git diff --cached --quiet; then
      log_info "  ${name}: workflow already up to date."
    else
      git commit -m "ci: render microservices-ci.yml (ARC self-hosted runners) [jenkins-2026]" >/dev/null
      # NOTE: GIT_TOKEN must carry the `workflow` scope or this push is rejected.
      if git push origin HEAD >/dev/null 2>&1; then log_info "  ${name}: workflow pushed (main)."; rendered=$((rendered+1));
      else log_warn "  ${name}: push of .github/workflows/ rejected — GIT_TOKEN needs the 'workflow' scope."; fi
    fi
    # Also publish the workflow to the fork's `develop` branch so a push to develop — or a
    # 1-click "Run workflow" from the develop branch — runs the DEVELOP tier. It is the SAME
    # file: the workflow derives ENV_NAME/TARGET_NS from github.ref_name at run time, so on
    # develop it deploys to the develop namespace. GitHub runs the workflow defined on the
    # branch being pushed, so without this push to develop would no-op (no workflow there).
    # Gated on the develop track being on AND the fork actually having a develop branch.
    if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED:-false}" == "true" ]] \
       && git ls-remote --exit-code --heads origin develop >/dev/null 2>&1; then
      _wf="$(mktemp)"; cp .github/workflows/microservices-ci.yml "${_wf}"
      git fetch --depth 1 origin develop >/dev/null 2>&1 && git checkout -q -B develop FETCH_HEAD
      mkdir -p .github/workflows; cp "${_wf}" .github/workflows/microservices-ci.yml; rm -f "${_wf}"
      git add .github/workflows/microservices-ci.yml
      if git diff --cached --quiet; then
        log_info "  ${name}: develop workflow already up to date."
      elif git commit -m "ci: render microservices-ci.yml (develop tier) [jenkins-2026]" >/dev/null 2>&1 \
           && git push origin develop >/dev/null 2>&1; then
        log_info "  ${name}: workflow pushed (develop tier)."
      else
        log_warn "  ${name}: push to develop rejected — GIT_TOKEN needs the 'workflow' scope."
      fi
    fi
    # Seed the repo secrets the rendered workflow needs onto each fork. Without them the Jib
    # step gets a 403 from ghcr.io and the GitOps tag-bump can't push. gh authenticates with
    # GIT_TOKEN (needs admin on the fork, which the owned forks grant). GitHub never exposes
    # secrets to fork-PR workflows, so seeding them on the (public) forks is the standard
    # self-hosted-CI model — only same-repo pushes/PRs (org members) ever see them.
    if command -v gh >/dev/null 2>&1; then
      GH_TOKEN="${GIT_TOKEN}" gh secret set GIT_USERNAME --repo "${repo_path}" --body "${git_user}" >/dev/null 2>&1 || true
      GH_TOKEN="${GIT_TOKEN}" gh secret set GIT_TOKEN    --repo "${repo_path}" --body "${GIT_TOKEN}" >/dev/null 2>&1 || true
      [[ -n "${REGISTRY_USERNAME:-}" ]] && GH_TOKEN="${GIT_TOKEN}" gh secret set REGISTRY_USERNAME --repo "${repo_path}" --body "${REGISTRY_USERNAME}" >/dev/null 2>&1 || true
      [[ -n "${REGISTRY_PASSWORD:-}" ]] && GH_TOKEN="${GIT_TOKEN}" gh secret set REGISTRY_PASSWORD --repo "${repo_path}" --body "${REGISTRY_PASSWORD}" >/dev/null 2>&1 || true
      log_info "  ${name}: CI secrets (GIT_*/REGISTRY_*) seeded on the fork."
    fi
    # Optional seed run so the Actions tab is populated from Day1 (parity with tekton.seedRuns).
    if [[ "${J2026_GHA_SEED_RUNS}" == "true" ]] && command -v gh >/dev/null 2>&1; then
      GH_TOKEN="${GIT_TOKEN}" gh workflow run microservices-ci.yml --repo "${repo_path}" --ref main >/dev/null 2>&1 \
        && log_info "  ${name}: seed run dispatched (main)." || true
      if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED:-false}" == "true" ]]; then
        GH_TOKEN="${GIT_TOKEN}" gh workflow run microservices-ci.yml --repo "${repo_path}" --ref develop >/dev/null 2>&1 \
          && log_info "  ${name}: seed run dispatched (develop)." || true
      fi
    fi
  )
  rm -rf "${work}"
done
log_info "GitHub Actions pipelines activated: ${rendered} workflow(s) rendered/updated across ${svc_count} fork(s)."
