# =============================================================================
# Persistent resources for exposing Jenkins, Microservices and Headlamp on the
# public internet via the GKE Gateway API (see README.md "Public access
# (GKE Gateway API + IAP)"):
#
#   - A global static IP that DNS A records point at.
#   - A Google-managed wildcard certificate, validated via a Certificate
#     Manager DNS authorization (one CNAME record, created once by hand at
#     the domain's DNS provider).
#
# The IAP OAuth client used by GCPBackendPolicy to put Identity-Aware Proxy in
# front of the Jenkins and Headlamp backends is NOT created here - the
# google_iap_brand/google_iap_client Terraform resources are deprecated
# (the IAP OAuth Admin API they depend on was deprecated after July 2025) and
# can no longer reliably create new brands/clients. It's a manual one-time
# Console step instead - see README.md "Public access (GKE Gateway API +
# IAP)".
#
# All names below are fixed/hardcoded so scripts/09-gateway.sh and
# terraform/gke can reference them without any extra secrets.
# =============================================================================

resource "google_compute_global_address" "gateway_ip" {
  project = var.project_id
  # Must match config/config.yaml's gateway.staticIPName - update both if you
  # ever change this.
  name = "jenkins-2026-gateway-ip"
}

resource "google_certificate_manager_dns_authorization" "this" {
  project = var.project_id
  name    = "jenkins-2026-dns-auth"
  domain  = var.base_domain
}

resource "google_certificate_manager_certificate" "this" {
  project = var.project_id
  name    = "jenkins-2026-cert"

  managed {
    domains = [
      var.base_domain,
      "*.${var.base_domain}",
    ]
    dns_authorizations = [google_certificate_manager_dns_authorization.this.id]
  }
}

resource "google_certificate_manager_certificate_map" "this" {
  project = var.project_id
  # Must match config/config.yaml's gateway.certMapName - update both if you
  # ever change this.
  name = "jenkins-2026-cert-map"
}

resource "google_certificate_manager_certificate_map_entry" "this" {
  project      = var.project_id
  name         = "jenkins-2026-cert-map-entry"
  map          = google_certificate_manager_certificate_map.this.name
  certificates = [google_certificate_manager_certificate.this.id]
  hostname     = "*.${var.base_domain}"
}
