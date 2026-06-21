#!/usr/bin/env python3
"""Generate the managed-azure dashboard variants from the canonical dashboards.

observability.mode=managed-azure visualizes telemetry in Azure Managed Grafana,
which reads from Azure Monitor datasources - not Prometheus/Loki/Tempo. This
script derives `<name>-azure.json` from each `../dashboards/<name>.json`,
changing only what must change so the variants stay in sync with the originals:

  - METRIC panels (Prometheus / PromQL): left untouched. Azure Monitor managed
    Prometheus is a Prometheus-compatible datasource, so the `${DS_PROMETHEUS}`
    datasource variable (type `prometheus`) binds to it and the PromQL queries
    work as-is.
  - LOG panels (Loki): rewritten to an Azure Monitor *Logs* query (KQL over the
    Application Insights `AppTraces` table - where the OTel logs land via the
    collector's azuremonitor exporter).
  - TRACE panels (Tempo): rewritten to an Azure Monitor *Traces* query over the
    same Application Insights resource (requests + dependencies spans).

Account-agnostic by construction: the Application Insights resource is selected
at runtime via the `${appinsights}` template variable (an Azure Resource Graph
query that lists `microsoft.insights/components` in whatever subscriptions the
datasource's managed identity can see) - no subscription / resource IDs are
baked into the JSON. The datasource itself authenticates with Azure Managed
Grafana's managed identity, so no secrets live in the dashboards either.

Regenerate after editing the canonical dashboards:
    python3 observability/grafana/dashboards-azure/generate.py

NOTE: validate the rendered panels against a real Azure account on first
integration - the Azure Monitor datasource query JSON (table names, query
types) may need minor field tweaks. See docs/observability.md "managed-azure".
"""
from __future__ import annotations

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SRC_DIR = HERE.parent / "dashboards"

AZURE_DS = {"type": "grafana-azure-monitor-datasource", "uid": "${DS_AZURE_MONITOR}"}

# Template variables that replace DS_LOKI / DS_TEMPO in the variants.
AZURE_TEMPLATING = [
    {
        "name": "DS_AZURE_MONITOR",
        "label": "Azure Monitor",
        "type": "datasource",
        "query": "grafana-azure-monitor-datasource",
        "refresh": 1,
        "hide": 0,
        "regex": "",
        "current": {},
        "options": [],
    },
    {
        "name": "appinsights",
        "label": "Application Insights",
        "type": "query",
        "datasource": AZURE_DS,
        # Azure Resource Graph: account-agnostic discovery of App Insights
        # resources across the accessible subscriptions - returns resource IDs.
        "query": {
            "queryType": "Azure Resource Graph",
            "azureResourceGraph": {
                "query": "resources | where type =~ 'microsoft.insights/components' | project id | order by id asc"
            },
        },
        "refresh": 1,
        "hide": 0,
        "includeAll": False,
        "multi": False,
        "current": {},
        "options": [],
    },
]


def _panel_ds_type(panel: dict) -> str | None:
    ds = panel.get("datasource") or {}
    if isinstance(ds, dict) and ds.get("type"):
        return ds["type"]
    for t in panel.get("targets", []) or []:
        tds = t.get("datasource") or {}
        if isinstance(tds, dict) and tds.get("type"):
            return tds["type"]
    return None


def _to_azure_logs(panel: dict) -> None:
    panel["datasource"] = dict(AZURE_DS)
    panel["type"] = "table"
    panel["targets"] = [
        {
            "datasource": dict(AZURE_DS),
            "queryType": "Azure Log Analytics",
            "azureLogAnalytics": {
                "resources": ["${appinsights}"],
                # Querying the App Insights RESOURCE uses the classic schema
                # (traces/requests/dependencies), NOT the workspace schema
                # (AppTraces/...). operation_Id is the App Insights trace id
                # (== OTel trace_id) - the correlation key to the trace panel.
                # dashboardTime scopes it to the dashboard time range.
                "query": (
                    "traces\n"
                    "| project timestamp, severityLevel, cloud_RoleName, operation_Id, message\n"
                    "| order by timestamp desc"
                ),
                "dashboardTime": True,
                "resultFormat": "table",
            },
            "refId": "A",
        }
    ]


def _to_azure_traces(panel: dict) -> None:
    panel["datasource"] = dict(AZURE_DS)
    panel["type"] = "table"
    panel["targets"] = [
        {
            "datasource": dict(AZURE_DS),
            "queryType": "Azure Log Analytics",
            # Spans live in requests (server) + dependencies (client/internal)
            # in the App Insights classic schema. operation_Id correlates 1:1
            # with the log panel above - App Insights' end-to-end trace id.
            "azureLogAnalytics": {
                "resources": ["${appinsights}"],
                "query": (
                    "union requests, dependencies\n"
                    "| project timestamp, operation_Id, cloud_RoleName, name, "
                    "duration, success, itemType\n"
                    "| order by timestamp desc"
                ),
                "dashboardTime": True,
                "resultFormat": "table",
            },
            "refId": "A",
        }
    ]


def transform(dash: dict) -> dict:
    # Swap DS_LOKI / DS_TEMPO out of the templating list, keep everything else.
    tlist = dash.get("templating", {}).get("list", [])
    tlist = [v for v in tlist if v.get("name") not in ("DS_LOKI", "DS_TEMPO")]
    tlist = AZURE_TEMPLATING + tlist
    dash.setdefault("templating", {})["list"] = tlist

    for panel in dash.get("panels", []):
        t = _panel_ds_type(panel)
        if t == "loki":
            _to_azure_logs(panel)
        elif t == "tempo":
            _to_azure_traces(panel)
        # prometheus / row / text panels: untouched.
    return dash


def main() -> None:
    for src in sorted(SRC_DIR.glob("*.json")):
        dash = json.loads(src.read_text())
        out = HERE / f"{src.stem}-azure.json"
        out.write_text(json.dumps(transform(dash), indent=2) + "\n")
        print(f"wrote {out.relative_to(HERE.parent.parent.parent)}")


if __name__ == "__main__":
    main()
