# The stack slug (subdomain) must be globally unique across all of Grafana Cloud.
# Rather than pin a fixed slug (which collides on re-create because Grafana Cloud
# reserves a deleted slug for a cooldown period - "That URL has already been
# taken"), generate a fresh one each time the stack is created. random_string is
# persisted in state, so re-applying is a no-op; the slug only changes after a
# destroy + re-create cycle (Day0.infra.02 create / Decom.infra.02 destroy), exactly like the
# ephemeral Azure/AWS managed-grafana backends.
resource "random_string" "slug_suffix" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "grafana_cloud_stack" "this" {
  # slug: lowercase alphanumeric only (subdomain); name: human-readable label.
  name        = "${var.stack_slug_prefix}-${random_string.slug_suffix.result}"
  slug        = "${var.stack_slug_prefix}${random_string.slug_suffix.result}"
  description = "jenkins-2026 PoC - Jenkins + Microservices OpenTelemetry traces/metrics/logs"
  region_slug = var.region_slug

  # Ephemeral by design: created by Day0.infra.02-grafana-cloud, torn down by
  # Decom.infra.02-grafana-cloud. The provider defaults delete_protection
  # to `true`, which makes the decommission `terraform destroy` fail with a
  # "409 Conflict ... has deletion protection enabled". Force it off so the
  # stack is freely destroyable; the Grafana Cloud org (free tier) is unaffected
  # - only this stack is created/destroyed.
  delete_protection = false
}
