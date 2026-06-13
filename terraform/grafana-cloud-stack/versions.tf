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
# terraform/grafana-cloud-stack is a one-time setup step, exactly like
# terraform/bootstrap: it provisions the persistent Grafana Cloud stack that
# jenkins-2026 sends OpenTelemetry data to and imports dashboards into when
# observability.mode == "grafana-cloud".
#
# Run it once via the "Grafana Cloud bootstrap" GitHub Actions workflow
# (.github/workflows/grafana-cloud-bootstrap.yml, state in the same GCS
# bucket as terraform/gke, prefix "jenkins-2026/grafana-cloud-stack") - or
# locally, with this directory's own local state
# (terraform/grafana-cloud-stack/terraform.tfstate, gitignored), if you'd
# rather not use GCS. The stack's slug/URL is meant to stay stable for the
# life of the project: re-running `terraform apply` against existing state is
# a no-op, but applying from scratch with no prior state tries to create a
# stack that already exists and fails. See README.md "GitHub Actions
# automation" for the GRAFANA_CLOUD_STACK_SLUG secret this stack's `slug`
# must match.
#
# gke-provision/gke-decommission do NOT run this module - they only manage
# the ephemeral access policy + tokens in terraform/grafana-cloud-token,
# which looks this stack up by slug via a data source.
# -----------------------------------------------------------------------------
