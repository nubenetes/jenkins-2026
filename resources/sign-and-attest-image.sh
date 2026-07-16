#!/usr/bin/env bash
# Sign + attest a freshly-built image DIGEST for Binary Authorization — the SINGLE
# source called by ALL FOUR CI engines (Jenkins vars/, Tekton, Argo Workflows, and
# the GitHub Actions microservices-ci.yml), exactly like resources/patch-app-source.sh
# keeps the JHipster patch in one place. So the supply-chain signing logic lives in
# ONE file, not four. See docs/507-BINARY-AUTHORIZATION.md.
#
# OPT-IN: this no-ops unless Binary Authorization is active. The caller (each engine's
# pipeline) invokes it AFTER pushing the image; it resolves the image's immutable
# DIGEST, then creates a Cloud-KMS-signed attestation that this project's attestor
# trusts. Under the cluster's Binary Authorization policy (terraform/gke), only images
# carrying such an attestation are admitted (enforce) or the violation is logged
# (dryrun). Never sign a mutable tag — always the digest.
#
# Usage:   sign-and-attest-image.sh <image-ref>
#   <image-ref> may be a tag (ghcr.io/org/img:tag) or already a digest (…@sha256:…).
#
# Env (sensible defaults; the pipeline exports the first three):
#   BINAUTHZ_ENABLED         "true" to act; anything else = no-op
#                            (default: J2026_BINARY_AUTHORIZATION_ENABLED, else false)
#   PROJECT_ID               GCP project (default: gcloud config value)
#   BINAUTHZ_ATTESTOR        attestor name (default: jenkins-2026-attestor)
#   BINAUTHZ_KMS_KEYVERSION  full KMS key VERSION resource name (projects/.../cryptoKeyVersions/N).
#                            If unset it is DERIVED FROM THE ATTESTOR's own trusted key —
#                            region-agnostic, so it always matches wherever terraform/gke created
#                            the key (location = var.region, NOT a fixed region). Set it to override.
set -euo pipefail

IMAGE="${1:-${IMAGE:-}}"

BINAUTHZ_ENABLED="${BINAUTHZ_ENABLED:-${J2026_BINARY_AUTHORIZATION_ENABLED:-false}}"
if [[ "${BINAUTHZ_ENABLED}" != "true" ]]; then
  echo "[sign-and-attest] Binary Authorization not enabled — skipping (no-op)."
  exit 0
fi
if [[ -z "${IMAGE}" ]]; then
  echo "[sign-and-attest] ERROR: no image ref given (arg 1 or \$IMAGE)." >&2
  exit 1
fi
command -v gcloud >/dev/null 2>&1 || { echo "[sign-and-attest] ERROR: gcloud not found on PATH." >&2; exit 1; }

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
BINAUTHZ_ATTESTOR="${BINAUTHZ_ATTESTOR:-jenkins-2026-attestor}"
# The KMS key lives wherever terraform/gke created it — location = var.region, NOT a fixed
# region. Hard-coding a location drifts from var.region and breaks signing (a real bug caught in
# live enforce validation: a europe-west1 default vs a europe-southwest1 cluster → NOT_FOUND). So
# DERIVE the exact key version from the ATTESTOR's own trusted key: region-agnostic, always in sync
# with terraform. An explicit BINAUTHZ_KMS_KEYVERSION still wins (e.g. multi-key attestors).
if [[ -z "${BINAUTHZ_KMS_KEYVERSION:-}" ]]; then
  _attestor_key="$(gcloud container binauthz attestors describe "${BINAUTHZ_ATTESTOR}" \
    --project="${PROJECT_ID}" --format='value(userOwnedGrafeasNote.publicKeys[0].id)' 2>/dev/null || true)"
  # The attestor stores it as //cloudkms.googleapis.com/v1/projects/.../cryptoKeyVersions/N;
  # sign-and-create wants the bare projects/.../cryptoKeyVersions/N — strip the URL prefix.
  BINAUTHZ_KMS_KEYVERSION="${_attestor_key#//cloudkms.googleapis.com/v1/}"
