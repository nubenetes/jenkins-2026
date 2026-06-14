output "otlp_endpoint" {
  description = "OTLP gateway endpoint for the stack (GRAFANA_CLOUD_OTLP_ENDPOINT)."
  # data.grafana_cloud_stack.this.otlp_url is the bare gateway host
  # (e.g. https://otlp-gateway-prod-eu-west-2.grafana.net) - the OTLP
  # ingest path is under /otlp (https://grafana.com/docs/grafana-cloud/...
  # /send-data/otlp/), and the otlphttp exporters in
  # observability/otel-collector/values-grafana-cloud*.yaml use this value
  # as-is for endpoint, appending /v1/{traces,metrics,logs} themselves.
  value = "${data.grafana_cloud_stack.this.otlp_url}/otlp"
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
