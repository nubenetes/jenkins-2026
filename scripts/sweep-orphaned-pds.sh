#!/usr/bin/env bash
# sweep-orphaned-pds.sh — reconcile GCP persistent disks against live PVs and
# delete ORPHANED CSI persistent disks (the cleanup half of the orphan-PD story;
# the prevention half is the graceful PVC reclaim in scripts/down.sh).
#
# WHY orphans exist: a Terraform `Decom` deletes the GKE cluster WITHOUT the CSI
# driver getting a chance to reclaim the PDs (reclaimPolicy=Delete never fires
# once the controller is gone), so the underlying `pvc-*` disks are left behind in
# the project and accumulate ONE generation per rebuild. They keep costing money
# and counting against the regional SSD_TOTAL_GB quota. See
# docs/501-PLATFORM_OPERATIONS.md § Orphaned persistent disks.
#
# SAFETY — this only ever deletes a disk that is ALL of:
#   1. named `pvc-*`            (a CSI *dynamically-provisioned* PV — never a node
#                                boot disk, which is `gke-*`),
#   2. UNATTACHED              (no VM is using it), and
#   3. NOT referenced by any live PersistentVolume in the current cluster.
# CRITICAL GUARD: if the cluster is unreachable (e.g. PAUSED), `kubectl get pv`
# FAILS and we ABORT — we never treat "can't list PVs" as "no live PVs" (that
# would delete a paused cluster's databases). A fresh cluster where `kubectl get
# pv` SUCCEEDS with an empty list is safe: every leftover `pvc-*` is genuinely an
# orphan from a previous incarnation.
#
# Idempotent. Run it at any cluster-up (up.sh calls it; or standalone). Flags:
#   J2026_ORPHAN_PD_SWEEP=false         disable entirely
#   J2026_ORPHAN_PD_SWEEP_DRYRUN=true   list what would be deleted, delete nothing
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

[[ "${J2026_ORPHAN_PD_SWEEP:-true}" == "true" ]] || { log_info "Orphan-PD sweep disabled (J2026_ORPHAN_PD_SWEEP=false) - skipping"; exit 0; }
command -v gcloud >/dev/null 2>&1 || { log_info "gcloud not available - skipping orphan-PD sweep"; exit 0; }

log_step "Sweeping orphaned CSI persistent disks (reconcile vs live PVs)"

# CRITICAL GUARD: the cluster must be reachable, or we cannot tell live from orphan.
if ! kubectl get pv >/dev/null 2>&1; then
  log_warn "Cluster not reachable (cannot list PersistentVolumes) - skipping sweep for SAFETY."
  log_warn "  (Never reconcile against an unreachable/paused cluster: it would look like '0 live PVs'.)"
  exit 0
fi

# 1. Disk names referenced by LIVE PersistentVolumes. pd.csi volumeHandle looks like
#    projects/<p>/zones/<z>/disks/<name> - keep the last path segment.
live="$(kubectl get pv -o jsonpath='{range .items[*]}{.spec.csi.volumeHandle}{"\n"}{end}' 2>/dev/null | awk -F/ 'NF{print $NF}' | sort -u)"
live_count="$(printf '%s\n' "${live}" | grep -c . || true)"
log_info "Live PVs reference ${live_count} disk(s) - those are never touched."

# 2. Candidate disks: CSI dynamic PVs (name pvc-*) that are UNATTACHED (no users).
deleted=0; kept=0; freed=0; dryrun="${J2026_ORPHAN_PD_SWEEP_DRYRUN:-false}"
while IFS=$'\t' read -r name zone size; do
  [[ -z "${name}" ]] && continue
  if printf '%s\n' "${live}" | grep -qxF "${name}"; then
    ((kept++)); continue   # referenced by a live PV -> keep
  fi
  if [[ "${dryrun}" == "true" ]]; then
    log_info "[dry-run] would delete orphan PD ${name} (${size}GB, ${zone})"
    freed=$((freed + size)); continue
  fi
  log_info "Deleting orphan PD ${name} (${size}GB, ${zone})"
  if gcloud compute disks delete "${name}" --zone="${zone}" --quiet >/dev/null 2>&1; then
    ((deleted++)); freed=$((freed + size))
  else
    log_warn "Could not delete ${name} (still in use? will retry on the next sweep)"
  fi
done < <(gcloud compute disks list --filter='name~^pvc- AND -users:*' \
           --format='value(name,zone.basename(),sizeGb)' 2>/dev/null)

if [[ "${dryrun}" == "true" ]]; then
  log_info "Orphan-PD sweep (DRY-RUN): ~${freed} GB across orphan disk(s) would be freed; ${kept} live disk(s) kept."
else
  log_info "Orphan-PD sweep done: ${deleted} orphan disk(s) deleted (~${freed} GB + quota freed), ${kept} live disk(s) kept."
fi
