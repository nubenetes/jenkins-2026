# =============================================================================
# Opt-in security feature flags — both count-gated, complete no-op when off.
#   • serviceMesh.mode=cloud-service-mesh  → managed Cloud Service Mesh (CSM),
#     the STANDALONE per-client SKU (NOT GKE Enterprise). docs/506-SERVICE-MESH.md
#   • security.binaryAuthorization.enabled → supply-chain admission control
#     (Cloud KMS attestor + project policy).           docs/507-BINARY-AUTHORIZATION.md
# The conditional project APIs for both live in main.tf's google_project_service.apis.
#
# PROVIDER NOTE: the google_gke_hub_* resources are GA in recent `google` provider
# versions. If `terraform init/validate` reports the `mesh {}` block or these
# resources need the beta provider on this repo's pinned version, add a
# `provider = google-beta` line (+ a google-beta provider block) — a one-line
# follow-up confirmed at the first live Day1 with mode=cloud-service-mesh.
# =============================================================================

# --- Cloud Service Mesh (managed control plane, STANDALONE SKU) ---------------
# Register the cluster to a Fleet, then enable the `servicemesh` Fleet feature with
# MANAGEMENT_AUTOMATIC: Google provisions the managed control plane + Mesh CA and
# keeps the data plane upgraded (no istiod to operate — the whole point of CSM here).
# Because we enable only mesh.googleapis.com + gkehub (NOT the GKE Enterprise API),
# billing stays on the per-mesh-client STANDALONE SKU (~$0.50/client/mo) — docs/506.
# The in-cluster half (namespace injection labels + STRICT PeerAuthentication + a
# default AuthorizationPolicy) is scripts/08.85-service-mesh.sh.
#
# Rebuild-safety (docs/104): the Fleet membership is a persistent, fixed-identity
# resource. count-gated on the flag AND keyed to THIS cluster, so Decom destroys it
# and Day1 re-registers it in lockstep with the cluster (reconcile-to-current) — no
# orphaned membership, no collision on the fixed membership_id.
resource "google_gke_hub_membership" "mesh" {
  count = var.service_mesh_mode == "cloud-service-mesh" ? 1 : 0

  project       = var.project_id
  membership_id = "${var.cluster_name}-membership"
  location      = "global"

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${google_container_cluster.this.id}"
    }
  }
}

resource "google_gke_hub_feature" "mesh" {
  count = var.service_mesh_mode == "cloud-service-mesh" ? 1 : 0

  project  = var.project_id
  name     = "servicemesh"
  location = "global"
}

resource "google_gke_hub_feature_membership" "mesh" {
  count = var.service_mesh_mode == "cloud-service-mesh" ? 1 : 0

  project    = var.project_id
  location   = "global"
  feature    = google_gke_hub_feature.mesh[0].name
  membership = google_gke_hub_membership.mesh[0].membership_id

  mesh {
    # MANAGEMENT_AUTOMATIC = Google-managed control plane + managed data plane.
    management = "MANAGEMENT_AUTOMATIC"
  }
}

# --- Binary Authorization (supply-chain admission control) -------------------
# The Cloud KMS asymmetric signing key (only the CI service account may use it via
# Workload Identity — no key material leaves KMS), the Container Analysis note the
# attestation attaches to, the attestor the cluster policy trusts, and the PROJECT
# singleton policy. resources/sign-and-attest-image.sh signs each image DIGEST after
# push (single source, all four engines). All count-gated on the flag → off = no-op.
#
# Rebuild-safety (docs/104): the keyring/key + attestor + note are persistent,
# fixed-identity. KMS keys enter a SCHEDULED-DESTRUCTION window (they are never
# hard-deleted immediately), so a same-name Decom+Day1 within the window must
# TOLERATE an existing keyring/key — hence no prevent_destroy and stable names;
# the keyring lingering is harmless. Old attestations (signed by the prior key)
# simply become invalid, which is fine: a rebuild rebuilds and re-signs the images.
resource "google_kms_key_ring" "binauthz" {
  count = var.binary_authorization_enabled ? 1 : 0

  project  = var.project_id
  name     = "jenkins-2026-binauthz"
  location = var.region
}

resource "google_kms_crypto_key" "binauthz" {
  count = var.binary_authorization_enabled ? 1 : 0

  name     = "jenkins-2026-attestor-key"
  key_ring = google_kms_key_ring.binauthz[0].id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "RSA_SIGN_PKCS1_4096_SHA512"
    protection_level = "SOFTWARE"
  }
}

