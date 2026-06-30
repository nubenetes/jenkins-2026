#!/usr/bin/env bash
# Deploys Jenkins (jenkinsci/helm-charts) as a SINGLE ArgoCD Application
# (argocd/jenkins-app.yaml) installing the official chart - the GitOps
# counterpart of how Tekton/Headlamp are deployed. This script:
#   1. retires Tekton if it is present (engines are mutually exclusive)
#   2. computes the per-deployment dynamic values (Grafana banner links, public
#      URL, branch, feature flags) and patches them into the jenkins-credentials
#      Secret (the chart's containerEnv reads them via secretKeyRef)
#   3. (re)creates the JCasC ConfigMaps from jenkins/casc/* with the chart's
#      config-sidecar label (single source of truth; ArgoCD doesn't own them)
#   4. applies the ArgoCD Application (substituting repo/branch/chart-version +
#      jenkinsUrl + a banner checksum), then waits for the rollout.
# Requires ArgoCD (08.5-argocd.sh runs before this in up.sh) and the
# jenkins-credentials Secret (01-namespaces.sh). See docs/401-JENKINS.md "GitOps".
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

# Engines are mutually exclusive (config ci.engine). Selecting Jenkins retires
# Tekton if it is present (switching back on a running cluster, or a stale
# leftover). The symmetric counterpart of 04-tekton.sh retiring Jenkins. The
# shared microservices are GitOps-managed (ArgoCD), so they survive; only the
# Tekton control plane / Dashboard / pipeline namespace + its gateway routing
# are removed. Idempotent / best-effort - the cluster-scoped Tekton CRDs are
# left dormant (a later switch back to tekton re-applies the controllers).
if [[ "${J2026_CI_ENGINE}" != "tekton" ]] && \
   { kubectl get application tekton -n "${J2026_ARGOCD_NAMESPACE}" >/dev/null 2>&1 \
     || kubectl get namespace "${J2026_TEKTON_NAMESPACE}" >/dev/null 2>&1; }; then
  log_step "Retiring Tekton if present (ci.engine=jenkins)"
  # Delete the ArgoCD app-of-apps FIRST so ArgoCD cascade-prunes the Tekton
  # components and does not re-sync them back. --wait=false keeps teardown moving.
  kubectl delete application tekton -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
  if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
    kubectl delete gcpbackendpolicy "${J2026_GATEWAY_IAP_POLICY_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found
    kubectl delete httproute "${J2026_GATEWAY_HTTPROUTE_TEKTON}" -n "${J2026_TEKTON_NAMESPACE}" --ignore-not-found
  fi
  kubectl delete namespace "${J2026_TEKTON_PIPELINE_NAMESPACE}" --ignore-not-found --timeout=3m || true
  kubectl delete namespace "${J2026_TEKTON_NAMESPACE}" --ignore-not-found --timeout=3m || true
fi

# Retire the GitHub Actions / ARC and Argo Workflows engines too (the other two alternatives).
# Delete each app-of-apps so ArgoCD cascade-prunes its controllers, then drop the namespaces.
log_step "Retiring GitHub Actions / ARC + Argo Workflows if present (ci.engine=jenkins)"
kubectl delete application githubactions -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
kubectl delete namespace "${J2026_GHA_NAMESPACE}" "${J2026_GHA_RUNNER_NAMESPACE}" --ignore-not-found --wait=false || true
kubectl delete application argoworkflows -n "${J2026_ARGOCD_NAMESPACE}" --ignore-not-found --wait=false || true
kubectl delete namespace "${J2026_ARGOWF_NAMESPACE}" "${J2026_ARGOWF_EVENTS_NAMESPACE}" --ignore-not-found --wait=false || true

# --- compute dynamic banner values and patch them into the Secret ------------
# Grafana base URL surfaced in the systemMessage banner (jcasc-base.yaml) and
# the OTel plugin's "View in Grafana" links (jcasc-otel.yaml). Resolved per
# observability.mode - from each mode's credentials Secret, so it only appears
# once the backend has actually been provisioned.
grafana_base_url=""
read_grafana_url_from_secret() {
  local secret="$1"
  if kubectl get secret "${secret}" -n "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
    kubectl get secret "${secret}" -n "${J2026_OBS_NAMESPACE}" -o jsonpath='{.data.GRAFANA_BASE_URL}' | base64 -d || true
  fi
}
case "${J2026_OBS_MODE}" in
  grafana-cloud)  grafana_base_url="$(read_grafana_url_from_secret "${J2026_GRAFANA_CLOUD_SECRET}")" ;;
  oss)
    if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
      grafana_base_url="https://${J2026_GATEWAY_GRAFANA_HOST}"
    else
      grafana_base_url="http://localhost:3000"
    fi
    ;;
  managed-azure)  grafana_base_url="$(read_grafana_url_from_secret "${J2026_AZURE_MONITOR_SECRET}")" ;;
  managed-aws)    grafana_base_url="$(read_grafana_url_from_secret "${J2026_AWS_MANAGED_SECRET}")" ;;
