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

# Delete ALL PodDisruptionBudgets up front. A PDB with ALLOWED DISRUPTIONS: 0
# (e.g. CNPG's postgres-* / postgres-*-primary) blocks voluntary pod eviction,
# which stalls BOTH namespace draining AND - critically - the GKE node-pool drain
# that `terraform destroy` runs next. A stuck CNPG pod kept a DELETE_NODE_POOL
# operation RUNNING for hours (run 28202019543). Removing PDBs is safe here (the
# whole cluster is about to be destroyed) and lets every later drain proceed.
if kubectl version >/dev/null 2>&1; then
  log_step "Removing all PodDisruptionBudgets (unblock node/namespace drains)"
  kubectl get pdb -A --no-headers 2>/dev/null | awk '{print $1, $2}' \
    | while read -r _ns _name; do
        [[ -n "${_name}" ]] && kubectl delete pdb "${_name}" -n "${_ns}" --ignore-not-found 2>/dev/null || true
      done

  log_step "Removing all Mutating and Validating Webhook Configurations (prevent webhook deadlocks during namespace deletion)"
  kubectl delete mutatingwebhookconfiguration --all --timeout=15s --ignore-not-found 2>/dev/null || true
  kubectl delete validatingwebhookconfiguration --all --timeout=15s --ignore-not-found 2>/dev/null || true

  # Node Auto-Provisioning: drop the Custom ComputeClass first so NAP stops provisioning
  # new Spot nodes for any still-pending CI agent mid-teardown (its auto-created pools go
  # away with the cluster on terraform destroy; emptying them as workloads scale to 0
  # lets NAP consolidate them down meanwhile). Best-effort — never block teardown.
  log_step "Removing Node Auto-Provisioning ComputeClass (if present)"
  kubectl delete computeclass --all --ignore-not-found --timeout=30s 2>/dev/null || true
fi

# eso teardown: the gateway IAP secret VALUE lives in GCP Secret Manager (pushed
# by 01-namespaces.sh). The in-cluster ESO resources die with the cluster, but the
# project-level Secret Manager secret would be orphaned. Delete it for a symmetric
# teardown — a future Day1 re-pushes it from the GitHub secret. The backend is
# DETECTED from the still-running cluster (ClusterSecretStore gcp-store), so no
# secrets_backend input is needed on the Decom workflows. Best-effort: never block
# teardown (needs roles/secretmanager.admin on the CI SA, granted in bootstrap).
if kubectl version >/dev/null 2>&1 && [[ "$(j2026_active_secrets_backend)" == "eso" ]]; then
  if [[ -n "${J2026_GATEWAY_IAP_SECRET:-}" ]] && \
     gcloud secrets describe "${J2026_GATEWAY_IAP_SECRET}" >/dev/null 2>&1; then
    log_step "Deleting GCP Secret Manager secret '${J2026_GATEWAY_IAP_SECRET}' (eso teardown)"
    if gcloud secrets delete "${J2026_GATEWAY_IAP_SECRET}" --quiet >/dev/null 2>&1; then
      log_info "Deleted Secret Manager secret '${J2026_GATEWAY_IAP_SECRET}'."
    else
      log_warn "Could not delete Secret Manager secret '${J2026_GATEWAY_IAP_SECRET}' (already gone / perms?)."
    fi
  fi
fi

