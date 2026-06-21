# Community Kubernetes dashboards (managed-aws)

Vendored, upstream Kubernetes / node-infra dashboards for **Amazon Managed
Grafana** (`observability.mode=managed-aws`), bound to **Amazon Managed Service
for Prometheus (AMP)** at publish time.

Why these live here at all: in `managed-aws` mode the cluster/node infra metrics
(cadvisor + kubelet + node-exporter + kube-state-metrics) are scraped by the OTel
Collector's `prometheus` receiver and remote-written to AMP via SigV4 (see
[`../../otel-collector/values-managed-aws.yaml`](../../otel-collector/values-managed-aws.yaml)).
Unlike Azure Managed Grafana (which auto-provisions infra dashboards from its
Azure Monitor integration), **AMG ships no Kubernetes dashboards** - the metrics
sit in AMP but nothing renders them. These dashboards fill that gap.

## Why the OTel pipeline doesn't break Prometheus dashboards

Our collector is the **OpenTelemetry Collector**, not a vanilla Prometheus
agent, so the scrape path is `prometheus receiver -> prometheusremotewrite
exporter -> AMP`. That round-trip *could* mangle metric names (OTLP unit/type
normalization, `add_metric_suffixes`, `resource_to_telemetry_conversion`), which
would silently break every Prometheus-ecosystem dashboard.

It doesn't, and we verified it against the live AMP workspace: the OTel
prometheus receiver preserves the original Prometheus metric name and the
remote-write exporter doesn't re-suffix already-suffixed names, so the names land
intact:

| Queried by the dashboards | In AMP |
|---|---|
| `container_cpu_usage_seconds_total` | ✅ identical |
| `container_memory_working_set_bytes` | ✅ identical |
| `kube_deployment_status_replicas` | ✅ identical |
| `node_cpu_seconds_total` | ✅ identical |
| histogram `*_bucket` / `_count` / `_sum` | ✅ intact |

The labels survive too (`cluster`, `namespace`, `pod`, `node`, `instance`,
`job`, `container`), so the dashboards' `$cluster` / `$namespace` template
variables resolve. **Conclusion: Prometheus-native dashboards work as-is against
AMP** - no per-metric rewriting needed, only the datasource binding (below).

## Why dotdc and not kube-prometheus-stack / kubernetes-mixin

The obvious choice would be the kube-prometheus-stack dashboards (the
`kubernetes-mixin` set). They're a poor fit **here** for two independent reasons:

1. **Recording rules.** The mixin panels query precomputed series produced by
   Prometheus *recording rules* - e.g.
   `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate`.
   Those rules are installed as `PrometheusRule` CRs and evaluated by a
   Prometheus server. We have **no in-cluster Prometheus** - the OTel Collector
   just remote-writes raw scrapes to AMP - so those series don't exist and the
   panels that depend on them render empty.
2. **They assume the full stack is present.** They're authored against the
   kube-prometheus-stack's own labels/jobs and operator-managed targets.

The **dotdc "Kubernetes / Views"** dashboards (+ **Node Exporter Full**) instead
query **raw** metrics (`kube_*`, `container_*`, `node_*`, `kubelet_*`) directly,
so they need **zero recording rules** and work against a managed AMP workspace
out of the box.

### The decision in one table

| | Footprint | What it unlocks | Verdict here |
|---|---|---|---|
| **A. dotdc Views + node-exporter** | zero rules, just dashboards | Cluster / Namespace / Node / Pod views + per-node detail | ✅ **chosen** |
| **B. dotdc + mixin recording rules in AMP** | upload rule-groups to AMP (`aws amp create-rule-groups-namespace`) - **no in-cluster Prometheus** | + the richer mixin views | 🔜 tracked follow-up if wanted |
| **C. full kube-prometheus-stack** | in-cluster Prometheus + Operator + CRDs + Alertmanager | the complete mixin + alerts | ❌ rejected |

Why **C is rejected** even though it's the "standard" install:

- **It duplicates AMP.** The whole point of `managed-aws` is that there is *no*
  Prometheus to operate - AMP **is** the Prometheus and the collector
  remote-writes to it. A kube-prometheus-stack Prometheus server re-scrapes and
  re-stores everything, so you'd run two scrape paths and two TSDBs and throw
  away the managed value proposition.
