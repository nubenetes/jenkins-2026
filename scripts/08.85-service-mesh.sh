#!/usr/bin/env bash
# Cloud Service Mesh (CSM) — in-cluster half of the OPT-IN
# serviceMesh.mode=cloud-service-mesh feature (default none). See
# docs/506-SERVICE-MESH.md for the full design + the why-CSM / why-NOT-Istio-self-
# managed / Traefik / other-meshes matrices and the per-mesh-client cost model.
#
# The CLOUD half (mesh.googleapis.com + Fleet membership + the `servicemesh` Fleet
# feature = managed control plane + Mesh CA, the STANDALONE per-client SKU — NOT the
# GKE Enterprise tier) is provisioned by terraform/gke (TF_VAR_service_mesh_mode,
# security.tf), so by the time this runs the managed control plane is (being) rolled
# out. This script does the IN-CLUSTER half:
#   1. mesh-wide STRICT (or PERMISSIVE) PeerAuthentication in istio-system;
#   2. labels the microservices namespace(s) for managed sidecar injection;
#   3. per-namespace STRICT PeerAuthentication + a baseline AuthorizationPolicy;
#   4. best-effort rolls the meshed workloads so they pick up the istio-proxy sidecar.
# When INACTIVE (mode=none, OR the injection webhook isn't up yet — the shared
# j2026_service_mesh_active gate in lib/common.sh): symmetric retire — removes the
# labels + policies left by a previous enabled run on this (persistent) cluster, so
# flipping the flag off converges with no manual kubectl.
#
# ⚠ MUTUALLY EXCLUSIVE with gateway.backendTls (lib/config.sh fails fast if both on —
# a mesh supersedes that LB→pod hop). Everything here is in-cluster state that dies
# with the cluster; the only persistent piece is the Fleet membership, owned by
# terraform/gke (rebuild-safe, docs/104). Non-fatal by design: no platform pod depends
# on the mesh (like NAP / the LLM app), so a mesh hiccup never blocks the core
# provision. Idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

if [[ "${J2026_PLATFORM}" != "gke" ]]; then
  log_info "platform.target='${J2026_PLATFORM}' — Cloud Service Mesh is GKE-specific, skipping."
  exit 0
fi

# Namespaces enrolled in the mesh: the microservices tier(s). The platform UIs stay
# OUT of the mesh — they are IAP-protected at the edge and not part of the app's
# east-west traffic.
mesh_namespaces=("${J2026_MICROSERVICES_NS_STABLE}")
if [[ "${J2026_MICROSERVICES_DEVELOP_TRACK_ENABLED}" == "true" ]]; then
  mesh_namespaces+=("${J2026_MICROSERVICES_DEVELOP_NAMESPACE}")
fi

# The managed-CSM injection revision label. With the fleet `servicemesh` feature in
# MANAGEMENT_AUTOMATIC, Google provisions a managed revision that namespaces opt into
# via this label. If a live cluster provisions a different revision, read it from
# `kubectl get controlplanerevision -n istio-system` and override MESH_INJECT_* here.
MESH_INJECT_LABEL_KEY="istio.io/rev"
MESH_INJECT_LABEL_VALUE="asm-managed"

# The managed CSM control plane (provisioned by the Fleet `servicemesh` feature in
# terraform/gke) comes up ASYNCHRONOUSLY — several minutes AFTER the terraform apply,
# so on the FIRST enablement its sidecar-injection webhook may not exist yet when this
# script runs. Wait (bounded, ~6 min) for it so a SINGLE Day1 converges the mesh
# instead of no-opping now and needing a second run. Non-fatal: if it never appears we
# fall through to the gate below (which no-ops with a warning; the next run converges).
# Only when mode=cloud-service-mesh — the retire path (mode=none) must not be delayed.
if [[ "${J2026_SERVICE_MESH_MODE}" == "cloud-service-mesh" ]]; then
  if ! kubectl get mutatingwebhookconfiguration 2>/dev/null | grep -qiE 'istio.*sidecar-injector|istiod'; then
    log_info "Waiting for the managed CSM control plane's injection webhook (up to ~6 min)..."
    for _i in $(seq 1 60); do
      sleep 6
      kubectl get mutatingwebhookconfiguration 2>/dev/null | grep -qiE 'istio.*sidecar-injector|istiod' && { log_info "  managed control plane is ready."; break; }
    done
  fi
