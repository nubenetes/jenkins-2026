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

variable "stack_slug_prefix" {
  type        = string
  default     = "jenkins2026obs"
  description = <<-EOT
    Lowercase-alphanumeric prefix for the generated stack slug. The full slug is
    "<prefix><random-suffix>" and forms the subdomain https://<slug>.grafana.net.
    A fresh random suffix is generated per stack so re-creates never collide with
    Grafana Cloud's reserved-slug cooldown. No longer a GitHub secret/variable -
    the slug is an OUTPUT read from this module's state by 0.2.01-gke-provision.
  EOT
}

variable "region_slug" {
  type        = string
  default     = "prod-eu-west-3"
  description = "Grafana Cloud region slug for the new stack - see https://grafana.com/docs/grafana-cloud/account-management/regions/ for the list of available regions."
}
