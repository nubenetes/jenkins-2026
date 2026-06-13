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

# -----------------------------------------------------------------------------
# terraform/grafana-cloud-stack is a one-time, *locally run* setup step,
# exactly like terraform/bootstrap: it provisions the persistent Grafana
# Cloud stack that jenkins-2026 sends OpenTelemetry data to and imports
# dashboards into when observability.mode == "grafana-cloud".
#
# It deliberately keeps its OWN local state
# (terraform/grafana-cloud-stack/terraform.tfstate, gitignored): the stack's
# slug/URL is meant to stay stable for the life of the project, so re-running
# `terraform apply` from scratch (e.g. in CI, with no prior state) would try
# to create a stack that already exists and fail. Run this once from your
# workstation (see README.md "GitHub Actions automation"), copy the printed
# `stack_slug` output into the GRAFANA_CLOUD_STACK_SLUG GitHub secret, and
# keep this directory's terraform.tfstate - if it's lost, either re-create
# the stack under a new slug (and update the secret) or `terraform import`
# the existing one.
#
# gke-provision/gke-decommission do NOT run this module - they only manage
# the ephemeral access policy + tokens in terraform/grafana-cloud-token,
# which looks this stack up by slug via a data source.
# -----------------------------------------------------------------------------
