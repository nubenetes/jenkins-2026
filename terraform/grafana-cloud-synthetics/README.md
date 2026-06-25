# terraform/grafana-cloud-synthetics

Grafana Cloud **Synthetic Monitoring** (GA) — uptime/latency HTTP probes against the
project's **public, non-IAP** endpoints, as code. Feeds uptime %, latency and
SLO-able metrics/logs in Grafana Cloud.

## GRAFANA-CLOUD ONLY

Synthetic Monitoring is a Grafana Cloud product. It has **no equivalent** in
`observability.mode=oss` (none), `managed-azure` (Azure availability tests) or
`managed-aws` (CloudWatch Synthetics). Apply this module **only in grafana-cloud mode**
— the Day1 workflow gates it the same way it gates `grafana-cloud-token`. Keyless: both
provider tokens derive from the stack Cloud Access Policy token.

## Why only the microservices host

The IAP-protected hosts (jenkins, argocd, headlamp, pgadmin) would return Google's
OAuth login page to an unauthenticated probe, not the app — meaningless for uptime. We
probe the **open** `microservices` host(s) (`var.targets`).

## Usage

```bash
cd terraform/grafana-cloud-synthetics
terraform init
terraform apply \
  -var stack_slug="$(terraform -chdir=../grafana-cloud-stack output -raw stack_slug)" \
  -var cloud_access_policy_token="<a stack access-policy token>"
```

In CI this is applied by `Day1.cluster.01` only when `observability_mode == grafana-cloud`
(reusing the stack slug + a minted access-policy token, like `grafana-cloud-token`).

`terraform destroy` removes the checks (and the SM installation).