fi

if [[ "$(j2026_service_mesh_active)" != "true" ]]; then
  # INACTIVE → retire any residue from a previous enabled run (idempotent).
  retired=0
  for ns in "${mesh_namespaces[@]}"; do
    kubectl get namespace "${ns}" >/dev/null 2>&1 || continue
    if kubectl get namespace "${ns}" -o "jsonpath={.metadata.labels.istio\.io/rev}" 2>/dev/null | grep -q .; then
      kubectl label namespace "${ns}" "${MESH_INJECT_LABEL_KEY}-" --overwrite >/dev/null 2>&1 || true
      retired=1
    fi
    kubectl delete peerauthentication default -n "${ns}" --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete authorizationpolicy allow-mesh-internal -n "${ns}" --ignore-not-found >/dev/null 2>&1 || true
  done
  kubectl delete peerauthentication default -n istio-system --ignore-not-found >/dev/null 2>&1 || true
  [[ "${retired}" -eq 1 ]] && log_info "serviceMesh.mode=none — retired the mesh injection labels/policies from a previous enabled run."
  exit 0
fi

log_step "Configuring Cloud Service Mesh (08.85, opt-in) — mTLS=${J2026_SERVICE_MESH_MTLS}, channel=${J2026_SERVICE_MESH_CHANNEL}"

# 1. mesh-wide PeerAuthentication (root namespace = istio-system), if it exists.
if kubectl get namespace istio-system >/dev/null 2>&1; then
  kubectl apply -f - >/dev/null <<YAML || log_warn "  mesh-wide PeerAuthentication apply reported an issue (non-fatal)"
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: ${J2026_SERVICE_MESH_MTLS}
YAML
fi

for ns in "${mesh_namespaces[@]}"; do
  kubectl get namespace "${ns}" >/dev/null 2>&1 || { log_warn "  namespace ${ns} not present yet — skipping (its pods inject once it exists + is labeled on the next run)"; continue; }
  # 2. label for managed sidecar injection.
  kubectl label namespace "${ns}" "${MESH_INJECT_LABEL_KEY}=${MESH_INJECT_LABEL_VALUE}" --overwrite >/dev/null
  # 3a. per-namespace PeerAuthentication (defense in depth).
  kubectl apply -f - >/dev/null <<YAML || log_warn "  ${ns} PeerAuthentication apply reported an issue (non-fatal)"
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ${ns}
spec:
  mtls:
    mode: ${J2026_SERVICE_MESH_MTLS}
YAML
  # 3b. baseline AuthorizationPolicy: allow traffic from within this namespace (the
  # app's own east-west) + from the ingress namespace; deny the rest. A starting
  # point — tighten per-service as the app grows (docs/506).
  kubectl apply -f - >/dev/null <<YAML || log_warn "  ${ns} AuthorizationPolicy apply reported an issue (non-fatal)"
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-mesh-internal
  namespace: ${ns}
spec:
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["${ns}"]
    - from:
        - source:
            namespaces: ["${J2026_GATEWAY_NAMESPACE}"]
YAML
  # 4. best-effort restart so existing pods get the sidecar (new pods inject on create).
  kubectl rollout restart deployment -n "${ns}" >/dev/null 2>&1 || true
  log_info "  meshed namespace ${ns} (injection label + ${J2026_SERVICE_MESH_MTLS} mTLS + baseline AuthorizationPolicy)"
done

log_info "Cloud Service Mesh in-cluster config applied. Verify: kubectl get peerauthentication,authorizationpolicy -A ; gcloud container fleet mesh describe --project \"\${PROJECT}\""
