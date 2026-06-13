variable "grafana_cloud_api_token" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Grafana Cloud Access Policy token (org-level), created once by hand in
    the Grafana Cloud portal (Administration > Access Policies > Create
    access policy, realm = your organization), with scopes:
    accesspolicies:read, accesspolicies:write, accesspolicies:delete,
    stacks:read, stacks:write, stacks:delete, stack-service-accounts:write.
    Then create a token for that policy. This same token is also used by
    terraform/grafana-cloud-token. See README.md "GitHub Actions automation".
  EOT
}

variable "stack_slug" {
  type        = string
  description = "Subdomain for the jenkins-2026 Grafana Cloud stack: https://<stack_slug>.grafana.net. Must be globally unique across all of Grafana Cloud."
}

variable "region_slug" {
  type        = string
  default     = "prod-eu-west-3"
  description = "Grafana Cloud region slug for the new stack - see https://grafana.com/docs/grafana-cloud/account-management/regions/ for the list of available regions."
}
