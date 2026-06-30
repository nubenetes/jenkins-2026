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
    # Secret Manager backs secrets.backend=eso: up.sh's provision_secret pushes
    # secret values here (gcloud secrets create / versions add) and the External
    # Secrets Operator reads them back via Workload Identity. Enabled
    # unconditionally — harmless/unused in the default imperative mode, and
    # re-enabling APIs is slow so it's left on. See docs/201 § Secrets Management.
    "secretmanager.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  # Disabling APIs on destroy can break other resources in the project that
  # rely on them - leave enabled.
  disable_on_destroy = false
}

# NOTE on the regional SSD_TOTAL_GB quota (the binding capacity ceiling — every
# pd-balanced/pd-ssd disk counts: node boot disks + HA CNPG Postgres PVs (data+WAL ×
# services) + Tekton workspace PVCs + concurrent ci-spot NAP nodes). It is NOT raised here:
# a consumer-quota override (google_service_usage_consumer_quota_override) can only set
# values WITHIN Google's self-service maximum, which for SSD_TOTAL_GB equals the current
# limit (500) — anything higher returns COMMON_QUOTA_CONSUMER_OVERRIDE_TOO_HIGH and would
# fail the apply. Raising it above 500 requires a Google-approved quota-increase REQUEST
# (Console → IAM & Admin → Quotas → SSD_TOTAL_GB → Edit/Request increase, or the Quota
# Adjuster), which is not Terraform-able. This is WHY {jenkins,tekton}.runNodePool defaults
# to `static` (no per-build PD, so CI doesn't push against this ceiling); ci-spot is the
# quota-hungry opt-in. See docs/runbooks/nap-spot-provisioning.md § SSD quota.

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

# --- External Secrets Operator identity (secrets.backend=eso) -----------------
# The cluster runs GKE Workload Identity (workload_metadata_config = GKE_METADATA
# below), so pods authenticate as the GCP SA bound to their Kubernetes SA — NOT
# as the node SA. ESO therefore needs its OWN least-privilege GSA (only
# secretmanager.secretAccessor) that the ESO controller KSA impersonates via
# Workload Identity. The KSA is annotated with this GSA's email by the
# external-secrets ArgoCD app (helm values templated in scripts/08.5-argocd.sh).
# Created unconditionally — harmless/unused in the default imperative mode. See
# docs/201-ARCHITECTURE.md § Secrets Management.
resource "google_service_account" "eso" {
  project      = var.project_id
  account_id   = "eso-secret-reader"
  display_name = "jenkins-2026 External Secrets Operator (Secret Manager reader)"
}

resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

