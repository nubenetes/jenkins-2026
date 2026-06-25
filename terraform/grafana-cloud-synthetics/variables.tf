variable "stack_slug" {
  type        = string
  description = "Grafana Cloud stack slug (output of terraform/grafana-cloud-stack)."
}

variable "cloud_access_policy_token" {
  type        = string
  sensitive   = true
  description = "Cloud Access Policy token for the stack (scopes incl. metrics:write/logs:write/set:* for SM). Minted like grafana-cloud-token; never committed."
}

variable "targets" {
  type        = map(string)
  description = "job name -> URL to probe. PUBLIC, non-IAP endpoints only (IAP hosts return the OAuth page)."
  default = {
    "microservices-stable"  = "https://microservices.jenkins2026.nubenetes.com/management/health"
    "microservices-develop" = "https://microservices-develop.jenkins2026.nubenetes.com/management/health"
  }
}

variable "probe_names" {
  type        = list(string)
  default     = ["Frankfurt", "London"]
  description = "Grafana-Cloud-hosted probe regions to run each check from."
}
