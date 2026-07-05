# Canonical Grafana dashboards — source of truth

This directory holds the **canonical dashboard JSON** for the platform: one
classic-model (`schemaVersion 42`, `panels[]`) file per dashboard, portable
across all four `observability.mode` backends. Edit the dashboards **here** —
the AWS/Azure variants are *generated* from these, and the cloud-export copies
are *backups*, so this is the one place a change should ever start.

It is **also a small Helm chart** ([`Chart.yaml`](Chart.yaml) +
[`values.yaml`](values.yaml) + [`templates/configmap.yaml`](templates/configmap.yaml)):
in `observability.mode=oss` the ArgoCD `oss-grafana-dashboards` child app renders
these `*.json` into a ConfigMap. The `*.json` consumers (`generate.py`,
`scripts/07-grafana-dashboards.sh`) glob only `*.json` and **ignore** the
`Chart.yaml` / `values.yaml` / `templates/` files, so the two roles coexist in
one directory without collision.

## Inventory — 10 dashboards

Six always ship; four are **CI-engine-gated** (only the active `ci.engine`'s CI
overview is deployed, so a cluster never shows an empty board for an engine that
isn't running):

| File | Ships when |
|---|---|
| `microservices-overview.json` | always |
| `k6-smoke-overview.json` | always |
| `postgres-overview.json` | always |
| `jvm-internals.json` | always |
| `node-autoprovisioning.json` | always |
| `rum-frontend.json` | always |
| `jenkins-overview.json` | `ci.engine=jenkins` only |
| `tekton-overview.json` | `ci.engine=tekton` only |
| `github-actions-ci.json` | `ci.engine=githubactions` only |
| `argo-workflows-ci.json` | `ci.engine=argoworkflows` only |

## How these get provisioned (per mode)

- **`oss`** — GitOps, **not** script-managed. The
  [`observability-oss`](../../../argocd/observability-oss/) app-of-apps emits an
  `oss-grafana-dashboards` child Application pointing at *this chart*, which
  renders the canonical `*.json` into the `jenkins-2026-grafana-dashboards`
  ConfigMap (mounted by Grafana via `dashboardsConfigMaps` in
  [`values-oss.yaml`](../values-oss.yaml)). The
  [`configmap.yaml`](templates/configmap.yaml) template drops the three
  off-engine CI overviews using the `ciEngine` value, which flows
  app-of-apps → parent Application parameter →
  [`scripts/03-observability.sh`](../../../scripts/03-observability.sh)
  (`{{ciEngine}}` substituted from `J2026_CI_ENGINE`). **Editing a dashboard and
  committing is enough** — ArgoCD auto-syncs it.
- **`grafana-cloud`** —
  [`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh)
  publishes every `*.json` here to Grafana Cloud via the legacy
  **`POST /api/dashboards/db`** import: an idempotent **upsert keyed by `uid`**
  (`overwrite:true`, into the *CI-CD Observability* folder). The script applies
  the same off-engine gating via its `KEEP_CI_DASHBOARD` variable (it publishes
  only the active engine's overview and deletes any stale off-engine one). The
  `loki`/`tempo` datasource uids are rewritten to the Grafana Cloud built-ins at
  import time.
- **`managed-azure` / `managed-aws`** — publish the *generated* `-azure` /
  `-aws` variants (see below), **not** these files, through the equivalent
  data-plane API.

> **⚠️ Hand-imported dashboard edits get clobbered on the next publish.** Both
> the OSS ArgoCD sync and the cloud `POST /api/dashboards/db` upsert are keyed
> by `uid` with `overwrite:true` (and the OSS ConfigMap is rendered fresh from
> git every sync), so any change you make in the **Grafana UI** is silently
> overwritten the next time the dashboards are published. **Round-trip through
> git instead**: export the live dashboard via
> `GET /api/dashboards/uid/<uid>` (Grafana returns the classic model even for a
> v2 dashboard), re-portabilize its datasource uids
> (`grafanacloud-logs`/`grafanacloud-traces` → `loki`/`tempo`; a hardcoded
> `grafanacloud-prom` → the `${DS_PROMETHEUS}` template var), and commit it as
> `<slug>.json` here.

## Adding or changing a dashboard

1. Edit (or add) the canonical `<slug>.json` in this directory. Keep datasources
   portable: Prometheus panels bind through the `${DS_PROMETHEUS}` template
   variable; Loki/Tempo panels use the neutral `loki`/`tempo` uids (rewritten
   per backend at publish/generate time).
2. Regenerate the cloud-provider variants so all four backends stay in sync:
   ```bash
   python3 observability/grafana/dashboards-aws/generate.py    # -> dashboards-aws/*.json
   python3 observability/grafana/dashboards-azure/generate.py  # -> dashboards-azure/*.json
   ```
3. Commit. In `oss` mode ArgoCD auto-syncs; in the cloud modes re-run
   `scripts/07-grafana-dashboards.sh` (or the matching `Day1`/`Day2.publish.*`
   workflow).

## Sibling directories

| Directory | Role |
|---|---|
| `dashboards/` *(this one)* | canonical classic-model source of truth **+** the OSS Helm chart |
| [`../dashboards-azure/`](../dashboards-azure/) | **generated** managed-azure variants (Loki/Tempo → Azure Monitor) |
| [`../dashboards-aws/`](../dashboards-aws/) | **generated** managed-aws variants (Loki → CloudWatch Logs, Tempo → X-Ray) + vendored community k8s boards |
| [`../dashboards-cloud-export/`](../dashboards-cloud-export/) | AI-optimized **v2** exports (backup + the source these copies are refreshed from) |

## See also

- [`docs/301-OBSERVABILITY.md` § Observability Dashboards](../../../docs/301-OBSERVABILITY.md#observability-dashboards)
  — the full dashboard architecture, per-dashboard inventory, provisioning flow,
  and the *HTTP API today, gcx + v2 tomorrow* rationale.
