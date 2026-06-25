variable "project_id" {
  type        = string
  description = "GCP project hosting the resources Grafana Cloud will scrape (the GKE project)."
}

variable "account_id" {
  type        = string
  default     = "grafana-cloud-gcp"
  description = "Service account ID (the part before @). Final email is <account_id>@<project>.iam.gserviceaccount.com."
}

variable "roles" {
  type = list(string)
  default = [
    "roles/monitoring.viewer",
    "roles/cloudasset.viewer",
  ]
  description = "Read-only roles for the Grafana Cloud GCP metrics scraper. Add roles/logging.viewer (+ a Pub/Sub export) only if you also enable GCP Logs."
}
