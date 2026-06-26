variable "project_id" {
  description = "GCP project ID (same one terraform/gke deploys into)."
  type        = string
}

variable "region" {
  description = "Region for the Terraform state bucket."
  type        = string
  default     = "us-central1"
}

variable "github_repo" {
  description = "GitHub \"org/repo\" allowed to assume the CI service account via Workload Identity Federation."
  type        = string
  default     = "nubenetes/jenkins-2026"
}

variable "state_bucket_name" {
  description = "GCS bucket name for terraform/gke's remote state. Must be globally unique; defaults to a project-scoped name."
  type        = string
  default     = ""
}

variable "state_bucket_force_destroy" {
  description = "Allow `terraform destroy` to delete the state bucket even when it still holds objects (other modules' state + non-current versions). Default false (safety). scripts/bootstrap.sh down passes true so the root teardown can remove the bucket."
  type        = bool
  default     = false
}

variable "ci_service_account_id" {
  description = "Account ID (local part of the email) for the CI service account."
  type        = string
  default     = "jenkins-2026-ci"
}

variable "workload_identity_pool_id" {
  description = "ID of the Workload Identity Pool created for GitHub Actions."
  type        = string
  default     = "jenkins-2026-github"
}

variable "workload_identity_provider_id" {
  description = "ID of the Workload Identity Pool Provider created for GitHub Actions."
  type        = string
  default     = "github-actions"
}

variable "base_domain" {
  description = "Public base domain. The PERMANENT delegated Cloud DNS zone (google_dns_managed_zone.public) is created here so its nameservers never change across gateway rebuilds; terraform/gateway-bootstrap fills it with the wildcard-A + cert-validation records. Must match config/config.yaml's gateway.baseDomain and terraform/gateway-bootstrap's base_domain."
  type        = string
  default     = "jenkins2026.nubenetes.com"
}
