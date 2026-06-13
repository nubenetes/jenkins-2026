resource "grafana_cloud_stack" "this" {
  name        = var.stack_slug
  slug        = var.stack_slug
  description = "jenkins-2026 PoC - Jenkins + PetClinic OpenTelemetry traces/metrics/logs"
  region_slug = var.region_slug

  # This stack is meant to persist for the life of the project - deleting it
  # changes its URL/instance IDs, breaking dashboards and the
  # grafana-cloud-credentials Secret until re-provisioned. Destroy
  # deliberately, not by accident: `terraform destroy
  # -target=grafana_cloud_stack.this` (this module is never run by CI).
  delete_protection = true
}
