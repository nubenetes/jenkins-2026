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
#   BINAUTHZ_KMS_KEYVERSION  full KMS key VERSION resource name; if unset it is derived
#                            from PROJECT_ID + the LOCATION/KEYRING/KEY/VERSION below
#                            (defaults match terraform/gke/security.tf).
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
BINAUTHZ_KMS_LOCATION="${BINAUTHZ_KMS_LOCATION:-europe-west1}"
BINAUTHZ_KMS_KEYRING="${BINAUTHZ_KMS_KEYRING:-jenkins-2026-binauthz}"
BINAUTHZ_KMS_KEY="${BINAUTHZ_KMS_KEY:-jenkins-2026-attestor-key}"
BINAUTHZ_KMS_VERSION="${BINAUTHZ_KMS_VERSION:-1}"
BINAUTHZ_KMS_KEYVERSION="${BINAUTHZ_KMS_KEYVERSION:-projects/${PROJECT_ID}/locations/${BINAUTHZ_KMS_LOCATION}/keyRings/${BINAUTHZ_KMS_KEYRING}/cryptoKeys/${BINAUTHZ_KMS_KEY}/cryptoKeyVersions/${BINAUTHZ_KMS_VERSION}}"

# 1. Resolve the tag → immutable digest (never sign a mutable tag).
if [[ "${IMAGE}" == *"@sha256:"* ]]; then
  IMAGE_DIGEST="${IMAGE}"
else
  echo "[sign-and-attest] Resolving digest for ${IMAGE} ..."
  digest="$(gcloud container images describe "${IMAGE}" --format='value(image_summary.digest)' 2>/dev/null || true)"
  if [[ -z "${digest}" ]] && command -v crane >/dev/null 2>&1; then
    # Fallback for non-GCR/AR registries (e.g. GHCR): crane if available.
    digest="$(crane digest "${IMAGE}" 2>/dev/null || true)"
  fi
  [[ -n "${digest}" ]] || { echo "[sign-and-attest] ERROR: could not resolve a digest for ${IMAGE}." >&2; exit 1; }
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
elif grep -qi "already exists" /tmp/binauthz-sign.log; then
  echo "[sign-and-attest] Attestation already exists for ${IMAGE_DIGEST} (idempotent) — OK."
else
  echo "[sign-and-attest] ERROR: attestation failed:" >&2
  cat /tmp/binauthz-sign.log >&2
  exit 1
fi