# Optional FULL purge of the eso-mode Secret Manager secrets (opt-in via
# J2026_PURGE_SECRETS=true — the "Decom Everything" umbrella sets it). Unlike the
# targeted gateway-IAP delete above (always run, cheaply re-derived from a GitHub
# secret), this sweeps EVERY secret provision_secret ever pushed — labelled
# managed-by=jenkins-2026 (see lib/secrets.sh) — across all four CI engines plus
# the shared platform secrets. Kept opt-in + default-OFF on purpose: sm_keep_or_generate
# relies on these SURVIVING a plain cluster Decom so generated passwords (e.g. the
# Jenkins admin password) stay STABLE across rebuilds; only a total teardown wants
# them gone. Label-scoped + cluster-independent (works even if the cluster is
# already destroyed); a no-op in imperative mode (no labelled secrets) and safe if
# gcloud lacks the project (best-effort, never blocks teardown).
if [[ "${J2026_PURGE_SECRETS:-false}" == "true" ]]; then
  log_step "Purging ALL jenkins-2026 Secret Manager secrets (J2026_PURGE_SECRETS=true)"
  mapfile -t _sm_secrets < <(gcloud secrets list \
    --filter="labels.managed-by=jenkins-2026" \
    --format="value(name.basename())" 2>/dev/null || true)
  if [[ "${#_sm_secrets[@]}" -eq 0 ]]; then
    log_info "No labelled Secret Manager secrets found — nothing to purge."
  else
    for _s in "${_sm_secrets[@]}"; do
      [[ -z "${_s}" ]] && continue
      if gcloud secrets delete "${_s}" --quiet >/dev/null 2>&1; then
        log_info "Deleted Secret Manager secret '${_s}'."
      else
        log_warn "Could not delete Secret Manager secret '${_s}' (already gone / perms?)."
      fi
    done
  fi
fi

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

# GitHub Actions / ARC (ci.engine=githubactions) is a GitOps-managed app-of-apps. Delete
# the parent while ArgoCD is alive so it cascade-prunes the controller + the runner scale
# set (which de-registers the runners from GitHub). Engine-agnostic: no-op when absent.
if kubectl get application githubactions -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing githubactions ArgoCD app-of-apps (ARC controller + runner scale set)"
  kubectl delete application githubactions -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
fi

# Argo Workflows (ci.engine=argoworkflows) is a GitOps-managed app-of-apps. Delete the
# parent while ArgoCD is alive so it cascade-prunes the Workflows/Events controllers +
# the WorkflowTemplates/EventSource/Sensor. Engine-agnostic: no-op when absent.
if kubectl get application argoworkflows -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing argoworkflows ArgoCD app-of-apps (Workflows + Events controllers)"
  kubectl delete application argoworkflows -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
fi

# Jenkins (ci.engine=jenkins) is a GitOps-managed single Application. Delete it
# while ArgoCD is alive so it cascade-prunes the chart. Engine-agnostic: no-op
# when absent. (The helm_uninstall below is a legacy fallback for pre-ArgoCD
# Jenkins installs.)
if kubectl get application jenkins -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing jenkins ArgoCD Application (Jenkins chart)"
  kubectl delete application jenkins -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
fi

