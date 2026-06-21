# -----------------------------------------------------------------------------
# terraform/azure-managed-grafana is a one-time setup step, like
# terraform/grafana-cloud-stack: it provisions the persistent Azure backend
# that jenkins-2026 sends OpenTelemetry data to when
# observability.mode == "managed-azure", plus the Azure Managed Grafana that
# visualizes it.
#
# Run it once by hand (local state in terraform/azure-managed-grafana/
# terraform.tfstate, gitignored) - it is NOT wired into CI, exactly like
# terraform/bootstrap and terraform/grafana-cloud-stack. Its outputs feed the
# AZURE_* / GRAFANA_* GitHub Actions secrets that 02.01-gke-provision.yml uses
# to create the in-cluster "azure-monitor-credentials" Secret.
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
  name                  = "${var.name_prefix}-grafana"
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  grafana_major_version = "11"

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

# Grant the named users/groups Grafana Admin on the instance.
resource "azurerm_role_assignment" "grafana_admins" {
  for_each             = toset(var.grafana_admin_object_ids)
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
}
