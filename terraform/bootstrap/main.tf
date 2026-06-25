data "google_project" "this" {
  project_id = var.project_id
}

locals {
  state_bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project_id}-jenkins-2026-tfstate"

  # Project-level roles granted to the CI service account so the GitHub
  # Actions workflows can run terraform/gke's apply/destroy end to end -
  # mirrors README.md's "Prerequisites" for running test/e2e.sh by hand.
  ci_roles = [
    "roles/container.admin",
    "roles/compute.networkAdmin",
    # roles/compute.networkAdmin can list but NOT delete Network Endpoint
    # Groups. The GKE Gateway/Ingress controller creates standalone zonal
    # NEGs for HTTPRoute/Service backends; on teardown scripts/down.sh must
    # force-delete any that linger, otherwise they pin the VPC and
    # terraform/gke's destroy fails ("network ... is already being used by
    # ... networkEndpointGroups/..."). loadBalancerAdmin adds
    # compute.networkEndpointGroups.delete (plus the rest of the LB resource
    # graph) without the breadth of roles/compute.admin.
    "roles/compute.loadBalancerAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
    # Lets Day0.infra.01-gateway's terraform/gateway-bootstrap manage the DNS
    # authorization + certificate map for the public Gateway's managed cert.
    # NOTE: must be OWNER, not editor — roles/certificatemanager.editor grants
    # create/get/list/update but NO .delete on ANY certificatemanager resource
    # (certs/certmaps/certmapentries/dnsauthorizations), so Decom.infra.01's
    # terraform destroy failed with 403 'certmapentries.delete denied' (run
    # 28202019543). owner includes the .delete permissions.
    "roles/certificatemanager.owner",
  ]
}

# APIs required by this bootstrap module itself (Workload Identity
# Federation + the state bucket). terraform/gke enables container.googleapis.com
# / compute.googleapis.com itself.
resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Remote state bucket for terraform/gke, shared by the gke-provision and
# gke-decommission GitHub Actions workflows.
# -----------------------------------------------------------------------------
resource "google_storage_bucket" "tf_state" {
  name     = local.state_bucket_name
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true
  # Default false (safety: don't let an apply nuke all remote state). The root
  # teardown (scripts/bootstrap.sh down) passes state_bucket_force_destroy=true so
  # `terraform destroy` can remove the bucket even though it still holds other
  # modules' state objects + non-current versions.
  force_destroy = var.state_bucket_force_destroy

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# CI service account used by GitHub Actions (via Workload Identity
# Federation - no JSON key).
# -----------------------------------------------------------------------------
resource "google_service_account" "ci" {
  project      = var.project_id
  account_id   = var.ci_service_account_id
  display_name = "jenkins-2026 GitHub Actions CI"
}

resource "google_project_iam_member" "ci_roles" {
  for_each = toset(local.ci_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci.email}"
}

resource "google_storage_bucket_iam_member" "ci_state_bucket" {
  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ci.email}"
}

# -----------------------------------------------------------------------------
# Workload Identity Federation: lets GitHub Actions workflows in
# var.github_repo impersonate google_service_account.ci without a
# long-lived JSON key.
# -----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "GitHub Actions"
  description               = "Identities for GitHub Actions workflows in ${var.github_repo}"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Restrict to this repo only - any branch/ref.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# 6. Google Cloud Storage bucket for PostgreSQL (CNPG) backups (persistent bootstrap tier)
resource "google_storage_bucket" "postgres_backups" {
  project       = var.project_id
  name          = "jenkins-2026-postgres-backups"
  location      = var.region
  force_destroy = false # Protect backup data

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7 # Prune backups older than 7 days
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 3 # Move backups to Nearline after 3 days to cut costs
    }
  }
}
