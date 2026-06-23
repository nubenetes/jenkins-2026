#!/usr/bin/env bash
# Installs Jenkins (jenkinsci/helm-charts) with the platform overlay for
# ${J2026_PLATFORM}, the JCasC fragments under jenkins/casc/, and a generated
# values overlay that wires controller.containerEnv to this repo's
# config/config.yaml + the "${J2026_JENKINS_CREDENTIALS_SECRET}" Secret
# (created by 01-namespaces.sh). On OpenShift, also applies the Route.
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

log_step "Pre-installation cleanup of JCasC ConfigMaps"
# Delete any old JCasC ConfigMaps to prevent merge conflicts with new files.
# Using '|| true' to ignore errors if they don't exist.
kubectl delete configmap -n "${J2026_JENKINS_NAMESPACE}" \
  -l "app.kubernetes.io/instance=${J2026_JENKINS_RELEASE},jenkins-jenkins-config=true" --ignore-not-found=true || true

GENERATED_DIR="${J2026_ROOT_DIR}/.generated"
mkdir -p "${GENERATED_DIR}"
RUNTIME_VALUES="${GENERATED_DIR}/jenkins-runtime-values.yaml"

log_step "Generating runtime values overlay (${RUNTIME_VALUES#${J2026_ROOT_DIR}/})"

# Grafana base URL surfaced in the systemMessage banner (jcasc-base.yaml) and
# used by the OTel plugin's "View in Grafana" build links (jcasc-otel.yaml).
# Resolved per observability.mode so the managed-grafana modes get the same
# banner link the grafana-cloud mode does - read from each mode's credentials
# Secret, so it only appears once the backend has actually been provisioned.
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
    # In-cluster Grafana: exposed publicly at https://grafana.<baseDomain> when
    # the gateway is enabled (HTTPRoute + IAP in scripts/09-gateway.sh), so the
    # banner link matches the other modes. Falls back to the kubectl
    # port-forward address when the gateway is disabled.
    if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
      grafana_base_url="https://${J2026_GATEWAY_GRAFANA_HOST}"
    else
      grafana_base_url="http://localhost:3000"
    fi
    ;;
  managed-azure)  grafana_base_url="$(read_grafana_url_from_secret "${J2026_AZURE_MONITOR_SECRET}")" ;;
  managed-aws)    grafana_base_url="$(read_grafana_url_from_secret "${J2026_AWS_MANAGED_SECRET}")" ;;
esac

if [[ -n "${grafana_base_url}" ]]; then
  kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
    --type=merge -p "{\"stringData\":{\"grafana-base-url\":\"${grafana_base_url}\"}}"
fi

# "Kubernetes Infrastructure" banner links, per observability.mode (the targets
# differ by backend, so they're not static in jcasc-base.yaml). The
# ${GRAFANA_K8S_APP_LINK} placeholder there can hold several <li> items:
#   grafana-cloud - the Grafana Cloud Kubernetes Monitoring app (/a/grafana-k8s-app)
#   managed-azure - Azure Managed Grafana's built-in Kubernetes dashboards
#                   (auto-provisioned from the Azure Monitor workspace): the
#                   filtered browse list + direct links to a few key ones. Those
#                   uids are Azure-assigned and stable across AMG instances
#                   (the shared ...6738 suffix).
#   oss - kube-prometheus-stack's bundled kubernetes-mixin + node-exporter
#         dashboards (loaded via the Grafana sidecar); their uids are pinned
#         upstream and stable across chart versions, so we deep-link them.
#   managed-aws - none (no auto-provisioned k8s dashboards on AMG).
# Empty -> the placeholder renders nothing. jq escapes the embedded HTML quotes.
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
      # kube-prometheus-stack ships the full kubernetes-mixin + node-exporter
      # dashboards via the Grafana sidecar. uids are pinned upstream and stable
      # across chart versions (verified live against the in-cluster Grafana):
      # browse-all + direct links to a few key ones, mirroring managed-azure.
      grafana_k8s_app_link="$(grafana_li "${grafana_base_url}" "/dashboards?query=Kubernetes" "Kubernetes Infrastructure (all)")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/efa86fd1d0c121a26444b636a3f509a8" "K8s Compute Resources / Cluster")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/7d57716318ee0dddbac5a7f451fb7753" "Node Exporter / Nodes")"
      grafana_k8s_app_link+="$(grafana_li "${grafana_base_url}" "/d/3138fa155d5915769fbded898ac09fd9" "Kubelet")"
      ;;
    managed-aws)
      # Amazon Managed Grafana doesn't auto-provision the k8s mixin like AMG
      # Azure does; link to the dashboards browse (import the community k8s
      # dashboards there, or they land via the Prometheus data source).
      grafana_k8s_app_link="$(grafana_li "${grafana_base_url}" "/dashboards?query=Kubernetes" "Kubernetes Infrastructure")"
      ;;
  esac
fi
kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
  --type=merge -p "$(jq -nc --arg v "${grafana_k8s_app_link}" '{stringData:{"grafana-k8s-app-link":$v}}')"

microservices_url=""
if [[ -n "${J2026_GATEWAY_BASE_DOMAIN}" ]]; then
  microservices_url="https://${J2026_GATEWAY_MICROSERVICES_HOST}"
fi
kubectl patch secret "${J2026_JENKINS_CREDENTIALS_SECRET}" -n "${J2026_JENKINS_NAMESPACE}" \
  --type=merge -p "{\"stringData\":{\"microservices-url\":\"${microservices_url}\"}}"

