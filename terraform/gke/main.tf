# =============================================================================
# Throwaway GKE cluster for test/e2e.sh.
#
# Everything here is self-contained (its own VPC/subnet/service account) so
# `terraform destroy` leaves no trace beyond the project-level API enablement
# (which is left enabled - re-enabling APIs is slow and harmless to leave on).
# =============================================================================

locals {
  network_name = "${var.cluster_name}-vpc"
  subnet_name  = "${var.cluster_name}-subnet"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  # Disabling APIs on destroy can break other resources in the project that
  # rely on them - leave enabled.
  disable_on_destroy = false
}

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = local.network_name
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  project       = var.project_id
  name          = local.subnet_name
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# Minimal-privilege service account for cluster nodes (logging/monitoring +
# read-only Artifact Registry, in case images are ever pulled from GCP).
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "jenkins-2026 GKE node service account"
}

resource "google_project_iam_member" "nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# IAM for Headlamp's per-user OIDC->GKE-API access-token passthrough (see
# README.md "Headlamp") - kept for if/when upstream fixes the backend bug
# that makes this non-functional today. roles/container.clusterViewer is the
# minimal role for the GKE API to accept a user's Google token; in-cluster
# RBAC (cluster-admin) for these emails is granted separately by
# scripts/08-headlamp.sh.
resource "google_project_iam_member" "headlamp_admins" {
  for_each = toset(var.admin_emails)

  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "user:${each.value}"
}

# Same admin email list also gates access through Identity-Aware Proxy on the
# Jenkins and Headlamp Gateway backends (see scripts/09-gateway.sh and
# README.md "Public access (GKE Gateway API + IAP)").
resource "google_project_iam_member" "iap_accessors" {
  for_each = toset(var.admin_emails)

  project = var.project_id
  role    = "roles/iap.httpsResourceAccessor"
  member  = "user:${each.value}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.zone

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Required for the Gateway/HTTPRoute/GCPBackendPolicy resources applied by
  # scripts/09-gateway.sh - see README.md "Public access (GKE Gateway API +
  # IAP)".
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Managed separately below so it can be sized/autoscaled independently.
  remove_default_node_pool = true
  initial_node_count       = 1

  # This cluster is a throwaway test fixture - allow `terraform destroy`
  # to remove it (the google provider defaults this to true).
  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "primary" {
  project  = var.project_id
  name     = "${var.cluster_name}-pool"
  location = var.zone
  cluster  = google_container_cluster.this.name

  initial_node_count = var.node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      app = "jenkins-2026"
    }

    tags = ["jenkins-2026"]
  }
}
