# terraform/aws-managed-grafana

The **`observability.mode=managed-aws` backend** (AWS analogue of
`azure-managed-grafana`) — Amazon Managed Grafana, Amazon Managed Service for
Prometheus, a CloudWatch log group, the GKE→AWS OIDC provider and the collector
IAM role. The in-cluster OTel collector authenticates at runtime via
`AssumeRoleWithWebIdentity` using a projected ServiceAccount web-identity token —
**no access keys**. Same persistent-bootstrap role as `grafana-cloud-stack`. See
[`docs/301`](../../docs/301-OBSERVABILITY.md).

## Lifecycle owner

Applied **one-time** by **`Day0.infra.04-aws-grafana.yml`** (GitHub-OIDC → AWS
auth), destroyed by **`Decom.infra.04-aws-grafana.yml`**. Safe to re-run.
**`Day1.cluster.01-gke` does NOT apply it** — it reads the outputs from the GCS
state (`terraform output`) to build the in-cluster `aws-managed-credentials`
Secret; those backend credentials never become GitHub secrets.

## State

GCS remote state in the bootstrap state bucket, prefix
**`jenkins-2026/aws-managed-grafana`** (same bucket as `terraform/gke`).

## Key inputs

- `gke_oidc_issuer_url` (required — the cluster's OIDC issuer, used to federate
  the collector SA). Only identifiers (`AWS_BOOTSTRAP_ROLE_ARN`/`AWS_REGION`/
  `GKE_OIDC_ISSUER_URL`) are GitHub secrets.
- `region` (default `eu-west-1`), `name_prefix`, `grafana_version`,
  `collector_namespace`/`collector_service_account` (the SA that assumes the AWS
  role), `github_repo`/`github_environment` (trust for the dashboard-publisher
  role), `grafana_admin_sso_emails` (IAM Identity Center Grafana admins).

## Key outputs (read by Day1 → `aws-managed-credentials` Secret)

- `aws_region`, `amp_remote_write_endpoint` / `amp_query_url` /
  `amp_workspace_id`, `collector_role_arn` (→ `AWS_ROLE_ARN`),
  `cloudwatch_log_group`, `grafana_endpoint` (→ `GRAFANA_BASE_URL`),
  `grafana_workspace_id`, `dashboard_publisher_role_arn`
  (→ `AWS_DASHBOARD_PUBLISH_ROLE_ARN`).
