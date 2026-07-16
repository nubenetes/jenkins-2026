# ADR 0001 — Intra-cluster TLS & supply-chain admission: Cloud Service Mesh (standalone) + Binary Authorization

- **Status:** Accepted (2026-07-14). Implemented as two opt-in feature flags; **pending live validation** (per the repo's build-then-validate norm).
- **Deciders:** platform maintainers.
- **Consulted docs:** [506. Service Mesh](../506-SERVICE-MESH.md) · [507. Binary Authorization](../507-BINARY-AUTHORIZATION.md) · [504. Backend TLS](../504-BACKEND_TLS.md) · [104. Rebuild-Safety](../104-REBUILD_SAFETY.md).

> ADRs are **leaf records** (like [runbooks](../README.md#runbooks--validated-live-procedures)): no prev/next nav chain. The *how/why detail* lives in the numbered guides above; this record captures the **decision and the rejected alternatives** so they aren't re-litigated.

## Context

The platform is a GKE PoC (two microservices). It already provides, by other means:

- **Transport encryption + L3/4 segmentation** — **GKE Dataplane V2, which *is* a Google-managed Cilium/eBPF dataplane**: WireGuard inter-node encryption (`in_transit_encryption_config`) + enforced NetworkPolicies. Google manages that Cilium — you **cannot** install upstream Cilium or Cilium Service Mesh on top.
- **Sidecar-free progressive delivery** — Argo Rollouts + the Gateway API traffic-router plugin (a deliberate choice to avoid sidecars).
- **Edge auth** — IAP at the GKE Gateway.
- **Observability** — OTel traces/metrics/logs.
- **Opt-in LB→pod re-encryption** — [backend TLS](../504-BACKEND_TLS.md) (cert-manager `BackendTLSPolicy`), *one-way, server-only, single hop*.
- **Supply-chain scanning** — Semgrep/CodeQL/Trivy in all four CI engines ([601](../601-DEVSECOPS.md)).

Two genuine gaps remain: **(1)** identity-based, *mutual* mTLS + L7 authorization on **east-west** hops (nothing provides this); **(2)** **deploy-time admission** — the pipeline *scans* images but nothing enforces that only scanned/attested images *run*.

## Decision Drivers

- Fit the platform ethos: **managed / minimal-ops**, GitOps, pluggable-behind-a-flag, right-sized for a PoC.
- **Cost** must be trivial for an ephemeral PoC cluster.
- Compose with — not duplicate — Dataplane V2, Rollouts, IAP, backend TLS.
- Reversible, additive, rebuild-safe ([104](../104-REBUILD_SAFETY.md)).

## Considered Options

### Gap 1 — east-west identity mTLS + L7 authZ

| Option | Verdict | Why |
|---|---|---|
| **Cloud Service Mesh (managed, standalone SKU)** | ✅ **chosen** | Google-managed control plane + Mesh CA; composes with Dataplane V2 by design; **standalone per-mesh-client SKU** (~$0.50/client/mo — NOT GKE Enterprise, that edition was **dissolved 2025-09**), so cents for this PoC. |
| Istio self-managed — **sidecar** | ❌ | A sidecar per pod clashes with the sidecar-free stance; istiod to operate; delicate two-layer combo beside the managed Cilium. |
| Istio self-managed — **ambient** | ⚠️ rejected *for now* | Sidecar-free (GA late-2024) removes the main objection, but still a **second control plane** beside Dataplane V2. If running managed Istio anyway, **CSM's managed control plane wins**. |
| **Traefik** (or any ingress-as-mesh) | ❌ | An **edge router — a different layer**. Adopting it means replacing the GKE Gateway and **losing Google IAP**. Category mismatch, not a mesh. |
| **Linkerd** | ❌ | Still **sidecar** (no ambient); **stable builds went commercial** (2024). |
| **Cilium Service Mesh** | ❌ unavailable | The cluster already runs managed Cilium (Dataplane V2), but **GKE does not expose the Cilium mesh API** nor allow upstream Cilium on top. |
| **Consul / Kuma / Kong Mesh** | ❌ | Solve **multi-platform service discovery** (VM+K8s, multi-zone) this repo doesn't have; whole extra control plane. |
| Traefik Mesh · NGINX SM · OSM · AWS App Mesh | ❌ dead | Discontinued / archived / EOL. |

### Gap 2 — supply-chain admission

| Option | Verdict | Why |
|---|---|---|
| **Binary Authorization** | ✅ **chosen** | GKE-native; **basic enforcement free**; KMS attestor + project policy; `dryrun`→`enforce`. Closes the scan→deploy loop. |
| Scan-only (status quo) | ❌ | No admission enforcement — an unscanned/rogue image still deploys. |
| Custom / OPA Gatekeeper admission webhook | ❌ | Build + operate your own webhook **and** signing story; BinAuthz is the native, lower-toil path. |

## Decision Outcome

1. **`serviceMesh.mode=cloud-service-mesh`** (default `none`): managed CSM via the Fleet `servicemesh` feature, standalone SKU. **Mutually exclusive** with `gateway.backendTls.enabled` — a mesh **supersedes** the LB→pod re-encryption hop. Enforced in two layers: a **fail-fast gate in `lib/config.sh`** (authoritative, every entry path) and a **single `intra_cluster_tls` dropdown** in the GHA forms (`none`\|`backend-tls`\|`cloud-service-mesh`) so the conflict cannot be expressed. Both-off is the default posture.
2. **`security.binaryAuthorization.enabled`** (default `false`, `enforcementMode: dryrun`): Binary Authorization admission control. **Orthogonal** — composes with any TLS choice; a separate boolean input.

## Consequences

**Positive** — identity-based zero-trust becomes demonstrable; the supply-chain scan→deploy loop is closed; both are cheap (CSM cents/PoC; BinAuthz effectively free); everything composes with the existing Dataplane V2 / Rollouts / IAP / OTel stack rather than duplicating it.

**Negative / costs** — the **CSM Fleet membership** and the **BinAuthz KMS key + attestor + note** are persistent, fixed-identity resources needing rebuild-safety handling ([104](../104-REBUILD_SAFETY.md)); backend TLS and CSM become mutually exclusive (documented, gated); image **signing must be wired into all four CI engines** (single source: `resources/sign-and-attest-image.sh`) and each engine's build environment needs `gcloud` + Workload Identity to the project — the **live-validation** work; the managed-CSM injection-revision label (`istio.io/rev=asm-managed`) may differ per fleet-provisioned revision.

## Validation

- `terraform init/validate` (the `google_gke_hub_*` resources may need the beta provider; the attestor public-key wiring).
- A live `Day1` with `intra_cluster_tls=cloud-service-mesh` (verify injection + STRICT mTLS + AuthorizationPolicy) and with `binary_authorization=true` (verify attestation on push, dryrun logs, then `enforce`).

## Links

[506. Service Mesh](../506-SERVICE-MESH.md) · [507. Binary Authorization](../507-BINARY-AUTHORIZATION.md) · [504. Backend TLS](../504-BACKEND_TLS.md) · [104. Rebuild-Safety](../104-REBUILD_SAFETY.md) · [601. DevSecOps](../601-DEVSECOPS.md)

---

*ADR 0001 — jenkins-2026*
