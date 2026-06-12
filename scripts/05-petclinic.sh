#!/usr/bin/env bash
# Installs the helm/petclinic chart into both the "stable" (petclinic) and
# "develop" (petclinic-develop) namespaces using their respective values
# files. Image tags default to "master"/"develop" - until the corresponding
# Jenkins pipelines (seeded by 06-seed-pipelines.sh) build and push real
# images, pods will sit in ImagePullBackOff. That's expected for a fresh
# environment; re-running this script is a no-op once pipelines have run.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

deploy_env() {
  local env_name="$1" namespace="$2" values_file="$3"
  helm upgrade --install "petclinic-${env_name}" "${J2026_ROOT_DIR}/helm/petclinic" \
    --namespace "${namespace}" \
    --create-namespace \
    -f "${J2026_ROOT_DIR}/helm/petclinic/${values_file}" \
    --set global.platform="${J2026_PLATFORM}" \
    --timeout 5m
}

run_bg petclinic-stable  deploy_env stable  "${J2026_PETCLINIC_NS_STABLE}"  values-stable.yaml
run_bg petclinic-develop deploy_env develop "${J2026_PETCLINIC_NS_DEVELOP}" values-develop.yaml

wait_bg
log_info "PetClinic charts installed (stable + develop)."
log_warn "Pods will show ImagePullBackOff until the seeded Jenkins pipelines build & push images."
