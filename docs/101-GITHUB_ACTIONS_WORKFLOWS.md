[← Previous: 100. Bootstrap](./100-BOOTSTRAP.md) | [🏠 Home](../README.md) | [→ Next: 102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md)

---

# 101. GitHub Actions Workflows

All workflows live in [`.github/workflows/`](../.github/workflows/), are manually-triggered (`workflow_dispatch`), and follow a `DayN.tier.ZZ-resource.yml` naming convention whose **alphabetical sort order in the GitHub Actions UI is the correct execution order** for every phase of the lifecycle.

## Understanding the workflow scheme (newcomers → specialists)

<details>
<summary>🧠 Mental model — the DayN workflow scheme (mindmap)</summary>

```mermaid
mindmap
  root((DayN workflows))
    Naming DayN.tier.ZZ
      DayN lifecycle phase
      tier semantic word
      ZZ per-resource id
      alphabetical = run order
    Phases
      Day0 bootstrap
      Day1 cluster
      Day2 ops
      Decom teardown
    Orchestration
      concurrency jenkins-2026-gke
      workflow_call reuse
      umbrellas up and down
    Approval gates
      five environments
      required reviewers
```

</details>

**Reading it —** the workflow inventory decoded in one picture: the **naming** (`DayN.tier.ZZ` — the prefix sorts the Actions UI into execution order), the four lifecycle **phases**, the **orchestration** (one shared concurrency group so runs queue instead of racing on Terraform state; reusable `workflow_call`; the one-click umbrellas), and the **approval gates**. The tables below are each of these in full.

<details>
<summary>🟢 For newcomers — what the filenames tell you</summary>

Every workflow is named `DayN.tier.ZZ-resource`, and that name is a tiny runbook:

- **`DayN` = lifecycle phase** (SRE Day-0/1/2 terminology): `Day0` = one-time persistent bootstrap (WIF, the Gateway IP/cert, observability backends) · `Day1` = create the throwaway GKE cluster + full stack · `Day2` = operations on a **running** cluster (redeploy a component, publish dashboards, run traffic) · `Decom` = teardown. `Decom` sorts after `Day2`, so teardown always lands last.
- **`tier` = a short word for the group within the phase** (`infra`, `cluster`, `redeploy`, `publish`, `traffic`, `scale`, `registry`) — a readable label, not a number.
- **`ZZ` = a per-resource id** that stays the same across phases: `03` is always Azure (`Day0.infra.03` → `Day2.publish.03` → `Decom.infra.03`), so you can follow one resource through its whole life by the suffix.

The punchline: **GitHub sorts the Actions sidebar by each workflow's `name:`, every `name:` starts with its `DayN.tier.ZZ` prefix, so reading the list top-to-bottom _is_ the order to run things** — Day0 → Day1 → Day2 → Decom (cluster before backends). No separate runbook needed.
</details>

<details>
<summary>🔴 For specialists — the mechanics behind the scheme</summary>

