#!/usr/bin/env bash
# =============================================================================
# End-to-end test: provisions a throwaway GKE cluster (terraform/gke), runs
# the full jenkins-2026 stack (scripts/up.sh), smoke-tests it
# (test/smoke-test.sh), then tears everything down again - scripts/down.sh
# AND `terraform destroy` - even if an earlier step fails, via the EXIT trap.
#
# Required env vars:
#   GCP_PROJECT_ID    GCP project ID (billing enabled). No default - required.
#
# Optional env vars:
#   GCP_REGION        default: europe-southwest1
#   GCP_ZONE          default: europe-southwest1-a
#   GCP_CLUSTER_NAME  default: jenkins-2026
#   JENKINS2026_OBS_MODE      override observability.mode (grafana-cloud|oss|managed)
#   JENKINS2026_PLATFORM      override platform.target - leave at "gke" for this test
#   REGISTRY_USERNAME / REGISTRY_PASSWORD / GIT_USERNAME / GIT_TOKEN
#                     forwarded to scripts/01-namespaces.sh, see test/.env.example
#   J2026_DELETE_NAMESPACES   forwarded to scripts/down.sh (default: true here,
#                             since the whole cluster is about to be destroyed
#                             anyway)
#
# Usage:
#   export GCP_PROJECT_ID=my-project
#   ./test/e2e.sh
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/gke"

# shellcheck source=../scripts/lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

retry() {
  local n=1
  local max=3
  local delay=10
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        log_warn "Command failed. Attempt $n/$max in ${delay}s..."
        sleep $delay
      else
        log_error "The command has failed after $n attempts."
        return 1
      fi
    }
  done
}

: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID to your GCP project ID (billing enabled)}"

require_cmd terraform "Install Terraform >= 1.9 (https://developer.hashicorp.com/terraform/install)" || exit 1
require_cmd gcloud "Install the Google Cloud CLI (https://cloud.google.com/sdk/docs/install) and run 'gcloud auth login' + 'gcloud auth application-default login'" || exit 1

export TF_VAR_project_id="${GCP_PROJECT_ID}"
export TF_VAR_region="${GCP_REGION:-europe-southwest1}"
export TF_VAR_zone="${GCP_ZONE:-europe-southwest1-a}"
export TF_VAR_cluster_name="${GCP_CLUSTER_NAME:-jenkins-2026}"
# Node Auto-Provisioning toggle: single source of truth is config.yaml
# (nodeAutoProvisioning.enabled), so cluster-level NAP can't desync from the in-cluster
# ComputeClass wiring. config.sh is sourced AFTER terraform apply here, so derive it now
# (honouring the per-run JENKINS2026_* override, same precedence as config.sh).
export TF_VAR_enable_node_autoprovisioning="${JENKINS2026_NODE_AUTOPROVISIONING_ENABLED:-$(yq '.nodeAutoProvisioning.enabled // true' "${ROOT_DIR}/config/config.yaml")}"

# The cluster is about to be destroyed wholesale, so also clean up
# in-cluster namespaces during scripts/down.sh unless the caller overrides.
export J2026_DELETE_NAMESPACES="${J2026_DELETE_NAMESPACES:-true}"

cluster_provisioned=0
stack_deployed=0

cleanup() {
  local exit_code=$?
  log_step "Cleanup (exit code ${exit_code})"

  if [[ "${stack_deployed}" == "1" ]]; then
    log_step "scripts/down.sh"
    "${ROOT_DIR}/scripts/down.sh" || log_warn "down.sh reported errors (continuing teardown)"
  fi

  if [[ "${cluster_provisioned}" == "1" ]]; then
    log_step "terraform destroy (removing GKE cluster, VPC, node pool)"
    terraform -chdir="${TF_DIR}" destroy -auto-approve -input=false \
      || log_error "terraform destroy failed - run it manually from ${TF_DIR#${ROOT_DIR}/} to avoid leaving billable resources running"
  fi

  exit "${exit_code}"
}
trap cleanup EXIT

log_step "terraform init (terraform/gke)"
retry terraform -chdir="${TF_DIR}" init -input=false

log_step "terraform apply (provisioning throwaway GKE cluster - this takes ~10 minutes)"
# Set *before* apply: a failed/partial apply can still have created billable
# resources, so the EXIT trap must still run `terraform destroy`.
cluster_provisioned=1
terraform -chdir="${TF_DIR}" apply -auto-approve -input=false

log_step "Fetching kubeconfig credentials"
gcloud container clusters get-credentials \
  "$(terraform -chdir="${TF_DIR}" output -raw cluster_name)" \
  --zone "$(terraform -chdir="${TF_DIR}" output -raw location)" \
  --project "${GCP_PROJECT_ID}"

log_step "scripts/00-check-prereqs.sh + scripts/01-namespaces.sh"
"${ROOT_DIR}/scripts/00-check-prereqs.sh"
"${ROOT_DIR}/scripts/01-namespaces.sh"

# In grafana-cloud mode, scripts/03-observability.sh requires the
# grafana-cloud-credentials Secret to already exist (see test/.env.example
# and observability/otel-collector/secret.example.yaml).
source "${ROOT_DIR}/scripts/lib/config.sh"
if [[ "${J2026_OBS_MODE}" == "grafana-cloud" ]]; then
  SECRET_FILE="${ROOT_DIR}/observability/otel-collector/secret.yaml"
  if [[ ! -f "${SECRET_FILE}" ]]; then
    log_error "observability.mode=grafana-cloud but ${SECRET_FILE#${ROOT_DIR}/} is missing."
    log_error "Copy observability/otel-collector/secret.example.yaml, fill in your Grafana"
    log_error "Cloud OTLP credentials, and re-run - or export JENKINS2026_OBS_MODE=oss for"
    log_error "a fully self-contained run with no external account."
    exit 1
  fi
  log_step "Applying grafana-cloud-credentials Secret"
  kubectl apply -f "${SECRET_FILE}"
fi

log_step "scripts/up.sh"
# Set *before* up.sh: a failed/partial run can still have created Helm
# releases/namespaces that scripts/down.sh should clean up.
stack_deployed=1
"${ROOT_DIR}/scripts/up.sh"

log_step "test/smoke-test.sh"
"${ROOT_DIR}/test/smoke-test.sh"

log_info "End-to-end test PASSED. Tearing down now (see Cleanup above)..."
