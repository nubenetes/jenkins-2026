[← Previous: 503. Networking](./503-NETWORKING.md) | [🏠 Home](../README.md) | [→ Next: 601. DevSecOps](./601-DEVSECOPS.md)

---

# 504. Backend TLS — LB→pod re-encryption (opt-in)

**TL;DR** — By default, TLS terminates at the global L7 LB and the LB→pod hop is
plain HTTP (VPC-internal, riding Google's default network-layer encryption —
the posture [docs/501 §3](./501-PLATFORM_OPERATIONS.md#3-zero-trust-security--workload-identity)
documents). Setting **`gateway.backendTls.enabled: true`** (override
`JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED`) and re-running `Day1` adds
**application-layer TLS on that hop** for the TLS-ready backends: cert-manager +
a cluster-internal CA are installed, the backend serves HTTPS itself, and a GKE
`BackendTLSPolicy` makes the LB **re-encrypt *and* validate** the connection
against the internal CA. Stages 1–8 convert all available web interfaces and backends:
**Headlamp**, the **faro RUM receiver**, **ArgoCD** (fully active for all four engines),
**pgAdmin**, the in-cluster **OSS Grafana** (doubly conditional on `observability.mode=oss`),
**Jenkins** (when `ci.engine=jenkins`), **Tekton Dashboard** (when `ci.engine=tekton`),
and **Argo Workflows Server** (when `ci.engine=argoworkflows`); the roadmap below has the
per-backend detail. Default **`false`** — zero impact until you opt in.

## Why (and why opt-in)

The plain-HTTP hop is already a deliberate, defensible posture: it never leaves
Google's VPC fabric, Google encrypts it at the network layer in transit, and
pod-to-pod traffic is WireGuard-encrypted between nodes (Dataplane V2). What
backend TLS adds on top is **application-layer** encryption + **server
authentication**: the LB proves it is talking to *the* backend holding a cert
minted by the cluster's CA, not merely to whatever answers on that endpoint.
That is defense-in-depth, not a gap fix — hence a feature flag, not a default:

- it needs an in-cluster PKI (cert-manager + CA) that the default posture
  doesn't,
- each backend must be individually converted to serve TLS (some have real
  blockers — see the roadmap), and
- it depends on a recent GKE Gateway capability (below).

## Should you enable it? (decision guide)

This section is deliberately non-technical — read it before touching the flag.

**What you already have with the flag OFF (`false`, the default) — nothing to
add, nothing missing that handles sensitive data in the clear:**

- **Every external client (browser, IAP) always gets full TLS.** The flag only
  ever touches the *internal* LB→pod hop; it never weakens or changes the
  Google-managed edge TLS a user's browser sees. This is true with the flag on
  *or* off.
- **The "plain HTTP" LB→pod hop is not "unencrypted on the wire" in the naive
  sense.** It never leaves Google's private VPC fabric (not internet-routable,
  no public IP involved), Google encrypts it at the network layer in transit,
  and Dataplane V2's WireGuard config separately encrypts inter-node pod
  traffic. Three independent layers already sit under this hop before backend
  TLS enters the picture.
- **No credential or secret crosses this hop in the clear because of the flag
  being off.** Authentication (IAP, OIDC, Jenkins basic-auth, ArgoCD tokens)
  happens at a layer above this one and is unaffected either way.

**What turning the flag ON actually adds — and it is real, just narrow:**

- **Application-layer encryption + server authentication on that one hop.**
  With the flag on, the LB cryptographically verifies it is talking to *the*
  specific backend that holds a certificate signed by this cluster's internal
  CA — not merely to whatever process happens to answer on that Service's IP
  and port.
- **The threat this closes**: something *already inside* the cluster/VPC
  intercepting or impersonating a backend Service between the LB and the pod
  (e.g. a compromised workload spoofing the `jenkins` Service to harvest
  traffic). It does **not** close a hole reachable from the public internet —
  that hop was never internet-reachable to begin with.
- In short: it is genuine **defense-in-depth against an already-compromised
  cluster**, not a fix for a hole in the current, internet-facing security
  boundary.

**The cost of turning it on — also real, seen firsthand in this project:**

- An in-cluster PKI to operate (cert-manager + a CA whose lifecycle now
  matters, even if ephemeral-by-design — see Lifecycle below).
- Meaningfully more moving parts and blast radius. The first live enablement
  of the Jenkins stage in this repo surfaced **four separate bugs** before it
  worked end-to-end (a Helm chart port collision, an ArgoCD sync race, a
  missing NetworkPolicy rule, and an internal script talking to the wrong
  port) — none of them security bugs, all of them the direct cost of the added
  complexity. That is the realistic price of enabling this, not a hypothetical
  one.