# The banner links above (Grafana base URL, the per-mode Kubernetes
# Infrastructure links, Microservices URL) reach the controller as env vars from
# the jenkins-credentials Secret, which are only read at pod start. Switching
# observability.mode on an existing cluster changes those Secret values but not
# the controller's pod template, so without forcing a restart the system banner
# keeps the previous backend's Grafana URLs. Fold them into a checksum exposed as
# a pod annotation so helm rolls the controller whenever they change.
banner_links_checksum="$(printf '%s|%s|%s' "${grafana_base_url}" "${grafana_k8s_app_link}" "${microservices_url}" | sha256sum | cut -c1-16)"

cat >"${RUNTIME_VALUES}" <<EOF
# Generated by scripts/04-jenkins.sh from config/config.yaml - do not edit by
# hand, do not commit (see .gitignore). Fully replaces
# controller.containerEnv from helm/jenkins/values-common.yaml with values
# resolved from this repo's config.
controller:
  jenkinsUrl: "${J2026_JENKINS_URL}"
  podAnnotations:
    jenkins-2026/banner-links-checksum: "${banner_links_checksum}"
  containerEnv:
    - name: JENKINS_ADMIN_ID
      value: "${J2026_JENKINS_ADMIN_USER}"
    - name: JENKINS_ADMIN_PASSWORD
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: admin-password
    - name: JENKINS_URL
      value: "http://localhost:8080/"
    - name: JENKINS_NAMESPACE
      value: "${J2026_JENKINS_NAMESPACE}"
    - name: JENKINS_PUBLIC_URL
      value: "${J2026_JENKINS_URL}"
    - name: JENKINS2026_REPO_URL
      value: "${J2026_SELF_REPO_URL}"
    - name: JENKINS2026_GITOPS_REPO_URL
      value: "https://github.com/nubenetes/jenkins-2026-gitops-config.git"
    - name: JENKINS2026_REPO_BRANCH
      value: "${J2026_SELF_REPO_BRANCH}"
    - name: JENKINS2026_PLATFORM
      value: "${J2026_PLATFORM}"
    - name: JENKINS2026_GENAI_SERVICE_ENABLED
      value: "${J2026_MICROSERVICES_GENAI_SERVICE_ENABLED}"
    - name: JENKINS2026_DEVELOP_TRACK_ENABLED
      value: "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}"
    - name: MICROSERVICES_REGISTRY
      value: "${J2026_MICROSERVICES_REGISTRY}"
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://otel-collector-gateway.${J2026_OBS_NAMESPACE}.svc.cluster.local:4317"
    - name: GRAFANA_BASE_URL
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: grafana-base-url
          optional: true
    - name: GRAFANA_K8S_APP_LINK
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: grafana-k8s-app-link
          optional: true
    - name: MICROSERVICES_URL
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: microservices-url
          optional: true

    - name: REGISTRY_USERNAME
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: registry-username
          optional: true
    - name: REGISTRY_PASSWORD
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: registry-password
          optional: true
    - name: GIT_USERNAME
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: git-username
          optional: true
    - name: GIT_TOKEN
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: git-token
          optional: true
    - name: JENKINS_OIDC_CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: oidc-client-id
          optional: true
    - name: JENKINS_OIDC_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: oidc-client-secret
          optional: true
    - name: JENKINS_OIDC_ADMIN_EMAIL
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: oidc-admin-email
          optional: true
    - name: ARGOCD_SERVER
      value: "argocd-server.${J2026_ARGOCD_NAMESPACE}.svc.cluster.local"
    - name: ARGOCD_AUTH_TOKEN
      valueFrom:
        secretKeyRef:
          name: ${J2026_JENKINS_CREDENTIALS_SECRET}
          key: argocd-token
          optional: true
EOF

helm_args=(
  upgrade --install "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_CHART_NAME}"
  --namespace "${J2026_JENKINS_NAMESPACE}"
  --create-namespace
  -f "${J2026_ROOT_DIR}/helm/jenkins/values-common.yaml"
  -f "${J2026_ROOT_DIR}/helm/jenkins/values-${J2026_PLATFORM}.yaml"
  -f "${RUNTIME_VALUES}"
  --set-file "controller.JCasC.configScripts.base=${J2026_ROOT_DIR}/jenkins/casc/jcasc-base.yaml"
  --set-file "controller.JCasC.configScripts.otel=${J2026_ROOT_DIR}/jenkins/casc/jcasc-otel.yaml"
  --set-file "controller.JCasC.configScripts.seed-job=${J2026_ROOT_DIR}/jenkins/casc/jcasc-seed-job.yaml"
)

if [[ -n "${J2026_JENKINS_CHART_VERSION}" ]]; then
  helm_args+=(--version "${J2026_JENKINS_CHART_VERSION}")
fi

log_step "Installing ${J2026_JENKINS_RELEASE} (${J2026_JENKINS_CHART_NAME}) into ${J2026_JENKINS_NAMESPACE} [platform=${J2026_PLATFORM}]"
helm "${helm_args[@]}"

# Use wait_for_resource with a 15m timeout. If it fails, trigger a manual
# rollback to keep the cluster clean.
if ! wait_for_resource "statefulset" "${J2026_JENKINS_RELEASE}" "${J2026_JENKINS_NAMESPACE}" "15m"; then
  log_error "Jenkins rollout failed, rolling back..."
  helm rollback "${J2026_JENKINS_RELEASE}" -n "${J2026_JENKINS_NAMESPACE}"
  exit 1
fi

log_info "Jenkins ready. Forward the UI with:"
log_info "  kubectl -n ${J2026_JENKINS_NAMESPACE} port-forward svc/${J2026_JENKINS_RELEASE} 8080:8080"
