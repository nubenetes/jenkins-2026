output "service_account_email" {
  value       = google_service_account.grafana_cloud_gcp.email
  description = "Paste this SA into the Grafana Cloud GCP integration (or use the key below)."
}

output "key_command" {
  value       = "gcloud iam service-accounts keys create grafana-cloud-gcp-key.json --iam-account=${google_service_account.grafana_cloud_gcp.email}"
  description = "Run this to mint the key JSON to upload in Grafana Cloud → Observability → Cloud provider → GCP. Treat the file as a secret; delete it after uploading. Rotate/disable keys you no longer use."
}
