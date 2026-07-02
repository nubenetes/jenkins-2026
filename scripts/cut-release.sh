#!/usr/bin/env bash
# =============================================================================
# cut-release.sh — cut a milestone release from CHANGELOG.md's [Unreleased] section
# =============================================================================
# The changelog convention (see RELEASING.md): changes accumulate under
# `## [Unreleased]` in CHANGELOG.md as PRs merge; a release is a MINOR bump cut at
# a milestone, and every version is a git tag AND a GitHub release, 1:1, cut from
# its own CHANGELOG section.
#
# Two phases, matching the repo's develop -> main GitFlow:
#
#   1. PREPARE  (run on `develop`):
#        scripts/cut-release.sh vX.Y.Z [YYYY-MM-DD]
#      Renames `## [Unreleased]` -> `## [vX.Y.Z] - <date>`, opens a fresh empty
#      `## [Unreleased]`, and adds a row to the Release index. Then commit + PR to main.
#
#   2. PUBLISH  (run on `main`, after the prepare PR has merged):
#        scripts/cut-release.sh vX.Y.Z --publish
#      Tags main at HEAD and creates the GitHub release, using that version's
#      CHANGELOG section body as the release notes. Idempotent-ish: refuses if the
#      tag or release already exists.
#
# Pure text tooling (awk/sed/gh) — does NOT need the J2026 config, so it is
# intentionally standalone (does not source lib/common.sh).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="${ROOT}/CHANGELOG.md"
REPO_SLUG="${RELEASE_REPO:-nubenetes/jenkins-2026}"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">> $*" >&2; }

VERSION="${1:-}"
[[ -n "${VERSION}" ]] || die "usage: cut-release.sh vX.Y.Z [YYYY-MM-DD | --publish]"
[[ "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like vX.Y.Z (got '${VERSION}')"
[[ -f "${CHANGELOG}" ]] || die "CHANGELOG.md not found at ${CHANGELOG}"

# Extract one version's section BODY (everything after the "## [vX.Y.Z] - date"
# header line, up to but excluding the next "## [" header). Trims trailing blanks.
section_body() {
  local ver="$1"
  awk -v ver="${ver}" '
    $0 ~ "^## \\[" ver "\\]"                    { grab=1; next }
    grab && (/^## / || /^---[[:space:]]*$/)     { exit }
    grab                                        { print }
  ' "${CHANGELOG}" \
    | sed -e 's/[[:space:]]*$//' \
    | awk '{ l[NR]=$0 } END {
        s=1; while (s<=NR && l[s]=="") s++;      # trim leading blanks
        e=NR; while (e>=1 && l[e]=="") e--;      # trim trailing blanks (keep internal)
        for (i=s; i<=e; i++) print l[i]
      }'
}

# ---------------------------------------------------------------------------
# PUBLISH phase
# ---------------------------------------------------------------------------
if [[ "${2:-}" == "--publish" ]]; then
  command -v gh >/dev/null || die "gh CLI not found"
  grep -qE "^## \[${VERSION//./\\.}\] - " "${CHANGELOG}" \
    || die "no '## [${VERSION}] - <date>' section in CHANGELOG.md — run the PREPARE phase (and merge it to main) first"
  git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null \
    && die "tag ${VERSION} already exists"
  gh release view "${VERSION}" --repo "${REPO_SLUG}" >/dev/null 2>&1 \
    && die "GitHub release ${VERSION} already exists"

  local_notes="$(mktemp)"; trap 'rm -f "${local_notes}"' EXIT
  section_body "${VERSION}" > "${local_notes}"
  [[ -s "${local_notes}" ]] || die "extracted release notes are empty for ${VERSION}"

  # Title theme = the leading _italic_ of the section's summary line (format:
  # "_theme._ prose…"), if present. Never fatal.
  THEME="$(grep -m1 -oE '^_[^_]+_' "${local_notes}" | sed -E 's/^_//; s/\.?_$//' || true)"
  TITLE="${VERSION}${THEME:+ — ${THEME}}"

  info "Tagging ${VERSION} at $(git rev-parse --short HEAD) and creating the GitHub release…"
  git tag -a "${VERSION}" -m "${VERSION}"
  git push origin "${VERSION}"
  gh release create "${VERSION}" --repo "${REPO_SLUG}" \
    --title "${TITLE}" \
    --notes-file "${local_notes}"
  info "Published ${VERSION}."
  exit 0
fi

# ---------------------------------------------------------------------------
# PREPARE phase
# ---------------------------------------------------------------------------
DATE="${2:-$(date +%F)}"
[[ "${DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "date must be YYYY-MM-DD (got '${DATE}')"
grep -qE '^## \[Unreleased\]' "${CHANGELOG}" || die "no '## [Unreleased]' section in CHANGELOG.md"
git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null && die "tag ${VERSION} already exists"

# Guard: the [Unreleased] section must contain at least one real entry (a '- ' bullet
# under a '### ' heading), not just the placeholder/comment.
UNREL_BODY="$(section_body 'Unreleased')"
echo "${UNREL_BODY}" | grep -qE '^### ' \
  || die "[Unreleased] has no entries to release (add ### Added/Changed/Fixed bullets first)"

TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
awk -v ver="${VERSION}" -v date="${DATE}" '
  # Rewrite the "## [Unreleased]" header into a fresh empty Unreleased block
  # followed by the new version header; the accumulated body stays under the
  # version header untouched.
  /^## \[Unreleased\]/ && !done1 {
    print "## [Unreleased]"
    print ""
    print "_Nothing yet — add entries here as PRs merge._"
    print ""
    print "## [" ver "] - " date
    done1=1
    next
  }
  # Insert the new index row right after the index table header separator.
  /^\| Version \| Date \| Theme \|/ { print; getline sep; print sep; print "| [" ver "](#" tolower(gensub(/[.]/,"","g",ver)) "---" date ") | " date " | _set me_ |"; next }
  { print }
' "${CHANGELOG}" > "${TMP}"

# Drop the placeholder "_Nothing yet_" line that ended up under the NEW version header
# (only the fresh Unreleased block should keep it). We removed the old placeholder by
# construction; nothing else to do here.

mv "${TMP}" "${CHANGELOG}"
trap - EXIT

info "Prepared ${VERSION} - ${DATE} in CHANGELOG.md."
info "Next: edit the new index row's theme, then:"
info "    git add CHANGELOG.md && git commit -m \"release: ${VERSION}\" && <PR develop -> main>"
info "  After it merges to main:  git checkout main && git pull && scripts/cut-release.sh ${VERSION} --publish"