- **Operator/CRD overhead.** It brings the Prometheus Operator and its large
  CRDs (the same class of giant-CRD object that tripped ArgoCD's 256 KB
  annotation limit for CNPG) - more to reconcile, more failure surface, in a PoC
  that deliberately chose managed backends to avoid exactly this.
- **It only helps one of four backends.** The OTel Collector pipeline is
  identical across `grafana-cloud` / `oss` / `managed-azure` / `managed-aws`.
  kube-prometheus-stack is Prometheus-specific - it does nothing for the Azure
  Monitor or Grafana Cloud OTLP paths.

If the mixin views are ever wanted, **B** is the proportionate move: AMP
evaluates recording/alerting rules server-side, so you upload the mixin rule
YAML as a rule-groups namespace and keep the single-collector architecture - no
Prometheus server.

## Why not go fully OTel-native instead?

There is **no mature "kube-prometheus-stack but OTel-native" bundle**. The
OTel-native building blocks exist - they'd replace the classic exporters:

| Replaces | OTel-native receiver | Emits |
|---|---|---|
| kube-state-metrics | `k8s_cluster` | `k8s.pod.phase`, `k8s.deployment.available`, … |
| cadvisor + kubelet | `kubeletstats` | `k8s.pod.cpu.usage`, `container.memory.working_set`, … |
| node-exporter | `hostmetrics` | `system.cpu.utilization`, `system.memory.usage`, … |

But those emit **OTel-semantic-convention** names (dotted: `k8s.pod.cpu.usage`),
which become `k8s_pod_cpu_usage` in Prometheus/AMP and match **no** existing
Prometheus dashboard - and the OTel-native dashboard ecosystem is far thinner
than the mixin/dotdc world. So going OTel-native means **more work and less
mature dashboards**.

Our approach is the pragmatic best-of-both: the OTel Collector is the single
unified transport, but it scrapes the classic exporters with the `prometheus`
receiver so metric names stay **Prometheus-native** - and we reuse the whole
mature Prometheus dashboard ecosystem for free.

## What `vendor.py` changes (and only this)

[`vendor.py`](vendor.py) downloads the pinned upstreams and normalizes each so it
imports cleanly and binds to AMP without baking in any account/datasource id:

- **renames the prometheus datasource template variable to `DS_PROMETHEUS`** and
  rewrites every `${<oldname>}` reference to `${DS_PROMETHEUS}`.
  [`../../../scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh)
  substitutes `${DS_PROMETHEUS}` with the real AMP datasource uid it discovers
  (or creates) at publish time - the same account-agnostic, keyless binding the
  custom `*-aws.json` variants use for their CloudWatch / X-Ray datasources.
- **strips `__inputs` / `__requires`** (the grafana.com import wrapper) and nulls
  `id`, so AMG imports by stable `uid` and overwrites in place on re-run.

Pinned sources (bump in `vendor.py`, then re-run):

| File | Upstream | Pin |
|---|---|---|
| `k8s-views-global.json` | dotdc `k8s-views-global` | `v3.0.6` |
| `k8s-views-namespaces.json` | dotdc `k8s-views-namespaces` | `v3.0.6` |
| `k8s-views-nodes.json` | dotdc `k8s-views-nodes` | `v3.0.6` |
| `k8s-views-pods.json` | dotdc `k8s-views-pods` | `v3.0.6` |
| `node-exporter-full.json` | grafana.com 1860 "Node Exporter Full" | rev `45` |

Re-vendor (refresh from the pinned upstreams):

```bash
python3 observability/grafana/dashboards-aws/community/vendor.py
```

## How they're published

`scripts/07-grafana-dashboards.sh` (mode `managed-aws`) publishes both
`dashboards-aws/*-aws.json` and `dashboards-aws/community/*.json` to AMG over its
Grafana HTTP API, binding `${DS_PROMETHEUS}` to the AMP datasource. It's
get-or-create / overwrite-by-uid, so re-runs converge without duplicates. See the
[parent README](../README.md) for the keyless service-account-token mechanics.

> **Live data caveat.** These render with data only when the cluster is in
> `managed-aws` mode (so the collector is actively remote-writing to AMP). In
> any other `observability.mode`, AMP receives no fresh samples and the panels
> read empty (or stale), even though the dashboards import fine.
