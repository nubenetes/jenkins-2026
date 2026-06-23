#!/usr/bin/env bash
# Tears down everything provisioned by up.sh, in (roughly) reverse order.
# Namespaces are left in place by default (they may contain useful
# build/debug artifacts); set J2026_DELETE_NAMESPACES=true to also delete
# them (and the "${J2026_JENKINS_CREDENTIALS_SECRET}" Secret inside).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

log_step "jenkins-2026 down - platform=${J2026_PLATFORM} observability=${J2026_OBS_MODE}"

helm_uninstall() {
  local release="$1" namespace="$2"
  if helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    helm uninstall "${release}" -n "${namespace}"
  else
    log_info "${release} (-n ${namespace}) not installed - skipping"
  fi
}

# In oss mode the in-cluster stack (kube-prometheus-stack/Loki/Tempo) is managed
# by the observability-oss ArgoCD app-of-apps. Delete it FIRST, while ArgoCD is
# still running, so the controller cascade-prunes those charts via the resources
# finalizer. --wait=false keeps teardown moving; any leftover Application
# finalizers are stripped later by drain_namespace. The helm_uninstall fallbacks
# below cover legacy (pre-ArgoCD) oss clusters.
if [[ "${J2026_OBS_MODE}" == "oss" ]] && \
   kubectl get application observability-oss -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing observability-oss ArgoCD app-of-apps (cascade-prune in-cluster OSS stack)"
  kubectl delete application observability-oss -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
fi

# Same for the platform-postgres app-of-apps (CNPG operator + pgAdmin) — delete
# while ArgoCD is alive so it cascade-prunes. --wait=false; drain_namespace
# strips any leftover finalizers.
if kubectl get application platform-postgres -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing platform-postgres ArgoCD app-of-apps (CNPG operator + pgAdmin)"
  kubectl delete application platform-postgres -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
fi

# Tekton (ci.engine=tekton) is the GitOps-managed CI engine app-of-apps. Delete
# the parent while ArgoCD is alive so it cascade-prunes Pipelines/Triggers/
# Dashboard + the pipelines-as-code. Engine-agnostic teardown: no-op when absent.
if kubectl get application tekton -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing tekton ArgoCD app-of-apps (Pipelines/Triggers/Dashboard)"
  kubectl delete application tekton -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
fi

# Jenkins (ci.engine=jenkins) is a GitOps-managed single Application. Delete it
# while ArgoCD is alive so it cascade-prunes the chart. Engine-agnostic: no-op
# when absent. (The helm_uninstall below is a legacy fallback for pre-ArgoCD
# Jenkins installs.)
if kubectl get application jenkins -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing jenkins ArgoCD Application (Jenkins chart)"
  kubectl delete application jenkins -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
fi

log_step "Uninstalling Helm releases in parallel"
run_bg microservices-stable   helm_uninstall microservices-stable  "${J2026_MICROSERVICES_NS_STABLE}"
run_bg jenkins            helm_uninstall "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}"
run_bg headlamp           helm_uninstall "${J2026_HEADLAMP_RELEASE}" "${J2026_HEADLAMP_NAMESPACE}"
run_bg argocd             helm_uninstall "${J2026_ARGOCD_RELEASE}" "${J2026_ARGOCD_NAMESPACE}"
run_bg otel-gateway       helm_uninstall "${J2026_OTEL_GATEWAY_RELEASE}" "${J2026_OBS_NAMESPACE}"
run_bg otel-logs          helm_uninstall "${J2026_OTEL_LOGS_RELEASE}" "${J2026_OBS_NAMESPACE}"
run_bg pdc-agent          helm_uninstall pdc-agent "${J2026_OBS_NAMESPACE}"
run_bg k8s-monitoring     helm_uninstall k8s-monitoring "${J2026_OBS_NAMESPACE}"
run_bg kube-state-metrics helm_uninstall kube-state-metrics "${J2026_OBS_NAMESPACE}"
run_bg node-exporter      helm_uninstall prometheus-node-exporter "${J2026_OBS_NAMESPACE}"

if [[ "${J2026_OBS_MODE}" == "oss" ]]; then
  # Legacy fallback: only hits for pre-ArgoCD oss clusters (no-op otherwise, the
  # charts are now ArgoCD-managed and pruned above).
  run_bg kube-prometheus-stack helm_uninstall kube-prometheus-stack "${J2026_GRAFANA_OSS_NAMESPACE}"
  run_bg loki                  helm_uninstall loki "${J2026_OBS_NAMESPACE}"
  run_bg tempo                 helm_uninstall tempo "${J2026_OBS_NAMESPACE}"
fi

wait_bg || log_warn "One or more uninstalls failed - see logs/ for details."

log_step "Cleaning up remaining observability artifacts"
kubectl delete configmap otel-collector-gateway -n "${J2026_OBS_NAMESPACE}" --ignore-not-found

