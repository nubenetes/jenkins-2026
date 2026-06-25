#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap.sh — the ROOT OF TRUST (Day0, "phase 0")
# =============================================================================
# This is the ONE human-run, local seed that everything else depends on. It is
# NOT a GitHub Actions workflow on purpose (the "bootstrap paradox"): the CI
# workflows authenticate to GCP via the Workload Identity Federation (WIF) trust
# and store their Terraform state in the GCS bucket that *this* script creates —
# so it cannot run from CI before it exists, and CI must never be able to
# recreate its own trust (privilege-escalation). See docs/100-BOOTSTRAP.md.
#
# What `up` creates (terraform/bootstrap):
#   - GCS bucket for ALL modules' remote Terraform state (versioned)
#   - GitHub WIF pool + provider + the CI service account (+ its IAM roles)
#   - the Postgres backups bucket
# then it MIGRATES its own state into that bucket (self-hosting, no fragile local
# .tfstate) and sets the 4 GitHub repo secrets the workflows need.
#
# `down` is the symmetric "Decom of the root": it migrates state back to local,
# terraform-destroys everything (force-emptying the state bucket), and removes
# the 4 GitHub secrets. Run it only AFTER a full Decom of clusters + backends.
#
# Usage:
#   ./scripts/bootstrap.sh up      # create / converge the root (default)
#   ./scripts/bootstrap.sh down    # destroy the root
#
# Non-interactive overrides (else you are prompted):
#   PROJECT_ID=... REGION=... GITHUB_REPO=... ./scripts/bootstrap.sh up
# =============================================================================
set -euo pipefail

ACTION="${1:-up}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT_DIR="${ROOT_DIR}/terraform/bootstrap"
STATE_PREFIX="jenkins-2026/bootstrap"   # where bootstrap self-hosts its own state

# ── pretty logging ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; X=$'\e[0m'; else B=; G=; Y=; R=; C=; X=; fi
step() { printf '%s\n' "${B}${C}▶ %s${X}" >&2; printf '%s\n' "  $*" >&2; }
info() { printf '%s\n' "  ${G}✓${X} $*" >&2; }
warn() { printf '%s\n' "  ${Y}!${X} $*" >&2; }
die()  { printf '%s\n' "${R}✗ $*${X}" >&2; exit 1; }

# ── prerequisites ────────────────────────────────────────────────────────────
for bin in gcloud gsutil terraform gh; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found in PATH — install it first (see docs/100-BOOTSTRAP.md § prerequisites)."
done

# ── identity / authentication (prompts only if not already authenticated) ─────
ensure_auth() {
  step "Checking identities (gcloud user, gcloud ADC, gh)"
  # 1) gcloud CLI user (for gsutil / gcloud admin calls)
  if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
    warn "No active gcloud account — launching 'gcloud auth login'…"
    gcloud auth login
  fi
  info "gcloud user: $(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"

  # 2) Application Default Credentials (what the Terraform google provider uses)
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    warn "No Application Default Credentials — launching 'gcloud auth application-default login'…"
    gcloud auth application-default login
  fi
  info "ADC present (Terraform will use these)."

  # 3) GitHub CLI (to set/remove repo secrets)
  if ! gh auth status >/dev/null 2>&1; then
    warn "Not logged in to GitHub — launching 'gh auth login'…"
    gh auth login
  fi
  info "gh: authenticated."
}

# ── collect inputs (env override > prompt) ────────────────────────────────────
collect_inputs() {
  PROJECT_ID="${PROJECT_ID:-}"
  if [[ -z "${PROJECT_ID}" ]]; then
    local cur; cur="$(gcloud config get-value project 2>/dev/null || true)"
    read -rp "  GCP project ID${cur:+ [$cur]}: " PROJECT_ID
    PROJECT_ID="${PROJECT_ID:-$cur}"
  fi
  [[ -n "${PROJECT_ID}" ]] || die "project ID is required."
  REGION="${REGION:-us-central1}"
  GITHUB_REPO="${GITHUB_REPO:-nubenetes/jenkins-2026}"
  BUCKET="${PROJECT_ID}-jenkins-2026-tfstate"   # matches local.state_bucket_name default in main.tf
  info "project=${PROJECT_ID}  region=${REGION}  repo=${GITHUB_REPO}"
  info "state bucket=${BUCKET}  (bootstrap state prefix: ${STATE_PREFIX})"
  gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1 || true
  cat > "${BOOT_DIR}/terraform.tfvars" <<EOF
# Written by scripts/bootstrap.sh — do not commit (gitignored).
project_id  = "${PROJECT_ID}"
region      = "${REGION}"
github_repo = "${GITHUB_REPO}"
EOF
}

