terraform {
  required_version = ">= 1.9.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "grafana" {
  cloud_access_policy_token = var.grafana_cloud_api_token
}

# -----------------------------------------------------------------------------
# terraform/grafana-cloud-stack provisions the Grafana Cloud stack that
# jenkins-2026 sends OpenTelemetry data to and imports dashboards into when
# observability.mode == "grafana-cloud". It is the grafana-cloud analogue of the
# azure-managed-grafana / aws-managed-grafana backends: created by
# 0.1.02-grafana-cloud-bootstrap.yml, destroyed by 9.2.02-grafana-cloud-
# decommission.yml (state in the same GCS bucket as terraform/gke, prefix
# "jenkins-2026/grafana-cloud-stack").
#
# The stack slug is GENERATED (random suffix, persisted in state) rather than
# pinned: re-applying is a no-op, but a destroy+recreate produces a fresh slug,
# avoiding Grafana Cloud's reserved-slug cooldown ("That URL has already been
# taken"). The slug is an output - 0.2.01-gke-provision reads it from this state
# and passes it to terraform/grafana-cloud-token (which looks the stack up by
# slug via a data source). The Grafana Cloud org/account (free tier) is created
# once by hand and is never managed here - only the stack is created/destroyed.
# -----------------------------------------------------------------------------
