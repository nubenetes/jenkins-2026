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
# terraform/bootstrap is a one-time, *locally run* setup step for the
# .github/workflows/gke-provision.yml / gke-decommission.yml automation:
#
#   - a GCS bucket to hold terraform/gke's state (so the two separate GitHub
#     Actions workflow runs - provision and decommission - share the same
#     cluster's state)
#   - a Workload Identity Federation pool/provider + service account so those
#     workflows can authenticate to GCP without a long-lived JSON key
#
# It deliberately keeps its OWN state local (terraform/bootstrap/terraform.tfstate,
# gitignored): bootstrapping the bucket that terraform/gke's CI runs will use
# from a backend stored *in* that same bucket would be circular. Run this
# once from your workstation (see README.md), copy the printed outputs into
# the repo's GitHub Actions secrets, and keep the local state file - if it's
# lost, re-running `terraform apply` will fail on "already exists" for each
# resource and they'll need to be imported (`terraform import`) or recreated
# by hand.
# -----------------------------------------------------------------------------
