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

# =============================================================================
# DNS records — make the public endpoint fully idempotent.
#
# The delegated zone itself lives in the PERMANENT root tier (terraform/bootstrap's
# google_dns_managed_zone.public, name "jenkins-2026-public-zone") so its
# nameservers — hence the one-time parent-domain delegation — never change. Here
# we just (re)create the records INSIDE it: every Day0.infra.01 / Day1.cluster.00
# run reconciles the wildcard A to the current static IP and ensures the cert
# authorization CNAME exists. So a Decom-everything — even an explicit Decom.infra.01
# gateway teardown that drops these records and the IP — comes back with NO manual
# DNS: the records are recreated against the unchanged zone on rebuild.
#
# managed_zone is referenced by the fixed NAME (the zone is in bootstrap's state,
# not this module's) — keep it in sync with terraform/bootstrap.
# =============================================================================
locals {
  public_zone_name = "jenkins-2026-public-zone" # == terraform/bootstrap google_dns_managed_zone.public.name
}

# Wildcard A → the persistent gateway IP. Covers every app host
# (argocd/jenkins/headlamp/pgadmin/grafana/microservices[-develop]).
resource "google_dns_record_set" "wildcard_a" {
  project      = var.project_id
  managed_zone = local.public_zone_name
  name         = "*.${var.base_domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.gateway_ip.address]
}

# Certificate Manager DNS-authorization CNAME — provisions the managed wildcard
# cert (jenkins-2026-cert) automatically, with no hand-created record.
resource "google_dns_record_set" "cert_auth" {
  project      = var.project_id
  managed_zone = local.public_zone_name
  name         = google_certificate_manager_dns_authorization.this.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.this.dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.this.dns_resource_record[0].data]
}
