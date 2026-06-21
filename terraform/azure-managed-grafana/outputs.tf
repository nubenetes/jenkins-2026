# These outputs feed the GitHub Actions secrets that 02.01-gke-provision.yml
# uses to build the in-cluster "azure-monitor-credentials" Secret (consumed by
# observability/otel-collector/values-managed-azure*.yaml). See README.md
# "GitHub Actions automation".

output "azure_monitor_connection_string" {
  description = "Application Insights connection string -> AZURE_MONITOR_CONNECTION_STRING (azuremonitor exporter: traces + logs)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "azure_monitor_prometheus_endpoint" {
  description = "Managed-Prometheus remote-write URL -> AZURE_MONITOR_PROMETHEUS_ENDPOINT (prometheusremotewrite exporter)."
  value       = "${azurerm_monitor_data_collection_endpoint.this.metrics_ingestion_endpoint}/dataCollectionRules/${azurerm_monitor_data_collection_rule.prom.immutable_id}/streams/Microsoft-PrometheusMetrics/api/v1/write"
}

output "azure_tenant_id" {
  description = "Entra tenant ID -> AZURE_TENANT_ID."
  value       = var.tenant_id
}

output "azure_client_id" {
  description = "Collector service-principal client ID -> AZURE_CLIENT_ID."
  value       = azuread_application.collector.client_id
}

output "azure_client_secret" {
  description = "Collector service-principal client secret -> AZURE_CLIENT_SECRET."
  value       = azuread_application_password.collector.value
  sensitive   = true
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana URL -> GRAFANA_BASE_URL (dashboard publishing in 07-grafana-dashboards.sh)."
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "grafana_identity_principal_id" {
  description = "Azure Managed Grafana system-assigned identity principal ID (for any additional role assignments)."
  value       = azurerm_dashboard_grafana.this.identity[0].principal_id
}