fi
if [[ -z "${BINAUTHZ_KMS_KEYVERSION}" ]]; then
  echo "[sign-and-attest] ERROR: could not resolve the KMS key version from attestor ${BINAUTHZ_ATTESTOR}." >&2
  echo "[sign-and-attest]        pass BINAUTHZ_KMS_KEYVERSION=projects/.../cryptoKeyVersions/N explicitly." >&2
  exit 1
fi

# 1. Resolve the tag → immutable digest (never sign a mutable tag).
if [[ "${IMAGE}" == *"@sha256:"* ]]; then
  IMAGE_DIGEST="${IMAGE}"
else
  # PREFER being handed an image@sha256:… by the caller — see below. This tag→digest
  # resolution is a fallback and only really works for GCR/Artifact Registry.
  echo "[sign-and-attest] Resolving digest for ${IMAGE} ..."
  digest="$(gcloud container images describe "${IMAGE}" --format='value(image_summary.digest)' 2>/dev/null || true)"
  if [[ -z "${digest}" ]] && command -v crane >/dev/null 2>&1; then
    # Fallback for non-GCR/AR registries (e.g. GHCR): crane if available. NOTE: it is NOT
    # in google/cloud-sdk:slim, the image every engine runs this in — so in practice this
    # branch never fires today. Kept for callers that do ship crane; do not mistake it for
    # working GHCR support.
    digest="$(crane digest "${IMAGE}" 2>/dev/null || true)"
  fi
  if [[ -z "${digest}" ]]; then
    echo "[sign-and-attest] ERROR: could not resolve a digest for ${IMAGE}." >&2
    echo "[sign-and-attest]   'gcloud container images describe' only speaks GCR/Artifact Registry," >&2
    echo "[sign-and-attest]   and crane is absent here. For GHCR (and any private non-GCR registry —" >&2
    echo "[sign-and-attest]   an authenticated manifest HEAD to ghcr.io 403s, verified live) the CALLER" >&2
    echo "[sign-and-attest]   must pass the image BY DIGEST: <image>@sha256:...  Builders know it for" >&2
    echo "[sign-and-attest]   free — Jib writes target/jib-image.digest, kaniko takes --digest-file." >&2
    echo "[sign-and-attest]   vars/microservicesImage.groovy does this; see docs/507 § Pipeline wiring." >&2
    exit 1
  fi
  IMAGE_DIGEST="${IMAGE%:*}@${digest}"   # strip the :tag (last colon), append @sha256:...
fi

echo "[sign-and-attest] Attesting ${IMAGE_DIGEST} via attestor ${BINAUTHZ_ATTESTOR} (project ${PROJECT_ID})"

# 2. Create the KMS-signed attestation. Idempotent: ALREADY_EXISTS is success.
if gcloud beta container binauthz attestations sign-and-create \
    --project="${PROJECT_ID}" \
    --artifact-url="${IMAGE_DIGEST}" \
    --attestor="${BINAUTHZ_ATTESTOR}" \
    --attestor-project="${PROJECT_ID}" \
    --keyversion="${BINAUTHZ_KMS_KEYVERSION}" >/tmp/binauthz-sign.log 2>&1; then
  echo "[sign-and-attest] Attestation created for ${IMAGE_DIGEST}."
elif grep -qiE "already exists|ALREADY_EXISTS|subject of a conflict|could not create occurrence" /tmp/binauthz-sign.log; then
  # A re-sign of the same digest returns ALREADY_EXISTS *or* a Grafeas occurrence "conflict"
  # (same meaning, different wording) — both mean the attestation is already there. Idempotent.
  echo "[sign-and-attest] Attestation already exists for ${IMAGE_DIGEST} (idempotent) — OK."
else
  echo "[sign-and-attest] ERROR: attestation failed:" >&2
  cat /tmp/binauthz-sign.log >&2
  exit 1
fi
