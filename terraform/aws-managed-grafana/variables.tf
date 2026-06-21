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
