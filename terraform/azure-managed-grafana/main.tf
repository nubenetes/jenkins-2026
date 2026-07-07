# -----------------------------------------------------------------------------
# terraform/azure-managed-grafana is a one-time setup step, like
# terraform/grafana-cloud-stack: it provisions the persistent Azure backend
# that jenkins-2026 sends OpenTelemetry data to when
# observability.mode == "managed-azure", plus the Azure Managed Grafana that
# visualizes it.
#
# Applied one-time by Day0.infra.03-azure-grafana.yml (GCS remote state via a
# CI-written backend_override.tf, GitHub-OIDC -> Azure auth, no stored client
# secret), exactly like terraform/grafana-cloud-stack and
# terraform/aws-managed-grafana. Day1.cluster.01-gke (managed-azure) reads its
# outputs straight from the GCS state to build the in-cluster
# "azure-monitor-credentials" Secret — those backend credentials never become
# GitHub secrets. GitHub Actions authenticates with TWO Entra apps (docs/102
# § Why the per-cloud asymmetry): a bootstrap app (App A — Contributor + UAA,
# runs this apply on the dedicated azure-bootstrap environment) and a
# low-privilege publish app (App B — Grafana Admin + Reader only, on
# gke-production, used by Day1 / Day2.publish.* — granted Grafana Admin by
# var.publish_app_client_id below).
#
# Architecture (Azure Managed Grafana is a frontend only - it does not ingest
# OTLP, so telemetry goes to Azure Monitor backends and Grafana reads them):
#   collector traces+logs -> Application Insights (azuremonitor exporter)
#   collector metrics      -> Azure Monitor workspace managed Prometheus
#                             (remote-write via the DCE/DCR below, Entra auth)
#   Azure Managed Grafana  -> Azure Monitor datasources over the above
# See observability/otel-collector/values-managed-azure.yaml and
# docs/observability.md "managed-azure".
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# --- Logs + traces: Log Analytics + Application Insights ----------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-logs"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name_prefix}-appinsights"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "other"
}

# --- Metrics: Azure Monitor workspace (managed Prometheus) --------------------

resource "azurerm_monitor_workspace" "this" {
  name                = "${var.name_prefix}-prom"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

# Data Collection Endpoint + Rule the collector's prometheusremotewrite exporter
# writes to. The remote-write URL (see outputs.tf) is the DCE's metrics
# ingestion endpoint + the DCR immutable id + the Prometheus stream.
resource "azurerm_monitor_data_collection_endpoint" "this" {
  name                = "${var.name_prefix}-dce"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  kind                = "Linux"
}

resource "azurerm_monitor_data_collection_rule" "prom" {
  name                        = "${var.name_prefix}-prom-dcr"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.this.id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }
}

# --- Entra service principal the collector uses for remote-write auth ---------

resource "azuread_application" "collector" {
  display_name = "${var.name_prefix}-otel-collector"
}

resource "azuread_service_principal" "collector" {
  client_id = azuread_application.collector.client_id
}

resource "azuread_application_password" "collector" {
  application_id = azuread_application.collector.id
  display_name   = "otel-collector-remote-write"
}

# The SP needs "Monitoring Metrics Publisher" on the DCR to remote-write
# Prometheus metrics into the Azure Monitor workspace.
resource "azurerm_role_assignment" "collector_metrics_publisher" {
  scope                = azurerm_monitor_data_collection_rule.prom.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azuread_service_principal.collector.object_id
}

# --- Azure Managed Grafana (frontend) -----------------------------------------

resource "azurerm_dashboard_grafana" "this" {
  name                = "${var.name_prefix}-grafana"
  resource_group_name = azurerm_resource_group.this.name
  # AMG isn't available in spaincentral - place it in grafana_location
  # (francecentral) within the spaincentral RG; it queries the Monitor
  # workspace cross-region via azure_monitor_workspace_integrations below.
  location = var.grafana_location
  # Azure Managed Grafana exposes its own managed major versions, which lag the
  # OSS releases - the Standard SKU currently only accepts "12" (not "13", and
  # "11" is retired). Unrelated to the oss mode's pinned OSS image (13.0.2).
  grafana_major_version = "12"

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }
}

# Grafana's managed identity must be able to read the metrics workspace
# (managed Prometheus) and the Application Insights / Log Analytics data.
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_rg_reader" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

# Grant the CI/bootstrap principal (whoever runs this apply — the GitHub Actions
# OIDC bootstrap SP, App A) Grafana Admin. Kept for single-app mode and so the
# apply principal always retains portal access; when the split below is active,
# the publish app (App B) is the one the workflows actually use.
resource "azurerm_role_assignment" "grafana_ci_deployer" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Split-app mode (docs/102 § Why the per-cloud asymmetry): also grant Grafana
# Admin to the dedicated low-privilege PUBLISH app (App B). Day1 / Day2.publish.*
# authenticate as this app, which holds ONLY Grafana Admin (here) + subscription
# Reader (assigned out-of-band) — never Contributor/UAA. Looked up by client id
# so no extra object-id secret is needed. var.publish_app_client_id left empty
# -> single-app mode (grafana_ci_deployer above is the only Grafana Admin grant).
data "azuread_service_principal" "publish" {
  count     = var.publish_app_client_id != "" ? 1 : 0
  client_id = var.publish_app_client_id
}

resource "azurerm_role_assignment" "grafana_publish_deployer" {
  count                = var.publish_app_client_id != "" ? 1 : 0
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azuread_service_principal.publish[0].object_id
}

# Grant the named users/groups Grafana Admin on the instance.
resource "azurerm_role_assignment" "grafana_admins" {
  for_each             = toset(var.grafana_admin_object_ids)
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
}
