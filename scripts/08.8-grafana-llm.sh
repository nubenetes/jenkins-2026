#!/usr/bin/env bash
# Grafana LLM app (AI assistant in Grafana) - OPT-IN via observability.llm.enabled /
# JENKINS2026_OBS_LLM_ENABLED, default false. KEYLESS by design, oss mode ONLY:
#
#   oss           - deploys a stateless single-pod LiteLLM gateway (OpenAI-
#                   compatible proxy) in the observability namespace. Its KSA
#                   (grafana-llm-sa) impersonates the grafana-llm-gsa GSA via GKE
#                   Workload Identity (terraform/gke, roles/aiplatform.user), so
#                   Application Default Credentials reach Vertex AI Gemini with no
#                   key. The grafana-llm-app plugin itself is installed by the
#                   values-oss-llm.yaml overlay (layered by the observability-oss
#                   app-of-apps when 03-observability.sh passes llmEnabled=true);
#                   this script provides the two script-managed companion objects
#                   the overlay expects (the LiteLLM stack + the
#                   grafana-llm-provisioning ConfigMap) - same companion-object
#                   pattern as grafana-runtime-config in 03. Nothing new is
#                   exposed publicly: Grafana->LiteLLM is ClusterIP inside the
#                   default-deny observability namespace, LiteLLM->Vertex is
#                   egress-only.
#   grafana-cloud - NO-OP: Grafana Cloud ships its AI assistant natively.
#   managed-*     - NO-OP by DECISION (2026-07-10, see docs/301 § Grafana LLM
#                   app): the grafana-llm-app plugin cannot authenticate
#                   keylessly to Azure OpenAI (no managed-identity support) nor
#                   talk to Amazon Bedrock at all (no provider, and no roadmap
#                   commitment upstream - issues #827/#952), and the only
#                   workaround (a public Gateway-exposed LiteLLM edge) was
#                   rejected to avoid new internet-facing surface. The full
#                   managed-mode trust chains (Azure OpenAI account + AMG
#                   managed-identity role, Bedrock invoke policy on the
#                   workspace role) were implemented and then deliberately
#                   REMOVED rather than left as dead staged config whose model
#                   pins rot - recover them from git history if the plugin ever
#                   gains native support.
#
# When INACTIVE: symmetric retire - removes the LiteLLM stack + provisioning
# ConfigMap left by a previous enabled run (the plugin itself self-heals away
# when 03 re-renders the app-of-apps without the overlay). The GCP-side trust
# chain (GSA + WI binding) is Terraform-conditional on the same flag, so it
# retires with the next terraform apply - cloud IAM and in-cluster wiring can
# never desync (docs/104 rebuild-safety: no orphaned identities). Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

GENERATED_DIR="${J2026_ROOT_DIR}/.generated/grafana-llm"

# oss-mode fixed names. The provisioning ConfigMap name must match the
# extraConfigmapMounts entry in observability/grafana/values-oss-llm.yaml; the
# Grafana Deployment name is the kube-prometheus-stack fullname (release 'oss').
LITELLM_NAME="litellm"
LLM_PROVISIONING_CONFIGMAP="grafana-llm-provisioning"
GRAFANA_DEPLOYMENT="oss-kube-prometheus-stack-grafana"

# Deterministic cleanup of the oss-mode companions (LiteLLM stack + provisioning
# ConfigMap). Called from the retire path (flag off) AND from every non-oss mode
# - switching observability.mode away from oss (with the flag on OR off) must
# not leak the LiteLLM pod (same mode-switch hygiene as the retire-other-modes
# secret loop in 03-observability.sh). All --ignore-not-found, so it's a cheap
# no-op when nothing was ever deployed.
retire_oss_llm_companions() {
  if kubectl get namespace "${J2026_OBS_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete deployment "${LITELLM_NAME}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete service "${J2026_OBS_LLM_LITELLM_SERVICE}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete configmap "${LITELLM_NAME}-config" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
    kubectl delete serviceaccount "${J2026_OBS_LLM_KSA}" -n "${J2026_OBS_NAMESPACE}" --ignore-not-found
  fi
  # The provisioning ConfigMap lives in GRAFANA's namespace (it must be
  # mountable by the Grafana pod) - same ns by default, but a separate knob.
  if kubectl get namespace "${J2026_GRAFANA_OSS_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete configmap "${LLM_PROVISIONING_CONFIGMAP}" -n "${J2026_GRAFANA_OSS_NAMESPACE}" --ignore-not-found
  fi
}

