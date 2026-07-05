[← Previous: 405. Argo Workflows](./405-ARGO_WORKFLOWS.md) | [🏠 Home](../README.md) | [→ Next: 502. Microservices GitOps](./502-MICROSERVICES_GITOPS.md)

---

# 501. Platform Operations

## Understanding platform operations (newcomers → specialists)

Everything around the CI engine — *how apps get deployed, how the world reaches them, how the cluster stays safe, and how releases roll out* — is **declarative and reconciled**. There is no "click to deploy": **Git is the input**, controllers do the work. Read this once and the rest of the page is "which controller owns which plane".

<details>
<summary>📊 Platform planes (mindmap)</summary>

```mermaid
mindmap
  root((Platform planes))
    Delivery
      ArgoCD GitOps
      app-of-apps
      selfHeal + prune
    Ingress
      one GKE Gateway
      HTTPRoute per app
      Google IAP
      wildcard cert
    Security
      Dataplane V2 netpols
      WireGuard inter-node
      Workload Identity
      ESO secrets
    Progressive delivery
      Argo Rollouts
      canary weights
      AnalysisRun gate
    Resilience
      CNPG HA failover
      NAP Spot ComputeClass
      in-place resize
```

</details>

<details>
<summary>🟢 For newcomers — the five platform planes</summary>

The platform splits into five concerns, each run by its own controller — you rarely touch them by hand:

| Plane | What it does | Owned by |
|---|---|---|
| **Delivery** | Turns Git into running workloads. You bump an image tag in the GitOps repo; ArgoCD notices and reconciles the cluster. | ArgoCD (`selfHeal` + `prune`) |
| **Ingress** | Puts apps on the public internet — **one** global HTTPS load balancer, **one** wildcard cert, one `HTTPRoute` per app. | GKE Gateway API |
| **Identity at the edge** | Before a request reaches Jenkins/Headlamp/pgAdmin, **Google IAP** checks you're an allowed account. (The demo `microservices` host is public — no IAP.) | Identity-Aware Proxy |
| **Security inside** | Every namespace is default-deny; only listed traffic flows. Pod-to-pod traffic between nodes is encrypted. No static cloud keys anywhere. | Dataplane V2 NetworkPolicies + WireGuard + Workload Identity |
| **Safe releases** | Ship a new version to 20% of users first, watch it, widen only if healthy. | Argo Rollouts (canary) |

So a deploy is: *CI writes a tag → ArgoCD syncs → the new pod comes up behind the Gateway → IAP gates who can reach it → NetworkPolicies gate what it can talk to → (optionally) Argo Rollouts shifts traffic to it gradually*.
</details>

<details>
<summary>🔴 For specialists — how each plane is wired here</summary>

