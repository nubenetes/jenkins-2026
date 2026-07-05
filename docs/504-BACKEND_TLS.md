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
against the internal CA. Stage 1 converts **Headlamp**; the roadmap below stages
the rest. Default **`false`** — zero impact until you opt in.

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

## The flag

Durable default in [`config/config.yaml`](../config/config.yaml), ephemeral
override via env var — the standard pattern:

| Key | Default | Override | Consumers |
|---|---|---|---|
| `gateway.backendTls.enabled` | `false` | `JENKINS2026_GATEWAY_BACKEND_TLS_ENABLED` | [`08.5-argocd.sh`](../scripts/08.5-argocd.sh) (Headlamp TLS values overlay) · [`08.7-backend-tls.sh`](../scripts/08.7-backend-tls.sh) (cert-manager + CA + certs) · [`09-gateway.sh`](../scripts/09-gateway.sh) (`BackendTLSPolicy` + HTTPS `HealthCheckPolicy`) |

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

## Stage 1: why Headlamp

| Criterion | Headlamp |
|---|---|
| Native TLS support | ✅ upstream `-tls-cert-path`/`-tls-key-path` flags, first-class chart values (0.43.0+), probe scheme knob |
| Cert format | ✅ plain PEM `tls.crt`/`tls.key` — exactly what cert-manager writes, no keystore conversion |
| Always deployed | ✅ engine- and obs-mode-neutral (unlike Jenkins/Tekton/Argo UIs or OSS Grafana) |
| In-repo manifests | ✅ ArgoCD app + values live here (unlike the microservices, whose deploy chart lives in the gitops-config repo) |
| Blast radius | ✅ an admin UI behind IAP; no other platform component consumes its Service |

## Converting the next backend (roadmap + checklist)

Each backend is an independent increment: make it serve TLS from a
cert-manager cert, then add its `BackendTLSPolicy` + HTTPS `HealthCheckPolicy`
pair (and trust-ConfigMap namespace) to `09-gateway.sh`/`08.7-backend-tls.sh`.
Known per-backend state:

| Backend | TLS mechanism | Blocker / note |
|---|---|---|
| **Headlamp** | native flags | ✅ **done (stage 1)** |
| **ArgoCD** | native — argocd-server watches the `argocd-server-tls` Secret and serves TLS when not `--insecure` | ⚠️ **all four CI engines'** deploy stages call the `argocd` CLI with `--plaintext` on `:80` ([`vars/microservicesDeploy.groovy`](../vars/microservicesDeploy.groovy), [`tekton/tasks/gitops-deploy.yaml`](../tekton/tasks/gitops-deploy.yaml), the Argo `WorkflowTemplate`, the rendered GHA workflow) — every caller must move to TLS (+ CA trust or `--insecure`) *first*, atomically with the server flip |
| **pgAdmin** | container env `PGADMIN_ENABLE_TLS` + certs mounted as `/certs/server.cert`/`server.key` | key names differ from cert-manager's (subPath remap); probe scheme + `service.targetPort` wiring through the runix subchart; values must thread through the `platform-postgres` app-of-apps |
| **Jenkins** | chart `controller.httpsKeyStore.*` + cert-manager `keystores.jks` (JKS + password Secret) | probes move to the plain-HTTP `httpPort` (8081); the WebSocket build agents dial the controller Service — they must trust the internal CA or stay on an internal plain port; highest blast radius |
| **Grafana (OSS)** | `grafana.ini` `server.protocol=https` + mounted cert | oss-mode-only (doubly conditional); values thread through the `observability-oss` app-of-apps |
| **microservices gateway (JHipster)** | Spring Boot `server.ssl.*` + cert-manager `keystores.pkcs12` | **cross-repo** — the deploy chart lives in `jenkins-2026-gitops-config`; also interacts with Argo Rollouts canary routes and every engine's smoke test URL |
| **faro receiver (otel-collector)** | OTLP/faro receiver `tls` block + mounted cert | health check is already TCP (protocol-agnostic); config threads through `03-observability.sh`'s collector values |

## Lifecycle

- **Enable**: set the flag (or export the env var) and **re-run `Day1`**
  ([applying changes = re-run, not Decom+Day1](../CLAUDE.md)). Note the
  per-engine `Day2.redeploy.*` workflows do *not* run `08.5`/`08.7`, so a flag
  flip needs the full `Day1` (or running `08.5` + `08.7` + `09` locally).
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

## Verifying it

```bash
kubectl get application cert-manager -n argocd                  # Synced/Healthy
kubectl get clusterissuer                                       # both Ready
kubectl get certificate -A                                      # CA + headlamp-tls Ready
kubectl get backendtlspolicy,healthcheckpolicy -n headlamp      # policy pair present
kubectl -n headlamp get cm jenkins-2026-backend-tls-ca -o jsonpath='{.data.ca\.crt}' | head -1
# The pod side: headlamp now speaks TLS on 4466
kubectl -n headlamp exec deploy/headlamp -- wget -q --no-check-certificate -O- https://localhost:4466/ >/dev/null && echo TLS-OK
# The LB side: the public host must still answer (IAP first, then the re-encrypted hop)
curl -sSI https://headlamp.<baseDomain> | head -3
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
