# Grafana Cloud Synthetic Monitoring — uptime/latency HTTP probes (GA).
# ---------------------------------------------------------------------------
# GRAFANA-CLOUD ONLY. Synthetic Monitoring is a Grafana Cloud product; it has no
# equivalent in observability.mode=oss/managed-azure/managed-aws, so this module is
# applied only in grafana-cloud mode (gated by the caller, like grafana-cloud-token).
#
# Keyless: both the cloud and SM provider tokens derive from the stack access policy
# (var.cloud_access_policy_token), the same Cloud-token pattern as grafana-cloud-token.
#
# Targets the PUBLIC, non-IAP endpoints only. The IAP-protected hosts (jenkins, argocd,
# headlamp, pgadmin) would return Google's OAuth login page, not the app, so probing
# them is meaningless — we probe the open microservices host(s).

data "grafana_cloud_stack" "this" {
  slug = var.stack_slug
}

resource "grafana_synthetic_monitoring_installation" "this" {
  stack_id              = data.grafana_cloud_stack.this.id
  metrics_publisher_key = var.cloud_access_policy_token
}

# Resolve Grafana-Cloud-hosted probe IDs by region name.
data "grafana_synthetic_monitoring_probes" "all" {
  provider = grafana.sm
}

# One HTTP check per public host. Grafana-Cloud-hosted probes from a few regions hit
# the health endpoint; results feed uptime %, latency, and SLO-able metrics/logs.
resource "grafana_synthetic_monitoring_check" "http" {
  for_each = var.targets
  provider = grafana.sm

  job     = each.key
  target  = each.value
  enabled = true
  probes  = [for name in var.probe_names : data.grafana_synthetic_monitoring_probes.all.probes[name]]
  labels  = { env = "stable", project = "jenkins-2026" }

  settings {
    http {
      method             = "GET"
      ip_version         = "V4"
      valid_status_codes = [200]
      fail_if_not_ssl    = true
    }
  }
}
