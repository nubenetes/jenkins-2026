data "grafana_cloud_stack" "this" {
  slug = var.stack_slug
}

# -----------------------------------------------------------------------------
# OTLP ingest credentials - GRAFANA_CLOUD_OTLP_ENDPOINT / GRAFANA_CLOUD_OTLP_AUTH
# -----------------------------------------------------------------------------
resource "grafana_cloud_access_policy" "otlp" {
  region       = data.grafana_cloud_stack.this.region_slug
  name         = "jenkins-2026-otlp"
  display_name = "jenkins-2026 OTLP ingest"

  scopes = [
    "metrics:write",
    "logs:write",
    "traces:write",
    "profiles:write",
  ]

  realm {
    type       = "stack"
    identifier = data.grafana_cloud_stack.this.id
  }
}

resource "grafana_cloud_access_policy_token" "otlp" {
  region           = data.grafana_cloud_stack.this.region_slug
  access_policy_id = grafana_cloud_access_policy.otlp.policy_id
  name             = "jenkins-2026-otlp"
  display_name     = "jenkins-2026 OTLP ingest"
}

# -----------------------------------------------------------------------------
# Dashboard-push credentials - GRAFANA_API_KEY, used by
# scripts/07-grafana-dashboards.sh against GRAFANA_BASE_URL's HTTP API.
# -----------------------------------------------------------------------------
resource "grafana_cloud_stack_service_account" "dashboards" {
  stack_slug = var.stack_slug
  name       = "jenkins-2026-dashboards"
  role       = "Editor"
}

resource "grafana_cloud_stack_service_account_token" "dashboards" {
  stack_slug         = var.stack_slug
  service_account_id = grafana_cloud_stack_service_account.dashboards.id
  name               = "jenkins-2026-dashboards"
}

# -----------------------------------------------------------------------------
# Jenkins Datasource Plugin
# -----------------------------------------------------------------------------
resource "grafana_cloud_stack_plugin" "jenkins" {
  stack_slug = var.stack_slug
  name       = "grafana-jenkins-datasource"
}
