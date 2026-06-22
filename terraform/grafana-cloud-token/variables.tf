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
