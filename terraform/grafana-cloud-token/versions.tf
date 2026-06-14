terraform {
  required_version = ">= 1.9.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
    }
  }
}

provider "grafana" {
  cloud_access_policy_token = var.grafana_cloud_api_token
}

provider "grafana" {
  alias = "instance"
  url   = "https://${var.stack_slug}.grafana.net"
  auth  = grafana_cloud_stack_service_account_token.dashboards.key
}

# -----------------------------------------------------------------------------
# terraform/grafana-cloud-token manages the *ephemeral* credentials
# gke-provision.yml puts into the "grafana-cloud-credentials" k8s Secret:
#
#   - an access policy + token scoped to the persistent stack from
#     terraform/grafana-cloud-stack (looked up by slug, below), with
#     metrics/logs/traces/profiles:write - used as the OTLP gateway's
#     Basic-auth password.
#   - a stack service account + token (Editor role) - used by
#     scripts/07-grafana-dashboards.sh to push dashboards via the Grafana
#     HTTP API.
#
# gke-provision.yml runs `terraform apply` here after provisioning the
# cluster; gke-decommission.yml runs `terraform destroy` here, revoking both
# tokens. State is remote (GCS, prefix "jenkins-2026/grafana-cloud-token",
# same bucket as terraform/gke) via backend_override.tf, written by both
# workflows - so the destroy run can find what the apply run created. This
# module never touches the stack itself (no grafana_cloud_stack resource
# here).
# -----------------------------------------------------------------------------
