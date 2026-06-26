output "state_bucket" {
  description = "GCS bucket holding terraform/gke's remote state. Set as the TF_STATE_BUCKET GitHub Actions secret/variable."
  value       = google_storage_bucket.tf_state.name
}

output "ci_service_account_email" {
  description = "Service account GitHub Actions impersonates. Set as the GCP_SERVICE_ACCOUNT GitHub Actions secret/variable."
  value       = google_service_account.ci.email
}

output "workload_identity_provider" {
  description = "Full resource name of the Workload Identity Pool Provider. Set as the GCP_WORKLOAD_IDENTITY_PROVIDER GitHub Actions secret/variable."
  value       = "projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
}

output "project_id" {
  description = "GCP project ID. Set as the GCP_PROJECT_ID GitHub Actions secret/variable."
  value       = var.project_id
}

output "dns_zone_name_servers" {
  description = "Nameservers of the permanent delegated <base_domain> zone. ONE-TIME, PERMANENT: at the parent domain's DNS (e.g. Squarespace) create NS records for <base_domain> pointing at these four. They never change (the zone lives in this never-torn-down root tier), so this delegation is done once for the life of the project."
  value       = google_dns_managed_zone.public.name_servers
}