resource "google_container_analysis_note" "binauthz" {
  count = var.binary_authorization_enabled ? 1 : 0

  project = var.project_id
  name    = "jenkins-2026-attestor-note"

  attestation_authority {
    hint {
      human_readable_name = "jenkins-2026 pipeline attestor"
    }
  }
}

# The attestor's trusted public key = the KMS crypto-key VERSION's PKIX PEM.
data "google_kms_crypto_key_version" "binauthz" {
  count      = var.binary_authorization_enabled ? 1 : 0
  crypto_key = google_kms_crypto_key.binauthz[0].id
}

resource "google_binary_authorization_attestor" "this" {
  count = var.binary_authorization_enabled ? 1 : 0

  project = var.project_id
  name    = "jenkins-2026-attestor"

  attestation_authority_note {
    note_reference = google_container_analysis_note.binauthz[0].name

    public_keys {
      id = data.google_kms_crypto_key_version.binauthz[0].id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.binauthz[0].public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.binauthz[0].public_key[0].algorithm
      }
    }
  }
}

# The PROJECT SINGLETON policy. default_admission_rule REQUIRES an attestation from
# our attestor; GKE-managed/system images are always allow-listed (the cluster
# cannot schedule kube-system otherwise). enforcement_mode: enforce→block, dryrun→
# log only. Destroying it (flag off) reverts the project to the default ALWAYS_ALLOW.
resource "google_binary_authorization_policy" "this" {
  count = var.binary_authorization_enabled ? 1 : 0

  project = var.project_id

  admission_whitelist_patterns {
    name_pattern = "gcr.io/gke-release/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gke.gcr.io/*"
  }
  admission_whitelist_patterns {
    name_pattern = "registry.k8s.io/*"
  }

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = var.binary_authorization_enforce ? "ENFORCED_BLOCK_AND_AUDIT_LOG" : "DRYRUN_AUDIT_LOG_ONLY"
    require_attestations_by = [
      google_binary_authorization_attestor.this[0].name,
    ]
  }

  global_policy_evaluation_mode = "ENABLE"
}

# --- Binary Authorization: the CI SIGNER identity (keyless, Workload Identity) --
# A dedicated GSA the CI build pods impersonate to sign+attest images
# (resources/sign-and-attest-image.sh, called by all four engines). Least privilege:
# use the KMS key to sign, write Container Analysis occurrences, read the attestor.
# Each engine's build KSA is bound via Workload Identity (var.binauthz_signer_ksas).
# ⚠ LIVE-VALIDATION: also annotate each bound KSA with
# iam.gke.io/gcp-service-account=<this GSA email> (the in-cluster half of WI), and
# confirm the per-engine KSA names. See docs/507 § Pipeline wiring.
resource "google_service_account" "binauthz_signer" {
  count = var.binary_authorization_enabled ? 1 : 0

  project                      = var.project_id
  account_id                   = "jenkins-2026-binauthz-signer"
  display_name                 = "jenkins-2026 Binary Authorization CI image signer"
  create_ignore_already_exists = true
}

resource "google_kms_crypto_key_iam_member" "binauthz_signer" {
  count = var.binary_authorization_enabled ? 1 : 0

  crypto_key_id = google_kms_crypto_key.binauthz[0].id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${google_service_account.binauthz_signer[0].email}"
}

resource "google_project_iam_member" "binauthz_signer_ca" {
  count = var.binary_authorization_enabled ? 1 : 0

  project = var.project_id
  role    = "roles/containeranalysis.occurrences.editor"
  member  = "serviceAccount:${google_service_account.binauthz_signer[0].email}"
}

resource "google_project_iam_member" "binauthz_signer_attestor" {
  count = var.binary_authorization_enabled ? 1 : 0

  project = var.project_id
  role    = "roles/binaryauthorization.attestorsViewer"
  member  = "serviceAccount:${google_service_account.binauthz_signer[0].email}"
}

# Let each CI engine's build KSA impersonate the signer GSA (keyless).
resource "google_service_account_iam_member" "binauthz_signer_wi" {
  for_each = var.binary_authorization_enabled ? toset(var.binauthz_signer_ksas) : toset([])

  service_account_id = google_service_account.binauthz_signer[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value}]"
}
