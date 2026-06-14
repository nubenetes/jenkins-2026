variable "grafana_cloud_api_token" {
  type        = string
  sensitive   = true
  description = "Same org-level Grafana Cloud Access Policy token as terraform/grafana-cloud-stack (GRAFANA_CLOUD_API_TOKEN GitHub secret)."
}

variable "stack_slug" {
  type        = string
  description = "Slug of the persistent stack created by terraform/grafana-cloud-stack (GRAFANA_CLOUD_STACK_SLUG GitHub secret) - looked up via the grafana_cloud_stack data source."
}

variable "jenkins_admin_password" {
  type        = string
  sensitive   = true
  description = "Password for the Jenkins admin user, used to configure the datasource."
}
