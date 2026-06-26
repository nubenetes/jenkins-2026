#!/usr/bin/env bash
# =============================================================================
# scripts/dev-setup.sh — configure a LOCAL operator workstation (Linux/WSL) to
# drive an already-provisioned jenkins-2026 GKE cluster.
# =============================================================================
# Run this ONCE after every from-scratch rebuild (Day1) — or any time `kubectl`
# suddenly starts timing out. A cluster rebuild rotates the control-plane IP, so
# a kubeconfig from a previous incarnation goes stale and you get:
#     Unable to connect to the server: dial tcp <old-ip>:443: i/o timeout
# This refreshes that (and the rest of your local setup). It is IDEMPOTENT and
# safe to re-run.
#
# It creates/destroys NO cloud resources (that is bootstrap.sh + Day1). It only
# configures YOUR machine:
#   1. checks required CLIs            4. installs gke-gcloud-auth-plugin
#   2. gcloud auth (user + ADC)        5. refreshes kubeconfig for the cluster
#   3. resolves the GCP project        6. restores scripts' +x bits (Windows)
# then verifies kubectl can reach the cluster.
#
# Why this is NOT part of bootstrap.sh: bootstrap is Day0 "phase 0" and runs
# BEFORE any cluster exists, so it has nothing to get-credentials for; and up.sh
# is platform-agnostic (works against whatever kubectl context you give it). This
# is purely local-operator convenience. See docs/901 § Operator workstation setup.
#
# Overrides (else auto-detected):
#   PROJECT_ID=...  CLUSTER_NAME=...  CLUSTER_LOCATION=...  ./scripts/dev-setup.sh
#
# First run after a fresh checkout (the +x bit may be missing): bash scripts/dev-setup.sh
# =============================================================================
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -t 1 ]]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; X=$'\e[0m'; else B=; G=; Y=; R=; C=; X=; fi
step() { printf '%s\n' "${B}${C}▶${X} $*" >&2; }
info() { printf '%s\n' "  ${G}✓${X} $*" >&2; }
warn() { printf '%s\n' "  ${Y}!${X} $*" >&2; }
die()  { printf '%s\n' "${R}✗ $*${X}" >&2; exit 1; }

