#!/usr/bin/env python3
"""Generate the managed-aws dashboard variants from the canonical dashboards.

observability.mode=managed-aws visualizes telemetry in Amazon Managed Grafana,
which reads from AWS datasources - not Prometheus/Loki/Tempo. This script derives
`<name>-aws.json` from each `../dashboards/<name>.json`, changing only what must
change so the variants stay in sync with the originals:

  - METRIC panels (Prometheus / PromQL): left untouched. Amazon Managed Service
    for Prometheus is a Prometheus-compatible datasource, so the
    `${DS_PROMETHEUS}` datasource variable (type `prometheus`) binds to it and
    the PromQL queries work as-is.
  - LOG panels (Loki): rewritten to a CloudWatch Logs Insights query over the
    collector's log group (where the OTel logs land via the awscloudwatchlogs
    exporter).
  - TRACE panels (Tempo): rewritten to an AWS X-Ray getTraceSummaries query
    (where the OTel traces land via the awsxray exporter).

Account-agnostic: the CloudWatch / X-Ray datasource uids are NOT baked in - they
are substituted at publish time by scripts/07-grafana-dashboards.sh (placeholders DS_CW_UID /
DS_XRAY_UID), the same way the Azure variant substitutes its datasource. The AMP
log group name is a project constant. The datasources authenticate with the AMG
workspace IAM role, so no secrets live in the dashboards.

Regenerate after editing the canonical dashboards:
    python3 observability/grafana/dashboards-aws/generate.py
"""
from __future__ import annotations

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SRC_DIR = HERE.parent / "dashboards"

# Placeholder uids substituted by scripts/07-grafana-dashboards.sh with the real AMG datasource uids.
CW_DS = {"type": "cloudwatch", "uid": "DS_CW_UID"}
XRAY_DS = {"type": "grafana-x-ray-datasource", "uid": "DS_XRAY_UID"}

# The collector's CloudWatch log group (project constant, see
# terraform/aws-managed-grafana + values-managed-aws*.yaml).
LOG_GROUP = "/jenkins-2026/jenkins-2026/otel"


def _panel_ds_type(panel: dict) -> str | None:
    ds = panel.get("datasource") or {}
    if isinstance(ds, dict) and ds.get("type"):
        return ds["type"]
    for t in panel.get("targets", []) or []:
        tds = t.get("datasource") or {}
        if isinstance(tds, dict) and tds.get("type"):
            return tds["type"]
    return None


def _to_cw_logs(panel: dict) -> None:
    panel["datasource"] = dict(CW_DS)
    panel["type"] = "logs"
    panel["targets"] = [
        {
            "datasource": dict(CW_DS),
            "queryMode": "Logs",
            "region": "default",
            "logGroups": [{"name": LOG_GROUP}],
            # CloudWatch Logs Insights. @message carries the OTel log record;
            # filtering is left broad so the panel always shows recent logs.
            "expression": (
                "fields @timestamp, @message, @logStream "
                "| sort @timestamp desc | limit 100"
            ),
            "refId": "A",
        }
    ]


def _to_xray_traces(panel: dict) -> None:
    panel["datasource"] = dict(XRAY_DS)
    panel["type"] = "table"
    panel["targets"] = [
        {
            "datasource": dict(XRAY_DS),
            "queryType": "getTraceSummaries",
            "query": "",
            "region": "default",
            "refId": "A",
        }
    ]


# RUM is ~entirely Grafana Faro (browser frontend) data, native to Grafana Cloud
# (Loki/Tempo + Frontend Observability). On Amazon Managed Grafana the Faro logs/traces
# are translated to CloudWatch Logs / X-Ray, which do not carry Faro's RUM data model,
# so Faro-specific panels degrade. Append a caveat to the note so it's expected.
_RUM_AWS_CAVEAT = (
    "\n\n---\n\n"
    "> **⚠️ AWS variant — RUM is a degraded view here.** Frontend signals come from "
    "**Grafana Faro** (browser RUM), native to Grafana Cloud (Loki/Tempo + Frontend "
    "Observability). On **Amazon Managed Grafana** the Faro logs/traces are mapped to "
    "**CloudWatch Logs / X-Ray**, which lack Faro's RUM data model, so Faro-specific panels "
    "(web-vitals, sessions, per-page/route breakdowns) show generic rows or no data. "
    "**For full RUM fidelity use the Grafana Cloud backend.**"
)


def _append_rum_caveat(dash: dict) -> None:
    title = dash.get("title", "")
    if "RUM" not in title and "Faro" not in title:
        return
    for panel in dash.get("panels", []):
        if panel.get("type") == "text":
            opts = panel.setdefault("options", {})
            opts["content"] = (opts.get("content", "") or "") + _RUM_AWS_CAVEAT
            return


def transform(dash: dict) -> dict:
    # Drop the Loki/Tempo datasource template variables; keep DS_PROMETHEUS
    # (binds to Amazon Managed Prometheus) and everything else.
    tlist = dash.get("templating", {}).get("list", [])
    tlist = [v for v in tlist if v.get("name") not in ("DS_LOKI", "DS_TEMPO")]
    dash.setdefault("templating", {})["list"] = tlist

    # Drop Loki/Tempo from __inputs / __requires so the import doesn't demand them.
    if "__inputs" in dash:
        dash["__inputs"] = [
            i for i in dash["__inputs"] if i.get("name") not in ("DS_LOKI", "DS_TEMPO")
        ]

    for panel in dash.get("panels", []):
        t = _panel_ds_type(panel)
        if t == "loki":
            _to_cw_logs(panel)
        elif t == "tempo":
            _to_xray_traces(panel)
        # prometheus / row / text panels: untouched.
    _append_rum_caveat(dash)
    return dash


def main() -> None:
    for src in sorted(SRC_DIR.glob("*.json")):
        dash = json.loads(src.read_text())
        out = transform(dash)
        dst = HERE / f"{src.stem}-aws.json"
        dst.write_text(json.dumps(out, indent=2) + "\n")
        print(f"  {src.name} -> {dst.name}")


if __name__ == "__main__":
    main()
