terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

# -----------------------------------------------------------------------------
# terraform/bootstrap is the ROOT OF TRUST (Day0 "phase 0"): the GCS bucket
# holding ALL modules' remote Terraform state, the GitHub OIDC / Workload
# Identity Federation trust + CI service account the workflows (e.g.
# Day1.cluster.01-gke.yml / Decom.cluster.01-gke.yml) authenticate with, the
# Postgres backups bucket, and the permanent delegated public DNS zone.
#
# Do NOT drive this module with a bare `terraform apply` - create/converge it
# with the one human-run wrapper:
#
#   ./scripts/bootstrap.sh up      (and `down` to destroy the root)
#
# The script seeds the first apply with local state, then MIGRATES this
# module's own state into the bucket it just created (prefix
# jenkins-2026/bootstrap, via a gitignored backend_override.tf) - so even
# bootstrap is remote-state after the first run. It also sets the GitHub
# Actions secrets from the outputs automatically, and self-heals a lost or
# never-migrated state file by importing the existing named singletons
# (reconcile_imports()) instead of failing on "already exists".
#
# Full story: docs/100-BOOTSTRAP.md + the header comment of scripts/bootstrap.sh.
# -----------------------------------------------------------------------------
