#!/usr/bin/env python3
"""Vendor community Kubernetes dashboards, normalized for Amazon Managed Grafana.

observability.mode=managed-aws ships the cluster/node infra metrics to Amazon
Managed Service for Prometheus (AMP) by scraping cadvisor + kubelet +
node-exporter + kube-state-metrics through the OTel Collector's `prometheus`
receiver (see ../../otel-collector/values-managed-aws.yaml). Those metrics keep
their Prometheus-native names in AMP (verified: e.g. container_cpu_usage_seconds_total
round-trips intact through the collector's prometheusremotewrite exporter), so
the mature Prometheus-ecosystem dashboards render against them as-is - AMG ships
no Kubernetes dashboards of its own.

We deliberately vendor the **dotdc "Kubernetes / Views"** set + **node-exporter
full** rather than the kube-prometheus-stack / kubernetes-mixin dashboards: the
mixin panels depend on Prometheus *recording rules* (node_namespace_pod_container:...)
that a managed AMP workspace doesn't evaluate, so half of them would be empty.
The dotdc + node-exporter dashboards query **raw** metrics, so they work with no
recording rules. (Loading the mixin recording rules into AMP as a rule-groups
namespace is the tracked follow-up if those richer views are ever wanted - no
in-cluster Prometheus required.)

What this script changes vs. the upstream JSON (and only this):
  - renames the dashboard's prometheus datasource template variable to
    `DS_PROMETHEUS`, and rewrites every `${<oldname>}` datasource reference to
    `${DS_PROMETHEUS}`. scripts/07-grafana-dashboards.sh binds `${DS_PROMETHEUS}`
    to the AMP datasource uid it discovers at publish time - the same
    account-agnostic, keyless substitution the custom *-aws.json variants use.
  - strips `__inputs` / `__requires` (the grafana.com import wrapper) and nulls
    `id` so the dashboard imports cleanly by stable `uid`.

Account-agnostic: no datasource uid, workspace id or account id is baked in.

Re-vendor (refresh from the pinned upstreams):
    python3 observability/grafana/dashboards-aws/community/vendor.py
"""
from __future__ import annotations

import json
import pathlib
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent

# Pinned upstream sources for reproducibility.
DOTDC_TAG = "v3.0.6"  # github.com/dotdc/grafana-dashboards-kubernetes
DOTDC_BASE = f"https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/{DOTDC_TAG}/dashboards"
NODE_EXPORTER_REV = 45  # grafana.com dashboard 1860 "Node Exporter Full"

SOURCES = {
    "k8s-views-global.json": f"{DOTDC_BASE}/k8s-views-global.json",
    "k8s-views-namespaces.json": f"{DOTDC_BASE}/k8s-views-namespaces.json",
    "k8s-views-nodes.json": f"{DOTDC_BASE}/k8s-views-nodes.json",
    "k8s-views-pods.json": f"{DOTDC_BASE}/k8s-views-pods.json",
    "node-exporter-full.json": (
        f"https://grafana.com/api/dashboards/1860/revisions/{NODE_EXPORTER_REV}/download"
    ),
}

# The template-variable name scripts/07-grafana-dashboards.sh binds to AMP.
DS_VAR = "DS_PROMETHEUS"


def _fetch(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=30) as resp:  # noqa: S310 (pinned hosts)
        return json.load(resp)


def _normalize(dash: dict) -> dict:
    # Find the prometheus datasource template variable and rename it to DS_PROMETHEUS.
    old_name = None
    for var in dash.get("templating", {}).get("list", []):
        if var.get("type") == "datasource" and var.get("query") == "prometheus":
            old_name = var["name"]
            var["name"] = DS_VAR
            break
    if old_name is None:
        raise SystemExit("no prometheus datasource template variable found")

    # Rewrite every `${old_name}` datasource reference to `${DS_PROMETHEUS}`.
    if old_name != DS_VAR:
        text = json.dumps(dash)
        text = text.replace("${" + old_name + "}", "${" + DS_VAR + "}")
        dash = json.loads(text)

    # Drop the grafana.com import wrapper and let AMG key by stable uid.
    dash.pop("__inputs", None)
    dash.pop("__requires", None)
    dash["id"] = None
    return dash


def main() -> None:
    for filename, url in SOURCES.items():
        dash = _normalize(_fetch(url))
        out = HERE / filename
        out.write_text(json.dumps(dash, indent=2) + "\n")
        print(f"vendored {filename}  (uid={dash.get('uid')})")


if __name__ == "__main__":
    main()
