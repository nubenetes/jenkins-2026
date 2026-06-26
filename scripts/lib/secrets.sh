#!/usr/bin/env bash
# =============================================================================
# scripts/lib/secrets.sh — secrets backend helper (imperative | eso)
# =============================================================================
# Sourced by the 0N scripts. Provides one function, `provision_secret`, that
# materialises a Kubernetes Secret one of two ways depending on the
# `secrets.backend` feature flag (J2026_SECRETS_BACKEND):
#
#   imperative (default): kubectl create the Secret directly in its namespace
#                         from the given key=value pairs (current behaviour).
#   eso:                  push the key=value pairs to a GCP Secret Manager secret
#                         (as a JSON blob); the External Secrets Operator then
#                         syncs it into the namespace via Workload Identity. The
#                         matching ExternalSecret lives in
#                         infrastructure/secrets/eso-bootstrap.yaml and is applied
#                         (+ waited on) by scripts/08.6-eso-sync.sh.
#
# Default behaviour is byte-identical to before — the `eso` branch is only taken
# when you opt in. Requires `gcloud` + `python3` in eso mode (already required by
# the rest of the tooling).
# =============================================================================

# --- GCP Secret Manager console deep-links -----------------------------------
# Resolve the active gcloud project ONCE per process (cached), so the eso logs
# below can emit a clickable console URL without a gcloud call per secret.
_J2026_GCP_PROJECT_CACHE=""
_gcp_project() {
  if [[ -z "${_J2026_GCP_PROJECT_CACHE}" ]]; then
    _J2026_GCP_PROJECT_CACHE="$(gcloud config get-value project 2>/dev/null || true)"
  fi
  printf '%s' "${_J2026_GCP_PROJECT_CACHE}"
}

# gcp_console_secret_url <name> — clickable Secret Manager deep-link (versions
# tab). Neither the project nor the secret name is sensitive (no secret VALUE is
# ever logged). Falls back to the bare name if the project can't be resolved.
gcp_console_secret_url() {
  local name="$1" proj
  proj="$(_gcp_project)"
  if [[ -n "${proj}" ]]; then
    printf 'https://console.cloud.google.com/security/secret-manager/secret/%s/versions?project=%s' \
      "${name}" "${proj}"
  else
    printf '%s' "${name}"
  fi
}

# provision_secret <namespace> <secret-name> <key=value> [<key=value> ...]
#   imperative -> kubectl upsert the Secret in <namespace>
#   eso        -> upsert a Secret Manager secret named <secret-name> holding a
#                 JSON {key:value,...} (idempotent: only adds a new version when
#                 the content changed). ESO projects it into <namespace> later.
provision_secret() {
  local ns="$1" name="$2"; shift 2

  if [[ "${J2026_SECRETS_BACKEND:-imperative}" != "eso" ]]; then
    # --- imperative (default): direct kubectl upsert ---------------------------
    local args=()
    local kv
    for kv in "$@"; do args+=(--from-literal="${kv}"); done
    kubectl create secret generic "${name}" -n "${ns}" "${args[@]}" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    log_info "Secret ${name} (-n ${ns}) applied (imperative)."
    return 0
  fi

  # --- eso: push the values to GCP Secret Manager as a JSON blob ---------------
  # Build {"k":"v",...} safely with python3 (handles quoting/escaping).
  local json
  json="$(python3 - "$@" <<'PY'
import json, sys
out = {}
for kv in sys.argv[1:]:
    k, _, v = kv.partition("=")
    out[k] = v
print(json.dumps(out))
PY
)"

  # Create the Secret Manager secret if it doesn't exist yet (project = the
  # active gcloud project; ESO's ClusterSecretStore omits projectID so it reads
  # from the hosting project too).
  if ! gcloud secrets describe "${name}" >/dev/null 2>&1; then
    gcloud secrets create "${name}" --replication-policy=automatic >/dev/null
    log_info "Secret Manager secret '${name}' created — $(gcp_console_secret_url "${name}")"
  fi

  # Only add a new version when the payload actually changed (avoids version churn
  # + audit noise on idempotent re-runs).
  local current=""
  current="$(gcloud secrets versions access latest --secret="${name}" 2>/dev/null || true)"
  if [[ "${current}" == "${json}" ]]; then
    log_info "Secret Manager secret '${name}' already up to date (no new version) — $(gcp_console_secret_url "${name}")"
  else
    printf '%s' "${json}" | gcloud secrets versions add "${name}" --data-file=- >/dev/null
    log_info "Secret Manager secret '${name}' updated (new version) — ESO will sync it into ${ns}. $(gcp_console_secret_url "${name}")"
  fi
}