esac

# "Kubernetes Infrastructure" banner links, per observability.mode (targets
# differ by backend). jq escapes the embedded HTML quotes. Empty -> the
# ${GRAFANA_K8S_APP_LINK} placeholder in jcasc-base.yaml renders nothing.
grafana_li() {
  printf '<li><a href="%s%s" style="color: #0052cc; text-decoration: underline;">%s</a></li>' "$1" "$2" "$3"
}
grafana_k8s_app_link=""
if [[ -n "${grafana_base_url}" ]]; then
  case "${J2026_OBS_MODE}" in
    grafana-cloud)
      grafana_k8s_app_link="$(grafana_li "${grafana_base_url}" "/a/grafana-k8s-app" "Kubernetes Infrastructure")"
      ;;
    managed-azure)
      grafana_k8s_app_link="$(grafana_li "${grafana_base_url}" "/dashboards?query=Kubernetes" "Kubernetes Infrastructure (all)")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/D3pVs6738" "Node Exporter / Nodes")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/fd0cac08a3f34e2994cf904627836738" "K8s Compute Resources / Cluster")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/184244a28b3d478e9c0de82def316738" "Kubelet")"
      ;;
    oss)
      grafana_k8s_app_link="$(grafana_li "${grafana_base_url}" "/dashboards?query=Kubernetes" "Kubernetes Infrastructure (all)")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/efa86fd1d0c121a26444b636a3f509a8" "K8s Compute Resources / Cluster")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/7d57716318ee0dddbac5a7f451fb7753" "Node Exporter / Nodes")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/3138fa155d5915769fbded898ac09fd9" "Kubelet")"
      ;;
    managed-aws)
      grafana_k8s_app_link="$(grafana_li "${grafana_base_url}" "/dashboards?query=Kubernetes" "Kubernetes Infrastructure")"
      ;;
  esac
fi

microservices_url=""
microservices_develop_url=""
jenkins_public_url=""
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  microservices_url="https://${J2026_GATEWAY_MICROSERVICES_HOST}"
  jenkins_public_url="${J2026_JENKINS_URL}"
  # Develop tier URL only when the lean develop track is enabled (09-gateway
  # generates its HTTPRoute under the same flag).
  if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
    microservices_develop_url="https://${J2026_GATEWAY_MICROSERVICES_DEVELOP_HOST}"
  fi
fi

# Pre-rendered <li> for the develop tier in the systemMessage banner - empty (so
# the line vanishes from the banner) unless the develop track is publicly exposed.
# Same inject-a-full-HTML-fragment pattern as grafana_k8s_app_link.
microservices_develop_link=""
if [[ -n "${microservices_develop_url}" ]]; then
  microservices_develop_link="<li>Microservices (develop): <a href=\"${microservices_develop_url}\" style=\"color: #0052cc; text-decoration: underline;\">${microservices_develop_url}</a></li>"
fi

log_step "Patching dynamic values into ${J2026_JENKINS_CREDENTIALS_SECRET}"
# GKE Node Auto-Provisioning: the ComputeClass the build agents target so NAP spins up
# Spot, scale-to-zero nodes for them. Empty when NAP is disabled, so agents fall back to
# the static pool (the Groovy pipelines emit a nodeSelector only when this is non-empty).
gke_compute_class=""
if [[ "${J2026_NODE_AUTOPROVISIONING_ENABLED}" == "true" ]]; then
  gke_compute_class="${J2026_NODE_AUTOPROVISIONING_COMPUTE_CLASS}"
fi

kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
  --type=merge -p "$(jq -nc \
    --arg gbu "${grafana_base_url}" \
    --arg gk8s "${grafana_k8s_app_link}" \
    --arg msu "${microservices_url}" \
    --arg msdu "${microservices_develop_url}" \
    --arg msdl "${microservices_develop_link}" \
    --arg jpu "${jenkins_public_url}" \
    --arg br "${J2026_SELF_REPO_BRANCH}" \
    --arg genai "${J2026_MICROSERVICES_GENAI_SERVICE_ENABLED}" \
    --arg dev "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" \
    --arg cc "${gke_compute_class}" \
    --arg rnp "${J2026_JENKINS_RUN_NODE_POOL}" \
    '{stringData:{
        "grafana-base-url":$gbu,
        "grafana-k8s-app-link":$gk8s,
        "microservices-url":$msu,
        "microservices-develop-url":$msdu,
        "microservices-develop-link":$msdl,
        "jenkins-public-url":$jpu,
        "repo-branch":$br,
        "genai-enabled":$genai,
        "develop-enabled":$dev,
        "gke-compute-class":$cc,
        "run-node-pool":$rnp
    }}')"

