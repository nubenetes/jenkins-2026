variable "project_id" {
  type        = string
  description = "GCP project ID - must match the project used by terraform/gke."
}

variable "base_domain" {
  type        = string
  default     = "jenkins2026.nubenetes.com"
  description = "Public base domain. The wildcard certificate covers this domain and *.<base_domain>. Override via TF_VAR_base_domain for forks using a different domain - must match config/config.yaml's gateway.baseDomain (or its JENKINS2026_BASE_DOMAIN override)."
}
