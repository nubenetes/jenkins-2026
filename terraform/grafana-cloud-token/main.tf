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
  role       = "Admin"
}

resource "grafana_cloud_stack_service_account_token" "dashboards" {
  stack_slug         = var.stack_slug
  service_account_id = grafana_cloud_stack_service_account.dashboards.id
  name               = "jenkins-2026-dashboards"
}

# -----------------------------------------------------------------------------
# Backstage Monitoring-tab credentials - BACKSTAGE_GRAFANA_TOKEN, the Bearer
# the portal's '/grafana/api' proxy sends (docs/505 § Grafana integration).
# Deliberately a SEPARATE, read-only (Viewer) service account: the dashboards
# SA above is Admin (it pushes dashboards), while the portal only ever reads
# /api/search + the alerting provisioning API - least privilege, and rotating
# one token never breaks the other consumer. Day1.cluster.01-gke reads the
# output from this module's GCS state and threads it to
# scripts/01-namespaces.sh as BACKSTAGE_GRAFANA_TOKEN (never a GitHub secret -
# the azure/aws credentials pattern). This static stack SA token is exactly
# the credential shape the managed Grafanas (Entra ID / AWS SigV4,
# short-lived) cannot issue - why the integration covers oss + grafana-cloud
# only (decision record in docs/505).
# -----------------------------------------------------------------------------
resource "grafana_cloud_stack_service_account" "backstage" {
  stack_slug = var.stack_slug
  name       = "jenkins-2026-backstage"
  role       = "Viewer"
}

resource "grafana_cloud_stack_service_account_token" "backstage" {
  stack_slug         = var.stack_slug
  service_account_id = grafana_cloud_stack_service_account.backstage.id
  name               = "jenkins-2026-backstage"
}

# -----------------------------------------------------------------------------
# Private Data Source Connect (PDC)
# -----------------------------------------------------------------------------
resource "grafana_cloud_private_data_source_connect_network" "this" {
  region           = data.grafana_cloud_stack.this.region_slug
  name             = "jenkins-2026-pdc"
  display_name     = "jenkins-2026 Private Network"
  stack_identifier = data.grafana_cloud_stack.this.id
}

resource "grafana_cloud_private_data_source_connect_network_token" "this" {
  pdc_network_id = grafana_cloud_private_data_source_connect_network.this.pdc_network_id
  region         = grafana_cloud_private_data_source_connect_network.this.region
  name           = "jenkins-2026-pdc-token"
}

# -----------------------------------------------------------------------------
# Jenkins Datasource
# -----------------------------------------------------------------------------
resource "grafana_data_source" "jenkins" {
  provider = grafana.instance

  type = "grafana-jenkins-datasource"
  name = "Jenkins"
  url  = "http://jenkins.jenkins.svc.cluster.local:8080"

  # Link to the PDC network
  private_data_source_connect_network_id = grafana_cloud_private_data_source_connect_network.this.pdc_network_id

  json_data_encoded = jsonencode({
    username = "admin"
  })

  secure_json_data_encoded = jsonencode({
    apiToken = var.jenkins_admin_password
  })
}