write_backend() {
  # Points bootstrap's OWN state at the bucket it manages (self-hosting).
  cat > "${BOOT_DIR}/backend_override.tf" <<EOF
# Written by scripts/bootstrap.sh — gitignored. Makes bootstrap self-host its
# state in the bucket it creates (so there is no fragile local .tfstate).
terraform {
  backend "gcs" {
    bucket = "${BUCKET}"
    prefix = "${STATE_PREFIX}"
  }
}
EOF
}

remote_state_exists() { gsutil ls "gs://${BUCKET}/${STATE_PREFIX}/" >/dev/null 2>&1; }

set_secrets() {
  step "Setting the 4 GitHub repo secrets from Terraform outputs"
  local pid sb wip sa
  pid="$(terraform -chdir="${BOOT_DIR}" output -raw project_id)"
  sb="$(terraform -chdir="${BOOT_DIR}" output -raw state_bucket)"
  wip="$(terraform -chdir="${BOOT_DIR}" output -raw workload_identity_provider)"
  sa="$(terraform -chdir="${BOOT_DIR}" output -raw ci_service_account_email)"
  gh secret set GCP_PROJECT_ID                 --repo "${GITHUB_REPO}" --body "${pid}"
  gh secret set TF_STATE_BUCKET                --repo "${GITHUB_REPO}" --body "${sb}"
  gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "${GITHUB_REPO}" --body "${wip}"
  gh secret set GCP_SERVICE_ACCOUNT            --repo "${GITHUB_REPO}" --body "${sa}"
  info "secrets set: GCP_PROJECT_ID, TF_STATE_BUCKET, GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT"
}

# ── up ───────────────────────────────────────────────────────────────────────
up() {
  ensure_auth
  collect_inputs
  if [[ -f "${BOOT_DIR}/backend_override.tf" ]] || remote_state_exists; then
    step "Root already seeded — converging against remote state (gs://${BUCKET}/${STATE_PREFIX})"
    write_backend
    terraform -chdir="${BOOT_DIR}" init -input=false -reconfigure
    terraform -chdir="${BOOT_DIR}" apply -input=false   # interactive approve
  else
    step "First seed — creating the bucket with LOCAL state, then migrating to remote"
    rm -f "${BOOT_DIR}/backend_override.tf"
    terraform -chdir="${BOOT_DIR}" init -input=false
    terraform -chdir="${BOOT_DIR}" apply -input=false   # creates bucket + WIF + SA
    info "Bucket created — migrating bootstrap's own state into it…"
    write_backend
    terraform -chdir="${BOOT_DIR}" init -input=false -migrate-state -force-copy
    info "State migrated to gs://${BUCKET}/${STATE_PREFIX} (no more local .tfstate)."
  fi
  set_secrets
  printf '\n%s\n' "${B}${G}✓ Root of trust is ready.${X} GitHub Actions can now authenticate (WIF) and store state." >&2
  printf '%s\n' "  Next: create DNS records / run Day0.infra.0N + Day1 (see docs/100-BOOTSTRAP.md)." >&2
}

# ── down ─────────────────────────────────────────────────────────────────────
down() {
  ensure_auth
  collect_inputs
  warn "This destroys the ROOT: the WIF trust, the CI service account, the Postgres"
  warn "backups bucket, AND the Terraform state bucket. ALL GitHub Actions workflows"
  warn "will lose GCP access until you run 'up' again. Run this ONLY after a full Decom."
  read -rp "  Type 'destroy-root' to confirm: " confirm
  [[ "${confirm}" == "destroy-root" ]] || die "aborted (confirmation did not match)."

  # Bring state back to LOCAL first: terraform cannot delete the bucket while its
  # own state lives inside it.
  if [[ -f "${BOOT_DIR}/backend_override.tf" ]] || remote_state_exists; then
    step "Migrating bootstrap state back to LOCAL (so the bucket can be deleted)"
    write_backend
    terraform -chdir="${BOOT_DIR}" init -input=false -reconfigure
    rm -f "${BOOT_DIR}/backend_override.tf"
    terraform -chdir="${BOOT_DIR}" init -input=false -migrate-state -force-copy
  else
    terraform -chdir="${BOOT_DIR}" init -input=false
  fi

  step "terraform destroy (force-empties the state bucket via state_bucket_force_destroy=true)"
  terraform -chdir="${BOOT_DIR}" destroy -input=false -var "state_bucket_force_destroy=true"

  step "Removing the 4 GitHub repo secrets"
  for s in GCP_PROJECT_ID TF_STATE_BUCKET GCP_WORKLOAD_IDENTITY_PROVIDER GCP_SERVICE_ACCOUNT; do
    gh secret delete "$s" --repo "${GITHUB_REPO}" 2>/dev/null && info "deleted ${s}" || warn "${s} not present"
  done
  printf '\n%s\n' "${B}${Y}Root destroyed.${X} To bring the project back: ./scripts/bootstrap.sh up" >&2
}

case "${ACTION}" in
  up)   up ;;
  down) down ;;
  *)    die "unknown action '${ACTION}' — use 'up' or 'down'." ;;
esac