# --- non-oss modes: retire-and-exit --------------------------------------------
if [[ "${J2026_OBS_MODE}" == "grafana-cloud" ]]; then
  # Nothing to provision (the assistant is native on the SaaS plane), but an
  # earlier oss run may have left the LiteLLM stack on this persistent cluster.
  retire_oss_llm_companions
  log_info "observability.mode=grafana-cloud - the Grafana Cloud AI assistant is native (SaaS plane), nothing to provision. Skipping."
  exit 0
fi

if [[ "${J2026_OBS_MODE}" == managed-* ]]; then
  retire_oss_llm_companions
  if [[ "${J2026_OBS_LLM_ENABLED}" == "true" ]]; then
    log_warn "observability.llm.enabled=true has NO effect in ${J2026_OBS_MODE}: the grafana-llm-app plugin cannot authenticate keylessly to a managed Grafana's cloud LLM (no managed-identity/Bedrock support upstream), and exposing a public LLM proxy was ruled out. Supported mode: oss. See docs/301 § Grafana LLM app; the removed managed-mode implementation lives in git history."
  else
    log_info "Grafana LLM app: nothing to do in ${J2026_OBS_MODE} (feature is oss-only by design - docs/301)."
  fi
  exit 0
fi

# ==============================================================================
# RETIRE - flag off (oss): deterministic cleanup of a previous enabled run
# ==============================================================================
if [[ "${J2026_OBS_LLM_ENABLED}" != "true" ]]; then
  log_step "Grafana LLM app is off (observability.llm.enabled=false) - retiring any leftovers"
  rm -rf "${GENERATED_DIR}"
  # The plugin install itself self-heals away via ArgoCD: 03-observability.sh
  # already re-rendered the app-of-apps with llmEnabled=false, dropping the
  # values-oss-llm.yaml overlay. Here we retire the script-managed companions.
  retire_oss_llm_companions
  log_info "Grafana LLM app is off - nothing more to do."
  exit 0
fi

# ==============================================================================
# ENABLE (oss): LiteLLM gateway (WIF -> Vertex AI) + plugin provisioning ConfigMap
# ==============================================================================
log_step "Grafana LLM app (keyless, mode=oss)"
mkdir -p "${GENERATED_DIR}"

require_cmd gcloud "Install the Google Cloud SDK - the LiteLLM Workload Identity annotation needs the active project." || exit 1
GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${GCP_PROJECT}" ]]; then
  log_error "Could not resolve the active gcloud project - required for the grafana-llm Workload Identity GSA email."
  exit 1
fi
LLM_GSA_EMAIL="${J2026_OBS_LLM_GSA}@${GCP_PROJECT}.iam.gserviceaccount.com"

# The GSA + WI binding are Terraform-owned (terraform/gke, gated on
# TF_VAR_observability_llm_enabled). Warn-and-continue if missing: everything
# here is idempotent, so the stack converges on the next run after terraform
# catches up (LiteLLM just crashloops on auth until then).
if ! gcloud iam service-accounts describe "${LLM_GSA_EMAIL}" >/dev/null 2>&1; then
  log_warn "GSA ${LLM_GSA_EMAIL} not found - re-run the GKE terraform with TF_VAR_observability_llm_enabled=true (Day1 exports it from observability.llm.enabled). Deploying anyway; LiteLLM will fail auth until the GSA exists."
fi

