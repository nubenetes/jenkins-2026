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
# terraform/gateway-bootstrap is a one-time setup step, exactly like
# terraform/grafana-cloud-stack: it provisions the persistent GCP resources
# (static IP, Certificate Manager DNS authorization/certificate/map) that
# public access to Jenkins/Microservices/Headlamp depends on.
#
# Run it once via the "Gateway bootstrap" GitHub Actions workflow
# (.github/workflows/gateway-bootstrap.yml, state in the same GCS bucket as
# terraform/gke, prefix "jenkins-2026/gateway-bootstrap") - or locally, with
# this directory's own local state (terraform.tfstate, gitignored).
#
# Re-running `terraform apply` against existing state is a safe no-op.
#
# The IAP OAuth client (IAP_OAUTH_CLIENT_ID/SECRET) is a separate, manual,
# one-time Console step - see README.md "Public access (GKE Gateway API +
# IAP)".
#
# gke-provision/gke-decommission do NOT run this module - scripts/09-gateway.sh
# only references its outputs by the fixed resource names defined in main.tf
# (jenkins-2026-gateway-ip, jenkins-2026-cert-map), via config/config.yaml's
# gateway.staticIPName / gateway.certMapName.
# -----------------------------------------------------------------------------