- Some backends have a documented, permanent gap even when enabled (e.g. the
  ArgoCD↔tekton/argoworkflows caller mismatch, the oss-mode Jenkins Grafana
  datasource — see the roadmap table), so "enabled" is not uniformly "every
  hop re-encrypted."

**A simple recommendation:**

| Situation | Recommendation |
|---|---|
| Single-tenant demo/PoC cluster, no other tenants sharing the VPC, no untrusted workloads that could plausibly spoof a Service (this repo's default posture) | **Leave it off.** The marginal security gain is real but narrow (see threat model above), and the default posture is already reasonably defended (VPC-only + network-layer encryption + WireGuard). Optimizing for reliability over an extra defense-in-depth layer is a defensible choice here. |
| You want to *demonstrate* or *exercise* zero-trust intra-cluster patterns, or you're hardening this toward a multi-tenant / production-like posture | **Enable it.** That is exactly the scenario this feature is for, and it is fully additive (default off, opt-in, `Day1`/`Day2.redeploy.*` accept the flag). |
| You're not sure | **Leave it off** until you have a concrete reason to turn it on — it costs nothing to stay on the default, and you can always enable it later per the Lifecycle section. |

Whatever you choose, the flag is **additive and reversible**: default `false`,
zero impact until opted in, and every consumer gates on
[`j2026_backend_tls_active`](../scripts/lib/common.sh) so a partial/older
cluster degrades consistently to the existing plain-HTTP posture instead of
502ing.

## The flag

Durable default in [`config/config.yaml`](../config/config.yaml), ephemeral
override via env var — the standard pattern:

| Key | Default | Override | Consumers |
|---|---|---|---|
| `gateway.backendTls.enabled` | `false` | `JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED` | [`08.5-argocd.sh`](../scripts/08.5-argocd.sh) (Headlamp TLS values overlay + the `backendTls` param it threads to the pgAdmin app-of-apps) · [`08.7-backend-tls.sh`](../scripts/08.7-backend-tls.sh) (cert-manager + CA + certs) · [`03-observability.sh`](../scripts/03-observability.sh) (faro TLS overlay + the `backendTls` param it threads to the observability-oss app-of-apps for OSS Grafana) · [`04-jenkins.sh`](../scripts/04-jenkins.sh) (Jenkins TLS values overlay + the agent-port env var patched into `jenkins-credentials`) · [`09-gateway.sh`](../scripts/09-gateway.sh) (`BackendTLSPolicy` + HTTPS `HealthCheckPolicy`) |

**No consumer reads the raw flag.** They all gate on
[`j2026_backend_tls_active`](../scripts/lib/common.sh) = *flag AND the cluster
serves the `BackendTLSPolicy` CRD*. GKE Gateway backend TLS went **GA 2026-05**
on `gke-l7-global-external-managed` (and the regional classes); on an older
cluster the CRD is absent, and if only *some* consumers acted the pod would
serve TLS the LB still speaks plain HTTP to (or vice versa) — an instant 502.
Gating everything on the same probe degrades **consistently** to plain HTTP
with a warning.

## How it works

```mermaid
flowchart LR
    client(["Browser"]) -->|"TLS · Google-managed wildcard cert"| lb["Global L7 LB<br/>GKE Gateway + IAP"]
    lb -->|"HTTPS · SNI = Service FQDN<br/>cert validated vs internal CA"| pod["headlamp-server :4466<br/>serves the headlamp-tls cert"]
    subgraph cm["cert-manager · ArgoCD app, flag-gated"]
        root["selfsigned<br/>ClusterIssuer"] --> ca["internal CA<br/>Certificate + ClusterIssuer"]
    end
    ca -->|"mints headlamp-tls Secret"| pod
    ca -->|"ca.crt trust ConfigMap"| btp["BackendTLSPolicy"]
    btp -.->|"re-encrypt + validate"| lb
```

The pieces, in execution order on a `Day1` re-run:

| Piece | Role |
|---|---|
| [`argocd/cert-manager-app.yaml`](../argocd/cert-manager-app.yaml) | cert-manager, GitOps-managed like the other operators (external-secrets / argo-rollouts). Chart pinned to **`v1.20.3`** ([docs/602](./602-VERSION_PINNING.md)); `crds.enabled=true, keep=false` (v1.15+ syntax) so deleting the app removes the CRDs — and with them every `Certificate`/`ClusterIssuer` — for a residue-free retire. `ServerSideApply` + `ServerSideDiff` (large CRDs, same pairing as argo-rollouts). |
| [`scripts/08.7-backend-tls.sh`](../scripts/08.7-backend-tls.sh) | Applies the app, waits for CRDs + webhook (the `08.6` ESO wait pattern), bootstraps the CA chain — `jenkins-2026-selfsigned` `ClusterIssuer` → `jenkins-2026-internal-ca` CA `Certificate` (10y, ECDSA P-256, in `cert-manager`) → `jenkins-2026-internal-ca` CA `ClusterIssuer` — then mints the per-backend server certs and projects the CA's `tls.crt` as the **`jenkins-2026-backend-tls-ca`** ConfigMap (key `ca.crt`) into each TLS-ready backend namespace. Flag off → symmetric retire (app + certs + trust bundles). |
| [`helm/headlamp/values-backend-tls.yaml`](../helm/headlamp/values-backend-tls.yaml) | The backend half, stage 1: `config.tlsCertPath`/`tlsKeyPath` make headlamp-server terminate TLS on its pod port 4466 from the mounted `headlamp-tls` Secret; `probes.scheme: HTTPS` keeps the kubelet probes green. `08.5-argocd.sh` appends this file to the headlamp Application's `valueFiles` **only when active** — the app manifest is re-rendered every run, so flipping the flag off re-applies it without the overlay and ArgoCD self-heals Headlamp back to plain HTTP. |
| [`scripts/09-gateway.sh`](../scripts/09-gateway.sh) | The LB half: generates the `BackendTLSPolicy` (below) + an **HTTPS `HealthCheckPolicy`** per converted backend when active; deletes both (CRD-guarded) when not. |
| [`scripts/down.sh`](../scripts/down.sh) | Teardown: deletes the `BackendTLSPolicy` in the Gateway block, cascade-deletes the cert-manager app while ArgoCD is alive, and includes `cert-manager` in the namespace sweep. |

## The GKE mechanics (what the policies actually do)

The generated policy for Headlamp:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: BackendTLSPolicy
metadata: {name: headlamp-backend-tls, namespace: headlamp}
spec:
  targetRefs:
    - {group: "", kind: Service, name: headlamp}
  validation:
    hostname: headlamp.headlamp.svc.cluster.local
    caCertificateRefs:
      - {group: "", kind: ConfigMap, name: jenkins-2026-backend-tls-ca}
```

- **`validation.hostname` is double-duty**: it is the **SNI** the LB sends in
  the handshake *and* the name the backend cert is validated against — so it
  must match a SAN of the cert `08.7` mints (we use the Service FQDN for both).
- **CA trust = a ConfigMap with key `ca.crt`** (PEM, same namespace as the
  policy/Service; ≤ 8 refs per policy). GKE's alternative,
  `wellKnownCACertificates: "System"`, is **not** a generic system-CA store —
  on GKE it must be paired with a Certificate Manager **TrustConfig**
  (`networking.gke.io/backend-trust-config` option), i.e. more Google-side
  state to manage. For a cluster-internal cert-manager CA, the ConfigMap ref is
  the right tool (and the two modes are mutually exclusive).
- **The health check does NOT follow automatically.** The default LB health
  check type follows the Service's `appProtocol` (unset here = HTTP), so
  without intervention the LB would keep probing plain HTTP against the
  now-TLS pod → backend unhealthy → 502 (the same failure family as the
  faro/argo-events POST-only receivers needing TCP checks). `09-gateway.sh`
  therefore pairs every `BackendTLSPolicy` with an explicit `HealthCheckPolicy`
  `type: HTTPS` probing the serving port.
- **What does *not* change**: the `HTTPRoute` (still targets Service port 80 →
  `targetPort` 4466), the IAP `GCPBackendPolicy` (IAP composes with backend
  TLS), and the NetworkPolicy (Headlamp's baseline already allows pod port
  4466, which now speaks TLS on the same port).
- **Requires the Network Security API project-wide.** The GKE Gateway
  controller compiles a `BackendTLSPolicy` into a load-balancer *server TLS
  policy*, which needs `networksecurity.googleapis.com` enabled on the GCP
  project — not just on the CRD/cluster side. `terraform/gke` enables it
  unconditionally (same treatment as `secretmanager.googleapis.com`), so a
  `Day1` from a clean project is covered. If the API was disabled when the
  flag first flipped true on an **already-provisioned** cluster (e.g. a bare
  `gcloud services enable networksecurity.googleapis.com` was skipped because
  the Terraform apply that would have enabled it hadn't run yet), `gceSync`
  fails with `NetworkSecurity API is not enabled, but server_tls_policies are
  present in the load balancer` — and because the Gateway is a **single
  shared resource**, this blocks `Programmed` for *every* hostname (Jenkins,
  ArgoCD, Grafana, microservices, …), not just Headlamp. Fix: enable the API
  (`gcloud services enable networksecurity.googleapis.com` or re-apply
  `terraform/gke`) and wait for the controller's next resync — no Gateway/HTTPRoute
  edit needed.

## Stage 1: why Headlamp

| Criterion | Headlamp |
|---|---|
| Native TLS support | ✅ upstream `-tls-cert-path`/`-tls-key-path` flags, first-class chart values (0.43.0+), probe scheme knob |
| Cert format | ✅ plain PEM `tls.crt`/`tls.key` — exactly what cert-manager writes, no keystore conversion |
| Always deployed | ✅ engine- and obs-mode-neutral (unlike Jenkins/Tekton/Argo UIs or OSS Grafana) |
| In-repo manifests | ✅ ArgoCD app + values live here (unlike the microservices, whose deploy chart lives in the gitops-config repo) |
| Blast radius | ✅ an admin UI behind IAP; no other platform component consumes its Service |

## Stage 5: the doubly-conditional one (OSS Grafana)

Grafana is the first backend that is **doubly conditional**: it exists in-cluster
*only* in `observability.mode=oss` (the Grafana Cloud / Azure / AWS backends live
off-cluster), so the conversion is gated on **the flag AND oss mode**, not the flag
alone. Two consequences shaped the implementation:

- **All three consumers stay oss-aware.** `08.7` mints `grafana-tls` only in oss
  mode (and retires it if the mode later switches away with the flag still on);
  `03-observability.sh` only *reaches* the overlay-threading code in its oss branch
  (the `observability-oss` app-of-apps it feeds the `backendTls` param to is applied
  nowhere else); `09-gateway.sh`'s grafana block is already inside `if oss`, and the
  BackendTLSPolicy/HTTPS-health-check pair is nested under the backend-TLS gate
  within it. In every non-oss mode the whole feature is a no-op for Grafana — no
  cert, no policy, no overlay — exactly as before.
- **The Grafana chart has no probe-scheme knob.** Unlike Headlamp (a first-class
  `probes.scheme` value) or pgAdmin (probe scheme derived from `service.portName`),
  the kube-prometheus-stack Grafana subchart (**Helm chart 12.4.x**, bundled in
  kube-prometheus-stack 87.0.1 — distinct from the Grafana **app** image, tag
  `13.1.0`, pinned in `values-oss.yaml`) renders `readinessProbe`/`livenessProbe`
  **verbatim** from values with no automatic HTTP→HTTPS switch when
  `server.protocol=https`. So the overlay must set `scheme: HTTPS` on both probes
  explicitly (copying the chart's default timings) — omit it and the kubelet keeps
  probing plain HTTP against the now-TLS listener and the pod never goes Ready. This
  is the reusable lesson for any future backend whose chart lacks a scheme knob.

Otherwise it is a standard increment: the cert-manager `grafana-tls` cert (SAN =
the `oss-kube-prometheus-stack-grafana` Service FQDN), the CA trust ConfigMap already
present in the observability namespace (projected there for faro), and the same
BackendTLSPolicy + HTTPS `HealthCheckPolicy` (`/api/health`) pair the other stages use.

## Converting the next backend (roadmap + checklist)

Each backend is an independent increment: make it serve TLS from a
cert-manager cert, then add its `BackendTLSPolicy` + HTTPS `HealthCheckPolicy`
pair (and trust-ConfigMap namespace) to `09-gateway.sh`/`08.7-backend-tls.sh`.
Known per-backend state:

| Backend | TLS mechanism | Blocker / note |
|---|---|---|
| **Headlamp** | native flags | ✅ **done (stage 1)** |
| **faro receiver (otel-collector)** | faro receiver `tls` block + mounted cert | ✅ **done (stage 2)** — the `faro-tls` overlay ([`values-backend-tls.yaml`](../observability/otel-collector/values-backend-tls.yaml)) is layered by `03-observability.sh` onto every mode's collector release; the `faro-tls` volume is declared `optional: true` in each `values-<mode>.yaml` so a flag-off collector still starts. Its HealthCheckPolicy stays **TCP** (protocol-agnostic), so only the `BackendTLSPolicy` flips — no health-check change |
| **ArgoCD** | native — argocd-server watches the `argocd-server-tls` Secret and serves TLS when not `--insecure` | ✅ **done (stage 3)** — Integrated for all four engines: the callers (Jenkins shared library, GHA ARC, Tekton task, and Argo Workflows Sensor) dynamically check if Backend TLS is active by looking for the `gateway-tls` secret in their target namespace, then dial port `443` (TLS) or port `80` (plaintext + `--plaintext`) accordingly. |
| **pgAdmin** | container env `PGADMIN_ENABLE_TLS` + `PGADMIN_LISTEN_PORT=8443`, certs mounted as `/certs/server.cert`/`server.key` | ✅ **done (stage 4)** — the [`values-backend-tls.yaml`](../helm/pgadmin/values-backend-tls.yaml) overlay flips the runix subchart to serve HTTPS on **8443** (non-privileged, the pod runs as UID 5050), remapping the cert-manager `tls.crt`/`tls.key` to pgAdmin's `server.cert`/`server.key` via `extraSecretMounts` subPath (with `defaultMode: 0644`, since subPath mounts don't get the pod's fsGroup). `service.portName: https` flips the chart probes to HTTPS; `09-gateway.sh` adds the `BackendTLSPolicy` + an HTTPS `HealthCheckPolicy` (`/misc/ping`). The overlay threads through the `platform-postgres` app-of-apps: `08.5` passes a `backendTls` helm param that makes the pgAdmin child app layer the overlay only when active |
| **Grafana (OSS)** | `grafana.ini` `server.protocol=https` + mounted cert | ✅ **done (stage 5)** — the [`values-oss-backend-tls.yaml`](../observability/grafana/values-oss-backend-tls.yaml) overlay flips the kube-prometheus-stack Grafana subchart to serve HTTPS on pod port **3000** (`grafana.ini` `server.protocol=https` + `cert_file`/`cert_key` from the mounted cert-manager `grafana-tls` Secret at `/etc/grafana/certs`). **Doubly conditional** — in-cluster Grafana exists only in `observability.mode=oss`, so both `08.7` (cert mint) and `09` (policies) are oss-gated, and the overlay threads through the `observability-oss` app-of-apps: `03-observability.sh` passes a `backendTls` helm param that makes the `oss-kube-prometheus-stack` child layer the overlay only when active. The Grafana chart renders probes verbatim (no auto-scheme from `protocol`), so the overlay sets `readinessProbe`/`livenessProbe` `scheme: HTTPS` explicitly; `09-gateway.sh` adds the `BackendTLSPolicy` + an HTTPS `HealthCheckPolicy` (`/api/health`). IAP (auth.proxy header trust) composes unchanged |
| **Jenkins** | chart `controller.httpsKeyStore.*` + cert-manager `keystores.jks` (JKS + password Secret) | ✅ **done (stage 6, `ci.engine=jenkins` only)** — highest blast radius of the six stages: build agents dial the controller **Service** directly in plain HTTP, so instead of requiring every in-cluster caller to trust the internal CA, [`values-backend-tls.yaml`](../helm/jenkins/values-backend-tls.yaml) uses the chart's **native** `controller.httpsKeyStore` feature: it moves the pod's plain-HTTP listener + kubelet probes to `httpsKeyStore.httpPort` (**8081**) while the Service's existing port (8080) becomes HTTPS, and `controller.extraPorts` re-exposes that plain pod port on the Service as **8082** (`port: 8082 → targetPort: 8081`). `08.7-backend-tls.sh` mints a JKS keystore (`keystore.jks`), encrypted with a password from `jenkins-https-jks-password` Secret. `04-jenkins.sh` patches `JENKINS_AGENT_PORT=8082` into `jenkins-credentials` only when active. |
| **Grafana-Jenkins Datasource** | Helm parameters | ✅ **done (stage 6a, `observability.mode=oss` only)** — Overridden dynamically in `argocd/observability-oss/templates/kube-prometheus-stack.yaml` to target `https://jenkins...:8080` and set `tlsSkipVerify: true` in the Grafana configuration when Backend TLS is active, resolving panel errors without configuration drift. |
| **microservices gateway (JHipster)** | Spring Boot `server.ssl.*` + cert-manager `keystores.pkcs12` | **cross-repo** — the deploy chart lives in `jenkins-2026-gitops-config`; also interacts with Argo Rollouts canary routes and every engine's smoke test URL |
| **Tekton Dashboard** | native arguments (`--tls-cert`/`--tls-key`) + mounted cert | ✅ **done (stage 8, `ci.engine=tekton` only)** — The `dashboard-tls` overlay is conditionally selected by the parent Application when `backendTls` is active, mounting the `tekton-dashboard-tls` secret, configuring `--tls-cert` and `--tls-key` arguments, and setting `HTTPS` scheme for both liveness and readiness probes. `09-gateway.sh` adds the matching `BackendTLSPolicy` and HTTPS `HealthCheckPolicy` (`/readiness`). |
| **Argo Workflows Server** | native arguments + mounted cert | ✅ **done (stage 9, `ci.engine=argoworkflows` only)** — The `workflows-tls` overlay is conditionally selected by the parent Application when `backendTls` is active, mounting the `argo-server-tls` secret and changing `readinessProbe` to HTTPS scheme. `09-gateway.sh` attaches the matching `BackendTLSPolicy` and HTTPS `HealthCheckPolicy` (`/`). |

## Does `secrets.backend=eso` change anything?

**No — deliberately.** The ESO backend ([docs/201](./201-ARCHITECTURE.md#secrets-backend-imperative--eso))
externalizes secrets whose **source of truth is outside the cluster** (the
GitHub-sourced credentials, groups 1–3). cert-manager certificates are the
opposite case: **minted, rotated and consumed entirely in-cluster**, with the
in-cluster CA as their source of truth — the same rationale that keeps group 4
(in-cluster / Terraform-minted secrets) imperative even in `eso` mode.
Round-tripping short-lived, auto-rotated private keys through GCP Secret Manager
would add an external copy of every key and rotation churn in the external
store, with no recoverability benefit — a rebuild regenerates the whole PKI
anyway (the CA is ephemeral per cluster; see Lifecycle).

The one *legitimate* ESO interaction is **optional CA persistence**: if you ever
wanted the CA **keypair** to survive rebuilds (so backend certs chain to a stable
root across `Decom`+`Day1`), you could store the CA Secret in Secret Manager and
have ESO restore it on provision — the same `sm_keep_or_generate` pattern the
platform uses for stable Postgres passwords ([docs/104](./104-REBUILD_SAFETY.md)).
With an **LB-only trust model** (no external client ever pins these certs; only
the LB validates them, and its trust anchor is regenerated in the same run) this
buys nothing, so it is **documented here and not implemented**.

## Why not a service mesh?

Backend TLS closes exactly one gap — application-layer TLS + server
authentication on the LB→pod hop. A service mesh (Istio, or GKE's managed **Cloud
Service Mesh**) also closes it, but by re-making platform decisions this repo
made deliberately: **sidecar-free** progressive delivery (Argo Rollouts + the
Gateway API traffic-router plugin — [docs/501 § Progressive Delivery](./501-PLATFORM_OPERATIONS.md)),
WireGuard transport encryption, and enforced Dataplane V2 NetworkPolicies. The
three options, in *this platform's* context (a two-microservice PoC that already
has those three):

| | **cert-manager + `BackendTLSPolicy`** (chosen) | **Istio (self-managed)** | **Cloud Service Mesh (GCP managed)** |
|---|---|---|---|
| **What it closes** | App-layer TLS on the LB→pod hop (+ the internal hop later) | mTLS with per-workload **identity** on **all** hops + L7 authZ | Same as Istio, managed control plane |
| **New moving parts** | cert-manager + one policy per host + cert Secrets in the apps | Control plane (istiod) + a sidecar per pod (or ambient ztunnel/waypoint) | Managed control plane; data-plane proxies still run in your pods |
| **Operational cost** | Low — cert-manager auto-rotates; no new plane to upgrade | High — control-plane upgrades, proxy version skew, debugging through sidecars | Medium — Google runs the control plane, **but requires GKE Enterprise** (licensing cost) |
| **Identity / authZ** | None (one-way TLS, no workload identity) | SPIFFE identities + `AuthorizationPolicy` L7 rules | Same, plus a managed mesh CA |
| **Redundancy with what's built** | None — composes with WireGuard / NetPols / Rollouts | **Triple overlap**: traffic-shifting (vs Rollouts + Gateway plugin), transport encryption (vs WireGuard + Google in-transit), L3/4 authZ (vs enforced Cilium NetworkPolicies) | Same overlaps, slightly attenuated by the Gateway API integration |
| **Interaction risk** | Health checks must switch to HTTPS (handled) | Dataplane V2 (managed Cilium/eBPF) + Istio is a *supported but delicate* two-layer combo | Same class of constraint, better documented by Google |
| **Fit for a 2-service PoC** | Right-sized | Overkill | Overkill + license |
| **Cost** | $0 | $0 licence, high toil | GKE Enterprise subscription |

**Why the meshes lost here** — not because meshes are wrong, but because this
platform already made the calls a mesh would re-make: Argo Rollouts + the Gateway
API plugin were chosen *specifically* to get canary/blue-green **without
sidecars**; WireGuard already closes plaintext-on-the-wire; enforced
NetworkPolicies already do L3/4 segmentation. A mesh would duplicate all three,
add a second networking layer beside Dataplane V2's managed Cilium, and (for
Cloud Service Mesh) couple the PoC to GKE Enterprise — while the **only** missing
property was app-layer TLS on one hop.

**When to revisit** — tens of services, a compliance mandate for **identity-based
mTLS to the pod**, fine-grained L7 authorization between workloads, or
multi-cluster. At that point prefer **Cloud Service Mesh over self-managed
Istio** (the operational delta is what you'd be buying) and retire this flag's
machinery in favour of the mesh CA. Until then, backend TLS is the minimal,
composable increment.

## Lifecycle

- **Enable**: set the flag — durable (`config.yaml`), per-run env
  (`JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED`), or the **`backend_tls` input**
  on the `Day1.cluster.00/01` GHA workflows — and **re-run `Day1`**
  ([applying changes = re-run, not Decom+Day1](../CLAUDE.md)): it is the only
  path that runs all three consumers (`08.5` + `08.7` + `09`) in one
  converging pass. The same `backend_tls` input exists on every
  `Day2.redeploy.*` workflow that runs a consumer (`.01-argocd` → `08.5` ·
  `.05-gateway` → `08.7`+`09` · the engine redeploys `.03/.06/.07` → `09`) —
  there it must **match the live cluster**: a flag *flip* through any single
  Day2 workflow leaves the pod and the LB disagreeing on the protocol
  (headlamp 502) until the other half runs.
- **Disable**: flip the flag off and re-run `Day1`. `08.5` re-renders Headlamp
  without the overlay (ArgoCD self-heals it back to HTTP), `08.7` retires the
  certs/trust bundles and cascade-deletes cert-manager, `09` deletes the
  policies. Expect a **brief Headlamp blip** while the LB policy removal and
  the pod's HTTP restart converge (it's an IAP-protected admin UI; nothing else
  consumes it).
- **Teardown**: [`down.sh`](../scripts/down.sh) removes the policy, the
  cert-manager app and (with `J2026_DELETE_NAMESPACES=true`) the namespace.
- **Rebuild safety** ([docs/104](./104-REBUILD_SAFETY.md)): everything this
  feature creates is **in-cluster state with no external identity** — the CA,
  certs, trust bundles and policies die with the cluster and are re-minted
  fresh on the next Day1. No collision, no residue, no new matrix row
  mechanism needed (safe-by-construction).
- **Cert rotation**: cert-manager renews the leaf (90d default) and the
  `BackendTLSPolicy` trust bundle is re-projected on every run; headlamp-server
  reads its cert at startup, so a renewal inside one cluster's lifetime needs a
  pod restart — `08-headlamp.sh` already restarts it on every Day1 re-run,
  which in practice covers this PoC's cluster lifetimes.

### GKE Gateway NEG & ServiceNetworkEndpointGroup Finalizer Self-Healing

When operating Backend TLS in GKE, you will hit a known GKE NEG controller lifecycle limitation on cluster redeployments or Helm upgrades. Because GKE Gateway uses container-native load balancing via Network Endpoint Groups (NEGs), it manages a custom resource in the cluster named `ServiceNetworkEndpointGroup` (`svcneg` in `networking.gke.io/v1beta1`).

This architecture creates two potential deadlocks that this project automatically self-heals:

#### 1. Bootstrapping Deadlock (HTTPS Probe Mismatch)
* **The Problem**: When Backend TLS is enabled, the backend pods serve HTTPS. However, GKE's default health checking uses HTTP. The matching HTTPS `HealthCheckPolicy` and `BackendTLSPolicy` are traditionally applied at the very end of the provisioning pipeline (`09-gateway.sh`). During a fresh cluster bootstrap, if the workload rollout scripts (`03-observability.sh` or `08-headlamp.sh`) wait for the deployment rollout to complete before proceeding, the pods remain unhealthy in the GCP Load Balancer (due to the HTTP/HTTPS probe mismatch). GKE keeps the NEG readiness gate (`cloud.google.com/load-balancer-neg-ready`) as `False`, permanently wedging the rollout and preventing the pipeline from ever reaching the gateway step that would apply the fixing policy.
* **The Self-Healing Fix**: The setup scripts for Grafana (`03-observability.sh`) and Headlamp (`08-headlamp.sh`) proactively generate and apply their respective `BackendTLSPolicy` and `HealthCheckPolicy` (HTTPS) **before** calling `wait_for_deployment`. This immediately configures the GCP Load Balancer to send HTTPS probes, satisfying the NEG readiness gate and allowing the rollout to proceed.

#### 2. Deterministic NEG Finalizer Deadlock (Stuck "Terminating" resources)
* **The Problem**: When a Service is deleted and recreated (e.g., during a Helm upgrade/redeploy or namespace reset), its UID changes. The GKE NEG controller attempts to delete the old `ServiceNetworkEndpointGroup` (`svcneg`) resource, which holds a finalizer (`networking.gke.io/neg-finalizer`). Because the new Service immediately registers itself with the *same* name, it reuses the same underlying Google Cloud NEG resource. The GKE NEG controller detects the GCP NEG is still in use and refuses to delete it, permanently wedging the old `ServiceNetworkEndpointGroup` object in `Terminating` status. ArgoCD sees this terminating resource and gets stuck in an infinite `Syncing` loop.
* **The Self-Healing Fix**: A proactive cleanup loop is embedded at the end of `scripts/01-namespaces.sh`. If it runs on GKE, it queries the API server for any `svcneg` resources containing a `deletionTimestamp` (meaning they are stuck in Terminating). It automatically patches them to clear their finalizers (`finalizers: null`). Once deleted, GKE's NEG controller automatically regenerates a fresh, clean `svcneg` object for the active Service, immediately resolving the ArgoCD sync loop and returning the application to a `Synced` and `Healthy` state.

## Verifying it

```bash
kubectl get application cert-manager -n argocd                  # Synced/Healthy
kubectl get clusterissuer                                       # both Ready
kubectl get certificate -A                                      # CA + headlamp-tls Ready
kubectl get backendtlspolicy,healthcheckpolicy -n headlamp      # headlamp policy pair present
kubectl get backendtlspolicy faro-backend-tls -n observability  # faro policy (health check stays TCP)
kubectl get certificate faro-tls -n observability               # faro-tls Ready
kubectl get backendtlspolicy,healthcheckpolicy -n pgadmin       # pgadmin policy pair present
kubectl get certificate pgadmin-tls -n pgadmin                  # pgadmin-tls Ready
# Grafana (observability.mode=oss ONLY): cert + policy pair in the observability namespace
kubectl get certificate grafana-tls -n observability            # grafana-tls Ready
kubectl get backendtlspolicy,healthcheckpolicy oss-kube-prometheus-stack-grafana -n observability 2>/dev/null; kubectl get backendtlspolicy grafana-backend-tls -n observability
kubectl -n headlamp get cm jenkins-2026-backend-tls-ca -o jsonpath='{.data.ca\.crt}' | head -1
# The pod side: headlamp now speaks TLS on 4466
kubectl -n headlamp exec deploy/headlamp -- wget -q --no-check-certificate -O- https://localhost:4466/ >/dev/null && echo TLS-OK
# faro: the collector serves TLS on 8027 (SNI = the Service FQDN, validated vs the CA)
kubectl -n observability get svc otel-collector-gateway -o jsonpath='{.spec.ports[?(@.name=="faro")].port}'
# pgAdmin: the pod now serves TLS on 8443 (Service port 80 -> targetPort 8443)
kubectl -n pgadmin get svc pgadmin-pgadmin4 -o jsonpath='{.spec.ports[0].targetPort}'; echo
kubectl -n pgadmin exec deploy/pgadmin-pgadmin4 -- wget -q --no-check-certificate -O- https://localhost:8443/misc/ping >/dev/null && echo TLS-OK
# Grafana (oss): the pod now serves TLS on 3000 (grafana.ini server.protocol=https)
kubectl -n observability exec deploy/oss-kube-prometheus-stack-grafana -c grafana -- wget -q --no-check-certificate -O- https://localhost:3000/api/health >/dev/null && echo TLS-OK
# Tekton Dashboard (tekton): the pod serves TLS on 9097
kubectl -n tekton-pipelines exec deploy/tekton-dashboard -- wget -q --no-check-certificate -O- https://localhost:9097/readiness >/dev/null && echo TLS-OK
# Argo Workflows Server (argoworkflows): the pod serves TLS on 2746
kubectl -n argo exec deploy/argo-server -- wget -q --no-check-certificate -O- https://localhost:2746/ >/dev/null && echo TLS-OK
# The LB side: the public hosts must still answer (IAP first for the admin UIs; faro is public)
curl -sSI https://headlamp.<baseDomain> | head -3
curl -sSI https://faro.<baseDomain>     | head -3
curl -sSI https://pgadmin.<baseDomain>  | head -3
curl -sSI https://grafana.<baseDomain>  | head -3   # observability.mode=oss only
curl -sSI https://tekton.<baseDomain>   | head -3   # ci.engine=tekton only
curl -sSI https://argo.<baseDomain>     | head -3   # ci.engine=argoworkflows only
```

If the host 502s after enabling, check `kubectl describe backendtlspolicy -n
headlamp` (an unattached/invalid policy is silently ignored — the same
`Attached=False` failure mode as the IAP `GCPBackendPolicy`, see
[docs/902](./902-TROUBLESHOOTING.md)) and the LB health-check state (the
`HealthCheckPolicy` must be HTTPS once the pod serves TLS).

---

[← Previous: 503. Networking](./503-NETWORKING.md) | [🏠 Home](../README.md) | [→ Next: 601. DevSecOps](./601-DEVSECOPS.md)

---

*504. Backend TLS — LB→pod re-encryption — jenkins-2026*
