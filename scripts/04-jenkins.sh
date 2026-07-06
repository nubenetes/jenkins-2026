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

# Engines are mutually exclusive (config ci.engine). Selecting Jenkins fully
# retires the other three (Tekton · GitHub Actions/ARC · Argo Workflows) — every
# ArgoCD app they own (parent app-of-apps + all children), their namespaces, and
# any stuck GKE NEG finalizer — via the shared, deadlock-proof helper in
# lib/common.sh. The GitOps-managed microservices are untouched; only the retired
# engines' control planes / dashboards / CI-run namespaces go. Idempotent.
retire_ci_engine tekton
retire_ci_engine githubactions
retire_ci_engine argoworkflows

# --- ensure the jenkins-namespace NetworkPolicies are current ----------------
# 01-namespaces.sh applies these on Day1, but the Jenkins-only redeploy
# (Day2.redeploy.02-jenkins) deliberately does NOT run 01-namespaces - so a
# change to the jenkins NetworkPolicy (notably the backend-TLS 8081 ingress
# rule, docs/504) would never reach the cluster on a redeploy, and build agents
# would hang "Waiting for agent to connect" (the LB→pod hop moves to the plain
# 8081 the policy must allow). Re-apply here too - idempotent, same file +
# ci.engine=jenkins guard as 01-namespaces - so a redeploy is self-sufficient.
# The jenkins namespace already exists (Day1's 01-namespaces created it; this
# script only runs after that), so the apply never races namespace creation.
kubectl apply -f "${J2026_ROOT_DIR}/infrastructure/networkpolicies-jenkins.yaml"

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

# Grafana dashboard uids for the banner's deep links, derived from the canonical
# dashboard JSONs at deploy time. The published uid is whatever the JSON carries -
# NOT always jenkins2026-<name> (jenkins-overview/rum-frontend/jvm-internals were
# round-tripped through Grafana Cloud and carry generated uids), so a uid
# hardcoded in jcasc-base.yaml 404s whenever the canonical file changes (the same
# class as the off-engine delete sites fixed in 07-grafana-dashboards.sh). Falls
# back to the legacy jenkins2026-<name> scheme if the JSON is unreadable.
dash_uid() {
  local uid
  uid="$(jq -r '.uid // empty' "${J2026_ROOT_DIR}/observability/grafana/dashboards/$1.json" 2>/dev/null || true)"
  printf '%s' "${uid:-jenkins2026-$1}"
}
dash_uid_jenkins="$(dash_uid jenkins-overview)"
dash_uid_microservices="$(dash_uid microservices-overview)"
dash_uid_k6="$(dash_uid k6-smoke-overview)"
dash_uid_rum="$(dash_uid rum-frontend)"
dash_uid_jvm="$(dash_uid jvm-internals)"

log_step "Patching dynamic values into ${J2026_JENKINS_CREDENTIALS_SECRET}"
# GKE Node Auto-Provisioning: the ComputeClass the build agents target so NAP spins up
# Spot, scale-to-zero nodes for them. Empty when NAP is disabled, so agents fall back to
# the static pool (the Groovy pipelines emit a nodeSelector only when this is non-empty).
gke_compute_class=""
if [[ "${J2026_NODE_AUTOPROVISIONING_ENABLED}" == "true" ]]; then
  gke_compute_class="${J2026_NODE_AUTOPROVISIONING_COMPUTE_CLASS}"
fi

# ArgoCD server address the pipeline's Deploy stage (microservicesDeploy.groovy)
# targets. With backend TLS active (docs/504) argocd-server serves TLS, so append
# ':443' - the groovy then keeps --grpc-web --insecure and DROPS --plaintext for a
# ':<non-80-port>' address. Port-less otherwise, so the groovy adds :80 + --plaintext.
argocd_server_addr="argocd-server.${J2026_ARGOCD_NAMESPACE}.svc.cluster.local"
if [[ "$(j2026_argocd_backend_tls_active)" == "true" ]]; then
  argocd_server_addr="${argocd_server_addr}:443"
fi

# Internal Service port build agents dial over WebSocket (jcasc-base.yaml
# jenkinsUrl). Plain HTTP always: when backend TLS (docs/504) is active, the
# controller's main port (8080) becomes HTTPS-only and the plain-HTTP listener
# moves to the pod's httpsKeyStore.httpPort (8081), exposed on the Service as
# port 8082 -> targetPort 8081 (controller.extraPorts, values-backend-tls.yaml;
# the Service port must differ from 8081 to avoid a containerPort collision -
# see that file). So agents dial the SERVICE port 8082. Empty when TLS is
# inactive, so jcasc-base.yaml's ${JENKINS_AGENT_PORT:-8080} default (the plain
# servicePort) applies unchanged.
jenkins_agent_port=""
if [[ "$(j2026_backend_tls_active)" == "true" ]]; then
  jenkins_agent_port="8082"
