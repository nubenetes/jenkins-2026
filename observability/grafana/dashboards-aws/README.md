# managed-aws dashboards

Two kinds, by design:

- **Custom** (`*-aws.json`, this dir): the project-specific views - the active
  CI engine's overview (one of `jenkins-overview` · `tekton-overview` ·
  `github-actions-ci` · `argo-workflows-ci`, gated by `ci.engine`),
  per-microservice RED, the k6 (`CI-CD / k6 Observability`) dashboard, and the
  AWS logs/traces panels. No public dashboard knows about these (the OTel
  `service_name`/
  `deployment_environment` labels, `ci_pipeline_run_*` metrics, the X-Ray /
  CloudWatch Logs schema), so they're generated and maintained here.
- **Kubernetes/node infra**: the collector scrapes cadvisor + kubelet +
  node-exporter + kube-state-metrics (with a `cluster` label) and remote-writes
  to AMP via SigV4 - see
  [`values-managed-aws.yaml`](../../otel-collector/values-managed-aws.yaml).
  **Unlike Azure Managed Grafana** (which auto-provisions infra dashboards from
  its Azure Monitor integration), **AMG ships no K8s dashboards** - the metrics
  are in AMP but nothing renders them out of the box. These are now provided by
  the vendored **dotdc "Kubernetes / Views" + Node Exporter Full** set in
  [`community/`](community) (chosen over `kube-prometheus-stack`/`kubernetes-mixin`
  because that set depends on Prometheus recording rules a managed AMP workspace
  doesn't evaluate). See [`community/README.md`](community/README.md) for the full
  rationale - including why the full kube-prometheus-stack and the OTel-native
  `k8s_cluster`/`kubeletstats` receivers are *not* the right fit here.

The custom `*-aws.json` variants are the `observability.mode=managed-aws`
counterparts of [`../dashboards/`](../dashboards). Amazon Managed Grafana reads
from **AWS datasources** (not Prometheus/Loki/Tempo), so the log and trace
panels are rewritten:

| Panel kind | Canonical (oss / grafana-cloud) | managed-aws variant |
|---|---|---|
| Metrics | Prometheus / PromQL | **unchanged** - Amazon Managed Service for Prometheus is Prometheus-compatible, so `${DS_PROMETHEUS}` binds to it and the PromQL works as-is |
| Logs | Loki / LogQL | **CloudWatch Logs** Insights over the collector's log group |
| Traces | Tempo / TraceQL | **AWS X-Ray** `getTraceSummaries` |
| Loki/Tempo **query** template variable (e.g. `log_namespace`) | options queried from Loki | converted to a static **`custom`** variable (keeps the all-value) - a LogQL options query has no CloudWatch/X-Ray equivalent, so this avoids a dangling `loki` datasource ref |

> **X-Ray plugin.** AMG creates the X-Ray datasource *entry* but does not
> register the datasource *plugin*, so trace panels return "Plugin not
> registered" until it's installed. `scripts/07` installs
> `grafana-x-ray-datasource` from the catalog (idempotent, `pluginAdminEnabled`
> is on) before publishing - no action needed.

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
(e.g. after a `Decom.cluster.01-gke` decommission + `Day1.cluster.01-gke`
re-provision, with the AMG backend left standing) converges without duplicates:

- the `jenkins-2026-dashboard-publisher` service account is reused by name;
- its token is uniquely named, short-lived, and deleted on exit;
- the AMP/CloudWatch/X-Ray datasources are matched by **type** and reused (one is
  created only if the workspace has none of that type);
- dashboards are overwritten in place by stable uid.

A full backend teardown (`Decom.infra.04-aws-grafana`) + re-bootstrap
(`Day0.infra.04-aws-grafana`) starts clean in a fresh workspace - just as idempotent.

See [`docs/301-OBSERVABILITY.md`](../../../docs/301-OBSERVABILITY.md#observability-modes).
