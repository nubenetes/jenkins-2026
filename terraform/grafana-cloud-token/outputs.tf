output "otlp_endpoint" {
  description = "OTLP gateway endpoint for the stack (GRAFANA_CLOUD_OTLP_ENDPOINT)."
  value       = data.grafana_cloud_stack.this.otlp_url
}

output "otlp_auth" {
  description = "Basic-auth credentials for the OTLP gateway, base64(\"<stack_id>:<token>\") (GRAFANA_CLOUD_OTLP_AUTH)."
  value       = base64encode("${data.grafana_cloud_stack.this.id}:${grafana_cloud_access_policy_token.otlp.token}")
  sensitive   = true
}

output "grafana_base_url" {
  description = "URL of the stack's Grafana instance (GRAFANA_BASE_URL)."
  value       = data.grafana_cloud_stack.this.url
}

output "grafana_api_key" {
  description = "Service account token for pushing dashboards via the Grafana HTTP API (GRAFANA_API_KEY)."
  value       = grafana_cloud_stack_service_account_token.dashboards.key
  sensitive   = true
}