log_step "Deploying the LiteLLM gateway (Vertex AI via Workload Identity, no keys)"
cat > "${GENERATED_DIR}/litellm.yaml" <<EOT
# GENERATED by scripts/08.8-grafana-llm.sh - do not edit; re-run the script.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${J2026_OBS_LLM_KSA}
  namespace: ${J2026_OBS_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${LITELLM_NAME}
    app.kubernetes.io/part-of: jenkins-2026
  annotations:
    # GKE Workload Identity: pods running as this KSA authenticate as the GSA
    # (terraform/gke grafana_llm_wi binds the reverse direction).
    iam.gke.io/gcp-service-account: ${LLM_GSA_EMAIL}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${LITELLM_NAME}-config
  namespace: ${J2026_OBS_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${LITELLM_NAME}
    app.kubernetes.io/part-of: jenkins-2026
data:
  config.yaml: |
    # Map the OpenAI-style model names the grafana-llm-app requests onto Vertex
    # AI Gemini. Auth is Application Default Credentials via Workload Identity -
    # no vertex_credentials/api_key anywhere. The 'base'/'large' aliases cover
    # the plugin's model abstraction; the gpt-* aliases cover its OpenAI-provider
    # defaults. No master_key is set: the proxy trusts namespace-internal
    # callers (Grafana's dummy key is ignored), and the observability
    # NetworkPolicy already walls the namespace off.
    model_list:
      - model_name: base
        litellm_params: &base
          model: vertex_ai/${J2026_OBS_LLM_MODEL_BASE}
          vertex_project: ${GCP_PROJECT}
          vertex_location: ${J2026_OBS_LLM_VERTEX_LOCATION}
      - model_name: gpt-3.5-turbo
        litellm_params: *base
      - model_name: gpt-4o-mini
        litellm_params: *base
      - model_name: large
        litellm_params: &large
          model: vertex_ai/${J2026_OBS_LLM_MODEL_LARGE}
          vertex_project: ${GCP_PROJECT}
          vertex_location: ${J2026_OBS_LLM_VERTEX_LOCATION}
      - model_name: gpt-4
        litellm_params: *large
      - model_name: gpt-4o
        litellm_params: *large
    litellm_settings:
      # Gemini doesn't accept every OpenAI param the plugin may send (e.g.
      # logit_bias); drop them instead of erroring the chat.
      drop_params: true
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${LITELLM_NAME}
  namespace: ${J2026_OBS_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${LITELLM_NAME}
    app.kubernetes.io/part-of: jenkins-2026
spec:
  # Stateless single pod: LiteLLM holds no data (config from the ConfigMap,
  # identity from the metadata server), so one replica suffices for the
  # assistant's interactive traffic and a reschedule loses nothing.
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${LITELLM_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${LITELLM_NAME}
        app.kubernetes.io/part-of: jenkins-2026
    spec:
      serviceAccountName: ${J2026_OBS_LLM_KSA}
      containers:
        - name: litellm
          image: ${J2026_OBS_LLM_LITELLM_IMAGE}:${J2026_OBS_LLM_LITELLM_VERSION}
          args: ["--config", "/etc/litellm/config.yaml", "--port", "${J2026_OBS_LLM_LITELLM_PORT}"]
          ports:
            - name: http
              containerPort: ${J2026_OBS_LLM_LITELLM_PORT}
          volumeMounts:
            - name: config
              mountPath: /etc/litellm
              readOnly: true
          readinessProbe:
            httpGet:
              path: /health/readiness
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health/liveliness
              port: http
            initialDelaySeconds: 30
            periodSeconds: 30
          resources:
            requests:
              cpu: 100m
              # LiteLLM v1.91.x needs >1Gi just to boot: it OOMKilled at a 1Gi
              # limit (exit 137, before ever opening the port) - the proxy loads
              # a heavy Python stack at startup. 512Mi request / 2Gi limit gives
              # the headroom to start cleanly.
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 2Gi
          securityContext:
            allowPrivilegeEscalation: false
      volumes:
        - name: config
          configMap:
            name: ${LITELLM_NAME}-config
---
apiVersion: v1
kind: Service
metadata:
  name: ${J2026_OBS_LLM_LITELLM_SERVICE}
  namespace: ${J2026_OBS_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${LITELLM_NAME}
    app.kubernetes.io/part-of: jenkins-2026
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: ${LITELLM_NAME}
  ports:
    - name: http
      port: ${J2026_OBS_LLM_LITELLM_PORT}
      targetPort: http
EOT
kubectl apply -f "${GENERATED_DIR}/litellm.yaml"
# Non-fatal wait: an optional feature must never wedge Day1 (same stance as
# the NAP ComputeClass apply); a failed rollout self-reports in the logs.
wait_for_deployment "${LITELLM_NAME}" "${J2026_OBS_NAMESPACE}" || log_warn "LiteLLM rollout not Ready (non-fatal) - the AI assistant will be degraded until it recovers."

# --- plugin provisioning (companion ConfigMap for values-oss-llm.yaml) --------
# File-provisioned because Grafana persistence is off in oss mode; the dummy
# key satisfies the plugin's "key required" validation, LiteLLM ignores it.
log_step "Provisioning grafana-llm-app -> LiteLLM (${J2026_OBS_LLM_LITELLM_SERVICE}:${J2026_OBS_LLM_LITELLM_PORT})"
LITELLM_URL="http://${J2026_OBS_LLM_LITELLM_SERVICE}.${J2026_OBS_NAMESPACE}:${J2026_OBS_LLM_LITELLM_PORT}"
cat > "${GENERATED_DIR}/grafana-llm-app.yaml" <<EOT
apiVersion: 1
apps:
  - type: grafana-llm-app
    org_id: 1
    disabled: false
    jsonData:
      # Top-level 'provider' is the current schema (plugin 1.0.x); the nested
      # openAI.provider stays for back-compat with older plugin versions.
      provider: openai
      openAI:
        provider: openai
        url: ${LITELLM_URL}
    secureJsonData:
      # Dummy - LiteLLM has no master_key and relies strictly on Workload
      # Identity toward Vertex AI; the plugin just requires a non-empty value.
      openAIKey: keyless-vertex-ai
EOT
# In GRAFANA's namespace (not J2026_OBS_NAMESPACE): the Grafana pod mounts it,
# and the two namespaces are separate knobs even though they default the same.
BEFORE_HASH="$(kubectl get configmap "${LLM_PROVISIONING_CONFIGMAP}" -n "${J2026_GRAFANA_OSS_NAMESPACE}" -o jsonpath='{.data}' 2>/dev/null | sha256sum | cut -d' ' -f1 || true)"
kubectl create configmap "${LLM_PROVISIONING_CONFIGMAP}" \
  -n "${J2026_GRAFANA_OSS_NAMESPACE}" \
  --from-file=grafana-llm-app.yaml="${GENERATED_DIR}/grafana-llm-app.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -
AFTER_HASH="$(kubectl get configmap "${LLM_PROVISIONING_CONFIGMAP}" -n "${J2026_GRAFANA_OSS_NAMESPACE}" -o jsonpath='{.data}' 2>/dev/null | sha256sum | cut -d' ' -f1 || true)"

# Grafana reads provisioning files at startup only, and the overlay mounts
# this ConfigMap optional=true (it may not have existed at pod start) - so
# restart Grafana whenever the provisioning content changed. No-op restart
# is avoided on idempotent re-runs (hashes match).
if [[ "${BEFORE_HASH}" != "${AFTER_HASH}" ]] \
   && kubectl get deployment "${GRAFANA_DEPLOYMENT}" -n "${J2026_GRAFANA_OSS_NAMESPACE}" >/dev/null 2>&1; then
  log_info "LLM provisioning changed - restarting Grafana to load it."
  kubectl rollout restart deployment "${GRAFANA_DEPLOYMENT}" -n "${J2026_GRAFANA_OSS_NAMESPACE}"
fi
log_info "Grafana LLM app wired: grafana-llm-app -> ${LITELLM_URL} -> Vertex AI (${J2026_OBS_LLM_MODEL_BASE} / ${J2026_OBS_LLM_MODEL_LARGE}) via Workload Identity."
