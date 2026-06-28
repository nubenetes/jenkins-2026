# Grafana Cloud dashboard exports (optimized) — backup / source of truth

These are the **6 platform dashboards exported from Grafana Cloud**, in Grafana's
**v2 dashboard schema** (`apiVersion: dashboard.grafana.app/v2`, `kind: Dashboard`),
serialized as **YAML**.

## Where they came from

1. The original dashboards (classic-model JSON in [`../dashboards/`](../dashboards/))
   were published to Grafana Cloud by `scripts/07-grafana-dashboards.sh` (via `gcx`).
2. They were then **deleted in Grafana Cloud, re-imported into a clean Grafana, and
   optimized + error-corrected by the Grafana Cloud AI assistant** (layout, queries,
   panel options and the in-panel documentation text).
3. The optimized result was **exported in the v2 schema (YAML)** — these files —
   on 2026-06-28 from stack namespace `stacks-1705996`.

They are **based on the previous dashboards but substantially more optimized.**

## Format note (why this folder is separate)

| | This folder (`dashboards-cloud-export/`) | [`../dashboards/`](../dashboards/) |
|---|---|---|
| Schema | **v2** (`dashboard.grafana.app/v2` — `elements` + `layout`) | **classic model** (`panels[]` + `gridPos`) |
| Form | Grafana **resource** (metadata + spec), YAML | dashboard model, JSON |
| Role | **immutable backup** of the AI-optimized exports, *as exported* | the dashboards the publish flow renders/pushes |

`metadata.name`/`uid` here are the **random ids Grafana assigned on re-import**
(e.g. `inwtd8q`), and `metadata.namespace` is the source stack — i.e. these are
*stack-specific snapshots*, kept verbatim for provenance. They are **not edited**.

## Mapping (title ← file)

| Dashboard | File |
|---|---|
| CI-CD / Jenkins Controller | `dashboard-1782669023549.yaml` |
| CI-CD / k6 Observability | `dashboard-1782669069528.yaml` |
| CI-CD / Microservices Overview | `dashboard-1782669097484.yaml` |
| CI-CD / PostgreSQL (CloudNativePG) | `dashboard-1782669127927.yaml` |
| CI-CD Frontend RUM (Angular / Faro) | `dashboard-1782669148583.yaml` |
| CI-CD JVM internals (all Java services + Jenkins) | `dashboard-1782669169211.yaml` |

## How these get provisioned

Provisioning is automated with **`gcx`** (`gcx login` + `gcx resources push`) from
`scripts/07-grafana-dashboards.sh`, the same tool the GitHub Actions workflows use to
push dashboards to Grafana Cloud. `gcx` consumes Grafana **resource manifests**
(`apiVersion/kind/metadata/spec`) — both the v1 form the script wraps classic JSON
into and the **v2** form of these files. See
[`docs/301-OBSERVABILITY.md`](../../../docs/301-OBSERVABILITY.md).

> Keep this folder as the verbatim backup. The operational, normalized resources that
> the publish flow pushes are derived from these (stable names, server-managed metadata
> stripped) — do not hand-edit Grafana and expect it to persist; round-trip through git.
