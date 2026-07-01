# Grafana Cloud dashboard exports (optimized) — backup / source of truth

This folder is the **backup / source of truth** for the platform dashboards **after the Grafana
Cloud AI assistant optimized them** (layout, queries, panel options, in-panel docs). For **each of
the 10 dashboards** it keeps **three files**:

| Suffix | Schema | What it is |
|---|---|---|
| **`.v2.yaml`** | **v2** (`dashboard.grafana.app/v2`, `kind: Dashboard` — `elements` + `layout`) | the AI-optimized export, YAML serialization |
| **`.v2.json`** | **v2** (same resource) | the AI-optimized export, JSON serialization (identical content to the YAML) |
| **`.v1.json`** | **v1 classic model** (`schemaVersion: 42`, `panels[]` + `gridPos`) | the same dashboard re-exported in the classic model — the form the deployed copy uses |

**File naming: `<slug>.<version>.<ext>`**, where `<slug>` is the **same slug as the deployed
[`../dashboards/<slug>.json`](../dashboards/)** — so all three exports of a dashboard sort together
and line up 1:1 with the operational copy (e.g. `jenkins-overview.*` ↔ `../dashboards/jenkins-overview.json`).
The files were canonicalized from Grafana's raw export names (`dashboard-<epoch>.{json,yaml}` for v2,
`CI-CD _ <Title>-<epoch>.json` for v1); the export epochs live in git history (see [*Provenance*](#provenance)).

Why keep all three: the **v2** export is the richest form the AI produces, but **v2 can't be
auto-provisioned reliably today** (see [*Format: v1 vs v2*](#format-v1-vs-v2-and-why-auto-import-is-limited)).
So the **v1 classic** is what the publish flow actually pushes — kept here as the source the deployed
copies are refreshed from — while the **v2** is retained for the future gcx/v2 migration.

## Inventory — 10 dashboards × 3 formats

Each row is one dashboard; the three columns are its three exports. The deployed (operational) copy is
[`../dashboards/<slug>.json`](../dashboards/) — same `<slug>` as the file names below.

| Dashboard | uid | v2 YAML | v2 JSON | v1 classic JSON |
|---|---|---|---|---|
| CI-CD / Jenkins Controller | `inwtd8q` | [`jenkins-overview.v2.yaml`](jenkins-overview.v2.yaml) | [`jenkins-overview.v2.json`](jenkins-overview.v2.json) | [`jenkins-overview.v1.json`](jenkins-overview.v1.json) |
| CI-CD / k6 Observability | `inwc64t` | [`k6-smoke-overview.v2.yaml`](k6-smoke-overview.v2.yaml) | [`k6-smoke-overview.v2.json`](k6-smoke-overview.v2.json) | [`k6-smoke-overview.v1.json`](k6-smoke-overview.v1.json) |
| CI-CD / Microservices Overview | `inwfvww` | [`microservices-overview.v2.yaml`](microservices-overview.v2.yaml) | [`microservices-overview.v2.json`](microservices-overview.v2.json) | [`microservices-overview.v1.json`](microservices-overview.v1.json) |
| CI-CD / PostgreSQL (CloudNativePG) | `inllvhz` | [`postgres-overview.v2.yaml`](postgres-overview.v2.yaml) | [`postgres-overview.v2.json`](postgres-overview.v2.json) | [`postgres-overview.v1.json`](postgres-overview.v1.json) |
| CI-CD Frontend RUM (Angular / Faro) | `in7bmb6` | [`rum-frontend.v2.yaml`](rum-frontend.v2.yaml) | [`rum-frontend.v2.json`](rum-frontend.v2.json) | [`rum-frontend.v1.json`](rum-frontend.v1.json) |
| CI-CD JVM internals (all Java services + Jenkins) | `innrq4f` | [`jvm-internals.v2.yaml`](jvm-internals.v2.yaml) | [`jvm-internals.v2.json`](jvm-internals.v2.json) | [`jvm-internals.v1.json`](jvm-internals.v1.json) |
| CI-CD / Node Auto-Provisioning (Spot) | `jenkins2026-node-autoprovisioning` | [`node-autoprovisioning.v2.yaml`](node-autoprovisioning.v2.yaml) | [`node-autoprovisioning.v2.json`](node-autoprovisioning.v2.json) | [`node-autoprovisioning.v1.json`](node-autoprovisioning.v1.json) |
| CI-CD / Tekton CI Observability | `jenkins2026-tekton-overview` | [`tekton-overview.v2.yaml`](tekton-overview.v2.yaml) | [`tekton-overview.v2.json`](tekton-overview.v2.json) | [`tekton-overview.v1.json`](tekton-overview.v1.json) |
| CI-CD / Argo Workflows CI Observability | `jenkins2026-argo-workflows-ci` | [`argo-workflows-ci.v2.yaml`](argo-workflows-ci.v2.yaml) | [`argo-workflows-ci.v2.json`](argo-workflows-ci.v2.json) | [`argo-workflows-ci.v1.json`](argo-workflows-ci.v1.json) |
| CI-CD / GitHub Actions (ARC) CI Observability | `jenkins2026-github-actions-ci` | [`github-actions-ci.v2.yaml`](github-actions-ci.v2.yaml) | [`github-actions-ci.v2.json`](github-actions-ci.v2.json) | [`github-actions-ci.v1.json`](github-actions-ci.v1.json) |

> The v2 YAML and v2 JSON of a row are the **same v2 resource**, two serializations — pick whichever
> the tooling prefers. The v1 classic JSON is the **source the deployed `../dashboards/<slug>.json`
> is refreshed from**.

## Format: v1 vs v2, and why auto-import is limited

**Which is which**

| Set | Schema | Files | Auto-provisioned? |
|---|---|---|---|
| The 10 AI-optimized exports | **v2** (`dashboard.grafana.app/v2`) | `<slug>.v2.{yaml,json}` (here) | **No** — kept for the future gcx/v2 migration |
| The same 10, re-exported classic | **v1 classic** (`schemaVersion 42`) | `<slug>.v1.json` (here) | Indirectly — they seed [`../dashboards/`](../dashboards/) |
| The **deployed** dashboards | **v1 classic** | [`../dashboards/<slug>.json`](../dashboards/) | **Yes** — this is what actually ships |

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
the `.v2.*` resources and drop the `POST /api/dashboards/db` loop — which is **exactly why the v2
exports are kept here.** Full rationale + migration steps:
[`docs/301-OBSERVABILITY.md` → *Grafana Cloud dashboard provisioning: HTTP API today, gcx + v2 tomorrow*](../../../docs/301-OBSERVABILITY.md).

## How these get provisioned

**Today:** [`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh) publishes the
classic-model [`../dashboards/*.json`](../dashboards/) — **not** the exports in this folder — to Grafana
Cloud via **`POST /api/dashboards/db`** (`overwrite:true`, keyed by `uid`, into the *CI-CD Observability*
folder), using the static `GRAFANA_API_KEY`; the `loki`/`tempo` datasource uids are rewritten to the
Grafana Cloud built-ins at import time. It **does not use `gcx`** (see *Format: v1 vs v2* above for why).
managed-azure / managed-aws publish their own `-azure`/`-aws` variants through the equivalent data-plane
API.

**These files' role** is backup + the source the deployed copies are refreshed from. To refresh a
deployed copy from an AI-optimized dashboard (the general recipe, e.g. the NAP/Spot dashboard, which had
lagged behind at a "lean free-tier slice"): **round-trip the live dashboard through the legacy
`GET /api/dashboards/uid/<uid>` endpoint** (which returns the classic model even for a v2 dashboard) →
re-portabilize its datasource uids (`grafanacloud-logs`/`grafanacloud-traces` → `loki`/`tempo`; a
hardcoded `grafanacloud-prom` → the `${DS_PROMETHEUS}` template var) → save as `../dashboards/<slug>.json`
→ regenerate the `dashboards-azure/`/`dashboards-aws/` variants with their `generate.py`. Do **not**
hand-edit Grafana and expect it to persist — round-trip through git.

## Where they came from

1. The original dashboards (classic-model JSON in [`../dashboards/`](../dashboards/)) were published to
   Grafana Cloud by [`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh) via the
   classic `POST /api/dashboards/db` import.
2. They were then **deleted in Grafana Cloud, re-imported into a clean Grafana, and optimized +
   error-corrected by the Grafana Cloud AI assistant** (layout, queries, panel options, in-panel docs).
3. The optimized result was **exported in the v2 schema** (`.v2.yaml` + `.v2.json`) and later **re-exported
   in the v1 classic model** (`.v1.json`) so the deployed copies can be refreshed from the same optimized
   source.

They are **based on the previous dashboards but substantially more optimized.**

## Provenance

- **v2 exports (AI-optimized snapshots):** Jenkins / k6 / Microservices / PostgreSQL / RUM / JVM were
  exported **2026-06-28** from stack `stacks-1705996` — these carry the **random uids Grafana assigned on
  re-import** (`inwtd8q`, `inwc64t`, `inwfvww`, `inllvhz`, `in7bmb6`, `innrq4f`). Node Auto-Provisioning +
  Tekton were exported **2026-06-29**, and Argo Workflows + GitHub Actions **2026-06-30**, both from
  `stacks-1707745` — these keep the stable `jenkins2026-*` uids. (The Terraform-generated stack slug changes
  on each rebuild, so a fresh export session lands in a new `stacks-*` namespace.)
- **v1 classic exports:** Argo + GitHub Actions **2026-06-30**; Node Auto-Provisioning + the other seven
  **2026-07-01**.
- These are **stack-specific snapshots kept verbatim** — the Grafana Cloud `grafanacloud-*` datasource uids
  are left intact (the deployed [`../dashboards/`](../dashboards/) copies are the portabilized versions,
  using `loki`/`tempo`/`${DS_PROMETHEUS}`). Filenames were canonicalized to `<slug>.<version>.<ext>`; the
  original Grafana export names and their epochs remain in git history. Do not hand-edit these — re-export
  from Grafana and round-trip through git.
