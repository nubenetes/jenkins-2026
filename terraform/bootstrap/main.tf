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
    # The SAME story, one resource type over — surfaced by the opt-in Cloud Service
    # Mesh (docs/506): CSM creates its own health-check firewall rule (`gke-csm-thc-*`)
    # on the VPC, GKE does NOT remove it with the cluster, and it pins the network
    # exactly like a lingering NEG does ("network ... is already being used by ...
    # firewalls/gke-csm-thc-..."), so Decom.cluster.01 must force-delete it. But despite
    # its name, roles/compute.networkAdmin grants firewalls.get/list ONLY: GCP files
    # firewall MUTATIONS under *security*, not *networking*. securityAdmin adds
    # compute.firewalls.delete — again without the breadth of roles/compute.admin.
    "roles/compute.securityAdmin",
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
    # Lets Day0.infra.01's terraform/gateway-bootstrap manage the delegated public
    # DNS zone + records (wildcard A → static IP, cert-validation CNAME) so the
    # public endpoint is idempotent across Decom/rebuild with no manual DNS. See
    # docs/501-PLATFORM_OPERATIONS.md § Public access.
    "roles/dns.admin",
    # secrets.backend=eso: up.sh runs as this CI SA and pushes secret values to
    # GCP Secret Manager (gcloud secrets create / versions add / versions access
    # for the idempotency check). secretmanager.admin is the minimal PREDEFINED
    # role that includes secrets.create (the secretVersion* roles don't). The
    # node SA gets the read-only secretAccessor in terraform/gke instead. Unused
    # in the default imperative mode. See docs/201 § Secrets Management.
    "roles/secretmanager.admin",
    # security.binaryAuthorization.enabled (docs/507): Day1's terraform/gke creates a
    # Cloud KMS keyring/key (+ setIamPolicy for the signer GSA), a Container Analysis
    # note, a Binary Authorization attestor + the project policy. These are the create/
    # admin roles for each — without them the apply 403s IAM_PERMISSION_DENIED on
    # cloudkms.keyRings.create / containeranalysis.notes.create.
    "roles/cloudkms.admin",
    # cloudkms.admin MANAGES keys but does NOT include cryptoKeyVersions.viewPublicKey
    # (that is an operation permission, not a management one). terraform/gke's data
    # source reads the attestor key's PEM public key to embed it in the attestor, so
    # the CI SA also needs publicKeyViewer.
    "roles/cloudkms.publicKeyViewer",
    "roles/containeranalysis.notes.editor",
    "roles/binaryauthorization.attestorsAdmin",
    "roles/binaryauthorization.policyEditor",
    # serviceMesh.mode=cloud-service-mesh (docs/506): Day1's terraform/gke registers
    # the cluster to a Fleet + enables the `servicemesh` Fleet feature (managed CSM).
    "roles/gkehub.admin",
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
    # For the permanent public DNS zone below.
    "dns.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Permanent public DNS zone (delegated subdomain). Lives HERE — in the never-
# torn-down root tier — so its nameservers are stable for the lifetime of the
# project: you delegate <base_domain> from the parent domain (e.g. Squarespace)
# to these nameservers ONCE, ever. terraform/gateway-bootstrap fills the zone
# with the wildcard-A (→ static IP) and cert-validation CNAME and re-applies them
# every Day0.infra.01 / Day1.cluster.00, so a Decom-everything — even an explicit
# Decom.infra.01 gateway teardown — and rebuild brings the URLs back with NO DNS
# changes (the zone, hence the delegation, never changes). The fixed zone name is
# referenced by terraform/gateway-bootstrap's google_dns_record_set.managed_zone.
# -----------------------------------------------------------------------------
resource "google_dns_managed_zone" "public" {
  project     = var.project_id
  name        = "jenkins-2026-public-zone"
  dns_name    = "${var.base_domain}."
  description = "Permanent public zone for jenkins-2026 (${var.base_domain}); delegated from the parent domain. Records are managed by terraform/gateway-bootstrap."

  # Let `bootstrap.sh down` (the root teardown) destroy the zone even if a record
  # the gateway-bootstrap module created still lingers — Cloud DNS otherwise
  # refuses to delete a non-empty zone. Mirrors the state bucket's force_destroy.
  # Only ever exercised by the root teardown; ordinary Decom keeps the zone.
  force_destroy = true

  depends_on = [google_project_service.apis]
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
# NOTE: project-scoped name (like the state bucket above). GCS bucket names share ONE
# global namespace, so a bare "jenkins-2026-postgres-backups" collides the moment the
# project is rebuilt under a new project ID (the old project still owns the name) —
# `apply` then fails with 409 "bucket name is not available". Prefixing with the
# (globally-unique) project ID makes it collision-proof and portable across rebuilds.
resource "google_storage_bucket" "postgres_backups" {
  project       = var.project_id
  name          = "${var.project_id}-jenkins-2026-postgres-backups"
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

# terraform/gke runs as the CI service account and manages the GKE node SA's
# objectAdmin binding ON this bucket (google_storage_bucket_iam_member.
# nodes_postgres_backups). A read-modify-write of a bucket's IAM policy needs
# storage.buckets.getIamPolicy + setIamPolicy, which none of the CI SA's
# project-level ci_roles grant — so without this, Day1's terraform/gke apply fails
# with 403 "does not have storage.buckets.getIamPolicy". Grant storage.admin scoped
# to THIS bucket only (least privilege; mirrors ci_state_bucket above).
resource "google_storage_bucket_iam_member" "ci_postgres_backups" {
  bucket = google_storage_bucket.postgres_backups.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.ci.email}"
}