# ── 1. prerequisites ─────────────────────────────────────────────────────────
step "1/6 Checking required tools"
missing=()
for bin in gcloud kubectl helm yq git; do command -v "$bin" >/dev/null 2>&1 || missing+=("$bin"); done
if (( ${#missing[@]} )); then
  warn "Missing: ${missing[*]}"
  warn "Install them and re-run. gcloud: https://cloud.google.com/sdk · kubectl/helm via gcloud components or your package manager · yq: mikefarah/yq (Go)."
  die "prerequisites missing"
fi
for bin in terraform gh; do command -v "$bin" >/dev/null 2>&1 || warn "optional '$bin' not found (only needed for terraform / gh tasks)"; done
info "core tools present (gcloud, kubectl, helm, yq, git)"

# ── 2. authentication (prompts only if missing) ──────────────────────────────
step "2/6 Ensuring gcloud auth (user + Application Default Credentials)"
if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
  warn "No active gcloud account — launching 'gcloud auth login'…"; gcloud auth login
fi
info "gcloud user: $(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  warn "No ADC — launching 'gcloud auth application-default login'…"; gcloud auth application-default login
fi
info "ADC present (used by terraform / the live-access helpers)"

# ── 3. project ───────────────────────────────────────────────────────────────
step "3/6 Resolving the GCP project"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "${PROJECT_ID}" && "${PROJECT_ID}" != "(unset)" ]] || die "no project set — run 'gcloud config set project <id>' or pass PROJECT_ID=…"
gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1 || true
info "project=${PROJECT_ID}"

# ── 4. gke-gcloud-auth-plugin ────────────────────────────────────────────────
step "4/6 Ensuring gke-gcloud-auth-plugin (kubectl needs it to auth to GKE)"
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
if command -v gke-gcloud-auth-plugin >/dev/null 2>&1; then
  info "plugin present: $(gke-gcloud-auth-plugin --version 2>/dev/null | head -1)"
elif gcloud components install gke-gcloud-auth-plugin --quiet 2>/dev/null; then
  info "installed via 'gcloud components install'"
else
  warn "Could not install via gcloud components (apt-managed SDK?). Install the package:"
  warn "  sudo apt-get install google-cloud-cli-gke-gcloud-auth-plugin"
  die "install the plugin, then re-run"
fi

# ── 5. kubeconfig (THE fix for the stale control-plane IP) ───────────────────
step "5/6 Refreshing the kubeconfig for the current cluster"
CLUSTER_NAME="${CLUSTER_NAME:-}"; CLUSTER_LOCATION="${CLUSTER_LOCATION:-}"
# Prefer terraform/gke outputs when its state is local (test/e2e.sh users)…
if [[ -z "${CLUSTER_NAME}" || -z "${CLUSTER_LOCATION}" ]]; then
  if terraform -chdir="${ROOT_DIR}/terraform/gke" output -raw cluster_name >/dev/null 2>&1; then
    CLUSTER_NAME="${CLUSTER_NAME:-$(terraform -chdir="${ROOT_DIR}/terraform/gke" output -raw cluster_name 2>/dev/null)}"
    CLUSTER_LOCATION="${CLUSTER_LOCATION:-$(terraform -chdir="${ROOT_DIR}/terraform/gke" output -raw location 2>/dev/null)}"
  fi
fi
# …otherwise (the usual local case: state lives in GCS via CI) auto-discover.
if [[ -z "${CLUSTER_NAME}" || -z "${CLUSTER_LOCATION}" ]]; then
  mapfile -t clusters < <(gcloud container clusters list --project "${PROJECT_ID}" --format='value(name,location)' 2>/dev/null)
  if (( ${#clusters[@]} == 1 )); then
    read -r CLUSTER_NAME CLUSTER_LOCATION <<<"${clusters[0]}"
  elif (( ${#clusters[@]} == 0 )); then
    die "no GKE clusters in ${PROJECT_ID} — run Day1 first, or pass CLUSTER_NAME/CLUSTER_LOCATION."
  else
    warn "multiple clusters found — pick one via CLUSTER_NAME=… CLUSTER_LOCATION=… :"
    printf '    %s\n' "${clusters[@]}" >&2
    die "ambiguous cluster"
  fi
fi
info "cluster=${CLUSTER_NAME} location=${CLUSTER_LOCATION}"
gcloud container clusters get-credentials "${CLUSTER_NAME}" --location "${CLUSTER_LOCATION}" --project "${PROJECT_ID}"
info "kubeconfig updated → context $(kubectl config current-context)"

# ── 6. restore script +x bits (Windows editors drop 100755 → 100644) ─────────
step "6/6 Restoring executable bits on scripts (Windows edits drop them)"
chmod +x "${ROOT_DIR}"/scripts/*.sh "${ROOT_DIR}"/scripts/lib/*.sh "${ROOT_DIR}"/test/*.sh 2>/dev/null || true
info "scripts/*.sh, scripts/lib/*.sh, test/*.sh are executable"

# ── verify ───────────────────────────────────────────────────────────────────
step "Verifying cluster connectivity"
if kubectl get nodes >/dev/null 2>&1; then
  info "kubectl reaches the cluster ($(kubectl get nodes --no-headers 2>/dev/null | grep -c .) node(s))"
else
  warn "kubectl still cannot reach the cluster. If it's a private-endpoint / master-authorized-networks cluster, your IP may be blocked; otherwise retry shortly."
fi
printf '\n%s\n' "${B}${G}✓ Local environment ready.${X} Now: ./scripts/status.sh, kubectl, helm, …" >&2
