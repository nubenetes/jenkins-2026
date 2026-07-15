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

output "grafana_llm_gsa_email" {
  description = "Email of the Grafana LLM GSA the LiteLLM KSA is annotated with (iam.gke.io/gcp-service-account). Empty when observability.llm.enabled is off."
  value       = var.observability_llm_enabled ? google_service_account.grafana_llm[0].email : ""
}

output "network_name" {
  description = <<-EOT
    The VPC name. Consumed by Decom.cluster.01-gke to sweep controller-created firewall
    rules that PIN this network and would otherwise fail its delete — scoping the sweep to
    this VPC keeps it away from the project's `default` network. See docs/104 § 4.8.
  EOT
  value       = google_compute_network.vpc.name
}
