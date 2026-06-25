# Grafana Cloud → Observability → Cloud provider → GCP
# ---------------------------------------------------------------------------
# Grafana Cloud runs a HOSTED scraper that pulls GCP Cloud Monitoring (and,
# optionally, Cloud Logging) into your stack — GKE control plane, Compute, the
# L7 Gateway/LB, GCS, quotas, etc. It is NOT a GCP workload, so it can't use
# Workload Identity Federation: it authenticates with a service-account KEY you
# paste into the Grafana Cloud UI.
#
# This module IaC-manages the durable, auditable part — the read-only service
# account and its roles. It deliberately does NOT create the key (a long-lived key
# in Terraform state would defeat the purpose, and everything else in this repo is
# keyless/WIF). Generate the key out-of-band and hand it to Grafana Cloud — see the
# `key_command` output and docs/301-OBSERVABILITY.md.
#
# HUMAN-RUN, local state (like terraform/bootstrap): it's a one-time, project-level
# IAM grant, not part of the per-cluster CI lifecycle. Optional / opt-in.

resource "google_service_account" "grafana_cloud_gcp" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = "Grafana Cloud GCP integration (read-only Cloud Monitoring scraper)"
  description  = "Used by Grafana Cloud's hosted GCP cloud-provider integration to read Cloud Monitoring metrics. Key is generated out-of-band and uploaded in the Grafana Cloud UI."
}

# Least privilege for the metrics scraper:
#   monitoring.viewer  — read Cloud Monitoring time series (required)
#   cloudasset.viewer  — resource metadata/labels so the integration can enrich
#                        and group resources (recommended by Grafana)
resource "google_project_iam_member" "roles" {
  for_each = toset(var.roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.grafana_cloud_gcp.email}"
}
