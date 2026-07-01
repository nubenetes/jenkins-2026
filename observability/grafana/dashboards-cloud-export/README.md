# Grafana Cloud dashboard exports (optimized) — backup / source of truth

These are the **platform dashboards exported from Grafana Cloud**, in Grafana's
**v2 dashboard schema** (`apiVersion: dashboard.grafana.app/v2`, `kind: Dashboard`),
kept in **both serializations**:

- **YAML** (`*.yaml`) — **10 dashboards** (the full set).
- **JSON** (`*.json`) — **10 dashboards** (same content, same set).

Both formats are the **same v2 resources** — pick whichever the tooling prefers
(`gcx resources push` accepts either).

The two newest (**Argo Workflows CI** + **GitHub Actions (ARC) CI**) *additionally* ship a
**v1 classic-model** export (`CI-CD _ … .json`, `schemaVersion: 42`, `panels[]`) — the same
model the auto-deployed [`../dashboards/`](../dashboards/) versions use — kept here as the
source those deployed copies are refreshed from (see *v1 classic-model exports* below).

## Where they came from

1. The original dashboards (classic-model JSON in [`../dashboards/`](../dashboards/))
   were published to Grafana Cloud by [`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh) (via `gcx`).
2. They were then **deleted in Grafana Cloud, re-imported into a clean Grafana, and
   optimized + error-corrected by the Grafana Cloud AI assistant** (layout, queries,
   panel options and the in-panel documentation text).
3. The optimized result was **exported in the v2 schema (YAML + JSON)** — these files.
   The first **six** were exported on 2026-06-28 from stack namespace `stacks-1705996`.
   The next two — **CI-CD / Node Auto-Provisioning (Spot)** and **CI-CD / Tekton CI
   Observability** — were redesigned in Grafana Cloud and exported on 2026-06-29 from
   `stacks-1707745` (a later stack incarnation — the Terraform-generated slug changes on
   each rebuild, so a fresh export session lands in a new `stacks-*` namespace). The two
   newest — **CI-CD / Argo Workflows CI Observability** and **CI-CD / GitHub Actions (ARC)
   CI Observability** — were redesigned + exported on 2026-06-30, also from `stacks-1707745`
   (v2 YAML + JSON, **plus a v1 classic-model JSON** so the auto-deployed copies can be
   refreshed from the same optimized source).

They are **based on the previous dashboards but substantially more optimized.**

## Format note (why this folder is separate)

| | This folder (`dashboards-cloud-export/`) | [`../dashboards/`](../dashboards/) |
|---|---|---|
| Schema | **v2** (`dashboard.grafana.app/v2` — `elements` + `layout`) | **classic model** (`panels[]` + `gridPos`) |
| Form | Grafana **resource** (metadata + spec), YAML | dashboard model, JSON |
| Role | **immutable backup** of the AI-optimized exports, *as exported* | the dashboards the publish flow renders/pushes |

`metadata.name`/`uid` is the dashboard uid — the first six carry the **random ids Grafana
assigned on re-import** (e.g. `inwtd8q`), while the four newest keep their stable
`jenkins2026-*` names (`jenkins2026-node-autoprovisioning`, `jenkins2026-tekton-overview`,
`jenkins2026-argo-workflows-ci`, `jenkins2026-github-actions-ci`).
`metadata.namespace` is the source stack — i.e. these are *stack-specific snapshots* (now
spanning `stacks-1705996` and `stacks-1707745`), kept verbatim for provenance. They are
**not edited**.

## Mapping (title ← file)

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

## v1 classic-model exports (source for the deployed copies)

The two 2026-06-30 CI dashboards also ship the **v1 classic model** they were optimized in
(`schemaVersion: 42`, `panels[]` + `gridPos`) — the exact model the publish flow renders from
[`../dashboards/`](../dashboards/):

| Dashboard | v1 classic JSON |
|---|---|
| CI-CD / Argo Workflows CI Observability | [`CI-CD _ Argo Workflows CI Observability-1782833412678_v1.json`](CI-CD%20_%20Argo%20Workflows%20CI%20Observability-1782833412678_v1.json) |
| CI-CD / GitHub Actions (ARC) CI Observability | [`CI-CD _ GitHub Actions (ARC) CI Observability-1782848871744.json`](CI-CD%20_%20GitHub%20Actions%20%28ARC%29%20CI%20Observability-1782848871744.json) |

These are the source for the AI-optimized [`../dashboards/argo-workflows-ci.json`](../dashboards/argo-workflows-ci.json)
+ [`../dashboards/github-actions-ci.json`](../dashboards/github-actions-ci.json) refresh. The only
adaptation needed: the Grafana Cloud `grafanacloud-logs` / `grafanacloud-traces` datasource uids
→ the repo's portable `loki` / `tempo` (then the `dashboards-azure/` / `dashboards-aws/` variants
are regenerated by their `generate.py`).

> **Node Auto-Provisioning (Spot)** got the same treatment retroactively. Its deployed
> [`../dashboards/node-autoprovisioning.json`](../dashboards/node-autoprovisioning.json) had lagged
> behind the AI-optimized v2 export (`dashboard-1782770232037.json`) — it was still the earlier
> "lean free-tier slice" (6 panels), missing *Peak Spot nodes*, *Node readiness* and *Node Detail
> Inventory*. Because `07-grafana-dashboards.sh` upserts by uid with `overwrite:true`, a manually
> imported v2 copy would be clobbered on the next publish. Fixed by **round-tripping the live
> dashboard through the legacy `GET /api/dashboards/uid/…` endpoint** (which returns the classic
> model), re-portabilizing its one hardcoded `grafanacloud-prom` datasource ref back to
> `${DS_PROMETHEUS}`, and regenerating the azure/aws variants — so the auto-deployed copy now *is*
> the 9-panel optimized dashboard.

## How these get provisioned

Provisioning is automated with **`gcx`** (`gcx login` + `gcx resources push`) from
[`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh), the same tool the GitHub Actions workflows use to
push dashboards to Grafana Cloud. `gcx` consumes Grafana **resource manifests**
(`apiVersion/kind/metadata/spec`) — both the v1 form the script wraps classic JSON
into and the **v2** form of these files. See
[`docs/301-OBSERVABILITY.md`](../../../docs/301-OBSERVABILITY.md).

> Keep this folder as the verbatim backup. The operational, normalized resources that
> the publish flow pushes are derived from these (stable names, server-managed metadata
> stripped) — do not hand-edit Grafana and expect it to persist; round-trip through git.
