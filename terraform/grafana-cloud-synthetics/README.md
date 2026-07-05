# terraform/grafana-cloud-synthetics

Grafana Cloud **Synthetic Monitoring** (GA) — uptime/latency HTTP probes against the
project's **public, non-IAP** endpoints, as code. Feeds uptime %, latency and
SLO-able metrics/logs in Grafana Cloud.

## GRAFANA-CLOUD ONLY

Synthetic Monitoring is a Grafana Cloud product. It has **no equivalent** in
`observability.mode=oss` (none), `managed-azure` (Azure availability tests) or
`managed-aws` (CloudWatch Synthetics). Apply this module **only in grafana-cloud mode**
— it is currently applied by hand (it is not wired into any workflow; `grafana-cloud-token`
shows the Day1 gating pattern to copy when it is). Keyless: both provider tokens derive
from the stack Cloud Access Policy token.

## Why only the microservices host

The auth-gated hosts — IAP-protected (jenkins/tekton/argo per `ci.engine`, headlamp,
pgadmin, grafana in oss mode) plus argocd (its own OIDC login, no IAP) — would return a
login page to an unauthenticated probe, not the app — meaningless for uptime. We probe the
**open** `microservices` host(s) (`var.targets`).

## Usage

```bash
cd terraform/grafana-cloud-synthetics
terraform init
terraform apply \
  -var stack_slug="$(terraform -chdir=../grafana-cloud-stack output -raw stack_slug)" \
  -var cloud_access_policy_token="<a stack access-policy token>"
```

This module is **not yet wired into CI** — no workflow applies it. Apply it by hand (the
Usage block above) after `Day0.infra.02-grafana-cloud` has created the stack; wiring it into
`Day1.cluster.01` behind `observability_mode == grafana-cloud` (like `grafana-cloud-token`)
is the intended follow-up.

`terraform destroy` removes the checks (and the SM installation).
