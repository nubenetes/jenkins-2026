variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS region for Amazon Managed Grafana, Amazon Managed Service for Prometheus, X-Ray and CloudWatch Logs."
}

variable "name_prefix" {
  type        = string
  default     = "jenkins-2026"
  description = "Prefix for resource names so they're easy to identify and don't collide."
}

variable "grafana_version" {
  type        = string
  default     = "12.4"
  description = "Amazon Managed Grafana workspace version (latest stable supported by AMG: 12.4 as of 2026-04). See https://docs.aws.amazon.com/grafana/latest/userguide/version-differences.html"
}

variable "gke_oidc_issuer_url" {
  type        = string
  description = <<-EOT
    The GKE cluster's OIDC issuer URL, e.g.
    https://container.googleapis.com/v1/projects/<project>/locations/<location>/clusters/<cluster>
    Get it with:
      gcloud container clusters describe <cluster> --zone <zone> \
        --format='value(selfLink)' | sed 's#.*/projects#https://container.googleapis.com/v1/projects#'
    or `kubectl get --raw /.well-known/openid-configuration | jq -r .issuer`.
    Used to federate the in-cluster collector ServiceAccount to an AWS IAM role
    via AssumeRoleWithWebIdentity (no long-lived keys).
  EOT
}

variable "collector_namespace" {
  type        = string
  default     = "observability"
  description = "Namespace of the otel-collector-gateway ServiceAccount that assumes the AWS role."
}

variable "collector_service_account" {
  type        = string
  default     = "otel-collector-gateway"
  description = "Name of the otel-collector-gateway ServiceAccount (matches the opentelemetry-collector chart's fullnameOverride)."
}

variable "github_repo" {
  type        = string
  default     = ""
  description = "owner/repo whose GitHub Actions OIDC may assume the dashboard-publisher role (e.g. nubenetes/jenkins-2026). 01.04-aws-bootstrap passes TF_VAR_github_repo=$GITHUB_REPOSITORY; left empty the role is created but unassumable."
}

variable "github_environment" {
  type        = string
  default     = "gke-production"
  description = "GitHub Actions environment 02.01-gke-provision runs in; the dashboard-publisher role trusts repo:<github_repo>:environment:<github_environment>."
}

variable "grafana_admin_sso_emails" {
  type        = string
  default     = ""
  description = <<-EOT
    Comma-separated email addresses of IAM Identity Center users to grant
    Grafana Admin on the workspace (e.g. "alice@example.com,bob@example.com").
    Each user must already exist in IAM Identity Center; the module looks them
    up by email and creates an aws_grafana_role_association. Managed via the
    AWS_GRAFANA_ADMIN_SSO_EMAILS GitHub secret passed as TF_VAR_grafana_admin_sso_emails
    by 0.1.04-aws-bootstrap.yml — never commit real addresses here.
  EOT
}
