# Runbook: validate GKE Node Auto-Provisioning → Spot CI nodes (and read the `SSD_TOTAL_GB` ceiling)

Validates, end-to-end on a live cluster, that **GKE Node Auto-Provisioning (NAP)** + the
**`ci-spot` Custom ComputeClass** provision **Spot, scale-to-zero** nodes for Jenkins/Tekton
build agents on demand — and teaches how to read the one limit that actually bounds it in
practice: the **regional `SSD_TOTAL_GB` quota**. Written from a real Day1 + builds run; the
node listings and events below are verbatim from that run.

> Conceptual background lives in [201. Architecture](../201-ARCHITECTURE.md) (the static-pool
> vs NAP split) and [501. Platform Operations](../501-PLATFORM_OPERATIONS.md) §"Elastic Node
> Auto-Provisioning". This runbook is the **operational** companion: how to *see* it work and
> how to diagnose it when an agent stays `Pending`.

## Background — what should happen

- Cluster-level NAP is enabled in [`terraform/gke`](../../terraform/gke) (the
  `cluster_autoscaling` block, var `enable_node_autoprovisioning`, default true). It is the
  GA, Google-native equivalent of Karpenter (there is no production-ready Karpenter provider
  for GCP).
- The Custom ComputeClass [`infrastructure/compute-classes/ci-spot.yaml`](../../infrastructure/compute-classes/ci-spot.yaml)
  (`nodePoolAutoCreation.enabled: true`, **Spot-first** priorities `c3`/`n2`/`c2`/`e2` →
  on-demand `e2`) tells NAP what to build. GKE auto-labels + taints the pools it creates with
  `cloud.google.com/compute-class=ci-spot:NoSchedule` (+ `cloud.google.com/gke-spot=true:NoSchedule`
  for Spot).
- The CI build agents target the class via `nodeSelector: cloud.google.com/compute-class: ci-spot`
  + matching tolerations, emitted **only when** the controller env `GKE_COMPUTE_CLASS` is set
  (surfaced through `jenkins-credentials` → JCasC from the `nodeAutoProvisioning.enabled` flag).
  The **static** `jenkins-2026-pool` keeps the long-lived platform; no platform Pod targets the
  class, so NAP is never on the provision's critical path.

**Expected lifecycle of one build:** agent Pod created → unschedulable on the static pool
(nodeSelector) → NAP creates a Spot node group (0→1) → node joins → agent lands and runs →
build finishes → node idles → NAP consolidates it away (back toward zero).

## 0. Get cluster access (the gotchas, in order)

The control plane is public-endpoint but you still hit three Windows/SDK papercuts:

1. **`gke-gcloud-auth-plugin` missing** → `kubectl` errors with *"client-go credential plugin
   not installed"*. If you can't install it cleanly, **bypass the exec plugin** with a bearer
   token (it still uses the kubeconfig's CA + server):
   ```bash
   kubectl --token="$(gcloud auth print-access-token)" get nodes
   ```
2. **gcloud grabs the wrong Python on Windows** (the WindowsApps `python3` stub → *Permission
   denied*). Point it at the SDK's bundled interpreter:
   ```bash
   export CLOUDSDK_PYTHON="$HOME/AppData/Local/Google/Cloud SDK/google-cloud-sdk/platform/bundledpython/python.exe"
   ```
3. **Stale control-plane IP after a rebuild** → `kubectl` times out (`dial tcp <old-ip>:443`).
   A Decom+Day1 (or cluster recreation) gives the API server a **new** public IP; the kubeconfig
   keeps the old one. Refresh it:
   ```bash
   gcloud container clusters get-credentials jenkins-2026 --zone europe-southwest1-a
   ```
   (Confirm the live endpoint with `gcloud container clusters describe … --format='value(endpoint)'`.)

## 1. Confirm the flag reached Jenkins (no build needed)

```bash
kubectl -n jenkins get secret jenkins-credentials -o jsonpath='{.data.gke-compute-class}' | base64 -d
# → ci-spot   (empty here means NAP is disabled → agents would use the static pool)
```

## 2. Trigger a build and watch the agent + node

Trigger a pipeline (Jenkins UI → e.g. the `gateway` job, or push to a service repo). Then:

```bash
# the agent Pod must carry the ComputeClass nodeSelector:
kubectl -n jenkins get pods -l jenkins=slave -o wide
kubectl -n jenkins get pod <agent> -o jsonpath='{.spec.nodeSelector}'   # → {"cloud.google.com/compute-class":"ci-spot"}

# NAP should bring up a Spot node labelled with the class (use -L, NOT custom-columns —
# escaping the dotted label key in custom-columns prints <none> and misleads you):
kubectl get nodes -L cloud.google.com/gke-spot,cloud.google.com/compute-class
```

**What "good" looks like** (verbatim from the live run — two builds running on Spot):

```
NAME                                                  STATUS  AGE    GKE-SPOT  COMPUTE-CLASS
gke-jenkins-2026-jenkins-2026-pool-3c1e2dc8-gcjz      Ready   58m                            ← static pool (platform)
gke-jenkins-2026-jenkins-2026-pool-3c1e2dc8-j5tx      Ready   58m
gke-jenkins-2026-nap-e2-standard-2-ms-0291c534-sxcm   Ready   61m                            ← NAP on-demand: platform overflow
gke-jenkins-2026-nap-n2-standard-4-sp-5708c3d9-cn4l   Ready   7m     true      ci-spot       ← NAP Spot: CI agent
gke-jenkins-2026-nap-n2-standard-4-sp-5708c3d9-jgtr   Ready   7m     true      ci-spot       ← NAP Spot: CI agent
```

```
# agents (9/9 = all build containers up) running ON the Spot nodes:
jhipstersamplemicroservice-1-…        9/9  Running  …  gke-…-nap-n2-standard-4-sp-…-jgtr
jhipstersamplemicroservice-develop-1-…9/9  Running  …  gke-…-nap-n2-standard-4-sp-…-cn4l
```

Two takeaways worth internalizing:
- NAP also auto-provisioned an **on-demand** `e2-standard-2` node for *platform* overflow
  (ArgoCD/Argo-Rollouts/CNPG that didn't fit the 2-node static pool) — i.e. NAP doubles as a
  general cluster autoscaler; only the **ComputeClass** workloads get **Spot** nodes.
- The Spot nodes are `n2-standard-4`, matching the ComputeClass's Spot-first `n2` priority.

## 3. The real ceiling: `SSD_TOTAL_GB` quota (the part everyone trips on)

In the live run a **third** concurrent build (`gateway`) stayed `Pending`. NAP was doing the
right thing — repeatedly trying to scale up, across machine families — but **GCE refused every
disk**:

```
TriggeredScaleUp  …  nap-n2-standard-4-sp-…  2->3
ScaleUpFailed     …  Quota 'SSD_TOTAL_GB' exceeded. Limit: 500.0 in region europe-southwest1
NotTriggerScaleUp …  Pod didn't trigger scale-up: 1 in backoff after failed scale-up
```

**Why a *disk* quota bounds *node count*:** every node's boot disk is `pd-balanced`, and
`pd-balanced` (an SSD-backed type) counts against the regional **`SSD_TOTAL_GB`** quota. So the
number of *concurrent* nodes is bounded by:

```
SSD_TOTAL_GB  ≥  Σ(node boot disks)  +  Σ(CNPG Postgres PVs and any other pd-ssd/pd-balanced PVCs)
```

**The math that bit us — and how the disk fix changes it.** With the original NAP default of
**100 GB/node** (vs the static pool's 50):

| Disk consumer | Before (100 GB NAP) | After fix (50 GB NAP) |
|---|---|---|
| Static pool (2 × 50) | 100 | 100 |
| NAP on-demand e2 (platform) | 100 | 50 |
| 2× NAP Spot n2 (CI agents) | 200 | 100 |
| CNPG Postgres PVs (stable HA + develop) | ~50–100 | ~50–100 |
| **Total vs 500 GB quota** | **~450–500 → 3rd node refused** | **~300–350 → room for more** |

The fix ([PR #405](https://github.com/nubenetes/jenkins-2026/pull/405)) sets NAP
`auto_provisioning_defaults.disk_size = var.disk_size_gb` (50, same as the static pool) in
[`terraform/gke/main.tf`](../../terraform/gke/main.tf). Ephemeral CI nodes cache images on the
host but keep **no persistent data**, so 50 GB is ample — and halving the boot disk roughly
**doubles** how many concurrent Spot CI nodes fit under the same 500 GB quota.

> **After the fix, the observed behaviour changes:** with 50 GB NAP nodes the third concurrent
> Spot node fits where it previously didn't. The *failure mode* is unchanged (it's still the
> `SSD_TOTAL_GB` quota), just reached at a higher node count. For genuinely more headroom,
> request an `SSD_TOTAL_GB` increase in the region — that is a **GCP project quota**, unrelated
> to the code; the disk right-sizing only stretches the existing budget.

**Important nuance — the fix is not retroactive.** `terraform apply` updates the NAP *defaults*;
nodes already created keep their old 100 GB disk. On an existing cluster, a `Pending` third
agent unblocks the moment one of the running builds finishes (its Spot node frees up and the
pending agent lands there, within quota) — you don't need to intervene. The new 50 GB sizing
applies to nodes NAP creates **after** the next Day1.

## 4. Cold-start caveat — the first build on a fresh Spot node is slow

The agent-image **prepull DaemonSet** that warms the ~9 agent container images
(maven/node/dind/helm/git/semgrep/codeql/trivy/jnlp) runs on the **static pool**, and does
**not** tolerate the `compute-class`/`gke-spot` taints — so it does **not** warm the Spot
nodes. The first build on a freshly auto-provisioned Spot node therefore pays: NAP node
creation (~1–3 min) + node join + a **cold pull of every agent image** (several minutes). Budget
**10–15+ min for the first build**; it is not stuck. (Future option: give the prepull DaemonSet
tolerations for the `ci-spot` taints, or accept the cold start — it's ephemeral CI.)

## Why the "CI-CD / Node Auto-Provisioning (Spot)" dashboard has data even on the free tier

The dashboard ([`observability/grafana/dashboards/node-autoprovisioning.json`](../../observability/grafana/dashboards/node-autoprovisioning.json))
counts nodes from kube-state-metrics. That collides with the free-tier `leanMetrics` profile,
which trims the high-cardinality cluster-infra metrics — so the naive version would show **No
data** in `grafana-cloud` mode. Two deliberate choices make it work in **every** mode instead:

1. **Read taints, not labels.** The panels query
   `kube_node_spec_taint{key="cloud.google.com/gke-spot"}` and
   `…{key="cloud.google.com/compute-class",value="ci-spot"}`. KSM emits `kube_node_spec_taint`
   **by default**. The intuitive alternative, `kube_node_labels{label_cloud_google_com_gke_spot="true"}`,
   does **not** work out of the box: KSM only populates the `label_*` dimensions of
   `kube_node_labels` when started with `--metric-labels-allowlist=nodes=[…]`, which we don't
   set. GKE auto-applies the `gke-spot` / `compute-class` taints to the pools NAP creates, so
   the taint metric is a reliable, zero-config signal.
2. **A node-inventory allow-list survives lean mode.** [`scripts/03-observability.sh`](../../scripts/03-observability.sh)
   does **not** disable cluster metrics wholesale in lean mode — it keeps kube-state-metrics
   deployed and scrapes **only** `kube_node_info`, `kube_node_labels`, `kube_node_spec_taint`
   and `kube_node_status_condition` (`clusterMetrics.kube-state-metrics.metricsTuning.useDefaultAllowList: false`
   + `includeMetrics`). That's ~30–50 series total — negligible against the 15k free-tier cap —
   while cadvisor/kubelet/node-exporter stay off. (`kube_node_labels` carries
   `label_node_kubernetes_io_instance_type`, the only cluster-wide source of a node's **machine
   type** for static-pool nodes — NAP node names embed it, static `…-pool-…` names don't. KSM
   already exposes that label via the chart's default `--metric-labels-allowlist`, so only the
   scrape keep-list needed it; the chart/KSM is untouched.)

So if the dashboard is empty, it is **not** the lean profile: check that the `kube-state-metrics`
Pod is `Running`, that the `k8s-monitoring-alloy` collector is up, and — most likely — that a
**build has actually triggered a Spot node** (no Spot nodes = the count is legitimately 0). The
panels use `or vector(0)`, so an empty result renders **0**, not "No data".

## Troubleshooting — agent stuck `Pending`

```bash
kubectl -n jenkins describe pod <agent> | sed -n '/Events:/,$p'
kubectl get events -A --sort-by=.lastTimestamp | grep -iE "scale|quota|FailedScheduling" | tail -20
```

| Event / symptom | Cause | Fix |
|---|---|---|
| `ScaleUpFailed … Quota 'SSD_TOTAL_GB' exceeded` | regional SSD disk quota full (§3) | wait for a running build to free a node; right-size NAP disk (this PR); request `SSD_TOTAL_GB` increase |
| `FailedScheduling … didn't match Pod's node affinity/selector` **and** no `TriggeredScaleUp` | NAP can't satisfy the ComputeClass (e.g. no priority matches) or NAP disabled | check `enable_node_autoprovisioning` + the ComputeClass priorities; `kubectl get computeclass ci-spot -o yaml` |
| agent has **no** `nodeSelector` for `compute-class` | `GKE_COMPUTE_CLASS` empty → flag off, or the JCasC chain didn't propagate | §1; confirm `nodeAutoProvisioning.enabled: true` and re-run `04-jenkins.sh` (`Day2.redeploy.02-jenkins`) |
| Pod `Pending` for minutes on a **new** Spot node, image pulls | cold-start (§4), not a fault | wait; it's the first-build tax |
| `gateway` etc. `ImagePullBackOff` after deploy | the service image isn't built yet (first run) | run the build; see the README "First run note" |

## Cost / cleanup

Spot nodes consolidate to zero a few minutes after builds finish (`consolidationDelayMinutes: 5`
in the ComputeClass), so idle cost is near zero. When you're done with the whole cluster, run
**`Decom.cluster.01-gke`** (or `down.sh`) to stop charges — NAP nodes go with the cluster, and
`down.sh` removes the ComputeClass first so nothing re-provisions mid-teardown.