fi

kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
  --type=merge -p "$(jq -nc \
    --arg gbu "${grafana_base_url}" \
    --arg argocdsrv "${argocd_server_addr}" \
    --arg gk8s "${grafana_k8s_app_link}" \
    --arg msu "${microservices_url}" \
    --arg msdu "${microservices_develop_url}" \
    --arg msdl "${microservices_develop_link}" \
    --arg jpu "${jenkins_public_url}" \
    --arg jap "${jenkins_agent_port}" \
    --arg br "${J2026_SELF_REPO_BRANCH}" \
    --arg genai "${J2026_MICROSERVICES_GENAI_SERVICE_ENABLED}" \
    --arg dev "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" \
    --arg cc "${gke_compute_class}" \
    --arg rnp "${J2026_JENKINS_RUN_NODE_POOL}" \
    --arg duj "${dash_uid_jenkins}" \
    --arg dum "${dash_uid_microservices}" \
    --arg duk "${dash_uid_k6}" \
    --arg dur "${dash_uid_rum}" \
    --arg duv "${dash_uid_jvm}" \
    '{stringData:{
        "grafana-base-url":$gbu,
        "grafana-k8s-app-link":$gk8s,
        "grafana-dash-uid-jenkins-overview":$duj,
        "grafana-dash-uid-microservices-overview":$dum,
        "grafana-dash-uid-k6-smoke-overview":$duk,
        "grafana-dash-uid-rum-frontend":$dur,
        "grafana-dash-uid-jvm-internals":$duv,
        "microservices-url":$msu,
        "microservices-develop-url":$msdu,
        "microservices-develop-link":$msdl,
        "jenkins-public-url":$jpu,
        "jenkins-agent-port":$jap,
        "repo-branch":$br,
        "genai-enabled":$genai,
        "develop-enabled":$dev,
        "gke-compute-class":$cc,
        "run-node-pool":$rnp,
        "argocd-server":$argocdsrv
    }}')"

# Rolls the controller whenever the Secret-backed banner/behaviour values change
# (ArgoCD won't roll on an out-of-band Secret edit otherwise) - passed as the
# controller.podAnnotations.bannerLinksChecksum helm parameter below.
banner_links_checksum="$(printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' \
  "${grafana_base_url}" "${grafana_k8s_app_link}" "${microservices_url}" \
  "${microservices_develop_url}" \
  "${jenkins_public_url}" "${J2026_SELF_REPO_BRANCH}" "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" \
  "${gke_compute_class}" "${J2026_JENKINS_RUN_NODE_POOL}" \
  "${dash_uid_jenkins}|${dash_uid_microservices}|${dash_uid_k6}|${dash_uid_rum}|${dash_uid_jvm}" \
  "${argocd_server_addr}" \
  "${jenkins_agent_port}" \
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
# Backend TLS (gateway.backendTls.enabled, docs/504): layer the TLS overlay so the
# controller serves HTTPS via a cert-manager-minted JKS keystore
# (08.7-backend-tls.sh) and the LB re-encrypts + validates the hop
# (09-gateway.sh). Gated on j2026_backend_tls_active (flag AND the
# BackendTLSPolicy CRD), never the raw flag, so the pod is never flipped to a
# TLS the LB can't speak. The app file is re-rendered from the template every
# run, so a flag-off run converges Jenkins back to plain HTTP with no overlay.
if [[ "$(j2026_backend_tls_active)" == "true" ]]; then
  log_info "Backend TLS active - adding the Jenkins TLS values overlay to the jenkins app"
  yq eval -i \
    '(.spec.sources[] | select(.chart == "jenkins") | .helm.valueFiles) += ["$values/helm/jenkins/values-backend-tls.yaml"]' \
    "${JENKINS_APP_FILE}"
fi
kubectl apply -f "${JENKINS_APP_FILE}"
rm -f "${JENKINS_APP_FILE}"

# Force ArgoCD to re-read git NOW rather than waiting for its ~3-min poll. The
# app's helm values live in the $values git source (helm/jenkins/values-*.yaml),
# so when their CONTENT changes (e.g. the backend-TLS overlay) a bare re-apply of
# the Application spec doesn't make ArgoCD re-render from the new commit - it
# renders from its cached revision, and the wait below can return against the
# still-old StatefulSet. A hard refresh makes the convergence deterministic
# (safe on every run: it just re-syncs from git, the source of truth). Ignore
# failure - the auto-poll is the fallback.
# App name is the literal "jenkins" in argocd/jenkins-app.yaml (not templated).
kubectl annotate application jenkins -n "${J2026_ARGOCD_NAMESPACE}" \
  argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

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