# cert-manager (gateway.backendTls, docs/504) is a GitOps-managed single
# Application, only present when the backend-TLS flag was on. Delete it while
# ArgoCD is alive so it cascade-prunes the chart (crds.keep=false takes the
# CRDs, and with them every Certificate/ClusterIssuer). Flag-agnostic teardown:
# no-op when absent.
if kubectl get application cert-manager -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing cert-manager ArgoCD Application (backend TLS)"
  kubectl delete application cert-manager -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
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
  kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_ARGOWF}" -n "${J2026_ARGOWF_NAMESPACE}" --ignore-not-found --timeout=5m
  # Backend-TLS policy (only present when gateway.backendTls was enabled). The
  # CRD guard matters: deleting an unknown resource TYPE is a hard error (not a
  # not-found) on clusters that never served the BackendTLSPolicy CRD.
  if kubectl get crd backendtlspolicies.gateway.networking.k8s.io >/dev/null 2>&1; then
    kubectl delete backendtlspolicy "${J2026_BACKEND_TLS_POLICY_HEADLAMP}" -n "${J2026_HEADLAMP_NAMESPACE}" --ignore-not-found --timeout=5m
    kubectl delete backendtlspolicy "${J2026_BACKEND_TLS_POLICY_PGADMIN}" -n "${J2026_PGADMIN_NAMESPACE}" --ignore-not-found --timeout=5m
    # Grafana BackendTLSPolicy (only present when observability.mode=oss + backendTls; a
    # no-op --ignore-not-found otherwise).
    kubectl delete backendtlspolicy "${J2026_BACKEND_TLS_POLICY_GRAFANA}" -n "${J2026_GRAFANA_OSS_NAMESPACE}" --ignore-not-found --timeout=5m
    # Jenkins BackendTLSPolicy (only present when ci.engine=jenkins + backendTls; a
    # no-op --ignore-not-found otherwise).
    kubectl delete backendtlspolicy "${J2026_BACKEND_TLS_POLICY_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found --timeout=5m
    # Tekton Dashboard BackendTLSPolicy
    kubectl delete backendtlspolicy "${J2026_BACKEND_TLS_POLICY_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found --timeout=5m
    # Argo Workflows Server BackendTLSPolicy
    kubectl delete backendtlspolicy "${J2026_BACKEND_TLS_POLICY_ARGOWF}" -n "${J2026_ARGOWF_NAMESPACE}" --ignore-not-found --timeout=5m
  fi

  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_JENKINS}" -n "${J2026_JENKINS_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_MICROSERVICES}" -n "${J2026_MICROSERVICES_NS_STABLE}" --ignore-not-found --timeout=5m
  # Develop tier route (only present when microservices.developTrackEnabled; ignored otherwise).
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_MICROSERVICES_DEVELOP}" -n "${J2026_MICROSERVICES_DEVELOP_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_HEADLAMP}" -n "${J2026_HEADLAMP_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_PGADMIN}" -n "${J2026_PGADMIN_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_PAC}" -n pipelines-as-code --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_ARGOWF}" -n "${J2026_ARGOWF_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_ARGOEVENTS}" -n "${J2026_ARGOWF_EVENTS_NAMESPACE}" --ignore-not-found --timeout=5m
  kubectl delete gateway "${J2026_GATEWAY_NAME}" -n "${J2026_GATEWAY_NAMESPACE}" --ignore-not-found --timeout=5m
fi

# CI-engine teardown is engine-agnostic: Decom.cluster.01-gke.yml runs down.sh
# with no ci_engine input, and a cluster may hold either engine. Jenkins is a
# Helm release (uninstalled above); Tekton is installed via kubectl apply, so
# remove it here. Best-effort + idempotent (no-op when tekton isn't installed).
if kubectl get namespace "${J2026_TEKTON_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing Tekton (PipelineRuns, control plane, CI namespace)"
  kubectl delete pipelinerun --all -n "${J2026_TEKTON_PIPELINE_NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
fi

