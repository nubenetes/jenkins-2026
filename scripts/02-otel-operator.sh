#!/usr/bin/env bash
# Installs the OpenTelemetry Operator (CRDs: OpenTelemetryCollector,
# Instrumentation). Must run before helm/petclinic (its Instrumentation CR is
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
  -f "${J2026_ROOT_DIR}/observability/otel-operator/values.yaml" \
  --wait --timeout 5m

log_step "Waiting for OpenTelemetry CRDs to be established"
for crd in opentelemetrycollectors.opentelemetry.io instrumentations.opentelemetry.io; do
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=120s
done

log_info "OpenTelemetry Operator ready."
