output "static_ip_address" {
  description = "Global static IP address. The *.<base_domain> wildcard A record is now managed by this module (google_dns_record_set.wildcard_a) in the permanent delegated zone — no manual record needed. (The zone's nameservers / one-time delegation come from terraform/bootstrap's dns_zone_name_servers output.)"
  value       = google_compute_global_address.gateway_ip.address
}

output "static_ip_name" {
  description = "Name of the static IP resource - referenced by config/config.yaml's gateway.staticIPName."
  value       = google_compute_global_address.gateway_ip.name
}

output "dns_authorization_record" {
  description = "Certificate-validation CNAME. Now created automatically by this module (google_dns_record_set.cert_auth) in the delegated zone; exposed for reference/debugging only."
  value = {
    name = google_certificate_manager_dns_authorization.this.dns_resource_record[0].name
    type = google_certificate_manager_dns_authorization.this.dns_resource_record[0].type
    data = google_certificate_manager_dns_authorization.this.dns_resource_record[0].data
  }
}

output "certmap_name" {
  description = "Name of the certificate map - referenced by config/config.yaml's gateway.certMapName."
  value       = google_certificate_manager_certificate_map.this.name
}