# Argo Workflows: delete any in-flight Workflows in the execution namespace before the
# namespace teardown below (the app-of-apps prune above removes the controllers).
# Best-effort + idempotent (no-op when argoworkflows isn't installed).
if kubectl get namespace "${J2026_ARGOWF_RUN_NAMESPACE}" >/dev/null 2>&1; then
  log_step "Removing Argo Workflows (Workflows, control plane, CI namespace)"
  kubectl delete workflow --all -n "${J2026_ARGOWF_RUN_NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
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
#  2. Issue a non-blocking `kubectl delete namespace --wait=false`, then
#     immediately patch spec.finalizers=[] via the /finalize sub-resource API so
#     the API server releases the namespace at once — event-driven, NO fixed
#     `--timeout` wait (the old `delete --timeout=2m` produced the noisy
#     "timed out waiting for the condition" lines and could add ~2 min per slow ns).
# reclaim_namespace_pvcs <ns>
# PREVENTION half of the orphaned-PD story (the cleanup half is
# scripts/sweep-orphaned-pds.sh). Deletes the namespace's PVCs *gracefully* —
# WITHOUT stripping the kubernetes.io/pvc-protection finalizer — so the CSI
# external-provisioner reclaims each PV (reclaimPolicy=Delete) and DELETES the
# backing GCP persistent disk while the driver is still alive. We then wait
# (bounded) for the backing PVs to disappear = PDs actually gone. Without this,
# drain_namespace's finalizer-strip + the subsequent terraform-destroy would
# remove the PVCs from etcd before CSI deletes the PDs -> orphaned disks that
# accumulate one generation per rebuild and burn SSD_TOTAL_GB quota + cost.
# Anything not reclaimed within the bound is left to the orphan-PD sweep.
# See docs/501-PLATFORM_OPERATIONS.md § Orphaned persistent disks.
reclaim_namespace_pvcs() {
  local ns="$1"
  kubectl get namespace "${ns}" > /dev/null 2>&1 || return 0
  local pvs
  pvs="$(kubectl get pvc -n "${ns}" -o jsonpath='{range .items[*]}{.spec.volumeName}{"\n"}{end}' 2>/dev/null | grep . || true)"
  [[ -z "${pvs}" ]] && return 0
  log_info "Reclaiming $(printf '%s\n' "${pvs}" | grep -c .) PV(s) in ${ns} via graceful PVC deletion (CSI deletes the PDs)..."
  # Graceful delete (keep the pvc-protection finalizer); pods were already removed above.
  kubectl delete pvc -n "${ns}" --all --wait=false 2>/dev/null || true
  # Bounded wait (~2 min) for the backing PVs to vanish = PDs deleted by CSI.
  local i=0 remaining
  while [[ $i -lt 60 ]]; do
    remaining=0
    while read -r pv; do
      [[ -n "${pv}" ]] && kubectl get pv "${pv}" > /dev/null 2>&1 && ((remaining++))
    done <<< "${pvs}"
    [[ "${remaining}" -eq 0 ]] && { log_info "All PVs in ${ns} reclaimed (PDs deleted)."; return 0; }
    sleep 2; ((i++))
  done
  log_warn "Some PVs in ${ns} not reclaimed within ~2m - the orphan-PD sweep will catch them."
}

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

  # Object finalizers were already stripped above, so the namespace can terminate
  # immediately. Delete WITHOUT blocking, then force-release via the /finalize
  # subresource — event-driven, no `delete --timeout` wait. (Force-finalize is safe
  # here precisely because the whole cluster is about to be terraform-destroyed.)
  log_info "Deleting namespace ${ns} (finalize-driven, no fixed timeout)..."
  kubectl delete namespace "${ns}" --ignore-not-found --wait=false 2>/dev/null || true
  kubectl get namespace "${ns}" -o json 2>/dev/null \
    | python3 -c "import sys,json; ns=json.load(sys.stdin); ns['spec']['finalizers']=[]; print(json.dumps(ns))" \
    | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - 2>/dev/null || true

  # Short, bounded confirmation poll (best-effort, ~10 s max; NOT a hard timeout —
  # any remnant is removed when the cluster itself is terraform-destroyed).
  local i=0
  while kubectl get namespace "${ns}" > /dev/null 2>&1 && [[ $i -lt 5 ]]; do
    sleep 2; ((i++))
  done
  kubectl get namespace "${ns}" > /dev/null 2>&1 \
    && log_warn "Namespace ${ns} still present — GKE will finish cleanup, or terraform destroy will remove it" \
    || log_info "Namespace ${ns} deleted."
}

if [[ "${J2026_DELETE_NAMESPACES:-false}" == "true" ]]; then
  log_step "Deleting namespaces (J2026_DELETE_NAMESPACES=true)"
  for ns in "${J2026_GATEWAY_NAMESPACE}" "${J2026_JENKINS_NAMESPACE}" "${J2026_TEKTON_NAMESPACE}" "${J2026_TEKTON_PIPELINE_NAMESPACE}" pipelines-as-code tekton-chains "${J2026_GHA_NAMESPACE}" "${J2026_GHA_RUNNER_NAMESPACE}" "${J2026_ARGOWF_NAMESPACE}" "${J2026_ARGOWF_EVENTS_NAMESPACE}" "${J2026_ARGOWF_RUN_NAMESPACE}" "${J2026_OBS_NAMESPACE}" "${J2026_GRAFANA_OSS_NAMESPACE}" "${J2026_HEADLAMP_NAMESPACE}" "${J2026_MICROSERVICES_NS_STABLE}" "${J2026_MICROSERVICES_DEVELOP_NAMESPACE}" "${J2026_ARGOCD_NAMESPACE}" "${J2026_PGADMIN_NAMESPACE}" "${J2026_BACKEND_TLS_CERT_MANAGER_NAMESPACE}"; do
    # microservices-develop only exists when the develop track was enabled;
    # drain_namespace no-ops on an absent namespace, so listing it is always safe.
    # First reclaim PVCs gracefully (CSI deletes the PDs → no orphaned disks),
    # THEN force-drain the namespace (finalizer-strip fallback for any straggler).
    reclaim_namespace_pvcs "${ns}"
    drain_namespace "${ns}"
  done
