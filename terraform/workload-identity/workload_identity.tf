# Terraform Configuration for GKE Workload Identity Federation (Zero-Trust)
# Connects external CI/CD engines (like GitHub Actions) and in-cluster pods to GCP APIs without static JSON keys.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Variable configuration
variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "github_repo" {
  type        = string
  description = "Target GitHub repository in org/name format"
}

# 1. Workload Identity Pool for GitHub Actions
resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool-2026"
  display_name              = "GitHub Actions WIF Pool"
  description               = "Identity pool for GitHub Actions OIDC"
}

# 2. OIDC Provider mapped to GitHub
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub OIDC Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# 3. GCP Service Account used by CI/CD workloads
resource "google_service_account" "ci_agent_sa" {
  project      = var.project_id
  account_id   = "jenkins-2026-ci-agent"
  display_name = "Jenkins 2026 CI Agent Service Account"
}

# 4. Impersonation Binding: Allows GitHub runner repository to assume the Service Account
resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = google_service_account.ci_agent_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}

# 5. GKE In-Cluster Workload Identity: Allow the Kubernetes ServiceAccount to impersonate the GCP ServiceAccount
resource "google_service_account_iam_member" "gke_workload_identity" {
  service_account_id = google_service_account.ci_agent_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[jenkins/jenkins-agent]"
}

# 6. GCP IAM Secrets Access: Grant secretAccessor to CI service account
resource "google_project_iam_member" "ci_agent_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.ci_agent_sa.email}"
}

# 7. GKE External-Secrets Workload Identity: Allow external-secrets SA to impersonate the GCP Service Account
resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.ci_agent_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}
