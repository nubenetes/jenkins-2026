output "project_id" {
  description = "GCP project ID the cluster was created in."
  value       = var.project_id
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "GKE cluster location (zone)."
  value       = google_container_cluster.this.location
}

output "get_credentials_command" {
  description = "Command to fetch kubeconfig credentials for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${google_container_cluster.this.location} --project ${var.project_id}"
}

output "endpoint" {
  description = "GKE API server endpoint."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}
