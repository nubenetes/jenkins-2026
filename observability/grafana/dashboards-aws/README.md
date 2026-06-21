# managed-aws dashboards

Two kinds, by design:

- **Custom** (`*-aws.json`, this dir): the project-specific views - Jenkins CI,
  per-microservice RED, the k6 smoke test, and the AWS logs/traces panels. No
  public dashboard knows about these (the OTel `service_name`/
  `deployment_environment` labels, `ci_pipeline_run_*` metrics, the X-Ray /
  CloudWatch Logs schema), so they're generated and maintained here.
- **Built-in infra** (nothing in this repo): generic Kubernetes/node infra is
  served by **Amazon Managed Grafana's own built-in dashboards**, fed from
  **Amazon Managed Service for Prometheus** - the AWS-native equivalent of what
  `oss` (kube-prometheus-stack) and `grafana-cloud` (k8s-monitoring app) ship.
  The collector just feeds them: it scrapes cadvisor + kubelet + node-exporter +
  kube-state-metrics (with a `cluster` label) and remote-writes to AMP via SigV4
  - see [`values-managed-aws.yaml`](../../otel-collector/values-managed-aws.yaml).

The custom `*-aws.json` variants are the `observability.mode=managed-aws`
counterparts of [`../dashboards/`](../dashboards). Amazon Managed Grafana reads
from **AWS datasources** (not Prometheus/Loki/Tempo), so the log and trace
panels are rewritten:

| Panel kind | Canonical (oss / grafana-cloud) | managed-aws variant |
|---|---|---|
| Metrics | Prometheus / PromQL | **unchanged** - Amazon Managed Service for Prometheus is Prometheus-compatible, so `${DS_PROMETHEUS}` binds to it and the PromQL works as-is |
| Logs | Loki / LogQL | **CloudWatch Logs** Insights over the collector's log group |
| Traces | Tempo / TraceQL | **AWS X-Ray** `getTraceSummaries` |

**Generated, not hand-edited.** Regenerate after changing the canonical
dashboards:

```bash
python3 observability/grafana/dashboards-aws/generate.py
```

[`scripts/07-grafana-dashboards.sh`](../../../scripts/07-grafana-dashboards.sh)
publishes these to Amazon Managed Grafana via its Grafana HTTP API when
`observability.mode=managed-aws`.

## Account-agnostic & keyless by design

- **No account / workspace / datasource ids** are baked into the JSON. The
  CloudWatch and X-Ray datasource uids are placeholders (`DS_CW_UID` /
  `DS_XRAY_UID`) substituted at **publish time** with the real uids that
  `scripts/07` discovers (or creates) via the AMG API - the same idea as the
  Azure variant's `${appinsights}` substitution. The CloudWatch log group is a
  project constant (`/jenkins-2026/jenkins-2026/otel`).
- **No secrets** in the dashboards, and no static Grafana API key anywhere:
  Amazon Managed Grafana authenticates users via IAM Identity Center, so
  `scripts/07` mints a **short-lived workspace service-account token** with the
  AWS API (`aws grafana create-workspace-service-account-token`,
  `seconds-to-live=900`, deleted on exit) just for the publish. The three AWS
  datasources (AMP / CloudWatch / X-Ray) authenticate with the **workspace IAM
  role**, so no credentials live in the datasources either.

## Idempotency across the lifecycle

Everything `scripts/07` does is get-or-create / overwrite, so re-running it
(e.g. after a `02.99` GKE decommission + `02.01` re-provision, with the AMG
backend left standing) converges without duplicates:

- the `jenkins-2026-dashboard-publisher` service account is reused by name;
- its token is uniquely named, short-lived, and deleted on exit;
- the AMP/CloudWatch/X-Ray datasources are matched by name and reused;
- dashboards are overwritten in place by stable uid.

A full backend teardown (`01.96`) + re-bootstrap (`01.04`) starts clean in a
fresh workspace - just as idempotent.

See [`docs/observability.md`](../../../docs/observability.md#managed-aws).