- **Controlled `tier` vocabulary**: `infra` (persistent Day0/Decom) · `cluster` (the GKE cluster) · `redeploy` (re-apply one component) · `publish` (push dashboards/alerts) · `traffic` (k6) · `scale` (pause/resume the node pools to park the cluster at ~zero cost) — deep-dive + the PDB/autoRepair gotchas in [501 § Pausing & resuming](./501-PLATFORM_OPERATIONS.md#pausing--resuming-the-cluster-cost-saving) · `registry` (prune old container image versions from ghcr). The tier-then-`ZZ` order is a real dependency chain in **Create** (`Day0.infra` before `Day1.cluster`) and **Decom** (`cluster` before `infra`), but in **Day2** the tiers are independent *categories*, not stages — nothing chains them.
- **GKE serialization**: every cluster-touching leaf workflow (`Day1.cluster.01`, `Decom.cluster.01`, and the `Day2.*` that act on the cluster) shares `concurrency: group: jenkins-2026-gke`, so GitHub **queues** them instead of letting two runs race the same Terraform state.
- **Reusable workflows + umbrellas**: `Day1.cluster.01` `workflow_call`s the matching `Day0.infra.0{2,3,4}` backend bootstrap as a preflight; the two opt-in umbrellas (`Day1.cluster.00` "Everything up" / `Decom.infra.00` "Everything") orchestrate the leaves via `workflow_call` with **no `concurrency:` of their own** (or they would deadlock holding the group their own child job needs).
- **Per-resource approval gates**: each persistent Day0 resource has its own required-reviewer GitHub Environment (`gateway-bootstrap`, `grafana-cloud-bootstrap`, `azure-bootstrap`, `aws-bootstrap`); the cluster + the **provisioning/teardown** Day2 use `gke-production`. The gate travels with the reusable workflow, so every entry point inherits the same single approval. **Exceptions (no gate):** `Day2.traffic.01-k6` drives only read-only HTTP traffic against the already-running public endpoints (provisions/destroys nothing, all secrets repo-level), so its gate was removed to unblock automation/scheduling; the `Day2.scale.*` pause/resume workflows only resize node pools. See [102 § Environment Protection](./102-GITHUB_ACTIONS_AUTOMATION.md#environment-protection-and-manual-approvals).
- **Cross-cutting `log_level` input**: every dispatchable workflow exposes a `log_level` dropdown (`info` default | `debug`); reusable workflows mirror it as a `workflow_call` input and the umbrellas/preflights pass it down. It exports `JENKINS2026_LOG_LEVEL` (drives `log_debug` in the scripts) and `TF_LOG=DEBUG` for the Terraform steps (only at `debug`). There is **no `trace`/`set -x` level** by design — bash xtrace would leak script-derived secret values GitHub doesn't mask; use the native `ACTIONS_STEP_DEBUG` for runner-level tracing. Durable default lives in `config.yaml` (`logging.level`).
  - **Don't confuse it with the observability volume knobs** on the same workflows (`Day1.cluster.01-gke` + the `Day1.cluster.00-all` umbrella, and the lighter `Day2.redeploy.01-argocd` / `Day2.publish.01-oss-grafana`): **`grafana_cloud_tier`** (`free` default | `paid`) is a profile that sets the free-tier-fitting defaults, and **`log_min_severity`** (`auto` default → derives from tier; or force a level) is the `otel-collector-logs` `filter` that trims **Grafana's logs panels** (app + platform). Both are unrelated to the CI run's chattiness. The tier governs **metrics** (`leanMetrics`) **and logs** (`logMinSeverity`) today (not traces yet). Durable defaults in `config.yaml` `observability.{grafanaCloudTier,leanMetrics,logMinSeverity}`; see [301 § Log Levels](./301-OBSERVABILITY.md#log-levels).
- **No auto-chaining**: every workflow is `workflow_dispatch`-only (no `workflow_run:`), so a human reviews each phase — critical for `Decom`, where an automatic trigger on a failed cluster teardown could cascade into destroying persistent backends.
</details>

## Branch protection & GitFlow promotion (both repos)

This PoC spans **two** repos with **deliberately opposite** `main` branch-protection policies. Both are documented here (and mirrored in the GitOps repo's `README`) because getting either wrong silently breaks things — a too-strict GitOps `main` wedges every deploy, while a too-loose infra `main` lets unreviewed changes bypass GitFlow.

### `jenkins-2026` (this repo) — strict GitFlow, human-reviewed

`main` is reachable **only via a pull request from `develop`**. Actual `main` protection (GitHub → Settings → Branches):

| Setting | Value | Why |
| :--- | :--- | :--- |
| Require a pull request before merging | **on** (0 required approvals) | No direct pushes to `main`; a PR is mandatory. 0 approvals because this is a single-maintainer PoC — the gate is the *check*, not a reviewer count. |
| Required status check | **`gitflow-guard`** | [`gitflow-guard`](../.github/workflows/gitflow-guard.yml) fails any PR into `main` whose head branch is not exactly `develop`. This is what forbids `feature/*` / `hotfix/*` / fork → `main`. |
| Include administrators (`enforce_admins`) | **on** | Even repo admins cannot bypass the PR + check (no "merge without waiting"). |
| Allow force pushes | **off** | `main` history is append-only. |
| Allow deletions | **off** | `main` cannot be deleted. |

- **Allowed → `main`:** a PR from `develop`, after `gitflow-guard` passes.
- **Forbidden → `main`:** direct push (any actor, incl. admin); a PR from `feature/*`, `hotfix/*`, a fork, or any branch ≠ `develop`; force-push; branch deletion.

**The GitFlow loop in practice:**
1. Branch off `develop` (e.g. `feat/...`), commit, open a PR **into `develop`** (never directly into `main`).
2. Merge to `develop` and validate there (a `Day1` dispatched from `develop` auto-tracks develop's shared library/seed via `GITHUB_REF_NAME`).
3. Open a **`develop` → `main`** promotion PR; `gitflow-guard` passes (head is `develop`); merge.

### `jenkins-2026-gitops-config` (GitOps config) — CI-writable, machine-managed

`main` is **direct-push** (no PR required). Actual `main` protection:

| Setting | Value | Why |
| :--- | :--- | :--- |
| Require a pull request before merging | **off** | The Jenkins **GitOps Update** stage pushes image-tag bumps straight to `main` (`git push origin main`). Require-PR would reject the PAT push (an admin PAT does **not** bypass protection) and **wedge every deploy**. |
| Required status checks | **none** | Image-tag bumps are machine-generated — nothing to gate them on. |
| Include administrators | **off** | — |
| Allow force pushes | **off** | Still protected against history rewrites / accidental clobber. |
| Allow deletions | **off** | `main` cannot be deleted. |

- **Allowed → `main`:** direct push (the CI's PAT, or a human pushing a chart/values edit).
- **Forbidden → `main`:** force-push, branch deletion.

> ⚠️ **Do NOT enable "Require a pull request" on the GitOps repo's `main`.** It is the single most common way to break this PoC: the next pipeline's *GitOps Update* push is rejected, no image tag lands, and ArgoCD silently keeps deploying the old tag. To human-review chart/values changes, do it via the PR-on-`jenkins-2026` flow that authored them — not by gating the GitOps `main`.

### Why opposite policies (best practice, not an oversight)

The **infra repo is human-authored** (scripts, Terraform, Helm values, docs) → it deserves strict GitFlow + review-gating. The **GitOps repo is machine-managed** (image tags written by CI on every successful build) → its `main` must accept unattended CI writes. "Harmonising" them either way breaks one side. See [`CLAUDE.md` § Conventions](../CLAUDE.md), [`502`](./502-MICROSERVICES_GITOPS.md), and the GitOps repo's `README`.

## Naming convention: `DayN.tier.ZZ-resource`

Each component of the filename encodes a different dimension of the workflow's role:

| Component | Values | Meaning |
|---|---|---|
| **DayN** | `Day0` `Day1` `Day2` `Decom` | **Lifecycle phase** (SRE Day-0/1/2 terminology) — self-documenting; see [Day-0/1/2 operations](#day-0--day-1--day-2-operations) below. `Decom` sorts after `Day2`, so teardown always lands last. |
| **tier** | `infra` `cluster` `redeploy` `publish` `traffic` `scale` `registry` | **Execution group within the phase** — a brief semantic word (controlled vocabulary) replacing the old middle digit. |
| **ZZ** | `00`–`05` | **Resource identifier** — stable for the same resource across all phases (`00` = umbrella). |
| **resource** | `gateway`, `gke`, `jenkins`, … | **Identifies the resource only** — no action verb (the `DayN` prefix already says bootstrap/publish/teardown). |

### Why this scheme sorts correctly

The GitHub Actions sidebar sorts by each workflow's `name:` field, and every `name:` begins with its `DayN.tier.ZZ` prefix. Reading the list top-to-bottom therefore **is** the runbook:

- `Day0` (persistent bootstrap) → `Day1` (cluster) → `Day2` (running-cluster ops) → `Decom` (teardown).
- Within a phase, `tier` then `ZZ` order the steps. Creation order is foundational-first (`Day0.infra` before `Day1.cluster`); teardown inverts it (`Decom.cluster` before `Decom.infra`) because the cluster depends on the persistent backends and must be destroyed first.

> **Scope of the "tier orders the steps" rule.** This sequencing holds for the **Create** (`Day0`→`Day1`) and **Decom** (`cluster`→`infra`) phases, where the tier order *is* a real dependency chain. It does **not** apply within **Day2**: there the tiers (`redeploy`, `publish`, `traffic`) are independent **categories**, not ordered stages — see [Day2 ordering: tiers are categories, not stages](#day2-ordering-tiers-are-categories-not-stages).

### Resource identifier (ZZ): stable across all phases

`ZZ` is the **stable identity of a resource**. Given `ZZ=03` (Azure) you can find all its workflows across the lifecycle by the suffix alone:

| ZZ | Resource | Day0 (bootstrap) | Day2 (ops) | Decom (teardown) |
|---|---|---|---|---|
| `01` | Gateway (static IP + cert) | `Day0.infra.01-gateway` | — | `Decom.infra.01-gateway` |
| `02` | Grafana Cloud stack | `Day0.infra.02-grafana-cloud` | `Day2.publish.02-grafana-cloud` | `Decom.infra.02-grafana-cloud` |
| `03` | Azure Managed Grafana | `Day0.infra.03-azure-grafana` | `Day2.publish.03-azure-grafana` | `Decom.infra.03-azure-grafana` |
| `04` | AWS AMG | `Day0.infra.04-aws-grafana` | `Day2.publish.04-aws-grafana` | `Decom.infra.04-aws-grafana` |
| `01` | GKE cluster | `Day1.cluster.01-gke` | — | `Decom.cluster.01-gke` |
| `01` | ArgoCD (CD engine) | *(by `Day1.cluster.01`)* | `Day2.redeploy.01-argocd` | *(by `Decom.cluster.01`)* |
| `02` | Jenkins | *(by `Day1.cluster.01`)* | `Day2.redeploy.02-jenkins` | *(by `Decom.cluster.01`)* |
| `03` | Tekton (CI engine, alt to Jenkins) | *(by `Day1.cluster.01` with ci_engine=tekton)* | `Day2.redeploy.03-tekton` | *(by `Decom.cluster.01`)* |
| `04` | Headlamp | *(by `Day1.cluster.01`)* | `Day2.redeploy.04-headlamp` | *(by `Decom.cluster.01`)* |
| `01` | OSS Grafana stack | *(by `Day1.cluster.01` via ArgoCD)* | `Day2.publish.01-oss-grafana` | *(by `Decom.cluster.01`)* |
| `05` | Grafana alerts | *(by `Day1.cluster.01`)* | `Day2.publish.05-alerts` | — |
| `01` | k6 traffic | — | `Day2.traffic.01-k6` | — |
| `02` | Synthetic RUM (Faro beacons) | — | `Day2.traffic.02-rum` | — |
| `01` | Cluster pause (nodes → 0) | — | `Day2.scale.01-pause` | — |
| `02` | Cluster resume (nodes back up) | — | `Day2.scale.02-resume` | — |
| `01` | Container registry retention (ghcr prune) | — | `Day2.registry.01-image-retention` | — |

*The same `ZZ` is reused across different `tier`s (e.g. `infra.01` is the Gateway, `cluster.01` is GKE, `redeploy.01` is ArgoCD); read `tier`+`ZZ` together. Within the `redeploy` tier `ZZ` follows install order — ArgoCD (`01`, the CD engine that deploys the rest), Jenkins (`02`), Tekton (`03`), Headlamp (`04`), Gateway/ingress (`05`) — so ArgoCD sorts first. Jenkins (`02`) and Tekton (`03`) are the two mutually-exclusive CI engines selected by the `ci.engine` flag (Jenkins default); only the active one is provisioned.*

> **CI engine choice.** `Day1.cluster.01-gke` has a `ci_engine` input (`jenkins` default | `tekton`) that flows to [`scripts/up.sh`](../scripts/up.sh) as `JENKINS2026_CI_ENGINE`, selecting which CI engine the provision installs. The `redeploy` tier therefore holds `01` ArgoCD, `02` Jenkins, `03` Tekton, `04` Headlamp — `02` and `03` are mutually-exclusive engines. See [403. Tekton](./403-TEKTON.md) for the deep-dive.

> **Full-teardown umbrella.** `Decom.infra.00` ("Everything") is an opt-in convenience workflow that tears down the GKE cluster **and** every persistent observability backend in one dispatch — so switching `observability.mode` around never leaves a forgotten, billed backend (e.g. an orphaned Grafana Cloud stack from before you moved to managed-azure). It reuses each per-resource Decom workflow via `workflow_call` (no teardown logic is duplicated); type `destroy` to confirm. The cluster runs first (its decom also destroys the ephemeral `grafana-cloud-token` that references the Grafana Cloud stack), then the backends in parallel. The three backend checkboxes default **on**; the Gateway static IP defaults **off** (keeping it avoids losing the IP and re-propagating DNS). Untick any to spare it.

---

## Full workflow matrix

Rows = resources · Columns = lifecycle phases · Cell = filename (link) or — if no workflow exists for that combination.

| Resource | `Day0/Day1` Create | `Day2` Update | `Decom` Destroy |
|---|---|---|---|
| **Gateway** (static IP + cert) | [Day0.infra.01-gateway](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.01-gateway.yml) | [Day2.redeploy.05-gateway](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.05-gateway.yml) *(in-cluster Gateway + routes/IAP)* | [Decom.infra.01-gateway](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.01-gateway.yml) |
| **Grafana Cloud stack** | [Day0.infra.02-grafana-cloud](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.02-grafana-cloud.yml) | [Day2.publish.02-grafana-cloud](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.02-grafana-cloud.yml) | [Decom.infra.02-grafana-cloud](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.02-grafana-cloud.yml) |
| **Azure Managed Grafana** | [Day0.infra.03-azure-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.03-azure-grafana.yml) | [Day2.publish.03-azure-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.03-azure-grafana.yml) | [Decom.infra.03-azure-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.03-azure-grafana.yml) |
| **AWS AMG** | [Day0.infra.04-aws-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.04-aws-grafana.yml) | [Day2.publish.04-aws-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.04-aws-grafana.yml) | [Decom.infra.04-aws-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.04-aws-grafana.yml) |
| **GKE cluster** | [Day1.cluster.01-gke](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.01-gke.yml) | — | [Decom.cluster.01-gke](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.cluster.01-gke.yml) |
| **ArgoCD** (CD engine) | *(provisioned by Day1.cluster.01)* | [Day2.redeploy.01-argocd](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.01-argocd.yml) | *(destroyed by Decom.cluster.01)* |
| **Jenkins** | *(provisioned by Day1.cluster.01)* | [Day2.redeploy.02-jenkins](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.02-jenkins.yml) | *(destroyed by Decom.cluster.01)* |
| **Tekton** (CI engine, alt to Jenkins) | *(provisioned by Day1.cluster.01 when ci_engine=tekton)* | [Day2.redeploy.03-tekton](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.03-tekton.yml) | *(destroyed by Decom.cluster.01)* |
| **Headlamp** | *(provisioned by Day1.cluster.01)* | [Day2.redeploy.04-headlamp](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.04-headlamp.yml) | *(destroyed by Decom.cluster.01)* |
| **OSS Grafana stack** (ArgoCD) | *(provisioned by Day1.cluster.01)* | [Day2.publish.01-oss-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.01-oss-grafana.yml) | *(destroyed by Decom.cluster.01)* |
| **Grafana alerts** | *(provisioned by Day1.cluster.01)* | [Day2.publish.05-alerts](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.05-alerts.yml) | — |
| **k6 traffic** | — | [Day2.traffic.01-k6](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.01-k6.yml) | — |
| **Synthetic RUM** (Faro beacons) | — | [Day2.traffic.02-rum](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.02-rum.yml) | — |
| **Cluster pause/resume** (cost) | — | [Day2.scale.01-pause](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.01-pause.yml) · [Day2.scale.02-resume](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.02-resume.yml) | — |
| **Container registry retention** (ghcr prune) | — | [Day2.registry.01-image-retention](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.registry.01-image-retention.yml) | — |
| **Everything** (umbrella, opt-in) | [Day1.cluster.00-all](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.00-all.yml) *(Gateway + cluster + backend, one click)* | — | [Decom.infra.00-all](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.00-all.yml) *(cluster + all backends, one click)* |

---

## Lifecycle diagram

<details>
<summary>Expand: full lifecycle flow (Mermaid)</summary>

```mermaid
flowchart TD
    subgraph PHASE0 ["Day0 + Day1 — Create (run in sorted order)"]
        direction TB
        P0_1["Day0.infra.01 Gateway\nDay0.infra.02 Grafana Cloud\nDay0.infra.03 Azure bootstrap\nDay0.infra.04 AWS bootstrap\n━━ one-time, persistent ━━"]
        P0_2["Day1.cluster.01 GKE\n━━ throwaway cluster ━━"]
        P0_1 -->|"persistent resources ready\n(GCS state, credentials)"| P0_2
    end

    subgraph PHASE5 ["Day2 — Update (independent, any order)"]
        direction TB
        P5_1o["Day2.publish.01 OSS dashboards"]
        P5_1g["Day2.publish.02 Grafana Cloud dashboards"]
        P5_1a["Day2.publish.03 Azure dashboards"]
        P5_1b["Day2.publish.04 AWS dashboards"]
        P5_1c["Day2.publish.05 Grafana alerts"]
        P5_2z["Day2.redeploy.01 ArgoCD"]
        P5_2a["Day2.redeploy.02 Jenkins"]
        P5_2t["Day2.redeploy.03 Tekton"]
        P5_2b["Day2.redeploy.04 Headlamp"]
        P5_9["Day2.traffic.01 k6"]
        P5_9r["Day2.traffic.02 Synthetic RUM"]
        P5_s1["Day2.scale.01 Pause (nodes → 0)"]
        P5_s2["Day2.scale.02 Resume"]
    end

    subgraph PHASE9 ["Decom — Destroy (run in sorted order)"]
        direction TB
        P9_1["Decom.cluster.01 GKE\n━━ throwaway cluster first ━━"]
        P9_2["Decom.infra.01 Gateway\nDecom.infra.02 Grafana Cloud\nDecom.infra.03 Azure decommission\nDecom.infra.04 AWS decommission\n━━ persistent resources last ━━"]
        P9_1 -->|"cluster gone\nno dangling references"| P9_2
    end

    UP["🟢 Day1.cluster.00 — Everything up\n(one-click umbrella: Gateway + cluster + backend)"]:::umbrella
    DOWN["🔴 Decom.infra.00 — Everything\n(one-click umbrella: cluster + all backends)"]:::umbrella
    UP -.->|"orchestrates"| PHASE0
    DOWN -.->|"orchestrates"| PHASE9

    PHASE0 -->|"cluster active"| PHASE5
    PHASE5 -->|"ready to tear down"| PHASE9
    PHASE9 -->|"clean slate"| PHASE0

    classDef umbrella fill:#ffd,stroke:#aa0,stroke-width:2px;
```

</details>

### Cluster lifecycle (state view)

<details>
<summary>📊 Cluster lifecycle — Day0 → Day1 → Day2 → Decom (state diagram)</summary>

```mermaid
stateDiagram-v2
    [*] --> Root: bootstrap.sh up (once, local)
    Root --> Day0: Day0.infra.0N (Gateway + backend, persistent)
    Day0 --> Day1: Day1.cluster.01 (cluster + full stack)
    Day1 --> Day2: cluster running
    Day2 --> Day2: redeploy / publish / traffic (re-runnable)
    Day2 --> DecomCluster: Decom.cluster.01
    DecomCluster --> Day0: cluster gone; backends + root kept
    DecomCluster --> DecomInfra: Decom.infra.0N (optional, permanent)
    DecomInfra --> RootTeardown: bootstrap.sh down (rare)
    RootTeardown --> [*]
    note right of DecomCluster
      re-provision = back to Day1
      (Day0 state in GCS is reused)
    end note
```

</details>

**Reading it —** the root of trust (`bootstrap.sh up`) is created once and sits beneath everything; `Day0` provisions the persistent infra, `Day1` the throwaway cluster, and `Day2` is the self-loop where day-to-day ops live (every box is re-runnable). The key edge is `Decom.cluster.01 → Day0`: a normal teardown drops only the cluster and **keeps the backends + root**, so re-provisioning skips `Day0` entirely (its state still lives in GCS). Only abandoning the project walks the rarely-used `Decom.infra → bootstrap.sh down` tail.

### Workflow dependencies & GKE serialization

<details>
<summary>📊 Workflow dependencies + the jenkins-2026-gke concurrency group</summary>

```mermaid
flowchart TD
    boot["bootstrap.sh up<br/>WIF + GCS state"]:::root
    gw["Day0.infra.01<br/>Gateway IP/cert"]
    bk["Day0.infra.02/03/04<br/>observability backend"]
    boot --> gw
    boot --> bk
    gw --> day1
    bk -.->|workflow_call preflight| day1
    subgraph cc["concurrency: jenkins-2026-gke — queued, not raced"]
        day1["Day1.cluster.01<br/>cluster + up.sh"]
        d2["Day2.* cluster ops"]
        decom["Decom.cluster.01"]
    end
    day1 --> d2 --> decom
    decom -.->|persistent kept| gw
    umb["umbrellas Day1.cluster.00 / Decom.infra.00<br/>no concurrency — orchestrate via workflow_call"]:::umb
    umb -.-> day1
    umb -.-> decom
    classDef root fill:#ffd,stroke:#aa0,stroke-width:2px;
    classDef umb fill:#eef,stroke:#66c;
```

</details>

**Reading it —** solid arrows are create-order dependencies (`Day0.infra.01` Gateway and the backend bootstrap must exist before `Day1`); dotted arrows are reuse/orchestration. The shaded box is the `jenkins-2026-gke` **concurrency group**: `Day1.cluster.01`, the cluster-touching `Day2.*`, and `Decom.cluster.01` all share it, so GitHub **queues** them rather than letting two runs race the same Terraform state. The umbrellas deliberately carry **no** concurrency of their own — otherwise they would hold the group their own child job needs and deadlock.

---

## Day-0 / Day-1 / Day-2 operations

These terms come from the SRE / platform-engineering world and describe **when in a system's life a task is performed**, not how difficult it is. The `DayN` prefix of every workflow filename maps directly to them:

| Term | What it means | When it runs | tiers used |
|---|---|---|---|
| **Day0** | Foundation bootstrapping — one-time setup of persistent infrastructure that survives across cluster sessions | Before the first deployment; rarely again unless rebuilding from scratch | `infra` |
| **Day1** | Initial provisioning — creating the cluster and deploying the full application stack on top of the Day0 foundation | Once per cluster session (provision → use → decommission cycle) | `cluster` |
| **Day2** | Operations — changes to a **running** system without reprovisioning: config updates, artifact publishing, simulations | Anytime while the cluster is alive | `redeploy`, `publish`, `traffic` |
| **Decom** | Teardown — the inverse of Day1 (cluster) and Day0 (persistent backends) | End of session / permanent shutdown | `cluster` then `infra` |

### Day × workflow matrix

| # | Workflow | Phase | Requires cluster? | Idempotent? | Typical frequency |
|:---:|---|:---:|:---:|:---:|---|
| 1 | [Day0.infra.01-gateway](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.01-gateway.yml) | **Day0** | no | yes | Once (re-run = no-op) |
| 2 | [Day0.infra.02-grafana-cloud](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.02-grafana-cloud.yml) | **Day0** | no | yes | Once (re-run = no-op) |
| 3 | [Day0.infra.03-azure-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.03-azure-grafana.yml) | **Day0** | no | yes | Once (re-run = no-op) |
| 4 | [Day0.infra.04-aws-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.04-aws-grafana.yml) | **Day0** | no | yes | Once (re-run = no-op) |
| 5 | [Day1.cluster.01-gke](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.01-gke.yml) | **Day1** | creates it | yes | Once per session |
| 6 | [Day2.redeploy.01-argocd](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.01-argocd.yml) | **Day2** | yes | yes | When ArgoCD config / an Application changes |
| 7 | [Day2.redeploy.02-jenkins](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.02-jenkins.yml) | **Day2** | yes | yes | When Jenkins config/JCasC changes |
| 8 | [Day2.redeploy.03-tekton](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.03-tekton.yml) | **Day2** | yes | yes | When Tekton config/pipelines change |
| 9 | [Day2.redeploy.04-headlamp](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.04-headlamp.yml) | **Day2** | yes | yes | When Headlamp config changes |
| 10 | [Day2.redeploy.05-gateway](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.05-gateway.yml) | **Day2** | yes | yes | When the Gateway/routes/IAP change |
| 11 | [Day2.publish.01-oss-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.01-oss-grafana.yml) | **Day2** | yes ³ | yes | When OSS dashboards/alerts change |
| 12 | [Day2.publish.02-grafana-cloud](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.02-grafana-cloud.yml) | **Day2** | yes ² | yes | When dashboard/alert JSON changes |
| 13 | [Day2.publish.03-azure-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.03-azure-grafana.yml) | **Day2** | **no** ¹ | yes | When dashboard JSON changes |
| 14 | [Day2.publish.04-aws-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.04-aws-grafana.yml) | **Day2** | **no** ¹ | yes | When dashboard JSON changes |
| 15 | [Day2.publish.05-alerts](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.05-alerts.yml) | **Day2** | yes ² | yes | When alert rules change |
| 16 | [Day2.traffic.01-k6](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.01-k6.yml) | **Day2** | yes | n/a | On demand / regular cadence |
| 17 | [Day2.traffic.02-rum](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.02-rum.yml) | **Day2** | yes | n/a | To populate/demo/validate the RUM dashboard (synthetic Faro beacons) |
| 18 | [Day2.scale.01-pause](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.01-pause.yml) | **Day2** | yes | yes | To park the cluster at ~zero cost for a few days |
| 19 | [Day2.scale.02-resume](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.02-resume.yml) | **Day2** | yes | yes | To bring a paused cluster back online |
| 20 | [Day2.registry.01-image-retention](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.registry.01-image-retention.yml) | **Day2** | **no** | yes | Scheduled/on-demand ghcr image prune (GitHub API, no cluster) |
| 21 | [Decom.cluster.01-gke](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.cluster.01-gke.yml) | **Decom** | destroys it | yes | Once per session |
| 22 | [Decom.infra.01-gateway](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.01-gateway.yml) | **Decom** | no | yes | Once (permanent — ⚠ loses static IP) |
| 23 | [Decom.infra.02-grafana-cloud](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.02-grafana-cloud.yml) | **Decom** | no | yes | Once (permanent — ⚠ irreversible) |
| 24 | [Decom.infra.03-azure-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.03-azure-grafana.yml) | **Decom** | no | yes | Once (permanent — ⚠ irreversible) |
| 25 | [Decom.infra.04-aws-grafana](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.04-aws-grafana.yml) | **Decom** | no | yes | Once (permanent — ⚠ irreversible) |

> ¹ **Day2.publish.03 and Day2.publish.04** connect directly to the persistent managed-grafana backends (Azure AMG / Amazon AMG) — no running GKE cluster needed. They read Terraform state from GCS and authenticate via GitHub OIDC → Azure/AWS.
>
> ² **Day2.publish.02 and Day2.publish.05** read Grafana credentials from k8s Secrets (grafana-cloud-credentials, azure-monitor-credentials, aws-managed-credentials) so they require an active cluster. Unlike the Azure/AWS managed-Grafana publishers (¹), the Grafana Cloud stack has no Terraform-state-readable API path here — its token lands in the in-cluster `grafana-cloud-credentials` Secret at Day1, so `Day2.publish.02` reads it from there (same as oss/alerts). The dashboards/alerts are also provisioned automatically by `Day1.cluster.01` via `scripts/up.sh` — these Day2 workflows just push changes without a full reprovision.
>
> ³ **Day2.publish.01** refreshes the in-cluster OSS Grafana on a running cluster. The OSS stack (kube-prometheus-stack/Loki/Tempo) is GitOps-managed by the `observability-oss` ArgoCD app-of-apps ([`argocd/observability-oss`](../argocd/observability-oss)), so chart/value changes — including the dashboards, now GitOps-managed by the `oss-grafana-dashboards` child app — auto-sync on commit; this workflow nudges an ArgoCD re-sync and republishes alert rules without a full reprovision.

### Pause / resume to save cost (without Decom + rebuild)

When you want to stop paying for a cluster for a few days but keep it intact,
**don't** `Decom.cluster.01` + `Day1.cluster.01` (a full teardown + ~20-min
rebuild + redeploy). Instead:

- **`Day2.scale.01-pause`** disables autoscaling and scales every GKE node pool to
  **0**. The 24/7 worker-VM cost goes to ~0 while the cluster, its persistent
  volumes (CNPG Postgres data), ArgoCD + all apps, the reserved static IP, DNS and
  certs all survive. Workloads go `Pending` (no nodes).
- **`Day2.scale.02-resume`** scales the pools back up and re-enables autoscaling
  (inputs default to [`terraform/gke`](../terraform/gke)'s `node_count`/`min`/`max`); pods reschedule
  and ArgoCD reconciles in **minutes** — nothing is rebuilt. It then runs a
  **post-resume recovery pass** for two one-time-init races on the fresh nodes:
  re-clones any CNPG replica the pause's force-drain left unstartable, and restarts
  ArgoCD dex if its OIDC connector init lost a race with DNS/egress (both idempotent
  no-ops on a clean resume — see [501 § resume-side gotcha](./501-PLATFORM_OPERATIONS.md#the-resume-side-gotcha-one-time-init-races-dns-on-fresh-nodes-real-incident)).

It uses imperative `gcloud` (fast), so [`terraform/gke`](../terraform/gke) state drifts (it still
records autoscaling on / `node_count` N) — that's benign and reconciled by Resume
or the next `Day1.cluster.01` apply. What still costs while paused (all tiny): the
zonal control plane (covered by the GKE free-tier management credit), the PVs'
persistent disks, and the reserved static IP. **Grafana Cloud is free-tier** so
there's nothing to pause there; the Azure/AWS managed backends, if ever
provisioned, are billed separately and would be torn down via their own
`Decom.infra.0{3,4}` (they don't "pause" cheaply).

### Typical session lifecycle

<details>
<summary>📊 Typical session lifecycle (Day0 → Day1 → Day2 → Decom)</summary>

```mermaid
flowchart TD
    subgraph D0["Day0 — one-time persistent bootstrap"]
        direction LR
        w0101["Day0.infra.01\nGateway bootstrap"]
        w0102["Day0.infra.02\nGrafana Cloud bootstrap"]
        w0103["Day0.infra.03\nAzure bootstrap"]
        w0104["Day0.infra.04\nAWS bootstrap"]
    end

    subgraph D1["Day1 — cluster provision (once per session)"]
        w0201["Day1.cluster.01\nGKE provision\n(runs scripts/up.sh in full)"]
    end

    subgraph D2["Day2 — operations on running cluster"]
        direction LR
        subgraph content["Content publish (no cluster needed for *.03/04)"]
            w5103["Day2.publish.03\nAzure dashboards"]
            w5104["Day2.publish.04\nAWS dashboards"]
            w5105["Day2.publish.05\nGrafana alerts"]
        end
        subgraph redeploy["Component redeploys"]
            w52ar["Day2.redeploy.01\nArgoCD"]
            w5202["Day2.redeploy.02\nJenkins"]
            w52tk2["Day2.redeploy.03\nTekton"]
            w5203["Day2.redeploy.04\nHeadlamp"]
        end
        subgraph sim["Traffic"]
            w5901["Day2.traffic.01\nk6"]
        end
    end

    subgraph DECOM["Decom (reverse order)"]
        direction LR
        w9101["Decom.cluster.01\nGKE decommission"]
        w92xx["Decom.infra.01–04\nPersistent backends\n(only if permanent)"]
        w9101 -->|"cluster gone"| w92xx
    end

    D0 -->|"GCS state reused by Day1.cluster.01"| D1
    D1 -->|"cluster running"| D2
    D2 -->|"session complete"| DECOM
    DECOM -->|"re-provision: skip Day0\n(GCS state still exists)"| D1

    style D0 fill:#e8f4e8,stroke:#4caf50
    style D1 fill:#e3f2fd,stroke:#2196f3
    style D2 fill:#fff8e1,stroke:#ff9800
    style DECOM fill:#fce4ec,stroke:#e91e63
```

</details>

A new session (reprovision after full teardown) only needs **Day1** — Day0 outputs are still in GCS state and are reused automatically by `Day1.cluster.01`.

---

## Complete workflow inventory — matrix table

All 27 workflows in a single numbered table (rows 1–25 in filename/execution order; **rows 26–27** are the two opt-in **umbrellas** — full-teardown and full-provision — which orchestrate the others and sit outside the linear runbook). The filename's three components (`DayN`, `tier`, `ZZ`) are broken out separately so the meaning of every part is visible at a glance. Click the code to open the workflow's **Run workflow** page directly in GitHub Actions.

> **Reading the sequence**: rows are ordered by filename (= correct execution order). `Day0`/`Day1` before `Day2` before `Decom`; within `Decom`, the cluster (row 21) before the persistent backends (rows 22–25). This ordering is **enforced by the `name:` prefixes** — opening the GitHub Actions sidebar and reading top-to-bottom gives the correct runbook. Row 26 (`Decom.infra.00`) is an opt-in umbrella that orchestrates a full teardown (it runs rows 21–25 for you, cluster first) and is therefore outside the linear order. Row 27 (`Day1.cluster.00`) is its symmetric **provision** umbrella — one click runs the Gateway bootstrap (row 1) then the cluster provision (row 5), which itself bootstraps the chosen backend — and is likewise outside the linear order (its filename sorts at position 5, before `Day1.cluster.01`). Row 20 (`Day2.registry.01-image-retention`) is a Day2-only ops workflow (ghcr image prune) with no Day0/Decom counterpart.

| # | `DayN` — Phase | `tier` — group | `ZZ` resource | Code → GitHub Actions | Description | Prerequisites | Frequency |
|:---:|---|---|---|---|---|---|---|
| **1** | **Day0** Create | **infra** — persistent first | **01** Gateway IP/cert | [**`Day0.infra.01-gateway`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.01-gateway.yml) | Provisions static external IP + wildcard cert map + DNS authorization ([`terraform/gateway-bootstrap`](../terraform/gateway-bootstrap)). Keeping these persistent avoids losing the IP and re-propagating DNS on every cluster rebuild. | [`terraform/bootstrap`](../terraform/bootstrap); DNS A record at registrar pointing to the static IP | **One-time** |
| **2** | **Day0** Create | **infra** — persistent first | **02** Grafana Cloud stack | [**`Day0.infra.02-grafana-cloud`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.02-grafana-cloud.yml) | Provisions the Grafana Cloud stack ([`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack), generated slug): Grafana instance, access-policy tokens, PDC agent. Preserves metrics/traces/logs history across GKE rebuilds. | [`terraform/bootstrap`](../terraform/bootstrap) applied (WIF + GCS bucket) | **One-time** |
| **3** | **Day0** Create | **infra** — persistent first | **03** Azure Mgd Grafana | [**`Day0.infra.03-azure-grafana`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.03-azure-grafana.yml) | Provisions Azure Managed Grafana + Azure Monitor workspace + App Insights + Log Analytics + Entra SP ([`terraform/azure-managed-grafana`](../terraform/azure-managed-grafana)). Auth: GitHub OIDC → Azure (no stored client secret). | [`terraform/bootstrap`](../terraform/bootstrap); `AZURE_*` GitHub secrets | **One-time** |
| **4** | **Day0** Create | **infra** — persistent first | **04** AWS AMG / AMP | [**`Day0.infra.04-aws-grafana`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day0.infra.04-aws-grafana.yml) | Provisions Amazon Managed Grafana + AMP + CloudWatch + GKE→AWS OIDC provider + collector IAM role ([`terraform/aws-managed-grafana`](../terraform/aws-managed-grafana)). Auth: GitHub OIDC → AWS (no access keys). | [`terraform/bootstrap`](../terraform/bootstrap); `AWS_*` GitHub secrets | **One-time** |
| **5** | **Day1** Create | **cluster** — depends on infra | **01** GKE cluster | [**`Day1.cluster.01-gke`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.01-gke.yml) | Provisions the throwaway GKE cluster ([`terraform/gke`](../terraform/gke)) then runs `scripts/up.sh` in full: namespaces → OTel → ArgoCD → observability → Jenkins → seed pipelines → Headlamp + smoke test. (ArgoCD precedes observability so oss mode can deploy the in-cluster stack via the `observability-oss` app-of-apps.) Reads persistent-resource outputs (rows 1–4) from GCS state. Always pair with row 21 (`Decom.cluster.01`). | Rows 1–4 as needed for the chosen `observability_mode`; [`terraform/bootstrap`](../terraform/bootstrap) | **Per session** |
| **6** | **Day2** Update | **redeploy** | **01** ArgoCD | [**`Day2.redeploy.01-argocd`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.01-argocd.yml) | Re-applies [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh): ArgoCD Helm upgrade + OIDC/RBAC + Jenkins API token, and re-applies the GitOps Applications it owns (platform-postgres, External Secrets, Headlamp, microservices AppSet). ArgoCD is the CD engine the rest deploy through, hence `ZZ=01`. | Cluster active (row 5 run) | **Anytime** |
| **7** | **Day2** Update | **redeploy** | **02** Jenkins | [**`Day2.redeploy.02-jenkins`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.02-jenkins.yml) | Re-applies [`scripts/04-jenkins.sh`](../scripts/04-jenkins.sh): Helm upgrade of [`helm/jenkins/`](../helm/jenkins) + JCasC, and re-seeds the Microservices pipelines against the existing cluster. For Jenkins-only changes without a full provision cycle. | Cluster active (row 5 run) | **Anytime** |
| **8** | **Day2** Update | **redeploy** | **03** Tekton | [**`Day2.redeploy.03-tekton`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.03-tekton.yml) | Re-applies [`scripts/04-tekton.sh`](../scripts/04-tekton.sh) (Tekton Pipelines/Triggers/Dashboard) + [`scripts/06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh) (`tekton/` pipelines + per-service PipelineRuns). For Tekton-only changes without a full provision. **Secrets-backend-aware** (`secrets_backend` input): re-runs `01-namespaces` + `08.6-eso-sync` so it never recreates an ESO-owned Secret imperatively. | Cluster active (row 5 run, ci_engine=tekton) | **Anytime** |
| **9** | **Day2** Update | **redeploy** | **04** Headlamp | [**`Day2.redeploy.04-headlamp`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.04-headlamp.yml) | Re-applies [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) (refreshes OIDC config keys on `headlamp-credentials`) and [`scripts/08-headlamp.sh`](../scripts/08-headlamp.sh) (Helm upgrade of [`helm/headlamp/`](../helm/headlamp)). **Secrets-backend-aware** (`secrets_backend` input). | Cluster active (row 5 run) | **Anytime** |
| **10** | **Day2** Update | **redeploy** | **05** Gateway | [**`Day2.redeploy.05-gateway`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.redeploy.05-gateway.yml) | Re-applies [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) (namespaces + IAP Secrets) + [`scripts/09-gateway.sh`](../scripts/09-gateway.sh) (the Gateway, HTTPRoutes and GCPBackendPolicies/IAP). Use it to apply Gateway/route/IAP changes without a full provision. **Secrets-backend-aware** (`secrets_backend` input): runs `08.6-eso-sync` after `01-namespaces` so the IAP Secret is in place before the GCPBackendPolicy. | Cluster active (row 5 run) | **Anytime** |
| **11** | **Day2** Update | **publish** | **01** OSS Grafana | [**`Day2.publish.01-oss-grafana`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.01-oss-grafana.yml) | Refreshes the in-cluster OSS Grafana without a reprovision: rebuilds the `jenkins-2026-grafana-dashboards` ConfigMap, nudges the `observability-oss` ArgoCD app to re-sync, republishes alert rules. The stack itself is GitOps-managed ([`argocd/observability-oss`](../argocd/observability-oss)). | Cluster active (row 5 run), `observability.mode=oss` | **Anytime** |
| **12** | **Day2** Update | **publish** | **02** Grafana Cloud | [**`Day2.publish.02-grafana-cloud`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.02-grafana-cloud.yml) | (Re)publishes the dashboards + alert rules to Grafana Cloud (via `gcx`) without re-provisioning the cluster. Reads the stack slug from [`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack) GCS state. Use when a dashboard/alert JSON changes. | Row 2 applied; `observability.mode=grafana-cloud` | **Anytime** |
| **13** | **Day2** Update | **publish** | **03** Azure Mgd Grafana | [**`Day2.publish.03-azure-grafana`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.03-azure-grafana.yml) | (Re)publishes [`observability/grafana/dashboards-azure/`](../observability/grafana/dashboards-azure) to Azure Managed Grafana without re-provisioning the cluster. Discovers the instance via `az grafana list`; auth via GitHub OIDC. Use when a dashboard JSON changes. | Row 3 applied; `AZURE_*` secrets | **Anytime** |
| **14** | **Day2** Update | **publish** | **04** AWS AMG | [**`Day2.publish.04-aws-grafana`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.04-aws-grafana.yml) | (Re)publishes [`observability/grafana/dashboards-aws/`](../observability/grafana/dashboards-aws) to Amazon Managed Grafana without re-provisioning. Reads AMG params from [`terraform/aws-managed-grafana`](../terraform/aws-managed-grafana) GCS state; auth via GitHub OIDC. | Row 4 applied; `AWS_DASHBOARD_PUBLISH_ROLE_ARN` secret | **Anytime** |
| **15** | **Day2** Update | **publish** | **05** Grafana alerts | [**`Day2.publish.05-alerts`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.publish.05-alerts.yml) | Pushes the alert rules to the active Grafana via its provisioning API without a full reprovision ([`scripts/07.5-grafana-alerts.sh`](../scripts/07.5-grafana-alerts.sh)). | Cluster active (row 5 run) | **Anytime** |
| **16** | **Day2** Update | **traffic** | **01** k6 | [**`Day2.traffic.01-k6`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.01-k6.yml) | Runs a continuous stream of synthetic k6 traffic against the stable endpoints to keep metrics and logs active in Grafana dashboards. Does not modify infrastructure. | Cluster active; public endpoints reachable | **Anytime** |
| **17** | **Day2** Update | **traffic** | **02** Synthetic RUM | [**`Day2.traffic.02-rum`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.traffic.02-rum.yml) | POSTs synthetic Grafana **Faro** browser beacons (Core Web Vitals, sessions, JS errors + OTLP browser traces) to the otel-collector faro receiver via `kubectl port-forward`, to populate/demo/validate the **RUM dashboard** before the Angular SPA is instrumented. No environment gate; modifies nothing. | Cluster active (row 5 run) | **Anytime** |
| **18** | **Day2** Update | **scale** | **01** Pause | [**`Day2.scale.01-pause`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.01-pause.yml) | Parks the cluster at ~zero cost without a Decom+rebuild: disables autoscaling and scales every node pool to 0 (preserves the cluster, PVs/CNPG data, ArgoCD/apps, static IP, DNS, certs). Imperative `gcloud`; the [`terraform/gke`](../terraform/gke) drift is benign. | Cluster active (row 5 run) | **To park for days** |
| **19** | **Day2** Update | **scale** | **02** Resume | [**`Day2.scale.02-resume`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.scale.02-resume.yml) | Brings a paused cluster back: scales the node pools up and re-enables autoscaling (inputs default to [`terraform/gke`](../terraform/gke)'s node_count/min/max); pods reschedule and ArgoCD reconciles in minutes. Then a post-resume recovery pass re-clones any unstartable CNPG replica and restarts dex if its OIDC init raced DNS (idempotent). | A paused cluster (row 18 run) | **To un-park** |
| **20** | **Day2** Update | **registry** | **01** Image retention | [**`Day2.registry.01-image-retention`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day2.registry.01-image-retention.yml) | Prunes old/untagged container images from the GitHub Container Registry (ghcr) to keep the registry tidy and within quota. Pure GitHub API — **no cluster needed**; scheduled and/or on-demand. Day2-only (no Day0/Decom counterpart). | None (GitHub API) | **Scheduled / anytime** |
| **21** | **Decom** Destroy | **cluster** — most dependent, first | **01** GKE cluster | [**`Decom.cluster.01-gke`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.cluster.01-gke.yml) | Tears down the stack (`scripts/down.sh`) and destroys the GKE cluster (`terraform destroy` on [`terraform/gke`](../terraform/gke)), then **sweeps orphaned PV disks** (CSI-provisioned PDs that `terraform destroy` can't delete — see [902](./902-TROUBLESHOOTING.md)). The ephemeral Grafana Cloud token is also destroyed. Persistent resources are untouched. Must run **before** rows 22–25. | Session complete | **Per session** |
| **22** | **Decom** Destroy | **infra** — foundational, last | **01** Gateway IP/cert | [**`Decom.infra.01-gateway`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.01-gateway.yml) | `terraform destroy` on [`terraform/gateway-bootstrap`](../terraform/gateway-bootstrap). Releases the static IP and cert map. **⚠ The IP is gone**: a future bootstrap will get a new IP, requiring DNS A-record updates and propagation delay. | **Row 21** complete | **One-time** |
| **23** | **Decom** Destroy | **infra** — foundational, last | **02** Grafana Cloud stack | [**`Decom.infra.02-grafana-cloud`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.02-grafana-cloud.yml) | `terraform destroy` on [`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack). Permanently removes the Grafana Cloud instance, dashboards, access-policy tokens. Irreversible. | **Row 21** complete | **One-time** |
| **24** | **Decom** Destroy | **infra** — foundational, last | **03** Azure Mgd Grafana | [**`Decom.infra.03-azure-grafana`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.03-azure-grafana.yml) | `terraform destroy` on [`terraform/azure-managed-grafana`](../terraform/azure-managed-grafana). Removes Azure Managed Grafana, Monitor workspace, App Insights, Log Analytics and the Entra SP. | **Row 21** complete | **One-time** |
| **25** | **Decom** Destroy | **infra** — foundational, last | **04** AWS AMG / AMP | [**`Decom.infra.04-aws-grafana`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.04-aws-grafana.yml) | `terraform destroy` on [`terraform/aws-managed-grafana`](../terraform/aws-managed-grafana). Removes Amazon Managed Grafana, AMP, CloudWatch log group, OIDC provider and IAM role. | **Row 21** complete | **One-time** |
| **26** | **Decom** Destroy | **infra.00** — umbrella, opt-in | **00** Everything | [**`Decom.infra.00-all`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.infra.00-all.yml) | Full teardown in one dispatch: tears down the cluster **and** every persistent backend, reusing rows 21–25 via `workflow_call` (no duplicated logic). Type `destroy` to confirm. Cluster first (so the ephemeral `grafana-cloud-token` is gone before the Grafana Cloud stack), then backends in parallel. Backend checkboxes default **on**; Gateway IP defaults **off**. Avoids leaving a forgotten/billed backend after switching `observability.mode`. | None (orchestrates rows 21–25) | **When done** |
| **27** | **Day1** Create | **cluster.00** — umbrella, opt-in | **00** Everything up | [**`Day1.cluster.00-all`**](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.00-all.yml) | One-click from-scratch provision — the symmetric counterpart of row 26. Bootstraps the persistent Gateway (row 1) then provisions the cluster + full stack (row 5, which itself bootstraps the chosen observability backend), reusing both via `workflow_call`. Idempotent: safe from absolute zero **or** the usual decommissioned state. `bootstrap_gateway` defaults **on** (uncheck to skip its gate when the IP/cert already exist). | None (orchestrates rows 1 + 5) | **Provision from scratch** |

---

## Provision: per-step workflows, plus an opt-in "Everything up" umbrella

Symmetric to the teardown umbrella below. Normally you provision in two clicks —
the one-time persistent bootstraps (`Day0.infra.0N`, only what your
`observability_mode` needs) and then `Day1.cluster.01-gke` (which itself bootstraps
the chosen backend as a preflight). The one structural gap is the **Gateway**:
`Day1` references the static IP/cert by name but does **not** create them, so a
truly-from-zero account needs `Day0.infra.01` first.

**`Day1.cluster.00` ("Everything up")** closes that gap in **one click**: it
`workflow_call`s `Day0.infra.01` (Gateway bootstrap) then `Day1.cluster.01`
(cluster + full stack + the selected backend bootstrap), in order (`needs`, with
`always() && !failure()` so a *skipped* gateway step — `bootstrap_gateway:false` —
doesn't skip provision). Every called workflow is idempotent, so this is safe from
absolute zero (it allocates the static IP — follow the job summary to point DNS at
it) **or** from the usual decommissioned state (where `Decom.infra.00` left the
Gateway in place, so the IP is unchanged and no DNS change is needed). Approvals
are the natural per-resource set: `gateway-bootstrap` + the selected backend's env
(via Day1's preflight) + `gke-production`. No provisioning logic is duplicated — the
umbrella only orchestrates the existing reusable workflows.

> **Umbrellas carry NO `concurrency:` block** (both `Day1.cluster.00` and
> `Decom.infra.00`). The GKE serialization lives on the leaf workflows that actually
> touch the cluster (`Day1.cluster.01` / `Decom.cluster.01`, group `jenkins-2026-gke`).
> If an umbrella *also* declared that group it would **hold** it while waiting for its
> own `provision`/`cluster` job — which needs the same group — deadlocking the reusable
> call; GitHub then fails the run before that job starts (this happened once on
> `Day1.cluster.00` and was fixed by removing its `concurrency`). The
> `Day0.infra.0N` bootstraps have no concurrency group, so nesting them under the
> cluster workflow never deadlocks either.

## Decom: independent per backend, plus an opt-in "Everything" umbrella

The persistent backends (Gateway IP/cert, Grafana Cloud, Azure, AWS) each have their **own** `Decom.infra.0{1..4}` workflow — one `terraform destroy` per module. They are independent and persistent: you normally use only one per cluster (and with the `oss` default, often none at all). For a **targeted** teardown, run **only** the per-backend workflow(s) for what you actually provisioned, after `Decom.cluster.01-gke`.

For a **full** teardown there is also an opt-in umbrella, **`Decom.infra.00` ("Everything")**, that tears down the cluster **and** every persistent backend in one dispatch — so switching `observability.mode` around never leaves a forgotten, billed backend (e.g. an orphaned Grafana Cloud stack from before you moved to managed-azure). It reuses each per-resource Decom via `workflow_call` (no teardown logic is duplicated); type `destroy` to confirm. Order is enforced with `needs`: the **cluster runs first** (its decom also destroys the ephemeral `grafana-cloud-token`, which references the Grafana Cloud stack), then the backends destroy in parallel. The three backend checkboxes default **on** (the point is destroy-all); the Gateway static IP defaults **off** (keeping it avoids losing the IP and re-propagating DNS). Untick any to spare it. This is the one place a cascade is intentional — gated behind the explicit `destroy` confirmation and per-backend opt-out.

## Day2 ordering: tiers are categories, not stages

A natural follow-up to the sort rule above: **is there a dependency or required sequence between the Day2 tiers** — must `redeploy.*` run before `publish.*` before `traffic.*`, or is there ordering between two workflows of the *same* tier?

**No.** The fourteen `Day2.*` workflows are independent and idempotent. There is no `redeploy → publish → traffic → scale` pipeline, and no required order between two workflows that share a tier. Two facts make this concrete:

1. **Nothing chains them.** Every `Day2.*` workflow is `workflow_dispatch`-only — there are no `workflow_run:`, no `workflow_call`/`uses: ./` references between Day2 workflows. The operator dispatches each one by hand.
2. **Every Day2 prerequisite points *backwards*, never *sideways*.** Each Day2 workflow depends on base state established by `Day1.cluster.01` (a running cluster) or by a `Day0.infra.0{3,4}` backend (managed Grafana) — **never on a sibling Day2 workflow**. Read down the *Prerequisites* column of the [inventory table](#complete-workflow-inventory--matrix-table) (rows 6–15): every entry says "Cluster active (row 5 run)" or "Row 3/4 applied". None lists another Day2 workflow.

So in Day2 the `tier` is a **classification of what kind of operation a workflow is** (publish content / redeploy a component / generate traffic), **not a stage that has to run at a particular point**. You pick the single workflow that matches what you changed; the order relative to other Day2 workflows is irrelevant.

### Case-by-case: the relationships one might *assume* are dependencies

| Apparent relationship | Real dependency? | Why |
|---|---|---|
| `redeploy.01-argocd` → `publish.01-oss-grafana` | **No** | `publish.01` nudges the `observability-oss` ArgoCD app to re-sync, but ArgoCD already exists from `Day1`. `redeploy.01` is only run if you **changed** ArgoCD config; `publish.01` works fine having never run it. |
| `redeploy.02-jenkins` → `traffic.01-k6` | **No** | k6 hits the gateway/microservices endpoints (deployed by `Day1` + the ArgoCD AppSet). Jenkins is CI — it doesn't serve the runtime traffic k6 targets. |
| `redeploy.02-jenkins` ↔ `redeploy.03-tekton` | **No (mutually exclusive, not ordered)** | They redeploy the two alternative CI engines selected by `ci.engine` (Jenkins default \| Tekton). Only the active engine is provisioned by `Day1`; you run whichever one matches your cluster's `ci.engine`. Not an ordering dependency. |
| `publish.05-alerts` ↔ `publish.01-oss-grafana` | **No (they overlap, they don't order)** | Both publish alert rules; they are idempotent and last-writer-wins. Running either one alone leaves the correct state. |
| any `publish.*` → needs a live Grafana | **Yes, but backwards to `Day1`/`Day0`** | The Grafana instance is provided by `Day1.cluster.01` (oss mode) or by a `Day0.infra.0{3,4}` backend (Azure/AWS) — never by a sibling Day2 workflow. |

Note the pattern in the last column: ArgoCD genuinely *is* "the engine the rest deploy through" (hence `ZZ=01` within `redeploy`), but that engine↔applications relationship is established in **Day1** (initial provision) and maintained by GitOps auto-sync — **not** re-litigated in Day2. By the time you run any Day2 workflow the cluster is already complete and running; each Day2 workflow is a targeted, idempotent patch on top of it.

### Consequence for the naming scheme

Because Day2 has no intra-phase ordering, **no extra sequence digit is needed** — not between tiers and not between same-tier workflows. The `ZZ` within a tier (e.g. `redeploy.01-argocd` before `redeploy.02-jenkins`) reflects *install order should you ever run them together after a fresh provision*, not a hard Day2 dependency. If a genuine hard dependency between two Day2 workflows ever appears (e.g. "publish dashboards only after redeploying Grafana"), the scheme-consistent fix is **not** a new number but either a `workflow_call` (as `Day1.cluster.01` already does with the `Day0.infra` bootstraps) or an explicit entry in the *Prerequisites* column — keeping the filename convention untouched.

---

## Are workflows auto-chained? Why not?

**No workflow triggers another automatically** (there are no `workflow_run:` triggers). Each is dispatched manually by the operator. This is intentional:

| Phase | Reason for manual dispatch |
|---|---|
| **Day0/Day1 — Create** | The `Day0.infra` bootstraps are one-time, human-supervised operations run months apart. `Day1.cluster.01` (GKE) runs frequently but independently — chaining it to `Day0.infra` would trigger a full reprovision every time a bootstrap is touched. |
| **Day2 — Update** | All updates are independent and optional. There is no canonical ordering between publishing a dashboard, redeploying Jenkins, and running a traffic simulation. |
| **Decom — Destroy** | `Decom.cluster.01` (GKE) **must** complete before any `Decom.infra`. A `workflow_run:` trigger could enforce this, but it would be dangerous: a transient GKE decommission failure would silently block — or, with `on: failure`, trigger — permanent destruction of Grafana Cloud or the Gateway. Manual dispatch means a human reviews the `Decom.cluster.01` result before running `Decom.infra`. |

**The filename order IS the runbook.** Open the GitHub Actions workflow list, read it top to bottom, and run in that order. No separate documentation needed to know what comes next.

> **One internal exception**: `Day1.cluster.01-gke` calls the matching `Day0.infra.0{2,3,4}` bootstrap via `workflow_call` (`uses: ./.github/workflows/…`) for the chosen `observability_mode`, so the persistent backend is always idempotently applied before the cluster reads its Terraform outputs. That is a *child-job* call within one dispatch, not an auto-chain between top-level workflows.

See [102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md) for the one-time setup (secrets, Workload Identity Federation) these workflows need.

---

## Reading the `Day1.cluster.01` run graph: jobs vs in-job branches

A common question when dispatching `Day1.cluster.01-gke`: the run graph shows **three bootstrap boxes** (one per observability backend) feeding a single **`provision`** box — but **no boxes for `jenkins` vs `tekton`**, nor for the different observability modes beyond the bootstrap. Why isn't every combination drawn?

**Because GitHub Actions only renders the _job graph_ — the `jobs:` and their `needs:` edges. It cannot show logic that happens _inside_ a job** (a step's `if:`, a script's branching). So the rule is simple:

- A choice modelled as **separate jobs** → **appears as boxes**.
- A choice modelled as a **runtime branch inside one job** → **invisible** in the graph.

### Why the bootstraps are boxes but the CI engine isn't

The observability bootstrap is **three separate jobs**, each a reusable workflow gated by `if:`, so each is a node with a `needs:` edge into `provision`:

```yaml
grafana-cloud-bootstrap:
  if: ${{ inputs.observability_mode == 'grafana-cloud' }}
  uses: ./.github/workflows/Day0.infra.02-grafana-cloud.yml
azure-bootstrap:
  if: ${{ inputs.observability_mode == 'managed-azure' }}
  uses: ./.github/workflows/Day0.infra.03-azure-grafana.yml
aws-bootstrap:
  if: ${{ inputs.observability_mode == 'managed-aws' }}
  uses: ./.github/workflows/Day0.infra.04-aws-grafana.yml
provision:
  needs: [grafana-cloud-bootstrap, azure-bootstrap, aws-bootstrap]
```

(You see all three even though only the one matching your `observability_mode` runs — the others are *skipped*, and `provision` runs `if: always() && !failure()`.)

The **CI engine** (`jenkins` | `tekton`) and the rest of the observability wiring are **not** separate jobs — they are a **runtime branch inside the single `provision` job**, decided by the `ci.engine` feature flag inside `scripts/up.sh`:

```bash
# scripts/up.sh — runs as a step inside the provision job
if [[ "${J2026_CI_ENGINE}" == "tekton" ]]; then
  04-tekton.sh ; 06-tekton-pipelines.sh     # Tekton path
else
  04-jenkins.sh ; 06-seed-pipelines.sh      # Jenkins path (default)
fi
```

GitHub has no way to draw that — it's a `bash if`, not a job — so `provision` is one box.

### What actually runs

<details>
<summary>📊 What actually runs — job graph vs in-job steps</summary>

```mermaid
flowchart TD
    subgraph JOBS["GitHub Actions job graph (what the workflow_dispatch UI shows)"]
        direction TB
        B1["grafana-cloud-bootstrap\nif mode=grafana-cloud\nuses Day0.infra.02\n🔒 env: grafana-cloud-bootstrap"]
        B2["azure-bootstrap\nif mode=managed-azure\nuses Day0.infra.03\n🔒 env: azure-bootstrap"]
        B3["aws-bootstrap\nif mode=managed-aws\nuses Day0.infra.04\n🔒 env: aws-bootstrap"]
        P["provision\nneeds: the 3 bootstraps\n🔒 env: gke-production"]
        B1 --> P
        B2 --> P
        B3 --> P
    end

    subgraph INSIDE["Inside the single 'provision' job — steps, NOT shown as boxes in the UI"]
        direction TB
        TF["terraform apply (GKE cluster)"]
        NS["01 namespaces + secrets\n(imperative kubectl, or push to\nSecret Manager when secrets.backend=eso)"]
        CD["08.5 ArgoCD -> 08.6 ESO sync (eso only) -> 03 observability"]
        UP{"up.sh branches on\nJENKINS2026_CI_ENGINE"}
        JEN["04-jenkins + 06-seed-pipelines"]
        TEK["04-tekton + 06-tekton-pipelines (PaC)"]
        REST["07/07.5 dashboards+alerts\n08 headlamp · 09 gateway/IAP"]
        SMOKE["smoke-test"]
        TF --> NS --> CD --> UP
        UP -->|jenkins default| JEN
        UP -->|tekton| TEK
        JEN --> REST
        TEK --> REST
        REST --> SMOKE
    end

    P -.->|"one job runs all of the below as steps"| INSIDE
```

</details>

> **Approval gates (🔒).** Each box is protected by its **own** required-reviewer
> GitHub Environment, so one approval maps to one concern and the cluster gate is
> never double-prompted: each backend bootstrap uses its own
> `grafana-cloud-bootstrap` / `azure-bootstrap` / `aws-bootstrap` environment, and
> only `provision` uses `gke-production`. The matching `Decom.infra.0{2,3,4}`
> teardown workflows reuse the same per-backend environments. (Before this split,
> Grafana Cloud borrowed `gke-production`, which got it approved twice in one Day1
> run.) See [102 § Environment Protection and Manual Approvals](./102-GITHUB_ACTIONS_AUTOMATION.md#environment-protection-and-manual-approvals).

### Why it's modelled this way (not as per-engine jobs)

| Choice | Modelled as | Why |
|---|---|---|
| Observability **backend** (grafana-cloud / azure / aws) | **Separate jobs** (`workflow_call`) | They are **persistent Day0 resources**, independently runnable on their own (`Day0.infra.0{2,3,4}`), and must run as a **preflight** so `provision` can read their Terraform outputs to build the in-cluster credentials Secret. Reusing them via `workflow_call` yields the graph nodes for free. |
| **CI engine** (jenkins / tekton) | **In-job branch** (`ci.engine` flag in `up.sh`) | Splitting `provision` into `provision-jenkins` / `provision-tekton` jobs would **duplicate the entire heavy preamble** (GCP auth, Terraform, kubeconfig, namespaces, ArgoCD, observability) for a one-line divergence. The feature-flag branch is the repo-wide pattern (same as `observability.mode`): one path, parameterised by config. |
| Observability **mode** wiring (beyond bootstrap) | **In-job** (`JENKINS2026_OBS_MODE` in `up.sh` + per-mode `values-*.yaml`) | Same reason — a config branch, not a structural one. |

So the run graph deliberately shows only the **structural** fan-in (the preflight backends) and folds every **configuration** choice into the single `provision` job. If you ever *wanted* the engine choice as boxes, you'd split `provision` into a shared-preamble job plus `if: ci_engine == …` deploy jobs (passing kubeconfig as an artifact) — possible, but a lot of duplication for a PoC, and it would break the "one idempotent provision" model described below.

---

## Idempotency: every workflow is safe to re-run

**All workflows are idempotent (or one-shot-but-safe). Re-running is the normal way to apply a change — you never need to decommission and re-provision to pick one up.**

### `Day1.cluster.01-gke` is idempotent — re-run it to apply changes

`Day1.cluster.01-gke` is the headline case because it does the most. Re-running it on an **already-provisioned** cluster **converges in place**; it does not require (and is not improved by) a prior `Decom`. Three layers make this true:

1. **Terraform converges, it doesn't recreate.** `terraform apply` against the GCS remote state is a **no-op when the cluster already exists** in state — it reconciles to the desired state, creating nothing twice. The one `-target` apply (the Grafana Cloud dashboards SA token, applied before the full apply so the `grafana` provider can authenticate) is explicitly a no-op once that token is in state.
2. **`up.sh` re-applies every step idempotently.** Each `scripts/0N-*.sh` step uses converging primitives — `kubectl create … --dry-run=client -o yaml | kubectl apply -f -` for every Secret/ConfigMap/RoleBinding/ClusterRole, `helm upgrade --install` for every chart, and `kubectl apply` for manifests. Re-running re-asserts the desired state without "already exists" errors.
3. **ArgoCD re-syncs from git.** The GitOps-managed components (microservices, observability-oss, Tekton app-of-apps, Jenkins app, External Secrets, Headlamp) are reconciled by ArgoCD against the repo, so a `Day1` re-run (or even just a `kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite`) pulls the latest committed manifests.

> **Consequence.** To apply a change: **re-run `Day1.cluster.01-gke`** on the existing cluster. For a CI-engine-only change, the lighter `Day2.redeploy.02-jenkins` / `Day2.redeploy.03-tekton` converge the same way (they also re-run `09-gateway`, so public routes/IAP are re-asserted). `Decom.cluster.01-gke` is **only** for tearing the cluster down when you are finished, to stop charges — it is not a prerequisite for changes. (Do still Decom an idle cluster: it is billed.)

### Per-workflow idempotency

Verdicts: **Idempotent** = converges to desired state, safe to re-run · **One-shot but safe** = an action (load test / dashboard publish) that simply repeats harmlessly, with no accumulation or error on re-run.

| Workflow | Verdict | Why |
|---|---|---|
| `Day0.infra.01-gateway` | **Idempotent** | `terraform apply` on the gateway/IP/cert module (GCS state) converges. |
| `Day0.infra.02-grafana-cloud` | **Idempotent** | `terraform apply`; the random stack slug is generated once and persisted in state, so re-applies reuse it. |
| `Day0.infra.03-azure-grafana` | **Idempotent** | `terraform apply` on the Azure backend (GCS state) converges. |
| `Day0.infra.04-aws-grafana` | **Idempotent** | `terraform apply` on the AWS backend (GCS state) converges. |
| `Day1.cluster.01-gke` | **Idempotent** | `terraform apply` no-ops on an existing cluster; `up.sh` re-applies every step (`--dry-run\|apply`, `helm upgrade --install`); ArgoCD re-syncs. See above. |
| `Day2.redeploy.01-argocd` | **Idempotent** | `08.5-argocd.sh` = `helm upgrade --install` + idempotent `kubectl apply` of the ArgoCD `Application`s. |
| `Day2.redeploy.02-jenkins` | **Idempotent** | `04-jenkins.sh` (`helm upgrade --install`, JCasC ConfigMaps via `--dry-run\|apply`) + `06-seed-pipelines.sh`. |
| `Day2.redeploy.03-tekton` | **Idempotent** | `01`/`04-tekton`/`06-tekton-pipelines`/`09-gateway` — all `kubectl apply` / `--dry-run\|apply`; PaC webhook creation skips if one already targets the controller. |
| `Day2.redeploy.04-headlamp` | **Idempotent** | `01-namespaces.sh` + `08-headlamp.sh` (`helm upgrade --install`). |
| `Day2.redeploy.05-gateway` | **Idempotent** | `01-namespaces.sh` (namespaces + IAP Secrets) + `09-gateway.sh` (Gateway/HTTPRoutes/GCPBackendPolicies, all `kubectl apply`). |
| `Day2.publish.01-oss-grafana` | **Idempotent** | Nudges the `observability-oss` app re-sync (`kubectl annotate --overwrite`), which reconciles the GitOps-managed dashboards child app + republishes alerts. |
| `Day2.publish.03-azure-grafana` | **One-shot but safe** | `az grafana dashboard create --overwrite` re-publishes; no error/dup on re-run. |
| `Day2.publish.04-aws-grafana` | **One-shot but safe** | `07-grafana-dashboards.sh` re-publishes to AMG; no accumulation. |
| `Day2.publish.05-alerts` | **Idempotent** | `07.5-grafana-alerts.sh` uses Grafana's provisioning API (contact points / rules / policies are upserts). |
| `Day2.traffic.01-k6` | **One-shot but safe** | Runs a k6 load test; re-running just runs another test (each uploads its own artifact). |
| `Decom.cluster.01-gke` | **Idempotent** | `terraform destroy` no-ops when already gone; `down.sh` uses `--ignore-not-found` / `\|\| true` throughout. |
| `Decom.infra.01-gateway` | **Idempotent** | `terraform destroy` on the gateway module is a no-op once destroyed. |
| `Decom.infra.02-grafana-cloud` | **Idempotent** | Applies first to drop delete-protection, then `terraform destroy`; both converge. |
| `Decom.infra.03-azure-grafana` | **Idempotent** | Pre-destroy cleanup guarded with `\|\| true`; `terraform destroy` tolerates absent resources. |
| `Decom.infra.04-aws-grafana` | **Idempotent** | `terraform destroy` on the AWS backend converges. |

### Should every workflow be *converging*-idempotent?

No — and the split above is by design, not an oversight:

- **State-managing workflows must converge, and all do.** `Day0`/`Day1` (provision), the `Day2.redeploy.*` (re-deploy a component), and the `Decom.*` (teardown) all describe a *desired state*; re-running them must reconcile to it without erroring or duplicating — which they do (Terraform `apply`/`destroy` on remote state, `kubectl --dry-run|apply` / `--ignore-not-found`, `helm upgrade --install`).
- **Action workflows are correctly one-shot, not converging.** `Day2.traffic.01-k6` (run a load test) and `Day2.publish.03/04` (publish dashboards) are *actions*, not state. "Converging" a load test is meaningless — the right property for an action is that **repeating it is harmless** (no error, no accumulation, no orphaning), which holds: k6 just runs again (each run uploads its own artifact), and the dashboard publishes use `--overwrite`. Forcing them into a "converge" model would add complexity for no benefit.

So the correct bar is **"safe to re-run"**, which every workflow meets; full state-convergence is required only of the state-managing ones, and there it is met universally.

**No non-idempotent workflow exists in the repo.** The invariants that guarantee this — and that any new workflow/script must preserve — are:

- **Terraform**: `apply`/`destroy` against remote GCS state converge; any randomness (e.g. the Grafana Cloud slug) is persisted in state, never regenerated. Avoid create-before-destroy patterns and un-stored random values.
- **Kubernetes**: never a bare `kubectl create` or `helm install`. Use `kubectl create … --dry-run=client -o yaml | kubectl apply -f -`, `kubectl apply`, `helm upgrade --install`, and `kubectl delete --ignore-not-found` (or `|| true`) for teardown.
- **External APIs**: prefer upsert/overwrite (`az … --overwrite`, Grafana provisioning API, "skip if the webhook already exists") over blind create.

This is the workflow-level expression of the repo-wide **idempotency** convention in [`CLAUDE.md`](../CLAUDE.md) ("every `scripts/0N-*.sh` step and Terraform module should be safe to re-run").

---

## Image retention (`registry` tier)

`Day2.registry.01-image-retention` prunes old microservices container image versions from ghcr — needed because the **immutable per-build image tags** (`<branch>-<build#>` for Jenkins, `<branch>-<pipelineRunName>` for Tekton — see [502](./502-MICROSERVICES_GITOPS.md)) accumulate one tag per build. Weekly cron + manual dispatch; inputs `keep` (recent versions to retain per service, default 30 — above deploy cadence so the live tag is never cut) and `dry_run`. It is the sole member of the `registry` tier: a pure **GitHub Packages** operation (no GKE, so no `jenkins-2026-gke` concurrency group) with no Day0/Decom counterpart.

---

[← Previous: 100. Bootstrap](./100-BOOTSTRAP.md) | [🏠 Home](../README.md) | [→ Next: 102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md)

---

*101. GitHub Actions Workflows — jenkins-2026*