log_step "Uninstalling OpenTelemetry Operator (CRDs)"
helm_uninstall "${J2026_OTEL_OPERATOR_RELEASE}" "${J2026_OBS_NAMESPACE}"

log_step "Removing RoleBindings granted to the Jenkins ServiceAccount"
for ns in "${J2026_MICROSERVICES_NS_STABLE}"; do
  kubectl delete rolebinding jenkins-edit -n "${ns}" --ignore-not-found
done

log_step "Removing Headlamp admin ClusterRoleBindings"
if [[ -n "${J2026_HEADLAMP_ADMIN_EMAILS}" ]]; then
  IFS=',' read -ra admin_emails <<<"${J2026_HEADLAMP_ADMIN_EMAILS}"
  for email in "${admin_emails[@]}"; do
    email="$(echo "${email}" | xargs)" # trim whitespace
    [[ -z "${email}" ]] && continue
    binding_name="headlamp-admin-$(echo "${email}" | tr '[:upper:]' '[:lower:]' | tr '@.+' '-')"
    kubectl delete clusterrolebinding "${binding_name}" --ignore-not-found
  done
fi

# Deleted by fixed name/namespace (scripts/09-gateway.sh), not by replaying
# .generated/gateway/ - that dir only exists on the machine that ran
# scripts/up.sh, but Decom.cluster.01-gke.yml runs down.sh from a fresh checkout.
# Deleting these explicitly (with their finalizers) before the namespaces/
# cluster are torn down lets the GKE Gateway controller release the external
# load balancer resources (forwarding rule, backend services, NEGs) it
# created - leaving them would otherwise orphan GCP resources or block
# `terraform destroy` on the VPC. Guarded the same way as
# scripts/09-gateway.sh: these CRDs only exist when platform.target=gke and
# the gateway was enabled.
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  log_step "Removing Gateway resources (Gateway, HTTPRoutes, GCPBackendPolicies)"
  # --timeout bounds the wait on the GKE Gateway controller's finalizers
  # (which release the external LB's forwarding rule/backend services/NEGs)
  # so a stuck controller can't hang this step indefinitely.
  kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_HEADLAMP}" -n "${J2026_HEADLAMP_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_PGADMIN}" -n "${J2026_PGADMIN_NAMESPACE}" --ignore-not-found --timeout=5m
  # Tekton Dashboard route/policy (only present when ci.engine=tekton; ignored otherwise).
  kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_MICROSERVICES}" -n "${J2026_MICROSERVICES_NS_STABLE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_HEADLAMP}" -n "${J2026_HEADLAMP_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_PGADMIN}" -n "${J2026_PGADMIN_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete gateway "${J2026_GATEWAY_NAME}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found --timeout=5m
fi

# CI-engine teardown is engine-agnostic: Decom.cluster.01-gke.yml runs down.sh
# with no ci_engine input, and a cluster may hold either engine. Jenkins is a
# Helm release (uninstalled above); Tekton is installed via kubectl apply, so
# remove it here. Best-effort + idempotent (no-op when tekton isn't installed).
if kubectl get namespace "${J2026_TEKTON_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing Tekton (PipelineRuns, control plane, CI namespace)"
  kubectl delete pipelinerun --all -n "${J2026_TEKTON_PIPELINE_NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
fi

# drain_namespace <ns>
# Deletes a namespace and ensures it fully terminates. Three-stage strategy:
#  1. Strip object-level finalizers from all Terminating resources in the
#     namespace. This covers:
#       - PVCs (kubernetes.io/pvc-protection) — jenkins-home volume detach
#       - ArgoCD Applications (resources-finalizer.argocd.argoproj.io) — the
#         ArgoCD controller is already gone so finalizers would never be
#         processed and the namespace would hang indefinitely
#       - Any other resource type stuck in Terminating
#  2. Issue kubectl delete namespace with a 2-minute timeout.
#  3. If still Terminating, patch spec.finalizers=[] via the /finalize
#     sub-resource API so the API server releases the namespace immediately.
drain_namespace() {
  local ns="$1"
  kubectl get namespace "${ns}" > /dev/null 2>&1 || { log_info "Namespace ${ns} does not exist - skipping"; return 0; }

  log_info "Stripping finalizers from all Terminating resources in ${ns}..."
  # Get every resource type that supports list (ignore errors for types with no instances)
  for resource in $(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null); do
    for obj in $(kubectl get "${resource}" -n "${ns}" \
        --field-selector='metadata.deletionTimestamp!=null' \
        -o name 2>/dev/null); do
      kubectl patch "${obj}" -n "${ns}" \
        --type='json' -p='[{"op":"replace","path":"/metadata/finalizers","value":[]}]' \
        2>/dev/null || true
    done
  done

  # PVCs may not yet be Terminating but still block the namespace — delete them explicitly
  for pvc in $(kubectl get pvc -n "${ns}" -o name 2>/dev/null); do
    kubectl patch "${pvc}" -n "${ns}" \
      --type='json' -p='[{"op":"replace","path":"/metadata/finalizers","value":[]}]' \
      2>/dev/null || true
    kubectl delete "${pvc}" -n "${ns}" --ignore-not-found --timeout=30s 2>/dev/null || true
  done

  log_info "Deleting namespace ${ns}..."
  kubectl delete namespace "${ns}" --ignore-not-found --timeout=2m && return 0

  # Namespace still terminating — patch spec.finalizers=[] via /finalize API
  log_warn "Namespace ${ns} still Terminating — patching namespace finalizers to unblock..."
  kubectl get namespace "${ns}" -o json 2>/dev/null \
    | python3 -c "import sys,json; ns=json.load(sys.stdin); ns['spec']['finalizers']=[]; print(json.dumps(ns))" \
    | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - 2>/dev/null || true

  # Give GKE up to 30 s to acknowledge the patch
  local i=0
  while kubectl get namespace "${ns}" > /dev/null 2>&1 && [[ $i -lt 6 ]]; do
    sleep 5; ((i++))
  done
  kubectl get namespace "${ns}" > /dev/null 2>&1 \
    && log_warn "Namespace ${ns} still present after finalize patch — GKE may finish cleanup in the background" \
    || log_info "Namespace ${ns} deleted."
}

if [[ "${J2026_DELETE_NAMESPACES:-false}" == "true" ]]; then
  log_step "Deleting namespaces (J2026_DELETE_NAMESPACES=true)"
  for ns in "${J2026_JENKINS_NAMESPACE}" "${J2026_TEKTON_NAMESPACE}" "${J2026_TEKTON_PIPELINE_NAMESPACE}" "${J2026_OBS_NAMESPACE}" "${J2026_GRAFANA_OSS_NAMESPACE}" "${J2026_HEADLAMP_NAMESPACE}" "${J2026_MICROSERVICES_NS_STABLE}" "${J2026_ARGOCD_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}"; do
    drain_namespace "${ns}"
  done
else
  log_info "Namespaces left in place. Set J2026_DELETE_NAMESPACES=true to remove them too."
fi

if command -v gcloud &>/dev/null; then
  # Try to get active GCP project from gcloud config or environment
  gcp_project="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -n "${gcp_project}" ]]; then
    # Try to read cluster name from output or tfstate
    cluster_name=""
    if command -v terraform &>/dev/null && [[ -d "${J2026_ROOT_DIR}/terraform/gke" ]]; then
      cluster_name=$(terraform -chdir="${J2026_ROOT_DIR}/terraform/gke" output -raw cluster_name 2>/dev/null || true)
    fi
    if [[ -z "${cluster_name}" ]]; then
      cluster_name="jenkins-2026"
    fi
    vpc_name="${cluster_name}-vpc"

    log_step "Waiting for GCP Network Endpoint Groups (NEGs) referencing VPC '${vpc_name}' to be deleted..."
    # Wait up to 5 minutes for NEGs to be deleted asynchronously by GKE controllers
    for i in {1..30}; do
      negs=$(gcloud compute network-endpoint-groups list \
        --filter="network:${vpc_name}" \
        --project="${gcp_project}" \
        --format="value(name)" 2>/dev/null || true)
      if [[ -z "${negs}" ]]; then
        log_info "All NEGs deleted successfully."
        break
      fi
      log_info "Still waiting for NEGs to be deleted (attempt $i/30): $(echo ${negs} | tr '\n' ' ')"
      sleep 10
    done

    # If NEGs still exist after timeout, force delete them to prevent blocking VPC deletion
    negs=$(gcloud compute network-endpoint-groups list \
      --filter="network:${vpc_name}" \
      --project="${gcp_project}" \
      --format="value(name)" 2>/dev/null || true)
    if [[ -n "${negs}" ]]; then
      log_warn "Timeout waiting for NEGs. Force-deleting remaining NEGs..."
      # value() output is tab-separated and never emits a header row (unlike
      # csv[no-header], which leaked a literal "name,zone" line here); zone is
      # returned as a full self-link URL, so .basename() trims it to the bare
      # zone name that `delete --zone` expects.
      gcloud compute network-endpoint-groups list \
        --filter="network:${vpc_name}" \
        --project="${gcp_project}" \
        --format="value(name,zone.basename())" 2>/dev/null | while read -r name zone; do
          if [[ -n "${name}" && -n "${zone}" ]]; then
            log_info "Force-deleting NEG '${name}' in zone '${zone}'..."
            gcloud compute network-endpoint-groups delete "${name}" \
              --zone="${zone}" \
              --project="${gcp_project}" \
              --quiet || log_warn "Failed to delete NEG '${name}' - terraform destroy of the VPC may fail."
          fi
        done
    fi
  fi
fi

rm -rf "${J2026_ROOT_DIR}/.generated"

log_info "jenkins-2026 down."
