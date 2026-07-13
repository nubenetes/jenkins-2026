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
# Jenkins Datasource (grafana-cloud ONLY - the plugin is Enterprise-gated, so
# it cannot exist in the oss mode's Grafana OSS; the former oss provisioning
# was removed 2026-07-13). CAVEATS, verified 2026-07-13 against the plugin
# docs: grafana-jenkins-datasource is in PUBLIC PREVIEW (1.1.0-preview,
# limited support, breaking changes possible) and its docs list Private Data
# Source Connect as UNSUPPORTED - yet PDC is the only route from the SaaS
# Grafana to the in-cluster controller, so treat this datasource as
# best-effort/Explore-only until GA. No dashboard in this repo queries it;
# the OTel-based jenkins-overview (engine-neutral contract) is the primary
# CI observability path. See docs/301 § Jenkins Data Source.
# -----------------------------------------------------------------------------
resource "grafana_data_source" "jenkins" {
  provider = grafana.instance

  type = "grafana-jenkins-datasource"
  name = "Jenkins"
  # Under backend TLS (docs/504 stage 6) the Service's 8080 turns HTTPS with a
  # cluster-internal CA the SaaS side can't validate; the plain listener for
  # in-cluster callers (agents, the Backstage plugin - and this PDC tunnel,
  # which terminates in-cluster) moves to 8082. Same flip 08.95-backstage.sh
  # does for JENKINS_BASE_URL.
  url = var.jenkins_backend_tls ? "http://jenkins.jenkins.svc.cluster.local:8082" : "http://jenkins.jenkins.svc.cluster.local:8080"

  # Link to the PDC network
  private_data_source_connect_network_id = grafana_cloud_private_data_source_connect_network.this.pdc_network_id

  json_data_encoded = jsonencode({
    username = "admin"
  })

  secure_json_data_encoded = jsonencode({
    apiToken = var.jenkins_admin_password
  })
}
