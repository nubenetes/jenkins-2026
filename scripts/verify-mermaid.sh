#!/usr/bin/env bash
# Render-verifies EVERY ```mermaid block in the repo's tracked *.md files with
# mermaid-cli (mmdc), reporting failures as file:line. Catches the "diagram
# silently fails to render on GitHub" class — e.g. a bare ';' in
# sequenceDiagram note/message text splits the line into two statements and
# kills the whole diagram (bit docs/403 §7.5 and docs/503's ingress sequence).
#
# Usage:
#   scripts/verify-mermaid.sh            # sweep every tracked *.md (~150 blocks, a few min)
#   scripts/verify-mermaid.sh docs/503-NETWORKING.md README.md   # only these files
#   MMDC=/path/to/mmdc scripts/verify-mermaid.sh                 # explicit binary
#
# mmdc resolution: $MMDC → PATH → newest ~/.nvm/versions/node/*/bin/mmdc.
# Install: npm install -g @mermaid-js/mermaid-cli (CI pins 11.16.0 — docs/602).
# Chromium runs headless with --no-sandbox (local WSL + CI runners).
#
# Exit: 0 = every diagram rendered; 1 = at least one failure (or mmdc missing).
# Standalone on purpose (no lib/common.sh): needs only bash, git, awk and mmdc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# --- resolve mmdc ---------------------------------------------------------------
MMDC_BIN="${MMDC:-}"
if [[ -z "${MMDC_BIN}" ]]; then
  MMDC_BIN="$(command -v mmdc || true)"
fi
if [[ -z "${MMDC_BIN}" ]]; then
  # nvm installs live outside non-interactive PATH — pick the newest node's mmdc.
  MMDC_BIN="$(ls -1 "${HOME}"/.nvm/versions/node/*/bin/mmdc 2>/dev/null | sort -V | tail -1 || true)"
fi
if [[ -z "${MMDC_BIN}" || ! -x "${MMDC_BIN}" ]]; then
  echo "ERROR: mmdc (mermaid-cli) not found. Install it with:" >&2
  echo "  npm install -g @mermaid-js/mermaid-cli" >&2
  echo "or point MMDC=/path/to/mmdc at an existing install." >&2
  exit 1
fi
echo "mmdc: ${MMDC_BIN} ($("${MMDC_BIN}" --version 2>/dev/null || echo '?'))"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
# Trusted local content → sandbox off (required in WSL; harmless on CI runners).
printf '{ "args": ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"] }\n' \
  > "${TMP}/pptr.json"

# --- extract every fenced mermaid block (file:line preserved) --------------------
if [[ $# -gt 0 ]]; then
  mdfiles=("$@")
else
  mapfile -t mdfiles < <(git ls-files '*.md')
fi
if [[ "${#mdfiles[@]}" -eq 0 ]]; then
  echo "No markdown files to scan."
  exit 0
fi

: > "${TMP}/index.txt"
awk -v tmp="${TMP}" '
  FNR == 1 { inm = 0 }
  !inm && /^```mermaid[ \t]*$/ { inm = 1; start = FNR + 1; buf = ""; next }
  inm && /^```[ \t]*$/ {
    inm = 0; n++
    bf = sprintf("%s/block-%04d.mmd", tmp, n)
    printf "%s", buf > bf; close(bf)
    printf "%04d %s:%d\n", n, FILENAME, start >> (tmp "/index.txt")
    next
  }
  inm { buf = buf $0 "\n" }
' "${mdfiles[@]}"

total=0
failed=0
failures=()
while read -r id loc; do
  total=$(( total + 1 ))
  src="${TMP}/block-${id}.mmd"
  out="${TMP}/block-${id}.svg"
  if "${MMDC_BIN}" -i "${src}" -o "${out}" -p "${TMP}/pptr.json" --quiet \
       > "${TMP}/err.log" 2>&1 && [[ -s "${out}" ]]; then
    echo "ok   ${loc}"
  else
    failed=$(( failed + 1 ))
    failures+=("${loc}")
    echo "FAIL ${loc}"
    # First error lines only — mmdc stacks are long and repetitive.
    grep -m1 -A2 -iE "error|expecting|parse" "${TMP}/err.log" 2>/dev/null \
      | sed 's/^/       /' || sed -n '1,3p' "${TMP}/err.log" | sed 's/^/       /'
  fi
done < "${TMP}/index.txt"

echo
echo "=== ${total} diagrams checked, ${failed} failed ==="
for f in "${failures[@]:-}"; do
  [[ -n "${f}" ]] && echo "  FAIL ${f}"
done
[[ "${failed}" -eq 0 ]]
