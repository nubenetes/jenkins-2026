# Grafana Cloud dashboard exports (optimized) — backup / source of truth

This folder holds the **platform dashboards exported from Grafana Cloud after the Grafana
Cloud AI assistant optimized them** (layout, queries, panel options, in-panel docs) — the
backup / source of truth. **Two dashboard schemas live here side by side:**

- **v2 schema** — `apiVersion: dashboard.grafana.app/v2`, `kind: Dashboard` (`elements` +
  `layout`). The AI-optimized exports, the **full set of 10 dashboards**, in **both
  serializations** (`*.yaml` + `*.json`, identical content). **File name:
  `dashboard-<epoch>.{json,yaml}`.**
- **v1 classic model** — `schemaVersion: 42`, `panels[]` + `gridPos`. A classic-model export
  of **three** dashboards (Argo Workflows CI, GitHub Actions (ARC) CI, Node Auto-Provisioning
  (Spot)) — the exact model the auto-deployed [`../dashboards/`](../dashboards/) copies use.
  **File name: `CI-CD _ <Title>-<epoch>.json`.**

> **The file-name prefix tells you the format:** `dashboard-…` = **v2**; `CI-CD _ …` = **v1
> classic**.

Why keep both: the v2 export is the richest form the AI produces, but **v2 cannot be
auto-provisioned reliably today** (see [*Format: v1 vs v2, and why auto-import is limited*](#format-v1-vs-v2-and-why-auto-import-is-limited)
below). So the three dashboards that back a deployed copy *also* carry the v1 classic model —
what the publish flow actually pushes — while all 10 keep the v2 export for the future gcx/v2
migration.

## Where they came from

1. The original dashboards (classic-model JSON in [`../dashboards/`](../dashboards/)) were
   published to Grafana Cloud by [`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh)
   via the classic **`POST /api/dashboards/db`** HTTP import.
2. They were then **deleted in Grafana Cloud, re-imported into a clean Grafana, and optimized +
   error-corrected by the Grafana Cloud AI assistant** (layout, queries, panel options and the
   in-panel documentation text).
3. The optimized result was **exported in the v2 schema (YAML + JSON)** — these files. The first
   **six** were exported on 2026-06-28 from stack namespace `stacks-1705996`. **Node
   Auto-Provisioning (Spot)** and **Tekton CI** were redesigned + exported on 2026-06-29, and
   **Argo Workflows CI** and **GitHub Actions (ARC) CI** on 2026-06-30 — all from `stacks-1707745`
   (a later stack incarnation; the Terraform-generated slug changes on each rebuild, so a fresh
   export session lands in a new `stacks-*` namespace).
4. For the **three** dashboards whose deployed copy was refreshed from the optimized version
   (Argo Workflows CI, GitHub Actions (ARC) CI, Node Auto-Provisioning), a **v1 classic-model
   JSON** was *also* exported (`CI-CD _ … .json`) — the source the [`../dashboards/`](../dashboards/)
   copies are refreshed from.

They are **based on the previous dashboards but substantially more optimized.**

## Format note (why this folder is separate)

| | This folder (`dashboards-cloud-export/`) | [`../dashboards/`](../dashboards/) |
|---|---|---|
| Schema | **v2** (all 10) **+ v1 classic** (3, the `CI-CD _ …` files) | **v1 classic model** (`panels[]` + `gridPos`) |
| Form | Grafana **resource** (metadata + spec) for v2; dashboard model for the v1 exports | dashboard model, JSON |
| Role | **immutable backup** of the AI-optimized exports, *as exported* | the dashboards the publish flow renders/pushes |

The v2 exports' `metadata.name`/`uid` is the dashboard uid — the first six carry the **random ids
Grafana assigned on re-import** (e.g. `inwtd8q`), while the four newest keep their stable
`jenkins2026-*` names (`jenkins2026-node-autoprovisioning`, `jenkins2026-tekton-overview`,
`jenkins2026-argo-workflows-ci`, `jenkins2026-github-actions-ci`). `metadata.namespace` is the
source stack — i.e. these are *stack-specific snapshots* (spanning `stacks-1705996` and
`stacks-1707745`), kept verbatim for provenance. They are **not edited**.

## Mapping (title ← file)

### v2 exports — all 10 (`dashboard-<epoch>.{json,yaml}`)

| Dashboard | YAML | JSON |
|---|---|---|
| CI-CD / Jenkins Controller | [`dashboard-1782669023549.yaml`](dashboard-1782669023549.yaml) | [`dashboard-1782669732187.json`](dashboard-1782669732187.json) |
| CI-CD / k6 Observability | [`dashboard-1782669069528.yaml`](dashboard-1782669069528.yaml) | [`dashboard-1782669744836.json`](dashboard-1782669744836.json) |
| CI-CD / Microservices Overview | [`dashboard-1782669097484.yaml`](dashboard-1782669097484.yaml) | [`dashboard-1782669755436.json`](dashboard-1782669755436.json) |
| CI-CD / PostgreSQL (CloudNativePG) | [`dashboard-1782669127927.yaml`](dashboard-1782669127927.yaml) | [`dashboard-1782669765865.json`](dashboard-1782669765865.json) |
| CI-CD Frontend RUM (Angular / Faro) | [`dashboard-1782669148583.yaml`](dashboard-1782669148583.yaml) | [`dashboard-1782669775397.json`](dashboard-1782669775397.json) |
| CI-CD JVM internals (all Java services + Jenkins) | [`dashboard-1782669169211.yaml`](dashboard-1782669169211.yaml) | [`dashboard-1782669785795.json`](dashboard-1782669785795.json) |
| CI-CD / Node Auto-Provisioning (Spot) | [`dashboard-1782770236821.yaml`](dashboard-1782770236821.yaml) | [`dashboard-1782770232037.json`](dashboard-1782770232037.json) |
| CI-CD / Tekton CI Observability | [`dashboard-1782777203013.yaml`](dashboard-1782777203013.yaml) | [`dashboard-1782777199433.json`](dashboard-1782777199433.json) |
| CI-CD / Argo Workflows CI Observability | [`dashboard-1782833394988.yaml`](dashboard-1782833394988.yaml) | [`dashboard-1782833386563.json`](dashboard-1782833386563.json) |
| CI-CD / GitHub Actions (ARC) CI Observability | [`dashboard-1782848857222.yaml`](dashboard-1782848857222.yaml) | [`dashboard-1782848852874.json`](dashboard-1782848852874.json) |

> Rows 7–8 (`jenkins2026-node-autoprovisioning` / `jenkins2026-tekton-overview`) are the
> 2026-06-29 exports and rows 9–10 (`jenkins2026-argo-workflows-ci` /
> `jenkins2026-github-actions-ci`) the 2026-06-30 exports — all from `stacks-1707745`; the
> first six are the 2026-06-28 set from `stacks-1705996`.

### v1 classic-model exports — 3 (`CI-CD _ <Title>-<epoch>.json`)

The **three** dashboards whose deployed [`../dashboards/`](../dashboards/) copy was refreshed from
the optimized version also ship the **v1 classic model** (`schemaVersion: 42`, `panels[]` +
`gridPos`) — the exact model the publish flow pushes:

| Dashboard | v1 classic JSON |
|---|---|
| CI-CD / Argo Workflows CI Observability | [`CI-CD _ Argo Workflows CI Observability-1782833412678_v1.json`](CI-CD%20_%20Argo%20Workflows%20CI%20Observability-1782833412678_v1.json) |
| CI-CD / GitHub Actions (ARC) CI Observability | [`CI-CD _ GitHub Actions (ARC) CI Observability-1782848871744.json`](CI-CD%20_%20GitHub%20Actions%20%28ARC%29%20CI%20Observability-1782848871744.json) |
| CI-CD / Node Auto-Provisioning (Spot) | [`CI-CD _ Node Auto-Provisioning (Spot)-1782897433407.json`](CI-CD%20_%20Node%20Auto-Provisioning%20%28Spot%29-1782897433407.json) |

These are the source for the AI-optimized [`../dashboards/argo-workflows-ci.json`](../dashboards/argo-workflows-ci.json),
[`../dashboards/github-actions-ci.json`](../dashboards/github-actions-ci.json) and
[`../dashboards/node-autoprovisioning.json`](../dashboards/node-autoprovisioning.json) refresh. The
only adaptation needed to make the committed copy portable: rewrite the Grafana Cloud datasource
uids (`grafanacloud-logs` / `grafanacloud-traces` → the repo's `loki` / `tempo`; a hardcoded
`grafanacloud-prom` → the `${DS_PROMETHEUS}` template var), then regenerate the `dashboards-azure/`
/ `dashboards-aws/` variants with their `generate.py`.

> **How a deployed copy is refreshed from an AI-optimized dashboard** (the NAP example, the general
> recipe): its deployed [`../dashboards/node-autoprovisioning.json`](../dashboards/node-autoprovisioning.json)
> had lagged behind the AI-optimized v2 export (`dashboard-1782770232037.json`) — still the earlier
> "lean free-tier slice" (6 panels), missing *Peak Spot nodes*, *Node readiness* and *Node Detail
> Inventory*. Because the publish flow upserts by `uid` with `overwrite:true`, a manually imported
> v2 copy gets clobbered on the next publish. Fixed by **round-tripping the live dashboard through
> the legacy `GET /api/dashboards/uid/…` endpoint** (which returns the classic model even for a v2
> dashboard), re-portabilizing its datasource ref, and regenerating the azure/aws variants — so the
> auto-deployed copy now *is* the 9-panel optimized dashboard. The v1 classic JSON in the table above
> is that same dashboard exported straight from Grafana.

## Format: v1 vs v2, and why auto-import is limited

**Which dashboards are which format**

| Set | Schema | Files | Auto-provisioned? |
|---|---|---|---|
| The 10 AI-optimized exports | **v2** (`dashboard.grafana.app/v2`) | `dashboard-<epoch>.{json,yaml}` (here) | **No** — kept for the future gcx/v2 migration |
| 3 of them, re-exported classic | **v1 classic** (`schemaVersion 42`) | `CI-CD _ <Title>-<epoch>.json` (here) | Indirectly — they seed [`../dashboards/`](../dashboards/) |
| The **deployed** dashboards | **v1 classic** | [`../dashboards/*.json`](../dashboards/) | **Yes** — this is what actually ships |

**The compatibility problem (today).** There are two ways to push a dashboard to Grafana Cloud, and
they do **not** accept the same schema:

- **Legacy HTTP API — `POST /api/dashboards/db`** (what [`07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh)
  uses): a single **idempotent upsert keyed by `uid`** (`overwrite:true`). It accepts **only the v1
  classic model** (`panels[]`); it **cannot** ingest a `dashboard.grafana.app/v2` resource. It is
  reliable — so this is the project's provisioning path.
- **`gcx resources push`** (Grafana's **Kubernetes-style resource API**, `apiVersion:
  dashboard.grafana.app/*`, `kind: Dashboard`): can carry **both v1 and v2** — but on Grafana Cloud
  today it is **not reliable for automation**. Pushing a v2 resource is treated as a *create*
  (`409 AlreadyExists` on re-runs; `409 "object has been modified"` on updates because
  `resourceVersion` isn't round-tripped), deletes are async (an immediate recreate hits the
  still-reserved name), and heavy churn can **desync the legacy vs k8s storage** (split-brain that
  rejects *both* paths). `gcx` is **not installed or called** by the script.

**Net effect:** the richest form (**v2**) is exactly the form that **can't be auto-imported reliably
right now**. So the deployed dashboards are kept as **v1 classic** and pushed via the legacy API, and
whenever the AI optimizes a dashboard in v2, its deployed copy is refreshed by pulling the **classic
model back** (`GET /api/dashboards/uid/<uid>` returns classic even for a v2 dashboard) rather than
pushing the v2 resource.

**Will this change?** Yes — that is the intended end state. Native **v2 + `gcx` (the k8s resource
API)** is Grafana's strategic direction (declarative, GitOps-style, the format Grafana now exports).
Once `gcx resources push` performs a proper server-side **apply/upsert** for `dashboard.grafana.app/v2`
(idempotent re-runs, no `409`, correct `resourceVersion` handling), the plan is to **switch the
`grafana-cloud` branch of `07-grafana-dashboards.sh` back to `gcx login` + `gcx resources push`** of
these v2 resources and drop the `POST /api/dashboards/db` loop — which is **exactly why the v2 exports
are kept here verbatim.** Full rationale + migration steps:
[`docs/301-OBSERVABILITY.md` → *Grafana Cloud dashboard provisioning: HTTP API today, gcx + v2 tomorrow*](../../../docs/301-OBSERVABILITY.md).

## How these get provisioned

**Today (accurate as of this repo):** [`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh)
publishes the classic-model [`../dashboards/*.json`](../dashboards/) — **not** these v2 exports — to
Grafana Cloud via **`POST /api/dashboards/db`** (`overwrite:true`, keyed by `uid`, into the *CI-CD
Observability* folder), using the static `GRAFANA_API_KEY`; the `loki`/`tempo` datasource uids are
rewritten to the Grafana Cloud built-ins at import time. It **does not use `gcx`** (see *Format: v1 vs
v2* above for why). managed-azure / managed-aws publish their own `-azure`/`-aws` variants through the
equivalent data-plane API.

**These files' role:** verbatim backup + the source the deployed copies are refreshed from. Do not
hand-edit Grafana and expect it to persist — round-trip through git: optimize in Grafana → export
(v2 here; plus the v1 classic for anything that backs a deployed copy) → refresh
[`../dashboards/`](../dashboards/) → regenerate the azure/aws variants.
