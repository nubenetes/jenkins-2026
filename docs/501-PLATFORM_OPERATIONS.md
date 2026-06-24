[← Previous: 403. Tekton](./403-TEKTON.md) | [🏠 Home](../README.md) | [→ Next: 502. Microservices GitOps](./502-MICROSERVICES_GITOPS.md)

---

# 501. Platform Operations

## ArgoCD Inventory (GitOps)

The deployment lifecycle is managed by **ArgoCD**. Application manifests are stored in [`nubenetes/jenkins-2026-gitops-config/argocd/`](https://github.com/nubenetes/jenkins-2026-gitops-config/tree/main/argocd) and applied to the cluster by `scripts/08.5-argocd.sh`. Jenkins CI writes image tags into that repo; ArgoCD detects the change and reconciles the cluster.

### Projects & Applications

| Resource | Type | Source repo | Source path | Target namespace | Health |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `microservices` | `AppProject` | — | — | `microservices` | — |
| `microservices` | `ApplicationSet` | `jenkins-2026-gitops-config` | `helm/microservices/` | (generates one App) | — |
| `microservices-stable` | `Application` | `jenkins-2026-gitops-config` | `helm/microservices/` + `values-stable.yaml` | `microservices` | Synced |
| `headlamp` | `Application` | `jenkins-2026-gitops-config` | `helm/headlamp/values.yaml` | `headlamp` | Healthy |
| `pgadmin` | `Application` | `jenkins-2026-gitops-config` | `helm/pgadmin/` | `pgadmin` | Healthy |
| `cnpg-operator` | `Application` | `cloudnative-pg` chart | `https://cloudnative-pg.github.io/charts` | `cnpg-system` | Healthy |
| `external-secrets` | `Application` | `external-secrets` chart | `https://charts.external-secrets.io` | `external-secrets` | Healthy |

### Security & Integration

- **Jenkins Integration**: A dedicated `jenkins` account is created in ArgoCD with a scoped **API Token**. This token is stored in the `jenkins-credentials` Secret and used by the `argocd` CLI inside pipeline agents to trigger `argocd app sync --wait`.
- **Auto-Sync**: All Applications are configured with `selfHeal: true` and `prune: true`.
- **Rollout Waiting**: After pushing a new tag to the gitops-config repo, the Jenkins pipeline calls `argocd app wait --health --timeout 300` before running smoke tests.

## Telemetry Verification & Simulation

### 1. Continuous Traffic Simulation (GitHub Actions)

Use the **[`Day2.traffic.01 Continuous Traffic Simulation`](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.01-k6.yml)** workflow:
- **Duration**: Default 15 minutes (configurable).
- **Purpose**: Simulates real-world user traffic from outside the cluster, hitting the GKE Gateway and triggering end-to-end traces.

The simulation reads the OTLP endpoint, auth and Grafana URL straight from the
in-cluster `grafana-cloud-credentials` Secret (provisioned by `Day1.cluster.01`), so no
extra GitHub secrets are needed — just run it against a live grafana-cloud
deployment.

### 2. On-Demand Smoke Test (Jenkins)

Trigger the **`microservices-k6-smoke`** job from the Jenkins UI. See [301. Observability](./301-OBSERVABILITY.md) for details on what it measures.

### 3. How to Verify Correlation in Grafana

Once traffic is running, go to your Grafana Cloud instance:
- **Metrics to Logs**: Open the **Microservices Overview** dashboard. Click on any metric spike and use the **"Show Logs"** split-view.
- **Logs to Traces**: In **Explore (Loki)**, look for logs containing `trace_id`. Grafana will show a "Tempo" link next to the `trace_id`.
- **End-to-End Traces**: In **Explore (Tempo)**, search for `service.name="gateway"` to see the full request path.

## Platform QA, Chaos & Compliance Validation

### 1. Automated Compliance Validation Gate

```bash
./test/validation_gate.sh
```

This script lints and dry-runs all platform resources (WIF, Karpenter, Gateway API, RBAC policies, VPA limits) against the target API schema.

### 2. Platform Verification & Stress-Test Playbooks

#### Scenario A: In-Place Resize Verification

Prove that dynamic build agents scale up their container resources dynamically without terminating or changing the Pod UID.

1. **Trigger Workload**: Run a dynamic microservice build job in Jenkins.
2. **Retrieve the Pod ID**: `kubectl get pods -n jenkins -l role=jenkins-agent`
3. **Trigger Resource Upscale**:
   ```bash
   kubectl patch pod <agent-pod-name> -n jenkins --type=json -p='[
     {"op": "replace", "path": "/spec/containers/0/resources/limits/cpu", "value": "3"},
     {"op": "replace", "path": "/spec/containers/0/resources/limits/memory", "value": "4Gi"}
   ]'
   ```
4. **Monitor the Resize Lifecycle**:
   ```bash
   kubectl get pod <agent-pod-name> -n jenkins -w -o jsonpath='{.status.resize}{"\t"}{.status.containerStatuses[0].resources}{"\n"}'
   ```
   Status transitions: `Resize: Proposed` → `Resize: InProgress` → `Resize: Succeeded` without the pod restarting.

#### Scenario B: Karpenter Elasticity & Spot Provisioning

1. **Deploy a Burst Load**: Schedule 50 parallel sleep pods targeted to the agent node group.
2. **Watch Node Allocation**: `kubectl get nodes -l role=jenkins-agent -o custom-columns=NAME:.metadata.name,CAPACITY:.metadata.labels.karpenter\.sh/capacity-type -w`
3. **Trigger Scale Down**: `kubectl scale deployment k6-burst-test -n jenkins --replicas=0`
4. **Verify Consolidation**: `kubectl get events --field-selector reason=ScaleDown -n kube-system`

#### Scenario C: Constrained Impersonation (Zero-Trust RBAC)

```bash
# Test Developer Impersonation (Allowed)
kubectl auth can-i create deployments -n microservices \
  --as=system:serviceaccount:headlamp:headlamp-service-account \
  --as-group=developer-group
# Output: yes

# Test Cluster-wide Escalation (Denied)
kubectl auth can-i get secrets --all-namespaces \
  --as=system:serviceaccount:headlamp:headlamp-service-account \
  --as-group=developer-group
# Output: no
```

#### Scenario D: CloudNative-PG Operator HA Failover

1. **Verify HA Replication**: `kubectl get cluster postgres-gateway -n microservices -o yaml`
2. **Simulate Primary Node Failover**:
   ```bash
   # Find the current primary
   kubectl get cluster postgres-gateway -n microservices -o jsonpath='{.status.currentPrimary}'
   # Delete the primary pod to simulate hard crash
   kubectl delete pod <current-primary-pod> -n microservices --grace-period=0 --force
   # Watch the cluster recovery
   kubectl get pod -n microservices -l cnpg.io/cluster=postgres-gateway -w
   ```
   Within seconds, CNPG promotes a standby to Primary. The deleted pod is automatically rescheduled as a standby replica.

## Golden Path IDP Modernizations (K8s v1.35/v1.36 & Karpenter)

The repository has been refactored to serve as a **Golden Path Internal Developer Platform (IDP)** utilizing Kubernetes v1.35/v1.36 features, Karpenter autoscaling, zero-trust security, and decoupled GitOps patterns.

### 1. Kubernetes v1.35/v1.36 Compliance
* **In-Place Pod Vertical Scaling (GA in v1.35)**: Jenkins ephemeral agent pod templates are defined with explicit `resizePolicy` parameters (`NotRequired` for CPU and Memory), allowing active Maven or Node build containers to scale resource requests/limits dynamically without restarting the pod.
* **Safe JVM Resource Resizing Floors**: Configured `VerticalPodAutoscaler` (VPA) rules for JVM microservices to enforce `minAllowed` memory thresholds (`512Mi`).
* **Workload-Aware / Gang Scheduling (v1.36)**: Integrated `PodGroup` scheduling resources (`parallel-smoke-tests`) to prevent resource starvation deadlocks during heavy concurrent microservice testing workflows.
* **UI/UX Constrained Impersonation**: Implemented K8s v1.36 `ConstrainedImpersonation` policies in Headlamp UI roles. This allows the Headlamp UI ServiceAccount to impersonate specific target user groups without requiring global cluster-admin role escalation permissions.

### 2. Elastic Karpenter Autoscaling (v1.0+)
* **GCPNodeClass**: Configures GKE machine parameters, 100 GB `pd-balanced` boot disks, and links Workload Identity node service accounts.
* **NodePool**: Manages Spot capacity-types, targeting compute families (`c2`, `n2`, `e2`, `c3`) and injecting taints (`jenkins-agent=true:NoSchedule`) so only build agents land on elastic spot pools.
* **Disruption Budgets**: Configured to restrict consolidations during core business hours (Mon-Fri) to safeguard long-running master build pipelines while allowing aggressive cost cutting at night.
* **Autoscaler Isolation**: Standard GKE nodes and Karpenter node pools are strictly isolated — preventing scheduling/autoscaling race conditions.

### 3. Zero-Trust Security & Workload Identity
* **Workload Identity Federation**: All static JSON Service Account keys are removed. Both external CI engines (GitHub Actions) and in-cluster workloads assume GCP IAM Roles dynamically via OIDC.
* **GKE Gateway API + BackendTLSPolicy**: Traffic between the Gateway load balancer and backend pods (Jenkins/Headlamp) is encrypted and validated using `BackendTLSPolicy` targets.
* **GKE Dataplane V2 (Cilium/eBPF) — NetworkPolicy *enforcement***: the cluster runs Dataplane V2 (`datapath_provider = ADVANCED_DATAPATH` in [`terraform/gke`](../terraform/gke/main.tf)). This is what makes the policies below *actually enforce* — without it (and without the legacy Calico addon, mutually exclusive with it) GKE accepts `NetworkPolicy` objects but silently ignores them.
* **Zero-Trust Network Policies** ([`infrastructure/networkpolicies*.yaml`](../infrastructure/)): every namespace egresses to CoreDNS by default-deny. Sensitive namespaces (**observability, microservices, postgres, pgadmin**, and **jenkins** in jenkins mode) run `default-deny` + curated allowlists. Workload UI/CI namespaces (**argocd, headlamp, tekton-ci**) get a **deny-ingress / allow-egress baseline**: each namespace's entry port stays reachable (Gateway, CI sync, port-forward, CLI) while internal components are intra-namespace only; the outbound-only pipeline pods get no ingress. Admission-webhook operator namespaces (**tekton-pipelines, cnpg-system, external-secrets, pipelines-as-code**) are intentionally left open — a `deny-ingress` there would block the API server's webhook calls unless the GKE control-plane CIDR is allowlisted (fragile, cluster-specific). The observability policy also allows the GKE L7 health-check/proxy ranges (`130.211.0.0/22`, `35.191.0.0/16`) so the Grafana backend stays healthy under enforcement.
* **Pod-to-pod WireGuard encryption**: `in_transit_encryption_config = IN_TRANSIT_ENCRYPTION_INTER_NODE_TRANSPARENT` has Dataplane V2's managed Cilium transparently encrypt **inter-node** pod traffic (sidecar-free, no service mesh, no app changes). This is *transport* encryption, not identity-based mutual auth (no per-workload mTLS identity/authZ like Istio/Linkerd) — it closes the plaintext-on-the-wire gap lightly. Same-node pod traffic never hits the wire, so it is not encrypted.
* **Secret Management via External Secrets Operator (ESO)**: Connects GKE Workload Identity with Google Secret Manager. ESO automatically pulls and syncs secret structures to namespaced secrets dynamically.

> ⚠️ Dataplane V2 + the WireGuard config are **immutable** cluster fields — applied by recreating the cluster (`Decom.cluster.01` → `Day1.cluster.01`), not an in-place re-run. Enabling enforcement activates the NetworkPolicies for the first time, so validate connectivity (OSS stack, CNPG metrics, microservices, gateway, ArgoCD sync, Tekton triggers) on the fresh cluster.

### 4. GitOps Separation of Concerns
All infrastructural manifests (`karpenter/`, `gateway/`, `headlamp/`, `scheduling/`) are decoupled from CI pipeline definitions and placed inside the [`infrastructure/`](../infrastructure/) directory for full reconciliation via Argo CD.

### 5. Build Performance & High Availability Caching
* **Jenkins Agent Caching**: Java (Maven `/root/.m2`) and Node (npm `/root/.npm`) containers in pipeline agent templates mount hostPath volumes (`/tmp/jenkins-maven-cache` and `/tmp/jenkins-npm-cache`). Sharing a fast local node directory avoids ReadWriteOnce volume mounting locks while reducing typical compilation times from 5-10 minutes to under 1 minute.
* **Database HA & Storage Lifecycles**: Distributes CloudNative-PG replicas across distinct physical zones using zonal anti-affinity constraints. GCS lifecycle rules automatically transition backups to `NEARLINE` storage class after 3 days and delete them after 7 days.

### 6. Progressive Delivery (Argo Rollouts + Gateway API)

Canary / blue-green delivery, **sidecar-free**, reusing the existing GKE Gateway API ingress (no service mesh):

* **Controller (installed)**: [`argocd/argo-rollouts-app.yaml`](../argocd/argo-rollouts-app.yaml) GitOps-installs the Argo Rollouts controller (Helm chart, pinned) with the **Gateway API traffic-router plugin** (`argoproj-labs/gatewayAPI`) configured via `controller.trafficRouterPlugins`. [`infrastructure/argo-rollouts-gatewayapi-rbac.yaml`](../infrastructure/argo-rollouts-gatewayapi-rbac.yaml) grants the controller `update/patch` on `gateway.networking.k8s.io` HTTPRoutes (the chart default lacks it). Applied by `scripts/08.5-argocd.sh`. The read-only Rollouts dashboard is enabled (cluster-internal).
* **How the canary shifts traffic**: a `Rollout` (replacing the `gateway` `Deployment`) with `stableService: gateway` + `canaryService: gateway-canary` and `trafficRouting.plugins."argoproj-labs/gatewayAPI"` pointing at the `microservices` HTTPRoute. The plugin rewrites the HTTPRoute `backendRefs` **weights** between the stable and canary Services through the canary steps (e.g. 20% → 50% → 100% with pauses). No Envoy, no sidecars.

**Remaining steps (cross-repo — the controller above is the in-cluster foundation):**

| Step | Where | Change |
|---|---|---|
| **B2** | this repo — [`scripts/09-gateway.sh`](../scripts/09-gateway.sh) | microservices HTTPRoute gets two `backendRefs` (`gateway` weight 100 + `gateway-canary` weight 0). **Land WITH B3** — adding the canary backendRef before its Service exists causes `BackendNotFound`. |
| **B3** | **microservices GitOps repo** (`helm/microservices`, external) | convert the `gateway` `Deployment` → `Rollout` (canary strategy + steps + the `gatewayAPI` plugin referencing the `microservices` HTTPRoute) and add the `gateway-canary` `Service`. |
| **B4** | this repo — [`tekton/tasks/gitops-deploy.yaml`](../tekton/tasks/gitops-deploy.yaml) | after the ArgoCD sync, wait on the Rollout (`kubectl argo rollouts status gateway -n microservices`) instead of `kubectl rollout status`. |

Activation order: merge the controller → `Day1` → apply B3 in the GitOps repo → land B2 + B4 here (coordinated with B3). A push to `gateway` then rolls out as a weighted canary visible in the Rollouts dashboard.

## Headlamp (Cluster Management UI)

[Headlamp](https://headlamp.dev/) gives a web UI for the GKE cluster itself (pods, deployments, logs, exec, RBAC, etc.), deployed into the `headlamp` namespace via [`helm/headlamp/values.yaml`](../helm/headlamp/values.yaml).

**Access model**: Users access the dashboard at `https://headlamp.<baseDomain>` (gated by IAP), click "Sign in with Google", and log in. Headlamp backend verifies the user's Google `id_token` to authenticate their browser session, but interacts with the GKE API server using the pod's mounted `headlamp` ServiceAccount token.

### One-time Setup: Google OAuth Client

Create a Google OAuth 2.0 **Web application** client:

1. [Google Cloud Console](https://console.cloud.google.com/) → **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID** → Application type **Web application**.
2. **Authorized redirect URIs**: add `http://localhost:8080/oidc-callback` and, if gateway is configured, `https://headlamp.<baseDomain>/oidc-callback`.
3. Note the **Client ID** and **Client secret**. Pass as `HEADLAMP_OIDC_CLIENT_ID` / `HEADLAMP_OIDC_CLIENT_SECRET` secrets.

### Adding Your Identity

Your Google account email is **never committed to this repo** — it's supplied via the `HEADLAMP_ADMIN_EMAILS` secret (comma-separated for multiple people):

```bash
gh secret set HEADLAMP_ADMIN_EMAILS --body "you@gmail.com,colleague@gmail.com"
```

Then (re-)run **Day1.cluster.01 GKE provision** to add the `roles/iap.httpsResourceAccessor` IAM binding via `terraform/gke`.

### Accessing the UI

- **Public URL (IAP-secured):** `https://headlamp.jenkins2026.nubenetes.com`
- **Local Port-Forward:**
  ```bash
  kubectl -n headlamp port-forward svc/headlamp 8080:80
  ```
  Then open <http://localhost:8080>.

#### Option A: Log in with Your Google ID (Recommended for GKE)
```bash
gcloud auth print-access-token
```
Copy the `ya29.` token, select **Token** login in Headlamp, paste, and click **Sign In**. GKE will authenticate you as your Google account.

#### Option B: Log in with a ServiceAccount Token
```bash
kubectl create token headlamp -n headlamp
```
Copy the token, select **Token** login in Headlamp, paste, and click **Sign In** (grants cluster-admin access).

## Public Access (GKE Gateway API + IAP)

Jenkins, Microservices, Headlamp, and pgAdmin can all be exposed on the public internet through a single **GKE Gateway** (`gatewayClassName: gke-l7-global-external-managed`) — one global external HTTPS load balancer, one Google-managed wildcard certificate, and one `HTTPRoute` per app:

| App | URL | Identity-Aware Proxy |
|---|---|---|
| Jenkins | `https://jenkins.<baseDomain>` | yes |
| Microservices | `https://microservices.<baseDomain>` | no (public demo app) |
| Headlamp | `https://headlamp.<baseDomain>` | yes |
| pgAdmin | `https://pgadmin.<baseDomain>` | yes |
| Grafana | `https://grafana.<baseDomain>` | yes (only when `observability.mode=oss`) |

`<baseDomain>` is `gateway.baseDomain` in `config/config.yaml` — `jenkins2026.nubenetes.com` by default.

**This whole feature is opt-in**: set `JENKINS2026_BASE_DOMAIN=""` to disable it. `scripts/09-gateway.sh` is also a no-op on `platform.target` other than `gke`.

### Authentication & Authorization Matrix

| Application | Edge-Level Authentication (GCP IAP) | App-Level Authentication | Authorization |
|---|---|---|---|
| **Jenkins** | Yes (Google IAP OAuth) | Google OIDC **or** local `admin` basic auth | RBAS: Default Google login = read-only; Admin email = full admin |
| **ArgoCD** | Yes (Google IAP OAuth) | Google OIDC (via Dex) **or** local `admin` secret | ArgoCD RBAC: Default OIDC = readonly; Admin email = role:admin |
| **Headlamp** | Yes (Google IAP OAuth) | Token Login (GKE OAuth access token or ServiceAccount token) | Kubernetes RBAC via GCP Identity mapping |
| **pgAdmin** | Yes (Google IAP OAuth) | Webserver Auth (trusts `X-Goog-Authenticated-User-Email` header) | Automated `.pgpass` injection for zero-password database login |
| **Microservices** | No (Public Demo App) | JWT Token verification | Spring Security Roles (`ROLE_USER`, `ROLE_ADMIN`) |

### One-time Setup

1. **Run the "Day0.infra.01 Gateway bootstrap" workflow** to create a global static IP and a Google-managed wildcard certificate for `<baseDomain>` and `*.<baseDomain>`.

2. **Add the two DNS records** it prints:
   - A wildcard **A** record: host `*.jenkins2026`, value the static IP.
   - The **CNAME** record from the workflow's "DNS authorization record" output.

3. **Create the IAP OAuth client by hand** (the Terraform resources for this are deprecated as of July 2025). In the [GCP Console](https://console.cloud.google.com/): **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID** → Application type **Web application**.

   **Authorized redirect URI**:
   ```
   https://iap.googleapis.com/v1/oauth/clientIds/<client ID>:handleRedirect
   ```

   ```bash
   gh secret set IAP_OAUTH_CLIENT_ID     --body "<client ID>"
   gh secret set IAP_OAUTH_CLIENT_SECRET --body "<client secret>"
   ```

4. **IAP access control** reuses `HEADLAMP_ADMIN_EMAILS`: each listed email is granted `roles/iap.httpsResourceAccessor` via `terraform/gke`.

### Troubleshooting: Load Balancer Propagation Delay

After initial provisioning, the public URLs may not be immediately reachable. This is normal — GFE edge proxies globally must receive and propagate routing tables, SSL policies, and URL mappings. This process typically takes **5 to 10 minutes**.

To verify the issue is just propagation delay:
```bash
# Verify DNS resolution
ping -c 1 jenkins.jenkins2026.nubenetes.com

# Verify certificate state
gcloud certificate-manager certificates describe jenkins-2026-cert \
  --format="yaml(managed.state,managed.authorizationAttemptInfo)"

# Verify backend health
gcloud compute backend-services get-health gkegw1-y6i2-jenkins-jenkins-8080-p2ivomotuf95 --global
```

---

[← Previous: 403. Tekton](./403-TEKTON.md) | [🏠 Home](../README.md) | [→ Next: 502. Microservices GitOps](./502-MICROSERVICES_GITOPS.md)

---

*501. Platform Operations — jenkins-2026*