- **Delivery:** ArgoCD (auto-tracking the latest **3.4.x** via a daily CronJob watcher) runs single `Application`s (microservices `ApplicationSet`→`microservices-stable`, `headlamp`, `external-secrets`, `jenkins`, `argo-rollouts`, and `platform-config` — the engine-aware static platform RBAC) plus **app-of-apps** (`platform-postgres` → CNPG operator + pgAdmin, `observability-oss`, and the active CI engine's — `tekton` / `githubactions` / `argoworkflows`). The four CI engines (`ci.engine`: **Jenkins** default · **Tekton** · **GitHub Actions (ARC)** · **Argo Workflows**) are mutually exclusive; a scoped ArgoCD account + API token lets the pipeline `argocd app sync --wait`. All apps `selfHeal: true` + `prune: true`.
- **Ingress:** one `Gateway` (`gatewayClassName: gke-l7-global-external-managed`) = one global external HTTPS LB + one Google-managed wildcard cert + one `HTTPRoute` per app; TLS terminates at the LB — the LB→pod hop is plain HTTP (no backend re-encryption; see §3 Zero-Trust). Opt-in via `gateway.baseDomain` (empty disables it; `09-gateway.sh` no-ops off-GKE).
- **Edge identity:** IAP gates `jenkins`/`headlamp`/`pgadmin`/`grafana(oss)`; access = the emails granted `roles/iap.httpsResourceAccessor` (reuses `HEADLAMP_ADMIN_EMAILS`). The `microservices` host is intentionally public.
- **Security inside:** Dataplane V2 (`datapath_provider = ADVANCED_DATAPATH`) is what makes NetworkPolicies *enforce*; sensitive namespaces are `default-deny` + curated allowlists (see the matrix below). `in_transit_encryption_config` adds transparent WireGuard inter-node pod encryption (transport, not mTLS identity). Workload Identity Federation removes all static SA JSON keys; ESO syncs Secret Manager → namespaced Secrets. Dataplane V2 + WireGuard are **immutable** cluster fields (changing them recreates the cluster).
- **Progressive delivery:** the `argo-rollouts` controller + the `argoproj-labs/gatewayAPI` traffic-router plugin patch `HTTPRoute` `backendRefs[].weight` between the stable and `*-canary` Services — sidecar-free, no mesh. An `AnalysisRun` can gate promotion on Prometheus span-metrics (5xx / p95) and auto-rollback.
- **Resilience:** CNPG HA promotes a standby on primary loss; GKE Node Auto-Provisioning auto-creates Spot pools (ComputeClass `ci-spot`, taints `cloud.google.com/compute-class=ci-spot:NoSchedule` + `cloud.google.com/gke-spot=true:NoSchedule`) that scale to zero; in-place vertical resize grows agent containers without pod restarts.
</details>

## ArgoCD Inventory (GitOps)

The deployment lifecycle is managed by **ArgoCD**. Application manifests are stored in this repo's [`argocd/`](../argocd/) directory and applied to the cluster by [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh); the [`nubenetes/jenkins-2026-gitops-config`](https://github.com/nubenetes/jenkins-2026-gitops-config) repo holds the microservices Helm chart (`helm/microservices/`) that the `ApplicationSet` deploys. Jenkins CI writes image tags into that repo; ArgoCD detects the change and reconciles the cluster.

### Projects & Applications

| Resource | Type | Source repo | Source path | Target namespace | Health |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `microservices` | `AppProject` | — | — | `microservices` | — |
| `microservices` | `ApplicationSet` | `jenkins-2026-gitops-config` | `helm/microservices/` | (generates one App) | — |
| `microservices-stable` | `Application` | `jenkins-2026-gitops-config` | `helm/microservices/` + `values-stable.yaml` | `microservices` | Synced |
| `headlamp` | `Application` | official `headlamp` chart 0.43.0 + `$values` from `jenkins-2026` | `helm/headlamp/values.yaml` | `headlamp` | Healthy |
| `pgadmin` *(child of the `platform-postgres` app-of-apps)* | `Application` | `jenkins-2026` | `helm/pgadmin/` | `pgadmin` | Healthy |
| `cnpg-operator` *(child of the `platform-postgres` app-of-apps)* | `Application` | `cloudnative-pg` chart | `https://cloudnative-pg.github.io/charts` | `cnpg-system` | Healthy |
| `external-secrets` | `Application` | `external-secrets` chart | `https://charts.external-secrets.io` | `external-secrets` | Healthy |
| `jenkins` | `Application` | `jenkins` chart (pinned 5.9.29) | `https://charts.jenkins.io` | `jenkins` | Healthy *(when `ci.engine=jenkins`)* |
| `argo-rollouts` | `Application` | `argo-rollouts` chart (2.37.7) | `https://argoproj.github.io/argo-helm` | `argo-rollouts` | Healthy |
| `platform-config` | `Application` | `jenkins-2026` | `argocd/platform-config/` (local Helm chart) | `argocd` | Healthy |

> Plus the **app-of-apps** (`platform-postgres`, `observability-oss` when `observability.mode=oss`, and the active CI engine's — `tekton` / `githubactions` / `argoworkflows`, one per `ci.engine`; Jenkins uses the single `jenkins` `Application` above), each a small Helm chart whose children carry the actual workloads. See [`argocd/README.md`](../argocd/README.md).
>
> **Switching engines is exclusive:** each `scripts/04-<engine>.sh` retires the *other three* via the shared `retire_ci_engine` helper in [`scripts/lib/common.sh`](../scripts/lib/common.sh) — it deletes their ArgoCD `Application`s (parent app-of-apps + every child), then their namespaces (clearing any stuck GKE NEG finalizer so termination isn't blocked), so only one CI engine ever exists at a time.
>
> `platform-config` renders the local [`argocd/platform-config/`](../argocd/platform-config/) Helm chart — the engine-aware static platform **RBAC** (CI-engine SA `edit` bindings, pgAdmin secret-reader, the OTel-instrumentation `ClusterRole`), GitOps-owned since it moved out of `01-namespaces.sh` / `02-otel-operator.sh`; `ciEngine` / `developTrackEnabled` are substituted by `08.5-argocd.sh` so only the active engine's RBAC renders. NetworkPolicies + quotas deliberately stay script-applied (Dataplane V2 timing).
>
> Not an `Application`, but applied alongside them: [`argocd/argocd-version-patch-watcher.yaml`](../argocd/argocd-version-patch-watcher.yaml) — a daily `CronJob` in the `argocd` namespace that keeps ArgoCD auto-tracking the latest **3.4.x** patch (see [602 § version pinning](./602-VERSION_PINNING.md)).

<details>
<summary>📊 ArgoCD application inventory & app-of-apps tree</summary>

```mermaid
---
config:
  layout: elk
---
flowchart TB
  argocd[ArgoCD]:::root

  subgraph single["Single Applications"]
    direction TB
    appset["microservices<br/>ApplicationSet"] --> msstable[microservices-stable]
    appset -. "develop track on (optional)" .-> msdev["microservices-develop<br/>(lean tier)"]
    headlamp[headlamp]
    eso[external-secrets]
    jenkins["jenkins<br/>(ci.engine=jenkins)"]
    rollouts[argo-rollouts]
    pcfg["platform-config<br/>(engine-aware RBAC)"]
  end

  subgraph aoa["App-of-apps (each a small Helm chart)"]
    direction TB
    pp["platform-postgres"] --> ppc["CNPG operator<br/>+ pgAdmin"]
    oss["observability-oss<br/>(mode=oss)"] --> ossc["kube-prometheus-stack<br/>Loki · Tempo · dashboards"]
    tk["tekton<br/>(ci.engine=tekton)"] --> tkc["pipelines · triggers · dashboard<br/>pruner · chains · pac"]
    gha["githubactions<br/>(ci.engine=githubactions)"] --> ghac["ARC controller<br/>+ runner scale set"]
    awf["argoworkflows<br/>(ci.engine=argoworkflows)"] --> awfc["Workflows controller+server<br/>· Argo Events · pac"]
  end

  argocd --> appset & headlamp & eso & jenkins & rollouts & pcfg
  argocd --> pp & oss & tk & gha & awf
  watcher[[daily CronJob<br/>auto-track 3.4.x]] -.-> argocd
  classDef root fill:#eef,stroke:#66c;
```

</details>

**Reading it —** ArgoCD owns two kinds of children. **Single `Application`s** map one chart/path to one namespace (the `microservices` `ApplicationSet` is the exception — it *generates* `microservices-stable`, and a `microservices-develop` when the develop track is on). **App-of-apps** are small Helm charts whose only job is to render a *family* of correlated children, so repo/branch/version flow down in one place — used where components must move together (Postgres operator+UI, the OSS stack, and each CI engine's control plane). The dashed watcher keeps ArgoCD itself on the latest 3.4.x patch. Engine/mode flags gate the rest: `observability-oss` on `observability.mode=oss`, and exactly one CI engine on `ci.engine` — `jenkins` (single `Application`) / `tekton` / `githubactions` / `argoworkflows` (app-of-apps).

### Security & Integration

- **CI Integration**: A dedicated ArgoCD account with a scoped **API Token** is created for the active CI engine (stored in that engine's credentials Secret — `jenkins-credentials`, `tekton-argocd`, `arc-argocd`, or `argoworkflows-argocd`) and used by the `argocd` CLI inside pipeline agents to trigger `argocd app sync --wait`.
- **Auto-Sync**: All Applications are configured with `selfHeal: true` and `prune: true`.
- **Rollout Waiting**: After pushing a new tag to the gitops-config repo, the pipeline waits for the app to converge with `argocd app wait microservices-<env> --sync --health --timeout 300` before running smoke tests (Jenkins and Tekton block on it; the GHA workflow waits best-effort with a trailing `|| true`).

## Telemetry Verification & Simulation

> **Full k6 reference:** the runners below share one parametrizable script — **profiles** (smoke/load/stress/soak/spike/breakpoint), the `K6SIM_*` contract, `stable`-vs-`develop` targeting, and the layered result analysis are all documented in **[302 · k6 Traffic, Load & Observability Testing](./302-K6_LOAD_TESTING.md)**. The summaries here are the platform-ops view.

### 1. Continuous Traffic Simulation (GitHub Actions)

Use the **[`Day2.traffic.01 Continuous k6 simulation`](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.01-k6.yml)** workflow:
- **Profile/shape**: `profile` input (default `smoke`) + overrides (`vus`, `duration`, `stages`, `rps`, thresholds) — a real **load/stress/spike** run, not just smoke. See [302 § GitHub Actions](./302-K6_LOAD_TESTING.md#github-actions).
- **Tier**: `env_name` input — `stable` (public `microservices.<domain>` host) or `develop` (public `microservices-develop.<domain>` host).
- **Purpose**: Simulates real-world user traffic from outside the cluster, hitting the GKE Gateway and triggering end-to-end traces.

The simulation auto-detects the active observability mode from whichever in-cluster
credentials Secret exists (`grafana-cloud-credentials` / `azure-monitor-credentials` /
`aws-managed-credentials`, provisioned by `Day1.cluster.01`) and routes k6's OTLP
accordingly — straight to the Grafana Cloud gateway in grafana-cloud mode, via the
in-cluster `otel-collector-gateway` in oss/managed modes — so no extra GitHub secrets are
needed and it works on any live deployment. A `preset` input (plus `run_all_presets` for a
one-click pass over every committed preset) loads configs from
[`jenkins/pipelines/k6/presets/`](../jenkins/pipelines/k6/presets/).

### 2. On-Demand Smoke Test (Jenkins)

Trigger the **`microservices-k6-smoke`** job (or **`microservices-k6-smoke-develop`** for the develop tier) from the Jenkins UI via **Build with Parameters** — pick the profile/VUs/duration/thresholds, or just Build for the default smoke. See [302 § Jenkins](./302-K6_LOAD_TESTING.md#jenkins) and [301. Observability](./301-OBSERVABILITY.md) for what it measures.

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

This script lints and dry-runs all platform resources (WIF, Node Auto-Provisioning ComputeClass, Gateway API, RBAC policies, VPA limits) against the target API schema.

### 2. Platform Verification & Stress-Test Playbooks

#### Scenario A: In-Place Resize Verification

Prove that dynamic build agents scale up their container resources dynamically without terminating or changing the Pod UID.

1. **Trigger Workload**: Run a dynamic microservice build job in Jenkins.
2. **Retrieve the Pod ID**: `kubectl get pods -n jenkins -l jenkins=slave` (the Kubernetes-plugin label the real ephemeral agents carry; `role=jenkins-agent` only exists in the unused `jcasc-modern-agents.yaml` worked example).
3. **Trigger Resource Upscale**:
   ```bash
   kubectl patch pod <agent-pod-name> -n jenkins --type=json -p='[
     {"op": "replace", "path": "/spec/containers/0/resources/limits/cpu", "value": "3"},
     {"op": "replace", "path": "/spec/containers/0/resources/limits/memory", "value": "4Gi"}
   ]'
   ```
4. **Monitor the Resize Lifecycle**:
   ```bash
   kubectl get pod <agent-pod-name> -n jenkins -w -o jsonpath='{.status.conditions[?(@.type=="PodResizeInProgress")]}{"\t"}{.status.containerStatuses[0].resources}{"\n"}'
   ```
   Watch the `PodResizePending` → `PodResizeInProgress` conditions clear and `containerStatuses[0].resources` reflect the new limits — without the pod restarting. (K8s ≥1.33 GA moved resize status from the beta `.status.resize` field to these pod conditions, so on this 1.35 cluster the old `.status.resize` jsonpath prints nothing.)

#### Scenario B: Node Auto-Provisioning Elasticity & Spot Provisioning

1. **Deploy a Burst Load**: `kubectl create deployment burst-sleep -n jenkins --image=busybox --replicas=50 -- sleep 3600`, then patch its pod template with `nodeSelector: {cloud.google.com/compute-class: ci-spot}` plus the matching `ci-spot` / `gke-spot` `NoSchedule` tolerations so the 50 pods land on the `ci-spot` ComputeClass.
2. **Watch Node Allocation**: `kubectl get nodes -l cloud.google.com/compute-class=ci-spot -o custom-columns=NAME:.metadata.name,SPOT:.metadata.labels.cloud\.google\.com/gke-spot -w`
3. **Trigger Scale Down**: `kubectl scale deployment burst-sleep -n jenkins --replicas=0`
4. **Verify Consolidation**: `kubectl get events --field-selector reason=ScaleDown -n kube-system`

#### Scenario C: Constrained Impersonation (Zero-Trust RBAC) — *reference design*

> The `ImpersonationPolicy` + `developer-group` RoleBindings behind this scenario are a **reference design** — [`infrastructure/headlamp/ImpersonationPolicy.yaml`](../infrastructure/headlamp/ImpersonationPolicy.yaml) is schema-validated by `test/validation_gate.sh` but **not applied by Day1**, and no RoleBinding anywhere grants `developer-group` create-deployments in `microservices`. To reproduce on a real cluster, first `kubectl apply -f infrastructure/headlamp/ImpersonationPolicy.yaml` (fixing its subject to the chart-created SA `headlamp`) **plus** a RoleBinding granting `developer-group` `edit` in `microservices`.

```bash
# Test Developer Impersonation (Allowed)
kubectl auth can-i create deployments -n microservices \
  --as=system:serviceaccount:headlamp:headlamp \
  --as-group=developer-group
# Output: yes

# Test Cluster-wide Escalation (Denied)
kubectl auth can-i get secrets --all-namespaces \
  --as=system:serviceaccount:headlamp:headlamp \
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

## Golden Path IDP Modernizations (Node Auto-Provisioning & modern scheduling)

The repository has been refactored to serve as a **Golden Path Internal Developer Platform (IDP)** utilizing modern Kubernetes scheduling features, GKE Node Auto-Provisioning, zero-trust security, and decoupled GitOps patterns.

### 1. Modern Scheduling Compliance
* **In-Place Pod Vertical Scaling** *(live)*: Jenkins ephemeral agent pod templates are defined with explicit `resizePolicy` parameters (`NotRequired` for CPU and Memory) in [`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy), allowing active Maven or Node build containers to scale resource requests/limits dynamically without restarting the pod.
* **Safe JVM Resource Resizing Floors** *(reference manifest — not applied by Day1)*: [`infrastructure/scheduling/VPA.yaml`](../infrastructure/scheduling/VPA.yaml) defines `VerticalPodAutoscaler` (VPA) rules for JVM microservices with `minAllowed` memory floors (`512Mi`).
* **Workload-Aware / Gang Scheduling** *(reference manifest — not applied by Day1)*: [`infrastructure/scheduling/PodGroup.yaml`](../infrastructure/scheduling/PodGroup.yaml) defines `PodGroup` scheduling resources (`parallel-smoke-tests`) to prevent resource starvation deadlocks during heavy concurrent microservice testing workflows.
* **UI/UX Constrained Impersonation** *(reference manifest — not applied by Day1)*: [`infrastructure/headlamp/ImpersonationPolicy.yaml`](../infrastructure/headlamp/ImpersonationPolicy.yaml) defines `ConstrainedImpersonation` policies for Headlamp UI roles, letting the Headlamp UI ServiceAccount impersonate specific target user groups without global cluster-admin escalation.

> The three reference manifests above are schema-validated by [`test/validation_gate.sh`](../test/validation_gate.sh) but must be applied by hand — only the first (`resizePolicy`) bullet is live in the provision.

### 2. Elastic Node Auto-Provisioning (Spot ComputeClass)
* **Cluster-level NAP**: [`terraform/gke`](../terraform/gke/) enables a `cluster_autoscaling` block (`resource_limits` for cpu/memory + `auto_provisioning_defaults`: the dedicated node SA `jenkins-2026-nodes`, COS_CONTAINERD, Shielded VMs, auto-repair/upgrade, `pd-balanced`, `OPTIMIZE_UTILIZATION` profile), gated by the `enable_node_autoprovisioning` variable (default true).
* **Custom ComputeClass `ci-spot`**: [`infrastructure/compute-classes/ci-spot.yaml`](../infrastructure/compute-classes/ci-spot.yaml) sets `nodePoolAutoCreation.enabled: true` with `priorities` preferring **Spot** across families (`c3`, `n2`, `c2`, `e2`) then falling back to on-demand `e2`, `whenUnsatisfiable: ScaleUpAnyway`. GKE auto-applies the `compute-class=ci-spot` / `gke-spot=true` `NoSchedule` taints so only build agents (which carry the matching nodeSelector + tolerations) land on the elastic Spot pools.
* **Per-engine placement — `<engine>.runNodePool: static | ci-spot`.** Whether build pods target the **static pool** (robust, no NAP/Spot/quota dependency) or the **`ci-spot` ComputeClass** (elastic Spot) is a feature flag *per CI engine* (each of the four — Jenkins, Tekton, GitHub Actions/ARC, Argo Workflows — has its own knob, override `JENKINS2026_<ENGINE>_RUN_NODE_POOL`), because the engines differ in Spot-suitability, so their **defaults differ**: a **Jenkins** build is a single agent pod, so a preemption just restarts that one build (a fine Spot citizen → `ci-spot` opt-in is low-risk) — defaults `static`; a **GitHub Actions/ARC** runner is a single ephemeral pod that runs exactly one job then terminates, the textbook Spot workload → it **defaults `ci-spot`** (this engine is the NAP-Spot showcase); a **Tekton** PipelineRun (and likewise an **Argo Workflows** run) pins *all* its tasks/steps to one node via the shared RWO workspace PVC (Tekton's affinity assistant), so a preemption kills the whole run and a too-small/full node hangs it (→ `static`, both default there). Except for GitHub Actions/ARC, the defaults keep **CI off the `SSD_TOTAL_GB` quota** (no per-build PD) out of the box; flip an engine to `ci-spot` to opt into Spot. Jenkins reads the flag in [`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy) (via JCasC `RUN_NODE_POOL`); Tekton applies it as the `default-pod-template` (see [`docs/403`](403-TEKTON.md)); ARC/Argo Workflows set it on the runner/Workflow pod spec (see [`docs/404`](404-GITHUB_ACTIONS.md) / [`docs/405`](405-ARGO_WORKFLOWS.md)).
* **Autoscaler Isolation**: The static `jenkins-2026-pool` (long-lived platform) and the NAP-auto-created Spot pools are strictly isolated, so a NAP issue never blocks the core provision.
* **Spot preemption — trade-off & resilience (read before relying on it).** Spot VMs can be reclaimed by GCE with **~30s notice**, so a node running a CI agent can disappear *mid-build*. This is a deliberate, acceptable trade-off here because **CI is exactly the right workload for Spot**: builds are **ephemeral and idempotent** (re-running produces the same artifact) and **nothing on the critical platform path runs on Spot** — ArgoCD, the active CI engine's controllers (Jenkins / Tekton / ARC / Argo Workflows), observability and CNPG all stay on the static pool. The resilience design is layered:
  * **On-demand fallback** — the `ci-spot` ComputeClass falls back to on-demand `e2` (`whenUnsatisfiable: ScaleUpAnyway`), so a Spot **stock-out** never leaves a build Pending; it just runs on a regular node.
  * **Preemption ≠ stuck** — if a Spot node *is* reclaimed, GKE reschedules the agent Pod and NAP provisions a fresh node (Spot, or on-demand on stock-out); the affected build fails fast and is simply re-run (no manual cleanup).
  * **Escape hatch** — for **guaranteed, non-preemptible completion**, set the engine's `runNodePool: static` (the default for Jenkins/Tekton/Argo Workflows; GitHub Actions/ARC defaults to `ci-spot`, so flip it explicitly) so its agents schedule on the static pool — finer-grained than disabling NAP. To remove NAP cluster-wide instead, set `nodeAutoProvisioning.enabled: false` (or `JENKINS2026_NODE_AUTOPROVISIONING_ENABLED=false`). One toggle, no manifest edits — see [`config/config.yaml`](../config/config.yaml).
  * **Watch it** — the **CI-CD / Node Auto-Provisioning (Spot)** Grafana dashboard ([`observability/grafana/dashboards/node-autoprovisioning.json`](../observability/grafana/dashboards/node-autoprovisioning.json)) shows Spot vs static node counts over time, so you can see scale-up on a build and consolidation back toward zero after it.
  * **The real ceiling is the regional `SSD_TOTAL_GB` quota, not NAP.** Each `ci-spot` node's `pd-balanced` boot disk counts against that quota, so the number of *concurrent* Spot CI nodes is bounded by `SSD_TOTAL_GB` ÷ disk-size (plus the CNPG Postgres PVs; the static pool's `pd-standard` boot disks are exempt — they charge `DISKS_TOTAL_GB`). Symptom when you hit it: the agent Pod stays `Pending` and `kubectl get events` shows `cluster-autoscaler … ScaleUpFailed … Quota 'SSD_TOTAL_GB' exceeded` (NAP keeps retrying across machine families — it's doing the right thing, GCE is refusing the disk). The NAP node disk is kept at `var.disk_size_gb` (50 GB, same as the static pool) precisely to stretch this quota. **Raising the quota is NOT self-service-instant**: a consumer-quota *override* caps at Google's self-service maximum, which for `SSD_TOTAL_GB` equals the current limit (500) — higher values return `COMMON_QUOTA_CONSUMER_OVERRIDE_TOO_HIGH` (so it can't be set in Terraform either). Above 500 needs an **approved increase request** — submit a Cloud Quotas `QuotaPreference` (`cloudquotas.googleapis.com`, quotaId `SSD-TOTAL-GB-per-project-region`) or Console → *IAM & Admin → Quotas*; it reconciles to `grantedValue` after Google approves. This is also **why `runNodePool` defaults to `static`** — CI then needs no extra SSD headroom. See [`docs/runbooks/nap-spot-provisioning.md`](runbooks/nap-spot-provisioning.md).

> **Runbook**: for a step-by-step live validation (get cluster access despite the
> auth-plugin/stale-IP gotchas, trigger a build, watch NAP bring up a Spot `ci-spot` node,
> and read the `SSD_TOTAL_GB` quota ceiling + cold-start behaviour) see the
> [NAP → Spot CI nodes runbook](./runbooks/nap-spot-provisioning.md).

#### The `SSD_TOTAL_GB` quota — how it's computed, what it costs, and the increase request

> **TL;DR** — `SSD_TOTAL_GB` is a **regional GCP quota** (currently **500 GB** in `europe-southwest1`) that caps the *total* SSD-backed disk in the region. It counts **every** `pd-ssd` **and** `pd-balanced` disk — the CNPG/observability PVs *and* the `ci-spot` Spot node boot disks — so it is the **binding capacity ceiling** for the cluster, and the reason `ci-spot` elasticity is bounded. (The always-on static pool's boot disks are `pd-standard`, charging the separate `DISKS_TOTAL_GB` quota, so they're **exempt**.) It is **only meaningfully consumed at scale by `ci-spot`**; the `static` default needs no extra headroom.

<details>
<summary>🧠 <b>Mental model</b> — the whole picture in one map (read this first)</summary>

**Basic version (one paragraph):** GCP limits how much fast disk (SSD) you can have in the region to **500 GB**. The `pd-ssd`/`pd-balanced` disks count: the databases, the monitoring stack, **and the Spot CI nodes' boot disks** (the always-on static pool's boot disks are `pd-standard`, so they charge a *different*, effectively-unlimited quota and don't count here). When CI runs on cheap **Spot** nodes, each new node adds a 50 GB `pd-balanced` boot disk — pile up enough at once and you hit the 500 GB wall, so the next build can't get a node and waits. The wall isn't a money limit (the quota is free); it's a **safety ceiling**. You pay only for disks that actually exist — which is why **pausing** the cluster (deletes the VM disks) drops the bill to almost nothing.

**Advanced version (the model):**

```mermaid
mindmap
  root((SSD_TOTAL_GB))
    Quota = ceiling, NOT cost
      500 GB region limit
      counts every pd-ssd + pd-balanced
      self-service override caps at 500
      raise via QuotaPreference -> 2000 pending
    What consumes it
      Persistent PVs ~70 GB
        CNPG pd-ssd 1GB data+WAL
        Observability pd-balanced 10GB
        Tekton workspaces RWO
      Static boot = pd-standard (quota-exempt)
      Spot ci-spot disks N x 50 pd-balanced
      Orphans ~32 GB reclaimable
    Cost drivers
      Quota itself = 0 dollars
      Paused = disk floor ~13/mo
      Running = compute dominates
      Spot = ~60-80% cheaper compute
    Levers
      runNodePool static default
      Pause or Decom
      clean orphaned PDs
      fewer HA Postgres instances
```

**The three things people conflate (and shouldn't):**
| Concept | What it is | What it is NOT |
|---|---|---|
| **Quota** (`SSD_TOTAL_GB`) | a *capacity ceiling* on total SSD GB in the region | not a cost, not per-node, not per-pod |
| **Disk** (`pd-ssd`/`pd-balanced`) | the actual billed storage (PVs + node boot disks) | not the quota; the quota just bounds their sum |
| **Placement** (`runNodePool`) | whether CI adds *new* node disks (Spot) or reuses the static pool | not a quota or cost setting directly — but `ci-spot` is what pushes disk demand up |

</details>

**How the quota is computed — every `pd-ssd`/`pd-balanced` disk sums against the 500 GB ceiling (the static pool's `pd-standard` boot disks are exempt):**

```mermaid
flowchart LR
    PV["① Persistent PVs — survive pause<br/>CNPG Postgres HA (data+WAL × instances × services)<br/>+ ArgoCD / Jenkins / Tekton workspace PVCs<br/>≈ 102 GB · 54 disks (measured, paused)"]
    STATIC["② Static pool boot disks<br/>2–4 × e2-standard-8 × 50 GB<br/><b>pd-standard → charges DISKS_TOTAL_GB, NOT this quota</b>"]
    SPOT["③ ci-spot NAP node boot disks<br/>N × 50 GB pd-balanced — elastic, one per concurrent build node<br/>(0 when no CI running)"]

    PV --> SUM{{"Σ must stay ≤ 500 GB<br/>(SSD_TOTAL_GB, region-wide)"}}
    SPOT --> SUM
    STATIC -. "exempt (pd-standard)" .-> SUM
    SUM -->|"within budget"| OK["✅ disks provision · nodes come up"]
    SUM -->|"exceeds 500"| BAD["❌ GCE refuses the disk<br/>agent Pod stuck Pending<br/>ScaleUpFailed … Quota 'SSD_TOTAL_GB' exceeded"]

    classDef ok fill:#0b6,stroke:#063,color:#fff;
    classDef bad fill:#c50,stroke:#720,color:#fff;
    class OK ok;
    class BAD bad;
```

Only **① Persistent PVs** and **③ ci-spot Spot boot disks** count against `SSD_TOTAL_GB` — **② the static pool's boot disks are `pd-standard`, so they charge the separate `DISKS_TOTAL_GB` quota (4 TB, ~empty) and are exempt from this cap**. ① is fixed (the platform + databases); only ③ grows with `ci-spot` concurrency. So the usable Spot budget is roughly `(500 − ~70 GB PVs)` ÷ 50 GB ≈ **8 concurrent Spot CI nodes** before the ceiling bites.

**Detailed disk inventory — ① the persistent PVs** (measured live; the architectural footprint, paused state):

| Namespace | Component | PVC(s) | Disk type | Size each | Qty | Subtotal | Why this size/type |
|---|---|---|---|---|---|---|---|
| `microservices` | **CNPG Postgres — stable HA** | `postgres-{gateway,jhipstersample}-{1,2,3}` + `…-wal` | `pd-ssd` | 1 GB | 12 | **12 GB** | 3 HA instances × 2 services × (data + WAL); `pd-ssd` for low-latency WAL fsync / random I/O |
| `microservices-develop` | **CNPG Postgres — lean dev** | `postgres-{gateway,jhipstersample}-1` + `…-wal` | `pd-ssd` | 1 GB | 4 | **4 GB** | single instance × 2 services × (data + WAL); non-HA dev tier |
| `observability` | **Prometheus TSDB** | `prometheus-…-0` | `pd-balanced` | 10 GB | 1 | 10 GB | metrics time-series store (mode=oss); balanced is enough |
| `observability` | **Loki** | `storage-oss-loki-0` | `pd-balanced` | 10 GB | 1 | 10 GB | log chunks store |
| `observability` | **Tempo** | `storage-oss-tempo-0` | `pd-balanced` | 10 GB | 1 | 10 GB | trace store |
| `pgadmin` | **pgAdmin** | `pgadmin-pgadmin4` | `pd-balanced` | 10 GB | 1 | 10 GB | pgAdmin config/session state |
| `tekton-ci` | **Tekton run workspaces** | `pvc-<hash>` (volumeClaimTemplate) | `pd-balanced` | 1–4 GB | ≤5 | ~14 GB | one RWO `source` workspace per PipelineRun; bounded by the Pruner `historyLimit: 5` |
| | | | | | | **≈ 70 GB live** | |

> ⚠️ **Orphaned disks inflate the measured total.** The region currently shows **102 GB / 54 disks**, ~32 GB above the ~70 GB live footprint. Evidence: **duplicate PVC names that cannot coexist in a live cluster** (e.g. `postgres-gateway-2` maps to **3** separate disks) and disks spanning **3 creation dates** (`06-27`, `06-28`, `06-29`). These orphans count against the quota and the ~$13/mo disk floor — see the dedicated subsection below for the cause and the **two-layer auto-reclaim**.

#### Orphaned persistent disks — cause, prevention (①), and the sweep (②)

When a `Decom` tears the cluster down via `terraform destroy`, the GKE control plane (and with it the **CSI driver**) disappears **before** Kubernetes gets to delete the PVCs — so `reclaimPolicy: Delete` never fires and the backing `pd-*` disks are **orphaned** in the GCP project. They **accumulate one generation per rebuild**, each costing money and consuming `SSD_TOTAL_GB`. Two complementary layers handle this automatically (durable default; disable with `J2026_ORPHAN_PD_SWEEP=false`):

```mermaid
flowchart LR
    subgraph PREV["① Prevention — scripts/down.sh (at teardown)"]
        A["pods already removed"] --> B["reclaim_namespace_pvcs:<br/>delete PVCs GRACEFULLY<br/>(keep pvc-protection finalizer)"]
        B --> C["CSI external-provisioner<br/>reclaims PV (reclaimPolicy=Delete)<br/>→ deletes the PD"]
        C --> D["wait ≤2m for PVs to vanish"]
        D -->|"straggler"| E["finalizer-strip fallback"]
    end
    subgraph SWEEP["② Sweep — scripts/sweep-orphaned-pds.sh (at every cluster-up)"]
        F["kubectl get pv → live disk handles"] --> G{"cluster reachable?"}
        G -->|"no (paused)"| H["ABORT — never guess"]
        G -->|"yes"| I["list unattached pvc-* disks"]
        I --> J["delete those NOT in the live set"]
    end
    E -.->|"anything missed"| F

    classDef bad fill:#c50,stroke:#720,color:#fff;
    class H bad;
```

| Layer | File | When | What it does | Why it's safe |
|---|---|---|---|---|
| **① Prevention** | [`scripts/down.sh`](../scripts/down.sh) `reclaim_namespace_pvcs` | teardown (`Decom`, `J2026_DELETE_NAMESPACES=true`) | deletes PVCs **gracefully** (finalizer intact) so CSI reclaims each PD *before* the cluster is destroyed; finalizer-strip only as fallback | runs while CSI is alive; bounded ~2 min/ns; data-namespace deletion is already gated behind the explicit `DELETE_NAMESPACES` flag |
| **② Sweep** | [`scripts/sweep-orphaned-pds.sh`](../scripts/sweep-orphaned-pds.sh) (called by [`up.sh`](../scripts/up.sh)) | every **cluster-up** (Day1), or standalone | reconciles all unattached `pvc-*` disks against live PV `volumeHandle`s and deletes the difference | deletes **only** `pvc-*` (never `gke-*` node disks), **only** unattached, **only** if not referenced by a live PV; **aborts if the cluster is unreachable** so a *paused* cluster's PVs are never mistaken for "0 live PVs" |

**Run it standalone** (e.g. after a `Resume`, with the cluster reachable):

```bash
# preview first (deletes nothing):
J2026_ORPHAN_PD_SWEEP_DRYRUN=true scripts/sweep-orphaned-pds.sh
# then the real sweep:
scripts/sweep-orphaned-pds.sh
```

> 🔒 **Why the sweep refuses to run against a paused cluster.** Identifying orphans means "every `pvc-*` disk **not** backing a live PV". If `kubectl` can't reach the cluster, the live-PV list comes back empty and *every* disk would look orphaned — including a paused cluster's live databases. The sweep therefore **hard-aborts** when `kubectl get pv` fails. This is exactly why the current ~32 GB of orphans are cleaned at the **next cluster-up**, not while paused.

**Disk class — why each workload gets `pd-ssd` vs `pd-balanced`:**

| Disk class | Workloads | Rationale | ≈ Cost |
|---|---|---|---|
| **`pd-ssd`** | CNPG Postgres data + WAL | DB needs low-latency random I/O + fast WAL fsync (commit latency) | ~$0.17 / GB·mo |
| **`pd-balanced`** | `ci-spot` NAP node boot disks · Prometheus/Loki/Tempo · pgAdmin · Tekton workspaces | general-purpose SSD; ample for append-mostly TSDB and scratch — **counts against `SSD_TOTAL_GB`** | ~$0.10 / GB·mo |
| **`pd-standard`** | **static `jenkins-2026-pool` node boot disks** | boot disks (OS + image cache + emptyDir) don't need SSD IOPS; **charges `DISKS_TOTAL_GB` (4 TB), exempt from `SSD_TOTAL_GB`** | ~$0.04 / GB·mo |

**② + ③ — node boot disks (static vs Spot) and the workload each serves:**

| Disk | Node pool | Class · size | Lifecycle | Workload it carries | Quota impact |
|---|---|---|---|---|---|
| **Static node boot** | `jenkins-2026-pool` | `pd-standard` · 50 GB | always-on (0 only when **Paused**) | platform (ArgoCD/Jenkins/observability/CNPG) **+ CI build pods by default** (`runNodePool: static`) | **none** — charges `DISKS_TOTAL_GB` (4 TB, ~empty), **exempt from `SSD_TOTAL_GB`** |
| **Spot node boot** | NAP `ci-spot` (auto-created) | `pd-balanced` · 50 GB | **per-build, scale-to-zero** | CI build pods **only when** `runNodePool: ci-spot` | **elastic** — N × 50 GB, 0 at rest |
| **Persistent PV** | — (CSI PD, not node-bound) | `pd-ssd`/`pd-balanced` · 1–10 GB | survives Pause; deleted only with the PVC | databases · observability · Tekton workspaces | **fixed** — ~70 GB live |

**Usage these days (measured, limit = 500 GB):**

| Cluster state | SSD used | % of 500 | What's on disk |
|---|---|---|---|
| **Paused** (`Day2.scale.01`, nodes → 0) | **102 GB** | **~20 %** | only ① — the 54 persistent PVs (DBs + platform); node disks are deleted |
| **Running, idle CI** | ~102 GB | ~20 % | ① only — static boot disks are `pd-standard` and don't count |
| **Running, CI under load (peak observed)** | ~492 GB | **~98 %** | ① + several `ci-spot` Spot node boot disks (`pd-balanced`) — *this is where builds wedged; the static pool's pd-standard disks stay exempt* |

**FinOps — cost breakdown** (approximate GCP list prices for `europe-southwest1`; verify in the [pricing calculator](https://cloud.google.com/products/calculator)).

*Basic:* the **quota is free**; you pay for **disks** (small) and **compute** (large). Paused ≈ **$20/month** (disks + IP only); running ≈ **$0.55/hour** (compute dominates); off (Decom) = **$0**.

*Advanced:* compute is ~95 % of the running cost, so disk/quota tuning is about **capacity, not the bill** — the bill lever is *node hours* (Pause/Decom) and *Spot* (−60–80 % on compute). Cleaning the ~32 GB of orphaned PDs saves ~$5/mo **and** frees quota.

**① Unit rates:**

| Resource | ≈ Rate | Note |
|---|---|---|
| `pd-ssd` | ~$0.17 / GB·month | low-latency SSD — CNPG data + WAL |
| `pd-balanced` | ~$0.10 / GB·month | general SSD — node boot, TSDBs, workspaces |
| `e2-standard-8` (on-demand) | ~$0.22 / hour (~$160/mo) | static pool compute |
| `e2-standard-8` (**Spot**) | ~$0.05–0.09 / hour | `ci-spot` nodes — **60–80 % cheaper**, preemptible |
| Cluster management fee | $0.10 / hour | **waived** for the 1st zonal cluster per billing account |
| Static external IP | ~$7 / month | the persistent Gateway IP |
| **`SSD_TOTAL_GB` quota** | **$0** | a ceiling, not a charge |

**② Disk cost by component** (the persistent floor — survives Pause):

| Component | Type | GB | ≈ $/month |
|---|---|---|---|
| CNPG Postgres — stable HA | `pd-ssd` | 12 | ~$2.0 |
| CNPG Postgres — develop | `pd-ssd` | 4 | ~$0.7 |
| Observability (Prometheus/Loki/Tempo) | `pd-balanced` | 30 | ~$3.0 |
| pgAdmin | `pd-balanced` | 10 | ~$1.0 |
| Tekton workspaces (≤5 runs) | `pd-balanced` | 14 | ~$1.4 |
| **Live PV subtotal** | | **70** | **~$8.1** |
| Orphaned PDs (**reclaimable**) | `pd-ssd` | 32 | ~$5.4 |
| **Measured total** | | **102** | **~$13.5** |

**③ Total cost by cluster lifecycle state:**

| State | What's billed | ≈ Per hour | ≈ Per month (if left 24×7) |
|---|---|---|---|
| **Decom** (destroyed) | nothing | **$0** | **$0** |
| **Paused** (`Day2.scale.01`, nodes → 0) | PVs (~102 GB) + static IP | ~$0.03 | **~$20** |
| **Running** (2 static nodes, idle CI) | 2× compute + node disks + PVs + IP | ~$0.55 | ~$345 |
| **Running + Spot CI burst** | + N `ci-spot` Spot nodes (per build) | +~$0.07 / node·hr | ephemeral (scale-to-zero) |

> 💡 The quota does **not** cost anything — raising it to 2000 does **not** raise the bill. You only ever pay for the disks you actually provision. The quota is purely a *safety ceiling*; the cost lever is **Pause** (drops compute to ~$13/mo) or **Decom** (drops to ~$0).

**Quota options — what you can set and how:**

| Option | Effective `SSD_TOTAL_GB` | Cost | Mechanism / constraint |
|---|---|---|---|
| **Current** (project default) | **500 GB** | — | the region default for `europe-southwest1` |
| **Self-service override** | **0 – 500 GB** | $0 | `google_service_usage_consumer_quota_override` (Terraform) / Service Usage API — can only **match or lower**; any value >500 → `COMMON_QUOTA_CONSUMER_OVERRIDE_TOO_HIGH` |
| **Approved increase request** | up to the granted value (**2000 filed**) | $0 | Cloud Quotas `QuotaPreference` (`SSD-TOTAL-GB-per-project-region`) / Console → Quotas — **needs Google approval** (currently pending) |
| **Reduce demand instead** (no quota change) | n/a | **saves $** | `runNodePool: static` (no per-build disk) · fewer HA instances (`postgresInstances` 3→1) · **clean orphaned PDs** (~32 GB reclaimable now) |

**The increase request to Google (500 → 2000):**
- A consumer-quota **override** caps at the self-service max, which for `SSD_TOTAL_GB` **equals the current limit (500)** → higher returns `COMMON_QUOTA_CONSUMER_OVERRIDE_TOO_HIGH`. **Not Terraform-able** (an override to 2000 would fail the apply).
- Going above 500 needs an **approved increase request**, submitted via the **Cloud Quotas API** as a `QuotaPreference` (`cloudquotas.googleapis.com`, quotaId `SSD-TOTAL-GB-per-project-region`, region `europe-southwest1`).
- **Status:** a request to **2000** was filed (`QuotaPreference ssd-total-gb-esw1`); it currently shows `preferredValue: 2000`, `grantedValue: 500`, i.e. **pending Google's approval** (small bumps auto-approve, a 4× may go to human review — minutes to days). Re-`GET` the preference (or Console → *IAM & Admin → Quotas*) and watch `grantedValue` catch up.

**Roadmap / decision guide:**

| Goal | Action |
|---|---|
| **Default / now** — robust CI, no quota pressure | `runNodePool: static` for Jenkins/Tekton/Argo Workflows (no per-build disk). 500 GB is plenty. (GitHub Actions/ARC defaults to `ci-spot` — its single-job runners are the Spot showcase; flip to `static` if quota-constrained.) |
| **Cut idle cost** | **Pause** (`Day2.scale.01`) → ~$13/mo · or **Decom** → ~$0 |
| **Enable Spot CI at concurrency** | Wait for the 500 → 2000 grant, **then** flip **Jenkins** (single-pod, best Spot fit) — or use **GitHub Actions/ARC**, already Spot by default — to `runNodePool: ci-spot`. Tekton / Argo Workflows stay `static` (shared-workspace runs). |
| **More DB headroom without more quota** | reduce the HA Postgres footprint (3 → 1 instance on the develop tier) — fewer PVs |

See the live-validation steps + the exact API call in [`docs/runbooks/nap-spot-provisioning.md`](runbooks/nap-spot-provisioning.md).

#### The engines on Spot (`ci-spot`) — why the placement flag is *per engine*

All four CI engines can target the `ci-spot` ComputeClass, but they fall into **two fundamentally different pod-scheduling shapes**, so the same Spot node behaves very differently under each. **Single-pod, one-job engines** (**Jenkins** agents, **GitHub Actions/ARC** runners) are textbook Spot workloads — a preemption loses one idempotent build/job that just re-runs. **Shared-workspace, multi-pod runs** (**Tekton** PipelineRuns via the affinity assistant, **Argo Workflows** runs sharing one RWO workspace PVC) pin every task/step to one node, so a preemption kills the whole run. This is why placement is a **separate flag per engine** (`<engine>.runNodePool`) rather than one shared knob — you want to make the engine-appropriate choice, and the engines are mutually exclusive anyway (`ci.engine`) so a shared flag would only ever describe the active one. The comparison below uses Jenkins vs Tekton as the two archetypes (ARC follows Jenkins; Argo Workflows follows Tekton).

```mermaid
flowchart TD
    flag{"runNodePool (per engine)"}
    flag -->|"static (default)"| sp["jenkins-2026-pool · e2-standard-8<br/>always on — no NAP/Spot/quota dependency"]
    flag -->|"ci-spot (opt-in)"| nap["GKE NAP → Spot ComputeClass node<br/>scale-to-zero · cheaper · SSD_TOTAL_GB-bound"]

    sp --> jok["Jenkins ✅ robust"]
    sp --> tok["Tekton ✅ robust — recommended"]
    nap --> jspot["Jenkins / GitHub Actions (ARC): 1 pod per build/job<br/>preemption → that 1 build re-runs<br/>✅ good Spot fit (ARC defaults here)"]
    nap --> tspot["Tekton / Argo Workflows: shared RWO workspace PVC<br/>pins ALL tasks/steps to one node<br/>preemption → whole run dies<br/>⚠ poor Spot fit — keep static"]

    classDef good fill:#0b6,stroke:#063,color:#fff;
    classDef warn fill:#c50,stroke:#720,color:#fff;
    classDef pool fill:#2563eb,stroke:#1e3a8a,color:#fff;
    class jok,tok,jspot good;
    class tspot warn;
    class sp,nap pool;
```


| Dimension | **Jenkins** | **Tekton** |
|---|---|---|
| **Build = how many pods?** | **One** ephemeral multi-container agent pod (maven/node/dind/… containers share it) | **Many** TaskRun pods (clone → build → scan → push → deploy), one pod per Task |
| **Inter-pod coupling** | None — the whole build *is* one pod | The Tasks share **one RWO `source` workspace PVC** (cloned once, reused), so Tekton's **affinity assistant** co-schedules **all** of a PipelineRun's pods onto **one node** (the only way to mount an RWO PVC across pods) |
| **Spot preemption blast radius** | **One build** — the agent pod dies, GKE reschedules it, NAP brings a fresh node, the build is simply **re-run** (idempotent). Minimal. | **The entire PipelineRun** — every Task rides the same node; lose it and *all* in-flight Tasks die together (the RWO PVC was on that node). Much larger. |
| **"Node too small/full" failure** | Rare — a single pod either fits the (4-vCPU+) Spot node or NAP scales another | **Real hazard** — if the assistant lands on a small NAP node (e.g. `e2-standard-2`), a later/retried Task (`codeql`, 500m) may not fit, and an affinity-pinned pod **can't move or trigger a useful scale-up** → the run hangs in `ExceededNodeResources` (the v0.28.53 bug) |
| **Spot fit** | **Good citizen** — single, idempotent, short-lived pod is the textbook Spot workload | **Poor fit as-is** — a long, multi-Task run pinned to one preemptible node is exactly what Spot is *bad* at |
| **Recommended `runNodePool`** | `static` by default; **`ci-spot` is the recommended opt-in** (most cost upside, least risk) | **`static`** (strongly) — keep Spot off unless you re-architect the workspace (RWX/Filestore + disable the affinity assistant, or per-Task `emptyDir` + artifact passing) |

**So: is `static` still the right *default* even though Jenkins is the better Spot citizen?** Yes — for two independent reasons:
1. **Robustness with zero preconditions.** `static` needs no NAP, no Spot capacity, and **no `SSD_TOTAL_GB` headroom** — it just works on a fresh cluster for everyone. `ci-spot` needs all three.
2. **The quota ceiling is currently binding.** Each `ci-spot` node's boot disk counts against the regional `SSD_TOTAL_GB` quota, which **caps at 500 self-service** (raising it needs an approved request — see above). At 500, a couple of concurrent `ci-spot` agents can wedge in `Pending`. We observed exactly this on a real Day1 (the `gateway` agent stuck on `ScaleUpFailed … Quota 'SSD_TOTAL_GB' exceeded`).

**Recommended rollout (sequenced)** — by shape (ARC follows the Jenkins column, Argo Workflows follows the Tekton column):

| Phase | Jenkins (· ARC) | Tekton (· Argo Workflows) |
|---|---|---|
| **Now** (quota = 500) | `static` (ARC ships `ci-spot` by default — its runners are single-job, low-risk) | `static` |
| **After the `SSD_TOTAL_GB` increase is granted** | **`ci-spot`** — best cost/elasticity, lowest risk (ARC already there) | `static` (the affinity-assistant / shared-workspace hazard is independent of quota; only an RWX-workspace redesign would make these engines Spot-safe) |

Flip per engine with the config flag (durable) or the **`run_node_pool` input** on that engine's redeploy workflow — `Day2.redeploy.02-jenkins` / `Day2.redeploy.03-tekton` / `Day2.redeploy.06-githubactions` / `Day2.redeploy.07-argoworkflows` (per-run, no commit). See the Tekton-specific mechanics and the RWX/affinity-assistant alternatives in [`docs/403`](403-TEKTON.md) (and the ARC / Argo Workflows equivalents in [`docs/404`](404-GITHUB_ACTIONS.md) / [`docs/405`](405-ARGO_WORKFLOWS.md)).

### 3. Zero-Trust Security & Workload Identity
* **Workload Identity Federation**: All static JSON Service Account keys are removed. External CI (the GitHub Actions infra workflows) and in-cluster workloads assume GCP IAM Roles dynamically via OIDC.
  * Note: the standalone [`terraform/workload-identity`](../terraform/workload-identity/README.md) module is a manual/auxiliary reference helper (its own pool `github-actions-pool-2026` + SA `jenkins-2026-ci-agent`) and is **not** the CI trust the lifecycle uses — that lives in [`terraform/bootstrap`](../terraform/bootstrap/README.md) (pool `jenkins-2026-github`, SA `jenkins-2026-ci`).
* **Edge TLS (GKE Gateway API)**: TLS terminates at the global L7 LB (the Google-managed wildcard cert). The LB→pod hop is **plain HTTP** — every routed backend (Jenkins :8080, Headlamp, ArgoCD, …) serves plain HTTP, so no `BackendTLSPolicy` backend re-encryption is configured (it would need an internal PKI plus TLS-serving backends — a possible future hardening). That hop never leaves Google's VPC fabric and rides Google's default network-layer encryption in transit; pod-to-pod traffic is covered by the WireGuard bullet below.
* **GKE Dataplane V2 (Cilium/eBPF) — NetworkPolicy *enforcement***: the cluster runs Dataplane V2 (`datapath_provider = ADVANCED_DATAPATH` in [`terraform/gke`](../terraform/gke/main.tf)). This is what makes the policies below *actually enforce* — without it (and without the legacy Calico addon, mutually exclusive with it) GKE accepts `NetworkPolicy` objects but silently ignores them.
* **Zero-Trust Network Policies** ([`infrastructure/networkpolicies*.yaml`](../infrastructure/)): every namespace egresses to CoreDNS by default-deny. Sensitive namespaces (**observability, microservices**(+`-develop`)**, pgadmin**, and **jenkins** in jenkins mode) run `default-deny` + curated allowlists (see the matrix below). Workload UI/CI namespaces (**argocd, headlamp**, plus the active engine's run namespace — **tekton-ci / arc-runners / argo-ci**) get a **deny-ingress / allow-egress baseline**: each namespace's entry port stays reachable (Gateway, CI sync, port-forward, CLI) while internal components are intra-namespace only; the outbound-only pipeline pods get no ingress. Admission-webhook/controller namespaces (**tekton-pipelines, arc-systems, argo, argo-events, cnpg-system, external-secrets, pipelines-as-code**) are intentionally left open — a `deny-ingress` there would block the API server's (or GitHub's) webhook calls unless the GKE control-plane CIDR is allowlisted (fragile, cluster-specific). The observability policy also allows the GKE L7 health-check/proxy ranges (`130.211.0.0/22`, `35.191.0.0/16`) so the Grafana backend stays healthy under enforcement.
* **Pod-to-pod WireGuard encryption**: `in_transit_encryption_config = IN_TRANSIT_ENCRYPTION_INTER_NODE_TRANSPARENT` has Dataplane V2's managed Cilium transparently encrypt **inter-node** pod traffic (sidecar-free, no service mesh, no app changes). This is *transport* encryption, not identity-based mutual auth (no per-workload mTLS identity/authZ like Istio/Linkerd) — it closes the plaintext-on-the-wire gap lightly. Same-node pod traffic never hits the wire, so it is not encrypted.
* **Secret Management via External Secrets Operator (ESO)**: Connects GKE Workload Identity with Google Secret Manager. ESO automatically pulls and syncs secret structures to namespaced secrets dynamically.

> ⚠️ Dataplane V2 + the WireGuard config are **immutable** cluster fields — applied by recreating the cluster (`Decom.cluster.01` → `Day1.cluster.01`), not an in-place re-run. Enabling enforcement activates the NetworkPolicies for the first time, so validate connectivity (OSS stack, CNPG metrics, microservices, gateway, ArgoCD sync, and the active CI engine's build/trigger path) on the fresh cluster.

<details>
<summary>NetworkPolicy under enforcement — the gotchas that bite on the first Dataplane V2 cluster</summary>

The first recreate with enforcement surfaced several latent rules that had silently been no-ops. Lessons baked into [`infrastructure/networkpolicies.yaml`](../infrastructure/networkpolicies.yaml):

- **Target the POD port, not the Service port.** GKE's container-native LB (NEG) sends to the pod's `targetPort`, not the Service port. The argocd/headlamp baselines first allowed `80`/`443` (Service ports) → the health checks hit `argocd-server:8080` / `headlamp:4466` and were dropped → **GKE backend UNHEALTHY**. Allow the real container ports.
- **The API server (control plane) is not a pod or an LB range.** Admission webhooks the API server calls — the **OTel operator** mutating webhooks (`9443`, in `observability`) and the Tekton control-plane webhooks — are blocked by a namespace default-deny. With `failurePolicy=Fail` this breaks applying the CRs (e.g. the `Instrumentation` CR → `microservices-stable` stuck OutOfSync); with `failurePolicy=Ignore` it silently skips work (no OTel agent injected). Allow the webhook port from any source, or leave the operator namespace open (we leave `tekton-pipelines`/`cnpg-system`/`external-secrets`/`pac` open by design).
- **GKE L7 health-check/proxy ranges** `130.211.0.0/22` + `35.191.0.0/16` must be allowed (by `ipBlock`) for any Gateway-exposed backend whose policy restricts ingress (e.g. Grafana).
- **Match CNPG pods by `cnpg.io/cluster`, not `app.kubernetes.io/name`.** CNPG labels its pods `app.kubernetes.io/name=postgresql`; an egress allow targeting `app.kubernetes.io/name: postgres-*[-pooler]` matches nothing → apps time out on Liquibase. (Carried by the additive `microservices-cnpg-platform` policy, plus `9187` ingress for metrics scraping.)
- **K8s-API egress for app discovery.** The JHipster microservice uses Hazelcast Kubernetes member discovery (queries the API server on `443`); without egress to `443` it never goes Ready. Apps that talk to the API need explicit egress.
- **Jenkins build agents need their OWN egress allow.** The `jenkins` `default-deny` caps every pod's egress at DNS, and `jenkins-policy`'s open egress only matches the controller (`app.kubernetes.io/name=jenkins`). The ephemeral Kubernetes-plugin agent pods (label `jenkins=slave`) matched neither, so they couldn't reach the controller's `8080` tcpSlaveAgentListener / `50000` JNLP — every build hung at "Waiting for agent to connect" and the **seed job timed out**. The separate `jenkins-agent-policy` (in [`networkpolicies-jenkins.yaml`](../infrastructure/networkpolicies-jenkins.yaml)) grants `jenkins=slave` pods open egress (no ingress — they're outbound-only, like the tekton-ci pipeline pods).
- **CI smoke tests must run where egress *and* ingress are allowed.** The post-deploy health check (`<svc>:8081/management/health`, or the gateway on `8080`) crosses into the locked-down `microservices` namespace. Two policies must both permit it: (a) the microservice's own ingress — `microservice-policy` (in the **gitops-config** repo, `helm/microservices/networkpolicies.yaml`) allows the app port from the `gateway` pod **and** every CI-engine run namespace (`jenkins` / `tekton-ci` / `arc-runners` / `argo-ci`); and (b) the smoke pod's **egress**. Tekton satisfies (b) naturally — its smoke runs as a pipeline pod in `tekton-ci` (open egress). Jenkins' `microservicesSmokeTest` originally did `kubectl -n microservices run`, putting the curl pod **in the microservices namespace** (default-deny egress = DNS only) → it could never connect → **curl exit 28**. Fixed by creating the pod in the **agent's `jenkins` namespace** labelled `jenkins=slave` (open egress via `jenkins-agent-policy`), targeting the microservices Service FQDN. Rule of thumb: a CI health-check pod must live in a namespace whose egress is open *and* that the target's ingress allows — never in the target's own locked-down namespace.
- **Additive vs owned.** A separate NetworkPolicy that no ArgoCD app owns (e.g. `microservices-cnpg-platform`) is **not reverted on sync** and survives recreates (it's in git, applied by `01-namespaces.sh`) — the clean way to add platform allows on top of app-chart policies you don't control.
</details>

#### NetworkPolicy matrix

> This matrix is the per-namespace allow/deny detail. For the **full network
> architecture** it sits inside — the landing zone (single-VPC, *not* hub-spoke),
> the VPC/subnet + pod/service **CIDR plan**, north-south ingress (Gateway + IAP +
> NEG) & egress, east-west (VPC-native · Dataplane V2 · WireGuard), and this
> segmentation model explained end to end — see **[503. Networking](./503-NETWORKING.md)**.

Every policy is in [`infrastructure/networkpolicies*.yaml`](../infrastructure/) (engine-neutral always-on, plus one per-engine file — `-jenkins` / `-tekton` / `-githubactions` / `-argoworkflows` — applied for the active `ci.engine`). `*` = "from/to any source" (the rule lists ports but no peer). Every `default-deny` namespace also egresses to CoreDNS (`kube-system:53`), omitted from the table.

| Namespace | Mode | Policy / pods | Ingress allowed | Egress allowed |
|---|---|---|---|---|
| `observability` | always | `observability-policy` (all) | intra-ns mesh; CI namespaces (`jenkins`, `tekton-ci`+`tekton-pipelines`, `arc-runners`, `argo-ci`) + `microservices`(+`-develop`) → **4317/4318** (OTLP); GKE LB `130.211.0.0/22`+`35.191.0.0/16` (Grafana health/traffic); **9443*** (API-server → OTel operator webhooks) | all |
| `microservices` | always | `microservices-cnpg-platform` (all) | `observability` → **9187** (CNPG metrics); `cnpg-system` → **8000** (operator instance-status) | pods `cnpg.io/cluster` → **5432**; **443*** (K8s API — Hazelcast discovery); `169.254.169.254`:**80/988** (WI metadata — barman GCS backups) |
| `microservices` | always (GitOps repo) | `gateway`/`microservice`/`postgres-policy` | Gateway → app port; intra-app | app chart's own allows (Postgres, OTLP) — *durable CNPG/9187/API fixes belong here* |
| `pgadmin` | always | `pgadmin-policy` (pgadmin) | **80*** (Gateway UI) | **443***; `microservices` → **5432** |
| `argocd` | always | `argocd-baseline` (all) | intra-ns mesh; **8080*** (argocd-server pod port: Gateway, CI sync, CLI, port-forward) | all |
| `headlamp` | always | `headlamp-baseline` (all) | intra-ns mesh; **4466*** (headlamp pod port: Gateway) | all |
| `tekton-ci` | `tekton` | `tekton-ci-baseline` (all) | intra-ns; EventListener **8080/9000*** (event/metrics). Pipeline pods get **no ingress** (outbound-only) | all |
| `jenkins` | `jenkins` | `jenkins-policy` (controller) + `jenkins-agent-policy` (`jenkins=slave`) | **controller:** **8080*** (UI/Gateway **+ build-agent WebSocket**), **50000** (legacy JNLP, unused) from intra-ns agents, `observability` → **8080**. **agents:** none (outbound-only) | **controller:** all. **agents:** all (reach controller **8080** via WebSocket + git/registry/ArgoCD) |
| `arc-runners` | `githubactions` | `arc-runners-baseline` (all) | intra-ns only (listener ↔ ephemeral runner). Runner pods get **no ingress** (outbound-only; ARC long-polls GitHub — no inbound webhook) | all |
| `argo-ci` | `argoworkflows` | `argoworkflows-ci-baseline` (all) | intra-ns only (controller/executor). Workflow pods get **no ingress** (outbound-only) | all |
| `tekton-pipelines`, `arc-systems`, `argo`, `argo-events`, `cnpg-system`, `external-secrets`, `pipelines-as-code` | per mode | *(none — open by design)* | all (hosts admission/webhook receivers the API server or GitHub call) | all |

#### NetworkPolicy flow diagram

<details>
<summary>📊 NetworkPolicy flow — who may talk to whom</summary>

```mermaid
flowchart LR
  net([Internet]):::ext
  lb([GKE Gateway / L7 LB<br/>130.211.0.0/22 · 35.191.0.0/16]):::ext
  api([Kube API server<br/>control plane]):::ext
  dns([CoreDNS<br/>kube-system :53]):::infra

  net --> lb

  subgraph obs[observability]
    graf[Grafana / Prometheus<br/>Loki · Tempo · OTel collector]
  end
  subgraph ms[microservices]
    gw[gateway / jhipster]
    pg[(CNPG Postgres<br/>cnpg.io/cluster)]
  end
  msd[microservices-develop<br/>optional develop tier · own lean CNPG]:::infra
  subgraph ci["active CI engine (one of four · ci.engine)"]
    cieng["jenkins :8080 WebSocket agents<br/>· tekton-ci EL :8080/:9000<br/>· arc-runners (ARC, outbound-only)<br/>· argo-ci (Argo Workflows)"]
  end
  argocd[argocd-server :8080]:::ui
  headlamp[headlamp :4466]:::ui
  pgadmin[pgAdmin :80]:::ui
  ciui["CI UI (tekton-dashboard / argo-server)<br/>— Tekton &amp; Argo Workflows only; ARC/GHA has none"]:::ui

  lb -->|:8080| gw
  lb -->|health+traffic| graf
  lb -->|:8080| argocd
  lb -->|:4466| headlamp
  lb -->|:80| pgadmin
  lb -->|when engine has a UI| ciui

  api -.->|:9443 webhooks| obs
  cieng -->|OTLP :4317/4318| obs
  cieng -->|smoke health<br/>jhipster :8081 / gateway :8080| gw
  gw -->|OTLP :4317/4318| obs
  graf -->|scrape :9187| pg
  gw -->|:5432| pg
  gw -->|:443 Hazelcast| api
  pgadmin -->|:5432| pg
  obs -. "OTLP :4317 + scrape :9187 (when develop on)" .- msd

  obs --> dns
  ms --> dns
  ci --> dns

  classDef ext fill:#fde,stroke:#c39;
  classDef infra fill:#eef,stroke:#66c;
  classDef ui fill:#efe,stroke:#393;
```

</details>

### 4. GitOps Separation of Concerns
All infrastructural manifests ([`compute-classes/`](../infrastructure/compute-classes/), [`gateway/`](../infrastructure/gateway/), [`headlamp/`](../infrastructure/headlamp/), [`scheduling/`](../infrastructure/scheduling/), the `networkpolicies*.yaml`) are decoupled from CI pipeline definitions and placed inside the [`infrastructure/`](../infrastructure/) directory. They belong to the **imperative (push) lane, not Argo CD**: [`01-namespaces.sh`](../scripts/01-namespaces.sh) applies the NetworkPolicies + the `ci-spot` ComputeClass (they must land before workloads), [`08.5-argocd.sh`](../scripts/08.5-argocd.sh) the Argo Rollouts RBAC; `gateway/` (and `headlamp/`, `scheduling/`) are reviewable static references — the live objects come from [`09-gateway.sh`](../scripts/09-gateway.sh) / the Helm charts. See the full imperative-vs-GitOps inventory in [`docs/201`](201-ARCHITECTURE.md).

### 5. Build Performance & High Availability Caching
* **Jenkins Agent Caching**: Java (Maven `/root/.m2`) and Node (npm `/root/.npm`) containers in pipeline agent templates mount hostPath volumes (`/tmp/jenkins-maven-cache` and `/tmp/jenkins-npm-cache`). Sharing a fast local node directory avoids ReadWriteOnce volume mounting locks while reducing typical compilation times from 5-10 minutes to under 1 minute.
* **Database HA & Storage Lifecycles**: Distributes CloudNative-PG replicas across distinct physical zones using zonal anti-affinity constraints. GCS lifecycle rules automatically transition backups to `NEARLINE` storage class after 3 days and delete them after 7 days.

### 6. Progressive Delivery (Argo Rollouts + Gateway API)

Canary / blue-green delivery, **sidecar-free**, reusing the existing GKE Gateway API ingress (no service mesh):

* **Controller (installed)**: [`argocd/argo-rollouts-app.yaml`](../argocd/argo-rollouts-app.yaml) GitOps-installs the Argo Rollouts controller (Helm chart, pinned) with the **Gateway API traffic-router plugin** (`argoproj-labs/gatewayAPI`) configured via `controller.trafficRouterPlugins`. [`infrastructure/argo-rollouts-gatewayapi-rbac.yaml`](../infrastructure/argo-rollouts-gatewayapi-rbac.yaml) grants the controller `update/patch` on `gateway.networking.k8s.io` HTTPRoutes (the chart default lacks it). Applied by [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh). The read-only Rollouts dashboard is enabled (cluster-internal).
* **How the canary shifts traffic**: a `Rollout` (replacing the `gateway` `Deployment`) with `stableService: gateway` + `canaryService: gateway-canary` and `trafficRouting.plugins."argoproj-labs/gatewayAPI"` pointing at the `microservices` HTTPRoute. The plugin rewrites the HTTPRoute `backendRefs` **weights** between the stable and canary Services through the canary steps (e.g. 20% → 50% → 100% with pauses). No Envoy, no sidecars.

**Remaining steps (cross-repo — the controller above is the in-cluster foundation):**

| Step | Where | Change |
|---|---|---|
| **B2** | this repo — [`scripts/09-gateway.sh`](../scripts/09-gateway.sh) | microservices HTTPRoute gets two `backendRefs` (`gateway` weight 100 + `gateway-canary` weight 0). **Land WITH B3** — adding the canary backendRef before its Service exists causes `BackendNotFound`. |
| **B3** | **microservices GitOps repo** (`helm/microservices`, external) | convert the `gateway` `Deployment` → `Rollout` (canary strategy + steps + the `gatewayAPI` plugin referencing the `microservices` HTTPRoute) and add the `gateway-canary` `Service`. |
| **B4** | this repo — the active engine's gitops-deploy step (e.g. [`tekton/tasks/gitops-deploy.yaml`](../tekton/tasks/gitops-deploy.yaml); the Jenkins / ARC / Argo Workflows equivalents mirror it) | after the ArgoCD sync, wait on the Rollout (`kubectl argo rollouts status gateway -n microservices`) instead of `kubectl rollout status`. |

Activation order: merge the controller → `Day1` → apply B3 in the GitOps repo → land B2 + B4 here (coordinated with B3). A push to `gateway` then rolls out as a weighted canary visible in the Rollouts dashboard.

#### Argo Rollouts in depth

<details>
<summary>🟢 For newcomers — what problem this solves</summary>

A plain Kubernetes `Deployment` rolls out a new version by **replacing pods**: once you bump the image, every user is on the new version within a minute. If it is broken, **everyone** is broken until you roll back.

**Progressive delivery** ships the new version to a *small slice* of traffic first, watches it, and only widens the slice if it looks healthy:

- **Canary**: run old (`stable`) and new (`canary`) side by side and move traffic gradually — e.g. 20% → (pause) → 50% → (pause) → 100%. A bad release only hits 20% of users and auto-halts.
- **Blue-green**: bring the new version up fully alongside the old, then flip 100% at once (with an instant flip-back).

**Argo Rollouts** is the controller that runs this. You swap your `Deployment` for a `Rollout` (almost the same spec, plus a `strategy:` block) and it manages two ReplicaSets (stable + canary) and the traffic split. The split is done by editing the weights on the GKE Gateway's `HTTPRoute` — the ingress that already serves the app — so there are **no sidecars and no service mesh**. You watch/promote/abort from the **Rollouts dashboard** or the `kubectl argo rollouts` CLI.
</details>

<details>
<summary>🔴 For specialists — architecture & mechanics</summary>

- **Controller**: the `argo-rollouts` controller watches `Rollout`/`AnalysisRun`/`Experiment` CRDs, owns the canary/stable **ReplicaSets** (selector-hash managed like a Deployment), and reconciles the traffic weight at each step.
- **Traffic routing — Gateway API plugin**: we register `argoproj-labs/gatewayAPI` via `controller.trafficRouterPlugins` (the controller fetches the binary on boot and records it in the `argo-rollouts-config` ConfigMap). At each `setWeight`, the plugin **patches `backendRefs[].weight`** on the named `HTTPRoute` (stable vs `*-canary` Service). That needs RBAC the chart omits — granted by [`infrastructure/argo-rollouts-gatewayapi-rbac.yaml`](../infrastructure/argo-rollouts-gatewayapi-rbac.yaml) (`update/patch` on `httproutes.gateway.networking.k8s.io`).
- **The `Rollout` spec** (replaces the `gateway` Deployment, B3):
  ```yaml
  strategy:
    canary:
      stableService: gateway
      canaryService: gateway-canary
      trafficRouting:
        plugins:
          argoproj-labs/gatewayAPI:
            httpRoute: { name: microservices, namespace: microservices }
      steps:
        - setWeight: 20
        - pause: { duration: 60 }     # or `pause: {}` to wait for a manual promote
        - setWeight: 50
        - pause: { duration: 60 }
        - setWeight: 100
  ```
- **Analysis-driven promotion (advanced)**: a step can run an `AnalysisTemplate` querying the in-cluster Prometheus (the span-metrics / HTTP RED already deployed) — e.g. abort if the canary's 5xx rate or p95 latency exceeds a threshold. The `AnalysisRun` gates the next `setWeight`; failure triggers automatic rollback (weight → 0, canary RS scaled down). No image re-pull.
- **ArgoCD interaction**: while a canary is mid-flight the `Rollout` is `Progressing`, so the owning app shows `Progressing` until promotion completes (expected). The large Rollouts CRDs use `ServerSideApply` + `compare-options: ServerSideDiff=true` (same pattern as kube-prometheus-stack / Tekton).
- **Day-2**: `kubectl argo rollouts get rollout gateway -n microservices -w`, `... promote`/`... abort`, or the dashboard. CI's `gitops-deploy` waits on Rollout health (B4) so it doesn't report success mid-canary.
</details>

<details>
<summary>📊 Argo Rollouts canary — traffic split mechanics</summary>

```mermaid
flowchart TB
  user([User traffic]):::ext --> route

  subgraph ctl[Argo Rollouts controller]
    rollout[Rollout: gateway<br/>steps: 20% → 50% → 100%]
    plugin[gatewayAPI trafficrouter plugin]
    analysis{{AnalysisRun<br/>query Prometheus<br/>5xx / p95}}
  end

  route["HTTPRoute: microservices<br/>backendRefs[].weight"]:::route

  subgraph ms[microservices namespace]
    svcS[Service: gateway<br/>stable] --> rsS[(ReplicaSet vN<br/>stable pods)]
    svcC[Service: gateway-canary] --> rsC[(ReplicaSet vN+1<br/>canary pods)]
  end

  route -->|weight 80| svcS
  route -.->|weight 20| svcC

  rollout -->|manages| rsS
  rollout -->|manages| rsC
  rollout -->|setWeight step| plugin
  plugin -->|patch weights| route
  analysis -->|fail → abort<br/>weight→0, scale down| rollout
  analysis -.->|pass → next step| rollout

  classDef ext fill:#fde,stroke:#c39;
  classDef route fill:#eef,stroke:#66c;
```

</details>

**Reading it —** the `Rollout` (replacing the `gateway` `Deployment`) owns two ReplicaSets — `stable` (vN) and `canary` (vN+1) — each behind its own Service. At every `setWeight` step the controller calls the **gatewayAPI plugin**, which patches the `backendRefs[].weight` on the shared `microservices` `HTTPRoute` — so the *existing* Gateway does the traffic split, with **no sidecar and no mesh**. An optional `AnalysisRun` queries the in-cluster Prometheus (5xx / p95); on failure it aborts → weight back to 0 and the canary RS scales down (no image re-pull).

#### Canary rollout steps (state)

<details>
<summary>📊 Canary progressive-delivery lifecycle</summary>

```mermaid
stateDiagram-v2
  [*] --> Stable: vN at 100%
  Stable --> Canary20: push vN+1 → setWeight 20
  Canary20 --> Paused20: pause (auto or manual)
  Paused20 --> Analysis: AnalysisRun 5xx / p95
  Analysis --> Aborted: metrics fail
  Analysis --> Canary50: metrics pass → setWeight 50
  Canary50 --> Canary100: pause → setWeight 100
  Canary100 --> Promoted: vN+1 is the new stable
  Aborted --> Stable: weight → 0, canary scaled down
  Promoted --> [*]
```

</details>

**Reading it —** the spine is the weighted promotion `20 → 50 → 100`, with a `pause` between steps (timed, or `pause: {}` to wait for a manual `kubectl argo rollouts promote`). The decisive branch is `Analysis`: an `AnalysisRun` gate turns a bad canary into an **automatic rollback** (`Aborted` → weight 0, canary scaled down) instead of a full-blast outage — a release only ever exposes ~20% of users to a regression. CI's `gitops-deploy` waits on Rollout health so it never reports success mid-canary.

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

Then (re-)run **Day1.cluster.01 GKE provision** to add the `roles/iap.httpsResourceAccessor` IAM binding via [`terraform/gke`](../terraform/gke/).

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

The active CI engine's UI, Microservices, ArgoCD, Headlamp, and pgAdmin can all be exposed on the public internet through a single **GKE Gateway** (`gatewayClassName: gke-l7-global-external-managed`) — one global external HTTPS load balancer, one Google-managed wildcard certificate, and one `HTTPRoute` per app:

| App | URL | Identity-Aware Proxy |
|---|---|---|
| Jenkins | `https://jenkins.<baseDomain>` | yes (only when `ci.engine=jenkins`) |
| Tekton Dashboard | `https://tekton.<baseDomain>` | yes (only when `ci.engine=tekton`) |
| Tekton PaC webhook | `https://pac.<baseDomain>` | no (GitHub webhook receiver; HMAC-protected) |
| Argo Workflows UI | `https://argo.<baseDomain>` | yes (only when `ci.engine=argoworkflows`) |
| Argo Events webhook | `https://argo-events.<baseDomain>` | no (GitHub webhook receiver; HMAC-protected) |
| Microservices | `https://microservices.<baseDomain>` | no (public demo app) |
| Microservices (develop) | `https://microservices-develop.<baseDomain>` | no (public demo app; only when `microservices.developTrackEnabled`) |
| ArgoCD | `https://argocd.<baseDomain>` | **no** (public route — ArgoCD's own Google-OIDC/dex login + RBAC is the auth) |
| Faro RUM beacon | `https://faro.<baseDomain>` | no (browser-facing otel-collector Faro receiver :8027; CORS-open, HMAC-less, always routed) |
| Headlamp | `https://headlamp.<baseDomain>` | yes |
| pgAdmin | `https://pgadmin.<baseDomain>` | yes |
| Grafana | `https://grafana.<baseDomain>` | yes (only when `observability.mode=oss`) |

> **GitHub Actions/ARC has no in-cluster UI route** — its runners are outbound-only (ARC long-polls GitHub), so nothing is exposed through the Gateway for that engine; you observe runs in GitHub's own Actions UI.

`<baseDomain>` is `gateway.baseDomain` in [`config/config.yaml`](../config/config.yaml) — `jenkins2026.nubenetes.com` by default.

**This whole feature is opt-in**: set `JENKINS2026_BASE_DOMAIN=""` to disable it. [`scripts/09-gateway.sh`](../scripts/09-gateway.sh) is also a no-op on `platform.target` other than `gke`.

<details>
<summary>📊 A request from the internet to a backend pod (Gateway + IAP)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as User (browser)
  participant GFE as Google GFE / GKE Gateway
  participant IAP as Identity-Aware Proxy
  participant HR as HTTPRoute
  participant Pod as Backend pod

  U->>GFE: HTTPS app.baseDomain (wildcard cert)
  alt host is IAP-gated (CI UI: jenkins/tekton/argo · headlamp/pgadmin · grafana-oss)
    GFE->>IAP: check session
    IAP-->>U: redirect to Google sign-in (if no session)
    U->>IAP: Google OAuth
    IAP->>IAP: email has roles/iap.httpsResourceAccessor?
    IAP-->>U: 403 if not allowed
    IAP->>HR: forward (+ X-Goog-Authenticated-User-Email)
  else public host (microservices demo · argocd (own SSO) · faro RUM beacon · CI webhook receivers pac/argo-events, HMAC-protected)
    GFE->>HR: forward directly
  end
  HR->>Pod: route to pod targetPort (jenkins 8080 / headlamp 4466)
  Note over GFE,Pod: TLS terminates at the LB — the LB→pod hop is plain HTTP<br/>(VPC-internal · Google network-layer encryption in transit)
  Pod-->>U: response
```

</details>

**Reading it —** one global external HTTPS LB terminates the wildcard cert, and a *per-host* decision follows: IAP-gated hosts must pass a Google sign-in **and** an allowlist check (`roles/iap.httpsResourceAccessor`, the same emails as `HEADLAMP_ADMIN_EMAILS`) before any traffic reaches the app — so the app's own auth (Jenkins OIDC, pgAdmin's trusted header, …) is a *second* layer, not the only one. The `microservices` host is deliberately public. Two gotchas live here: the **NetworkPolicy** ingress allow must target the pod `targetPort` (8080/4466), not the Service port the `HTTPRoute` references (80), or the GKE health check is dropped and the backend goes UNHEALTHY; and TLS ends at the LB — the LB→pod hop is plain HTTP (no `BackendTLSPolicy` re-encryption; the backends don't serve TLS).

### Authentication & Authorization Matrix

| Application | Edge-Level Authentication (GCP IAP) | App-Level Authentication | Authorization |
|---|---|---|---|
| **Jenkins** *(ci.engine=jenkins)* | Yes (Google IAP OAuth) | Google OIDC **or** local `admin` basic auth | RBAS: Default Google login = read-only; Admin email = full admin |
| **Tekton Dashboard / Argo Workflows UI** *(the other in-cluster CI engines)* | Yes (Google IAP OAuth) | IAP header is the auth — behind it both UIs are **read-write** (Tekton Dashboard deployed in `full` mode can start/cancel runs; the Argo Workflows Server runs `--auth-mode=server`, acting as its ServiceAccount) | IAP allowlist = the entire access control (GitHub Actions/ARC has no in-cluster UI) |
| **ArgoCD** | **No** (public `HTTPRoute` at `argocd.<baseDomain>`; no GCPBackendPolicy/IAP — ArgoCD's own SSO is the gate) | Google OIDC (via Dex, reusing the IAP OAuth client) **or** local `admin` secret | ArgoCD RBAC: Default OIDC = readonly; Admin email = role:admin |
| **Headlamp** | Yes (Google IAP OAuth) | Token Login (GKE OAuth access token or ServiceAccount token) | Kubernetes RBAC via GCP Identity mapping |
| **pgAdmin** | Yes (Google IAP OAuth) | Webserver Auth (trusts `X-Goog-Authenticated-User-Email` header) | Automated `.pgpass` injection for zero-password database login |
| **Microservices** | No (Public Demo App) | JWT Token verification | Spring Security Roles (`ROLE_USER`, `ROLE_ADMIN`) |

### One-time Setup

**Idempotency model.** Only **two** of the steps below are genuinely manual and
permanent — the **`NS` delegation** (step 1) and the **IAP OAuth client** (step 3).
Both live outside the per-cluster lifecycle (the permanent root tier's DNS zone in
the parent domain / a project-level OAuth client + GitHub secrets), so they survive
a `Decom`-everything — even an explicit `Decom.infra.01` gateway teardown — and are
done **once, ever**. Everything else (the static IP, certificate, the zone's `A`/`CNAME`
records, the IAP access bindings) is created/reconciled by Terraform on every
`Day0.infra.01` / `Day1.cluster.00-all` run, so a teardown + rebuild brings the public
URLs back with **no manual work**. (The delegated DNS **zone** itself is created once
by the root bootstrap and never destroyed, which is what keeps the delegation permanent.)

1. **Delegate the subdomain — one time, permanent.** The **root bootstrap** (`scripts/bootstrap.sh up`, Day0 "phase 0") creates a **permanent** delegated Cloud DNS zone for `<baseDomain>` and prints its four nameservers (`dns_zone_name_servers` output). At the **parent** domain's DNS (e.g. **Squarespace** for `nubenetes.com`), create an `NS` record set for `<baseDomain>` (host `jenkins2026`) pointing at those four nameservers. This is the **only** manual DNS step, and it is truly **once, ever**: the zone lives in the never-torn-down root tier, so its nameservers never change — not even an explicit `Decom.infra.01` gateway teardown touches them. Remove any old hand-made `*.<baseDomain>` / `_acme-challenge.<baseDomain>` records from the parent zone — the delegation supersedes them.

2. **Run the "Day0.infra.01 Gateway bootstrap" workflow** to create the global static IP, the Google-managed wildcard certificate for `<baseDomain>` and `*.<baseDomain>`, the Certificate Manager DNS authorization, and the **records inside the delegated zone** (wildcard `A` → static IP, cert-validation `CNAME`). These are re-applied on every `Day0.infra.01` / `Day1.cluster.00-all` run, so they always track the current IP — a `Decom`-everything + rebuild brings the URLs back with **no further DNS work**.

3. **Create the IAP OAuth client by hand — one time, permanent** (the Terraform resources for this are deprecated as of July 2025). In the [GCP Console](https://console.cloud.google.com/): **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID** → Application type **Web application**. The client ID/secret are project-level and outlive any cluster; the `IAP_OAUTH_CLIENT_ID`/`IAP_OAUTH_CLIENT_SECRET` GitHub secrets feed the `gateway-iap-oauth` Kubernetes Secret each rebuild (via [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh), or pushed to GCP Secret Manager and synced by External Secrets when `secrets.backend=eso`). So like the `NS` delegation, this is done once and survives `Decom`/rebuild.

   **Authorized redirect URI**:
   ```
   https://iap.googleapis.com/v1/oauth/clientIds/<client ID>:handleRedirect
   ```

   ```bash
   gh secret set IAP_OAUTH_CLIENT_ID     --body "<client ID>"
   gh secret set IAP_OAUTH_CLIENT_SECRET --body "<client secret>"
   ```

4. **IAP access control** reuses `HEADLAMP_ADMIN_EMAILS`: each listed email is granted `roles/iap.httpsResourceAccessor` via [`terraform/gke`](../terraform/gke/).

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

## Pausing & resuming the cluster (cost saving)

Park the throwaway cluster at **~zero compute cost** without a Decom + Day1 rebuild: scale every GKE node pool to **0** (the worker VMs are the bulk of the spend), leaving everything else intact, then scale back in minutes.

| Workflow | What it does |
|---|---|
| **[`Day2.scale.01 Pause`](../.github/workflows/Day2.scale.01-pause.yml)** | Scales every node pool → 0. Cluster, PVs (CNPG Postgres data), ArgoCD + apps, static IP, DNS, certs all survive — only the worker VMs go away. |
| **[`Day2.scale.02 Resume`](../.github/workflows/Day2.scale.02-resume.yml)** | Scales node pools back up; pods reschedule, ArgoCD reconciles, CNPG recreates its PDBs — no rebuild. Then runs a **post-resume recovery pass** (re-clones any unstartable CNPG replica, restarts ArgoCD dex if its OIDC connector init raced DNS — see below). |

**What still costs while paused** (all small): the zonal **control plane** (covered by the GKE free-tier management credit), the **persistent disks** backing the PVs, and the reserved **static IP**. Grafana Cloud is free-tier (nothing to pause). Azure/AWS managed backends, if ever provisioned, are billed separately and are **not** paused here.

> Pause/resume is **not** a rebuild and keeps the disks. For a full teardown that stops *all* charges use [`Decom.cluster.01-gke`](../.github/workflows/Decom.cluster.01-gke.yml); to recreate, [`Day1.cluster.01-gke`](../.github/workflows/Day1.cluster.01-gke.yml) (a re-apply also reconciles the gcloud state drift the imperative pause leaves in [`terraform/gke`](../terraform/gke/) state).

### The four gotchas a naïve "resize to 0" hits (real incident)

A plain `gcloud container clusters resize --num-nodes 0` **stalls forever / bounces back** on this cluster. There are **four independent node-recreating forces** — disabling fewer than all four leaves nodes running:

1. **CNPG Postgres PodDisruptionBudgets block the graceful drain.** Each Postgres pod has a PDB `minAvailable=1`; single-instance tiers (the `develop` tier, and any primary once it is down to one) → **ALLOWED DISRUPTIONS = 0**. The resize drains via the **eviction API**, which honours PDBs → it waits indefinitely, the `gcloud` client times out (~20 min) and the GitHub step fails while the **server-side operation stays RUNNING and wedged** (and it cannot be cancelled — only node-upgrade ops can).
2. **node-pool `autoRepair` recreates the drained nodes.** With `management.autoRepair: true`, GKE flags cordoned/drained nodes as unhealthy and **recreates** them.
3. **node-pool `autoUpgrade` surge-creates replacement nodes.** A version auto-upgrade does a surge (new nodes before draining old), re-adding nodes mid-pause.
4. **Cluster-level Node Auto-Provisioning (NAP) re-provisions nodes for the Pending pods.** ⚠️ *This is the subtle one.* NAP (`autoscaling.enableNodeAutoprovisioning`) is a **cluster** setting, **separate from a node pool's autoscaling**: for any Pending pod it can't place it spins up **brand-new nodes/pools** — so even with the node pool's own autoscaling off, NAP brings the cluster **straight back up** (node count seen bouncing to 3-4). NAP **is** Terraform-managed ([`terraform/gke`](../terraform/gke/) `enable_node_autoprovisioning`, driven by `nodeAutoProvisioning.enabled`, default true) — the pause turns it off imperatively and Resume deliberately leaves it off; like the rest of the pause's gcloud changes this is benign state drift that the next `Day1.cluster.01-gke` re-apply reconciles back on (the node pool's own min/max autoscaling, restored by Resume, carries normal operation meanwhile).

**The fix (now in the pause workflow) — disable ALL FOUR forces, then drain + resize:**

- **Delete every PodDisruptionBudget up front** — the node-pool resize runs GKE's *own* graceful drain, which respects PDBs regardless of our force-drain; if a node slips in after the drain snapshot (e.g. an in-flight auto-repair) a CNPG PDB can hang the resize for ~1h. Safe: PDBs gate only voluntary disruptions and CNPG recreates them on Resume.
- **Disable cluster NAP** (`gcloud container clusters update --no-enable-autoprovisioning`) — *first*, the root cause of the bounce-back.
- **Disable the node pool's autoscaling, autoRepair AND autoUpgrade** using specific node pool commands (`gcloud container node-pools update --no-enable-autoscaling` and `--no-enable-autorepair --no-enable-autoupgrade`) to prevent API lock conflicts.
- **Serialize GKE mutations** via the new `wait_for_gke_operations` helper function. Since GKE allows only one mutating operation at a time, the workflow blocks and waits until each in-progress operation finishes before starting the next.
- **Force-drain** every node: `kubectl drain --disable-eviction --force --delete-emptydir-data --ignore-daemonsets`. `--disable-eviction` deletes pods via the **DELETE API instead of the eviction API**, so it **bypasses PDBs entirely** — safe because the data lives on the PVs, not the pod.
- Then `gcloud container clusters resize ... --num-nodes 0` — nodes are already empty and nothing can re-add them → it completes and **stays** at 0.
- **Resume re-enables autoscaling + autoRepair + autoUpgrade** (with similar serialization and specific node-pool updates; NAP is deliberately left off — this is benign drift the next `Day1` re-apply reconciles back on, see gotcha 4).

<details><summary>🔁 Pause / resume sequence (Mermaid)</summary>

```mermaid
flowchart TD
  subgraph Pause["⏸️ Day2.scale.01 Pause"]
    P0["Disable cluster NAP<br/>--no-enable-autoprovisioning"] --> P1["Disable pool autoscaling<br/>+ autoRepair + autoUpgrade"]
    P1 --> P3["Force-drain all nodes<br/>kubectl drain --disable-eviction<br/>(bypasses CNPG PDBs)"]
    P3 --> P4[Resize each pool to 0]
    P4 --> P5["Nodes 0 - STAYS 0<br/>(all 4 recreate-forces off)<br/>workloads Pending"]
  end
  subgraph Resume["▶️ Day2.scale.02 Resume"]
    R1[Resize each pool to N] --> R2["Re-enable autoscaling +<br/>autoRepair + autoUpgrade<br/>(NAP left off — drift; next Day1 re-adds)"]
    R2 --> R3[Pods reschedule]
    R3 --> R4[ArgoCD reconciles - CNPG recreates PDBs]
    R4 --> R5["Post-resume recovery<br/>re-clone stuck CNPG replicas<br/>+ restart dex if connector init raced DNS"]
  end
  P5 -. "minutes later" .-> R1
```

</details>

> **Manual recovery (interrupted / partial pause).** If a pause is interrupted, or you run the
> steps by hand and the cluster won't reach 0, **do NOT fire several `gcloud container clusters
> resize --num-nodes 0` back-to-back** — each queues a separate node-pool operation and they
> **fight** (one stalls draining a CNPG primary behind its PDB while another reconciles nodes back),
> so the count keeps churning (seen bouncing 0→2→3).
> 
> _Note: The automated pause/resume workflows now include a `wait_for_gke_operations` helper that
> automatically checks and waits for any pending/running GKE operations to avoid these conflicts._
> 
> Recover deterministically, once:
> 1. Confirm **all four** recreate-forces are off — `gcloud container clusters describe …` →
>    `autoscaling.enableNodeAutoprovisioning` empty (NAP), and `… node-pools describe …` →
>    `autoscaling`/`management.autoRepair`/`management.autoUpgrade` all empty.
> 2. `kubectl drain <node> --disable-eviction --force --ignore-daemonsets --delete-emptydir-data` every node (DELETE bypasses the CNPG PDBs).
> 3. **Wait until `gcloud container operations list --filter='status=RUNNING'` is empty** — a wedged
>    `SET_NODE_POOL_SIZE` can't be cancelled; let it finish before issuing anything new.
> 4. Issue **one** `gcloud container clusters resize … --num-nodes 0` and let its operation complete.
>
> A concurrent **`UPGRADE_MASTER`** op (control-plane auto-upgrade, cluster `RECONCILING`) is harmless
> — it never creates worker nodes, so the pool stays at 0.

<details><summary>🗺️ What pause removes vs what survives (dependency map)</summary>

```mermaid
graph LR
  Pause["Day2.scale.01 Pause"]
  Pause -->|neutralise first| B1["CNPG Postgres PDBs<br/>force-drain --disable-eviction"]
  Pause -->|neutralise first| B2["node autoRepair<br/>disabled"]
  Pause -->|removes| M1["node pool MIG to 0"]
  M1 --> M2["worker VMs deleted<br/>(approx the whole compute bill)"]
  Pause -.->|untouched, survives| S1["GKE control plane"]
  Pause -.->|untouched, survives| S2["PVs / CNPG Postgres data"]
  Pause -.->|untouched, survives| S3["ArgoCD + all apps<br/>(Pending until resume)"]
  Pause -.->|untouched, survives| S4["static IP - DNS - certs"]
  Pause -.->|external, free-tier| S5["Grafana Cloud"]
```

</details>

### The resume-side gotcha: one-time init races DNS on fresh nodes (real incident)

A resume brings up **brand-new nodes**. For a short window after they go Ready, CoreDNS + the egress path are still converging (Dataplane V2 / WireGuard re-establishing). Workloads that run a **one-time startup init and never retry it** can run that init inside this window, fail, and stay broken even though the pod looks `Running`/`Ready`. Two cases were hit and are now auto-healed by the **post-resume recovery step** in `Day2.scale.02 Resume`:

1. **CNPG replicas left unstartable by the pause's force-drain.** The `--disable-eviction` DELETE that bypasses the PDBs is ungraceful, so a replica's data dir can come back in a state the instance-manager can't start postgres from — the **startup probe fails with HTTP 500 forever** (zero postgres logs; the operator just keeps polling and seeing `connection refused` on the local socket). Fix = **re-clone the replica**: delete its PVCs (data + WAL) + pod, and the operator re-bootstraps it via `pg_basebackup` from the primary. The step does this **only for replicas** — the current primary (`.status.currentPrimary`) is never auto-recreated (it holds the authoritative data; a stuck primary is surfaced as a `::warning::` for manual handling). A grace window lets genuinely-still-starting replicas settle first, so a healthy resume is a no-op.

2. **ArgoCD dex's OIDC connector init.** dex dials the SSO provider's `/.well-known/openid-configuration` **once at startup**; if DNS/egress wasn't ready it logs `failed to open all connectors` / `failed to initialize server`, never retries, and **doesn't listen on `:5556`** — so SSO login fails with `dial tcp …:5556: connect: connection refused` (note: the pod still reports `Ready`, so the readiness probe doesn't catch this). dex is stateless (`storage=memory`), so the step **restarts the deployment** (only when that failure is actually in its log) and it re-inits cleanly.

> Both are **idempotent** — on a clean resume nothing matches and the step is a no-op. They exist because the failing inits don't self-retry; everything else (app Deployments, the CNPG primary, ArgoCD's other components) reconciles on its own once nodes return.

Related lifecycle: [`Day1.cluster.01-gke`](../.github/workflows/Day1.cluster.01-gke.yml) (provision / reconcile drift), [`Decom.cluster.01-gke`](../.github/workflows/Decom.cluster.01-gke.yml) (full teardown). Full workflow inventory: [101](./101-GITHUB_ACTIONS_WORKFLOWS.md).

---

[← Previous: 405. Argo Workflows](./405-ARGO_WORKFLOWS.md) | [🏠 Home](../README.md) | [→ Next: 502. Microservices GitOps](./502-MICROSERVICES_GITOPS.md)

---

*501. Platform Operations — jenkins-2026*
