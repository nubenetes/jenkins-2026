output "stack_slug" {
  description = "Generated subdomain of the stack (https://<stack_slug>.grafana.net). Read from this module's state by 0.2.01-gke-provision and passed to terraform/grafana-cloud-token, which looks the stack up by this value."
  value       = grafana_cloud_stack.this.slug
}

output "stack_id" {
  description = "Numeric Grafana Cloud stack ID - the OTLP gateway's Basic-auth username."
  value       = grafana_cloud_stack.this.id
}

output "org_slug" {
  description = "Grafana Cloud organization slug that owns this stack."
  value       = grafana_cloud_stack.this.org_slug
}

output "region_slug" {
  description = "Region the stack was created in."
  value       = grafana_cloud_stack.this.region_slug
}

output "grafana_url" {
  description = "URL of this stack's Grafana instance."
  value       = grafana_cloud_stack.this.url
}

output "otlp_endpoint" {
  description = "OTLP gateway endpoint for this stack (GRAFANA_CLOUD_OTLP_ENDPOINT)."
  # grafana_cloud_stack.this.otlp_url is the bare gateway host - see
  # terraform/grafana-cloud-token/outputs.tf otlp_endpoint for why /otlp is
  # appended.
  value = "${grafana_cloud_stack.this.otlp_url}/otlp"
}