# Rolls the controller whenever the Secret-backed banner/behaviour values change
# (ArgoCD won't roll on an out-of-band Secret edit otherwise) - passed as the
# controller.podAnnotations.bannerLinksChecksum helm parameter below.
banner_links_checksum="$(printf '%s|%s|%s|%s|%s|%s|%s|%s|%s' \
  "${grafana_base_url}" "${grafana_k8s_app_link}" "${microservices_url}" \
  "${microservices_develop_url}" \
  "${jenkins_public_url}" "${J2026_SELF_REPO_BRANCH}" "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" \
  "${gke_compute_class}" "${J2026_JENKINS_RUN_NODE_POOL}" \
  | sha256sum | cut -c1-16)"

# --- JCasC ConfigMaps (single source: jenkins/casc/*) ------------------------
# Delivered as labeled ConfigMaps the chart's config sidecar (configAutoReload)
# auto-loads/reloads - the chart selects them by label jenkins-jenkins-config=true.
# Created here (not GitOps-owned) so jenkins/casc/* stays the single source and
# JCasC can be reloaded live, the same script-managed-companion pattern as the
# OSS Grafana dashboards ConfigMap.
log_step "Applying JCasC ConfigMaps (jenkins/casc/*) for the config sidecar"
apply_jcasc_cm() {
  # Separate declarations: a single `local a=$1 b=...$a` expands all RHS before
  # binding any, so ${key} would be unbound under `set -u`.
  local key="$1" file="$2"
  local name="jenkins-2026-casc-${key}"
  kubectl create configmap "${name}" -n "${J2026_JENKINS_NAMESPACE}" \
    --from-file="${key}.yaml=${file}" --dry-run=client -o yaml \
    | kubectl label --local -f - \
        "jenkins-jenkins-config=true" \
        "app.kubernetes.io/instance=${J2026_JENKINS_RELEASE}" \
        "app.kubernetes.io/managed-by=jenkins-2026" -o yaml \
    | kubectl apply -f -
}
apply_jcasc_cm base     "${J2026_ROOT_DIR}/jenkins/casc/jcasc-base.yaml"
apply_jcasc_cm otel     "${J2026_ROOT_DIR}/jenkins/casc/jcasc-otel.yaml"
apply_jcasc_cm seed-job "${J2026_ROOT_DIR}/jenkins/casc/jcasc-seed-job.yaml"

# --- apply the ArgoCD Application --------------------------------------------
chart_version="${J2026_JENKINS_CHART_VERSION:-*}"
[[ -z "${chart_version}" ]] && chart_version="*"

log_step "Applying Jenkins ArgoCD Application (chart ${chart_version}, jenkinsUrl ${J2026_JENKINS_URL})"
JENKINS_APP_FILE="$(mktemp)"
REPO_URL="${J2026_SELF_REPO_URL:-https://github.com/nubenetes/jenkins-2026.git}"
sed "s@{{repoUrl}}@${REPO_URL}@g;
     s@{{branchStable}}@${J2026_SELF_REPO_BRANCH}@g;
     s@{{chartVersion}}@${chart_version}@g;
     s@{{jenkinsUrl}}@${J2026_JENKINS_URL}@g;
     s@{{bannerChecksum}}@${banner_links_checksum}@g" \
    "${J2026_ROOT_DIR}/argocd/jenkins-app.yaml" > "${JENKINS_APP_FILE}"
kubectl apply -f "${JENKINS_APP_FILE}"
rm -f "${JENKINS_APP_FILE}"

# ArgoCD syncs the chart asynchronously. Wait for the StatefulSet to come up.
if ! wait_for_resource "statefulset" "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}" "15m"; then
  log_error "Jenkins rollout did not complete - check 'kubectl -n ${J2026_ARGOCD_NAMESPACE} get application jenkins' and the controller pod events."
  exit 1
fi

# Warm the agent image caches on every node so build pods start fast (a build pod
# only goes Running once ALL its container images are present; the microservices
# pipeline pod has 8, incl. the multi-GB codeql image). Best-effort: a slow/missing
# pre-pull never blocks builds, it just makes the first one on a fresh node slower.
log_step "Applying Jenkins agent image pre-pull DaemonSet"
kubectl apply -f "${J2026_ROOT_DIR}/helm/jenkins/agent-image-prepull.yaml" || \
  log_warn "Agent image pre-pull DaemonSet not applied - first builds on a fresh node will be slower."

log_info "Jenkins ready (ArgoCD Application 'jenkins'). Forward the UI with:"
log_info "  kubectl -n ${J2026_JENKINS_NAMESPACE} port-forward svc/${J2026_JENKINS_RELEASE} 8080:8080"
