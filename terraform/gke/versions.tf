# Pinned to the latest stable Terraform (1.15.x) and a current 6.x google
# provider. Developed/tested against Terraform v1.15.6.
#
# NOTE on Terraform Stacks: Stacks (.tfstack.hcl/.tfdeploy.hcl) are an
# HCP Terraform-only feature aimed at orchestrating many similar
# deployments (e.g. per-environment fleets) and require an HCP Terraform
# org/account. This module provisions a single throwaway cluster for
# test/e2e.sh with a local backend, so a plain root module keeps the
# "no extra accounts beyond GCP" property of the rest of this repo. If you
# adopt HCP Terraform for your own use, this module's resources can be
# lifted into a Stack component largely as-is.
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
  region  = var.region
}
