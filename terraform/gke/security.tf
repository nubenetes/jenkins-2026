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

  # Register the Fleet membership only once the cluster is IDLE. The Fleet API rejects a
  # membership create/delete while any cluster operation is in flight (`Error code 9 …
  # cluster is currently running another operation. Please retry after the operation is
  # done`, seen live on the first from-zero rebuild — run 29433092250). Depending on the
  # node pool — the last thing to settle after the cluster itself — makes Terraform wait
  # for the whole cluster+pool create to finish before touching Fleet, and the delete
  # timeout gives the symmetric Decom room for the same drain (the workflow also waits).
  depends_on = [google_project_service.apis, google_container_node_pool.primary]

  timeouts {
    create = "20m"
    delete = "20m"
  }
}

resource "google_gke_hub_feature" "mesh" {
  count = var.service_mesh_mode == "cloud-service-mesh" ? 1 : 0

  project  = var.project_id
  name     = "servicemesh"
  location = "global"

  depends_on = [google_project_service.apis]
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
# fixed-identity. KMS keyrings and keys are NEVER hard-deleted — a keyring cannot be
# deleted at all, and a key only enters a SCHEDULED-DESTRUCTION window — so `Decom`'s
# `terraform destroy` drops them from STATE while they LINGER in GCP. A same-name
# Decom+Day1 must therefore ADOPT the survivors, not re-create them: a bare create of an
# existing keyring 409s (`KeyRing ... already exists`, seen live on the first from-zero
# rebuild — run 29433092250), the fixed-identity-collision hazard (docs/104 §2). Stable
# names + no prevent_destroy are necessary but NOT sufficient — the crypto-key re-adopts
# its scheduled-destroyed version by name, but a keyring create still 409s. The adoption
# is done by the Day1 workflow's "Adopt lingering KMS keyring/key" step, which
# `terraform import`s them ONLY when they already exist in GCP (an import block can't be
# used here: it fails `plan` on a truly-fresh project where the keyring does NOT exist
# yet). Old attestations signed by the prior key simply become invalid — fine, a rebuild
# re-signs its images.
resource "google_kms_key_ring" "binauthz" {
  count = var.binary_authorization_enabled ? 1 : 0

  project  = var.project_id
  name     = "jenkins-2026-binauthz"
  location = var.region

  depends_on = [google_project_service.apis]
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

  depends_on = [google_project_service.apis]
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

  # --- PLATFORM / CI infrastructure allow-list -------------------------------
  # The attestation requirement is meant to protect the APP supply chain — the
  # microservices images this repo's pipelines build and sign
  # (ghcr.io/nubenetes/jenkins-2026-microservices/**, deliberately NOT listed here,
  # so they alone must carry an attestation). EVERY OTHER workload is trusted
  # third-party/platform infra pulled by tag and never attested: without these
  # patterns, flipping to `enforce` blocks the platform itself — found live
  # 2026-07-17, where enforce denied `docker.io/jenkins/inbound-agent` (a Jenkins
  # build agent) with "Expected digest ... got tag", i.e. it would wedge the very CI
  # that produces the signed images. `global_policy_evaluation_mode = ENABLE` (below)
  # covers only Google-managed GKE system images (gke-release, incl. the regional
  # Artifact Registry mirror), NOT these. Patterns are `**` (cross-`/`) registry/org
  # scopes derived from every image actually running in the stack; extend when a new
  # component introduces a new registry. `enforce` needs this to be production-usable.
  admission_whitelist_patterns {
    name_pattern = "docker.io/**" # Jenkins controller/agents, grafana/loki/tempo, pgadmin, k6, otel-collector, build tools (maven/node/docker/trivy/…)
  }
  admission_whitelist_patterns {
    name_pattern = "index.docker.io/**" # Docker Hub canonical host (short refs like `maven`/`node` normalise here)
  }
  admission_whitelist_patterns {
    name_pattern = "quay.io/**" # ArgoCD + Argo Rollouts, cert-manager (jetstack), kube-prometheus-stack (prometheus-operator/node-exporter)
  }
  admission_whitelist_patterns {
    name_pattern = "mcr.microsoft.com/**" # CodeQL container (DevSecOps scan)
  }
  admission_whitelist_patterns {
    name_pattern = "oci.external-secrets.io/**" # External Secrets Operator (eso mode)
  }
  admission_whitelist_patterns {
    name_pattern = "public.ecr.aws/**" # AWS ECR Public (e.g. redis base)
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/tekton-releases/**" # Tekton control plane + tasks (ci.engine=tekton)
  }
  admission_whitelist_patterns {
    name_pattern = "ghcr.io/actions/**" # ARC runner + controller (ci.engine=githubactions)
  }
  admission_whitelist_patterns {
    name_pattern = "ghcr.io/cloudnative-pg/**" # CNPG operator + Postgres/PgBouncer
  }
  admission_whitelist_patterns {
    name_pattern = "ghcr.io/dexidp/**" # Dex (ArgoCD IAP authproxy SSO)
  }
  admission_whitelist_patterns {
    name_pattern = "ghcr.io/headlamp-k8s/**" # Headlamp
  }
  admission_whitelist_patterns {
    name_pattern = "ghcr.io/open-telemetry/**" # OTel operator + Java autoinstrumentation
  }
  # Our OWN Backstage image — a platform component published out-of-band
  # (Day2.publish.06-backstage), NOT built/signed by the microservices pipeline, so
  # it is allow-listed rather than attested. Sibling ghcr.io/nubenetes path to the
  # app images, but a DISTINCT repo, so this does not exempt the microservices.
  admission_whitelist_patterns {
    name_pattern = "ghcr.io/nubenetes/jenkins-2026-backstage*"
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

# `sign-and-create` writes an occurrence that ATTACHES to the attestor's note, and
# occurrences.editor above does NOT cover that: attaching is gated by the separate
# containeranalysis.notes.attachOccurrence permission, on the NOTE side. Without this the
# signing step dies with `Permission 'containeranalysis.notes.attachOccurrence' denied`
# and no attestation is ever created — the CI SA's own firewall/NEG split all over again
# (see terraform/bootstrap local.ci_roles). notes.attacher is the minimal predefined role
# that grants it: notes.editor / containeranalysis.admin also would, but both also allow
# EDITING notes, which a signer has no business doing.
resource "google_project_iam_member" "binauthz_signer_note_attacher" {
  count = var.binary_authorization_enabled ? 1 : 0

  project = var.project_id
  role    = "roles/containeranalysis.notes.attacher"
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