# Let the ESO controller KSA (namespace/name external-secrets/external-secrets,
# the chart defaults) impersonate the GSA above.
resource "google_service_account_iam_member" "eso_wi" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
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

  # GKE Dataplane V2 (Cilium/eBPF, replaces kube-proxy/iptables). Two reasons:
  #   1. It ENFORCES NetworkPolicy natively. Without it (and without the legacy
  #      Calico `network_policy` addon, which is mutually exclusive with this and
  #      must therefore stay absent), the cluster accepts the NetworkPolicy
  #      objects in infrastructure/networkpolicies*.yaml but silently does NOT
  #      enforce them — a false sense of microsegmentation. Dataplane V2 makes the
  #      default-deny + allow rules actually take effect.
  #   2. It is the prerequisite for Cilium-based, sidecar-free mTLS if we later
  #      close the pod-to-pod encryption gap that way (cheaper than Istio here).
  # NOTE: this field is immutable — changing it forces the cluster to be
  # RECREATED. Pick it up with a fresh provision (Decom.cluster.01 then
  # Day1.cluster.01), not an in-place Day1 re-run.
  datapath_provider = "ADVANCED_DATAPATH"

  # Pod-to-pod TRANSPARENT ENCRYPTION (WireGuard), the lightweight, sidecar-free
  # way to close the in-cluster encryption gap on GKE — Dataplane V2's managed
  # Cilium does it for us (we can't configure Cilium directly on GKE). Requires
  # ADVANCED_DATAPATH above. It encrypts INTER-NODE pod traffic on the wire (pods
  # co-located on the same node never leave it, so they aren't encrypted).
  # Caveat: this is transport encryption, NOT identity-based mutual auth (no
  # per-workload mTLS identity/authZ like Istio/Linkerd) — it closes the
  # "plaintext on the wire" gap without a service mesh. Some CPU/latency overhead.
  in_transit_encryption_config = "IN_TRANSIT_ENCRYPTION_INTER_NODE_TRANSPARENT"

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

  # GKE Node Auto-Provisioning (NAP) — the GA, Google-native equivalent of Karpenter
  # (there is no production-ready Karpenter provider for GCP). NAP watches for
  # unschedulable Pods and auto-creates/deletes right-sized node pools, including Spot
  # pools and scale-to-zero, driven by the Custom ComputeClasses in
  # infrastructure/compute-classes/ (Pods select one via the
  # `cloud.google.com/compute-class` nodeSelector; GKE auto-labels + taints the pools it
  # creates with the class name). The static pool above stays for the long-lived platform;
  # NAP only kicks in for the tainted CI-agent workloads that target a ComputeClass, so a
  # NAP hiccup never blocks the core provision (no platform pod depends on it).
  # `auto_provisioning_defaults` reuses the dedicated node SA (least privilege, not the
  # broad default compute SA), Shielded VMs, and auto-repair/upgrade. Toggle with
  # `enable_node_autoprovisioning`. OPTIMIZE_UTILIZATION makes the autoscaler consolidate
  # and scale auto-created pools down aggressively (right for ephemeral CI bursts).
  dynamic "cluster_autoscaling" {
    for_each = var.enable_node_autoprovisioning ? [1] : []
    content {
      enabled             = true
      autoscaling_profile = "OPTIMIZE_UTILIZATION"

      resource_limits {
        resource_type = "cpu"
        minimum       = 0
        maximum       = var.nap_max_cpu
      }
      resource_limits {
        resource_type = "memory"
        minimum       = 0
        maximum       = var.nap_max_memory_gb
      }

      auto_provisioning_defaults {
        service_account = google_service_account.nodes.email
        oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
        image_type      = "COS_CONTAINERD"
        disk_type       = "pd-balanced"
        # Match the static pool's disk (var.disk_size_gb, default 50) instead of the 100 GB
        # NAP default. Ephemeral CI nodes cache images on the host but keep no persistent
        # data, so 50 GB is ample — and `pd-balanced` counts against the regional
        # `SSD_TOTAL_GB` quota, so an oversized boot disk starves NAP of headroom to add
        # Spot nodes (observed live: NAP scale-ups failing `Quota 'SSD_TOTAL_GB' exceeded`).
        # Halving it lets ~2× more concurrent Spot CI nodes fit under the same quota.
        disk_size = var.disk_size_gb

        management {
          auto_repair  = true
          auto_upgrade = true
        }

        shielded_instance_config {
          enable_secure_boot          = true
          enable_integrity_monitoring = true
        }
      }
    }
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

  # Deleting a node pool gracefully drains it (evicting pods, respecting PDBs +
  # terminationGracePeriod). down.sh's final drain-prep removes the usual
  # blockers, but give GCP comfortable headroom so a slow drain still completes
  # within terraform's wait instead of erroring at the 30m default (the op keeps
  # RUNNING and finishes anyway — a re-run then converges, but this avoids the
  # spurious failure). See scripts/down.sh § Final drain-prep.
  timeouts {
    delete = "60m"
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

  lifecycle {
    ignore_changes = [
      node_config[0].kubelet_config,
    ]
  }
}

# Grant objectAdmin privileges on the pre-created backups bucket to the GKE node
# service account. Bucket name is project-scoped (matches terraform/bootstrap's
# google_storage_bucket.postgres_backups — see the note there on the global GCS
# namespace). The CI SA can manage this binding because bootstrap grants it
# storage.admin on the bucket (google_storage_bucket_iam_member.ci_postgres_backups).
resource "google_storage_bucket_iam_member" "nodes_postgres_backups" {
  bucket = "${var.project_id}-jenkins-2026-postgres-backups"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.nodes.email}"
}

# --- CNPG Postgres backups identity (barman -> GCS via Workload Identity) ------
# The microservices CNPG Clusters archive WAL + base backups to the bucket above.
# Under Workload Identity the postgres pods authenticate as the GSA bound to their
# Kubernetes SA - NOT the node SA - so nodes_postgres_backups does not help them
# (it stays for any node-level access). CNPG names the KSA after each Cluster
# (postgres-<svc>, from the gitops chart templates/postgres.yaml) and annotates it
# with this GSA via serviceAccountTemplate; the microservices ApplicationSet passes
# the GSA account_id + project + bucket as helm params (scripts/08.5-argocd.sh), so
# the chart's placeholder defaults (jenkins-2026-sa@jenkins-2026) are overridden by
# the real project at deploy time. See docs/502 / docs/902 § Postgres WAL backups.
resource "google_service_account" "pg_backups" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-pg-backups"
  display_name = "jenkins-2026 CNPG Postgres backups (GCS writer)"
}

# storage.admin (bucket-scoped), NOT objectAdmin: barman-cloud-check-wal-archive does a
# storage.buckets.get when validating the destination, which objectAdmin lacks — so
# objectAdmin makes WAL archiving fail 403 ("does not have storage.buckets.get") and no
# backup can ever run. Mirrors ci_postgres_backups (same lesson) and is still least-
# privilege: scoped to the one backups bucket only.
resource "google_storage_bucket_iam_member" "pg_backups" {
  bucket = "${var.project_id}-jenkins-2026-postgres-backups"
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.pg_backups.email}"
}

# Let each CNPG Cluster KSA (microservices/postgres-<svc>) impersonate the GSA.
# The set mirrors the services in jenkins/pipelines/services.yaml (each gets a CNPG
# Cluster + KSA named postgres-<svc>); extend this set if services are added.
resource "google_service_account_iam_member" "pg_backups_wi" {
  for_each           = toset(["postgres-gateway", "postgres-jhipstersamplemicroservice"])
  service_account_id = google_service_account.pg_backups.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[microservices/${each.value}]"
}