else
  log_info "Namespaces left in place. Set J2026_DELETE_NAMESPACES=true to remove them too."
fi

# Final drain-prep — guarantee the upcoming GKE node-pool drain (run by the
# `terraform destroy` step AFTER this script) cannot stall. That drain gracefully
# evicts pods respecting PodDisruptionBudgets; CNPG's postgres PDB has ALLOWED
# DISRUPTIONS: 0 and is RE-created by its operator — especially once ArgoCD is
# uninstalled above and can't finish the cascade-prune — so the up-front blanket
# PDB delete isn't enough and the drain hangs past terraform's timeout (the
# DELETE_NODE_POOL op stays RUNNING; see run 28233699049). Since the whole cluster
# is about to be destroyed, forcibly clear the blockers: scale workload
# controllers to 0 (stop pod/PDB recreation), drop EVERY PDB, then force-delete
# EVERY pod — the drain then finds nothing to evict and completes promptly. All
# best-effort; never blocks teardown.
if kubectl version >/dev/null 2>&1; then
  log_step "Final drain-prep: stop controllers + clear PDBs + force-delete pods (so the node-pool drain can't stall)"
  kubectl get ns -o name 2>/dev/null | sed 's#^namespace/##' \
    | grep -vE '^(kube-system|kube-node-lease|kube-public|gke-managed|gmp-)' \
    | while read -r _ns; do
        kubectl scale deployment,statefulset -n "${_ns}" --all --replicas=0 2>/dev/null || true
      done
  kubectl delete pdb --all --all-namespaces --ignore-not-found 2>/dev/null || true
  kubectl delete pods --all --all-namespaces --grace-period=0 --force 2>/dev/null || true
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

    # =======================================================================
    # Layered, dependency-safe NEG (container-native LB endpoint) teardown.
    # GCP refuses to delete a NEG while a backend service references it, and a
    # leftover NEG blocks terraform/gke's VPC delete. Three complementary layers
    # (see docs/902 § container-native LB NEGs):
    #   L1 precise GC  — the Gateway + HTTPRoutes were already deleted above with a
    #       finalizer-wait (--timeout), so the GKE controller releases the Gateway LB
    #       chain WHILE THE CLUSTER IS STILL ALIVE. The clean path; most NEGs go here.
    #   L2 absorb async — poll up to 10m for the controller's async GC to finish.
    #   L3 backstop    — force-delete survivors in DEPENDENCY ORDER (forwarding-rule →
    #       target-proxy → url-map → backend-service → NEG) so the delete can't fail
    #       with "resource in use". Each step is best-effort/idempotent.
    # NOT exclusive: L1 makes the common case clean+fast, L2 tolerates the async GC,
    # L3 guarantees the worst case still drains. Avoid the anti-pattern of destroying
    # the cluster first — that orphans the NEGs (controller gone) and L3 then races the
    # dependencies.
    # =======================================================================

    # L3 helper: tear down the L7 LB chain that pins a NEG, then delete the NEG. Uses
    # jq on `--format=json` (the group/service/target/urlMap fields are full self-links,
    # so match by an `endswith "/<name>"` suffix) — robust where gcloud --filter on list
    # fields is not. Global external LB scope (the PoC's Gateway); regional deletes just
    # no-op via 2>/dev/null.
    _force_delete_neg() {  # <name> <zone>
      local name="$1" zone="$2" bss bs ums um tp
      bss=$(gcloud compute backend-services list --project="${gcp_project}" --format=json 2>/dev/null \
        | jq -r --arg n "/${name}" '.[] | select([.backends[]?.group // ""] | any(endswith($n))) | .name' 2>/dev/null | sort -u)
      for bs in ${bss}; do
        ums=$(gcloud compute url-maps list --project="${gcp_project}" --format=json 2>/dev/null \
          | jq -r --arg b "/${bs}" '.[] | select(([.defaultService // ""] + [.pathMatchers[]?.defaultService // ""] + [.pathMatchers[]?.pathRules[]?.service // ""]) | any(endswith($b))) | .name' 2>/dev/null | sort -u)
        for um in ${ums}; do
          for tp in $(gcloud compute target-https-proxies list --project="${gcp_project}" --format=json 2>/dev/null | jq -r --arg u "/${um}" '.[] | select((.urlMap // "") | endswith($u)) | .name' 2>/dev/null) \
                    $(gcloud compute target-http-proxies  list --project="${gcp_project}" --format=json 2>/dev/null | jq -r --arg u "/${um}" '.[] | select((.urlMap // "") | endswith($u)) | .name' 2>/dev/null); do
            gcloud compute forwarding-rules list --global --project="${gcp_project}" --format=json 2>/dev/null \
              | jq -r --arg t "/${tp}" '.[] | select((.target // "") | endswith($t)) | .name' 2>/dev/null \
              | while read -r fr; do [[ -n "${fr}" ]] && { log_info "    L3: deleting forwarding-rule '${fr}'"; gcloud compute forwarding-rules delete "${fr}" --global --project="${gcp_project}" --quiet 2>/dev/null; }; done
            log_info "    L3: deleting target-proxy '${tp}'"
            gcloud compute target-https-proxies delete "${tp}" --project="${gcp_project}" --quiet 2>/dev/null
            gcloud compute target-http-proxies  delete "${tp}" --project="${gcp_project}" --quiet 2>/dev/null
          done
          log_info "    L3: deleting url-map '${um}'"
          gcloud compute url-maps delete "${um}" --project="${gcp_project}" --quiet 2>/dev/null
        done
        log_info "    L3: deleting backend-service '${bs}' (referenced NEG '${name}')"
        gcloud compute backend-services delete "${bs}" --global --project="${gcp_project}" --quiet 2>/dev/null
      done
      log_info "  L3: force-deleting NEG '${name}' (zone ${zone})..."
      gcloud compute network-endpoint-groups delete "${name}" --zone="${zone}" --project="${gcp_project}" --quiet \
        || log_warn "  NEG '${name}' still won't delete (a backend may remain) — re-run down.sh (idempotent) or inspect the LB chain; terraform destroy of the VPC may fail until it's gone."
    }

    # --- L2: bounded adaptive wait (up to 2m) for the controller's async GC ---
    log_step "Releasing container-native LB NEGs for VPC '${vpc_name}' (await GKE GC, then dependency-safe force-delete)"
    _neg_deadline=$(( SECONDS + 120 ))
    while :; do
      negs=$(gcloud compute network-endpoint-groups list --filter="network:${vpc_name}" --project="${gcp_project}" --format="value(name)" 2>/dev/null || true)
      if [[ -z "${negs}" ]]; then
        log_info "L2: all NEGs released by the GKE controller — no force-delete needed (clean L1 path)."
        break
      fi
      if [[ ${SECONDS} -ge ${_neg_deadline} ]]; then
        log_warn "L2: NEGs still present after 2m of async GC — switching to dependency-ordered force-delete (L3)."
        break
      fi
      log_info "  L2: waiting for the GKE controller to release $(echo ${negs} | wc -w) NEG(s) ($(( _neg_deadline - SECONDS ))s left)"
      sleep 15
    done

    # --- L3: dependency-ordered force-delete of any survivors -----------------
    gcloud compute network-endpoint-groups list --filter="network:${vpc_name}" --project="${gcp_project}" \
      --format="value(name,zone.basename())" 2>/dev/null | while read -r name zone; do
        [[ -n "${name}" && -n "${zone}" ]] && _force_delete_neg "${name}" "${zone}"
      done
  fi
fi

rm -rf "${J2026_ROOT_DIR}/.generated"

log_info "jenkins-2026 down."
