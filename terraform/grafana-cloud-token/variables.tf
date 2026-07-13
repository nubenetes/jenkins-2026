variable "grafana_cloud_api_token" {
  type        = string
  sensitive   = true
  description = "Same org-level Grafana Cloud Access Policy token as terraform/grafana-cloud-stack (GRAFANA_CLOUD_API_TOKEN GitHub secret)."
}

variable "stack_slug" {
  type        = string
  description = "Slug of the stack created by terraform/grafana-cloud-stack - looked up via the grafana_cloud_stack data source. The slug is generated (random) by that module; CI reads it from its state output (terraform output -raw stack_slug) and passes it here, so it is no longer a GitHub secret/variable."
}

variable "jenkins_admin_password" {
  type        = string
  sensitive   = true
  description = "Password for the Jenkins admin user, used to configure the datasource."
}

variable "jenkins_backend_tls" {
  type        = bool
  default     = false
  description = "Whether gateway.backendTls is active on the cluster (docs/504 stage 6): the Jenkins Service's 8080 then serves HTTPS and the plain-HTTP listener for in-cluster callers moves to 8082 - the datasource URL must follow, because the PDC tunnel terminates in-cluster and dials it verbatim. Day1.cluster.01-gke passes the workflow's backend_tls input."
}
