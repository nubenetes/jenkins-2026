#!/usr/bin/env bash
# Installs the OpenTelemetry Operator (CRDs: OpenTelemetryCollector,
# Instrumentation). Must run before helm/microservices (its Instrumentation CR is
# guarded by a Capabilities check, but auto-instrumentation only takes effect
# once the operator's mutating webhook is live) and before
# 03-observability.sh's collector releases on platforms where the operator
# also reconciles OpenTelemetryCollector CRs.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

log_step "Installing ${J2026_OTEL_OPERATOR_RELEASE} (${J2026_OTEL_OPERATOR_CHART}) into ${J2026_OBS_NAMESPACE}"

helm upgrade --install "${J2026_OTEL_OPERATOR_RELEASE}" "${J2026_OTEL_OPERATOR_CHART}" \
  --namespace "${J2026_OBS_NAMESPACE}" \
  --create-namespace \
  -f "${J2026_ROOT_DIR}/observability/otel-operator/values.yaml"

wait_for_deployment "${J2026_OTEL_OPERATOR_RELEASE}-opentelemetry-operator" "${J2026_OBS_NAMESPACE}"

log_step "Waiting for OpenTelemetry CRDs to be established"
for crd in opentelemetrycollectors.opentelemetry.io instrumentations.opentelemetry.io; do
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=120s
done

# The built-in 'edit' ClusterRole doesn't cover the OTel Operator's CRDs
# (helm/microservices/templates/instrumentation.yaml manages an Instrumentation
# resource per namespace) - `helm upgrade` needs get/list/watch on it (plus
# write verbs to create/update it) to diff against the live cluster, or it
# fails with "instrumentations.opentelemetry.io ... is forbidden".
log_step "Granting Jenkins ServiceAccount access to the Instrumentation CRD"
kubectl create clusterrole jenkins-otel-instrumentation-editor \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=instrumentations.opentelemetry.io \
  --dry-run=client -o yaml | kubectl apply -f -
for ns in "${J2026_MICROSERVICES_NS_STABLE}"; do
  kubectl create rolebinding jenkins-otel-instrumentation-editor \
    --clusterrole=jenkins-otel-instrumentation-editor \
    --serviceaccount="${J2026_JENKINS_NAMESPACE}:jenkins" \
    -n "${ns}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

log_info "OpenTelemetry Operator ready."
