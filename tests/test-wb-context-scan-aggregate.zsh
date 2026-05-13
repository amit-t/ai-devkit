#!/usr/bin/env zsh
# test-wb-context-scan-aggregate.zsh —
#   aggregate produces correct table rows for mixed states:
#   scanned, scan-failed, missing, orphan, plus CONTEXT-MAP variant.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
LIB="${REPO_ROOT}/lib/wb-context-scan.zsh"

scratch="$(mktemp -d -t wbctxscan-agg.XXXXXX)"
WB="$scratch/wb"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$WB/context" "$WB/repos"
cat > "$WB/project.conf" <<'CONF'
REPOS=(
  "name=a;url=https://github.com/example/a;role=service;stack=go;added_by=test"
  "name=b;url=https://github.com/example/b;role=service;stack=node;added_by=test"
  "name=c;url=https://github.com/example/c;role=shared-lib;stack=ts;added_by=test"
  "name=e;url=https://github.com/example/e;role=automation-tests;stack=py;added_by=test"
)
CONF

# a: scanned (CONTEXT.md with success frontmatter)
mkdir -p "$WB/context/a"
cat > "$WB/context/a/CONTEXT.md" <<'CTX'
---
generated_by:   ai-devkit/repo-context-scan
generated_at:   2026-05-13T14:22:18Z
source_repo:    a
source_url:     https://github.com/example/a
source_commit:  abc123
devkit_version: 1.0.0
skill_version:  abc123def456
status:         scanned
---
# a

Domain concepts: **Alpha**, **Bravo**, **Charlie**, **Delta**. Repeat **Alpha**.
CTX

# b: scan-failed
mkdir -p "$WB/context/b"
cat > "$WB/context/b/CONTEXT.md" <<'CTX'
---
generated_by:   ai-devkit/repo-context-scan
generated_at:   2026-05-13T14:22:18Z
source_repo:    b
source_url:     https://github.com/example/b
source_commit:  no-head
devkit_version: 1.0.0
skill_version:  abc123def456
status:         scan-failed
fail_reason:    "boom"
failed_at:      2026-05-13T14:22:18Z
retry_with:     "wb.rescan b"
---
# b (scan failed)

Stub body — should not contribute top concepts.
CTX

# c: in REPOS but no context dir → missing (NO context/c at all)

# d: not in REPOS, on disk → orphan
mkdir -p "$WB/context/d"
cat > "$WB/context/d/CONTEXT.md" <<'CTX'
---
generated_by:   ai-devkit/repo-context-scan
source_repo:    d
status:         scanned
---
# d

Concepts: **Money**, **CustomerId**.
CTX

# e: CONTEXT-MAP variant (multi-context)
mkdir -p "$WB/context/e"
cat > "$WB/context/e/CONTEXT-MAP.md" <<'CTX'
---
generated_by:   ai-devkit/repo-context-scan
source_repo:    e
status:         scanned
---
# e

Concepts: **Customer**, **Order**, **Cart**.
CTX

# ── run aggregate ─────────────────────────────────────────────────────
zsh "$LIB" aggregate "$WB" >/dev/null

idx="$WB/context/README.md"
[[ -f "$idx" ]] || { print -u2 -r -- "FAIL: aggregate did not write context/README.md"; exit 1; }

# ── assert each row ──────────────────────────────────────────────────
# Use fixed-string grep (-F) so `[`, `]`, `|`, `.`, `*`, `(`, `)` etc. are literal.
assert_row() {
  local pattern="$1" label="$2"
  if ! grep -F -q -- "$pattern" "$idx"; then
    print -u2 -r -- "FAIL ($label): expected row matching: $pattern"
    print -u2 -r -- "--- README dump ---"
    cat "$idx" >&2
    exit 1
  fi
}

# a — scanned, role=service, concepts include Alpha/Bravo/Charlie (first 3 unique bolded)
assert_row '| [a](./a/CONTEXT.md) | service | scanned | Alpha, Bravo, Charlie |' "a-scanned"

# b — scan-failed, role=service, concepts em-dash
assert_row '| [b](./b/CONTEXT.md) | service | scan-failed | — |' "b-scan-failed"

# c — missing (in REPOS, no context dir). Plan note: use REPOS-recorded role.
assert_row '| c | shared-lib | missing | — |' "c-missing"

# d — orphan (not in REPOS, on disk). role becomes (none).
assert_row '| [d](./d/CONTEXT.md) | (none) | orphan | — |' "d-orphan"

# e — multi-context CONTEXT-MAP variant
assert_row '| [e](./e/CONTEXT-MAP.md) | automation-tests | scanned | Customer, Order, Cart |' "e-context-map"

print -r -- "PASS: all 5 row variants present (scanned, scan-failed, missing, orphan, CONTEXT-MAP)"

# ── header + legend present ───────────────────────────────────────────
grep -q '^# Workbench Context Index'              "$idx" || { print -u2 -r -- "FAIL: header missing"; exit 1; }
grep -q '^| Repo | Role | Status | Top concepts |'"$idx" >/dev/null 2>&1 || \
  grep -q 'Repo | Role | Status | Top concepts'    "$idx" || { print -u2 -r -- "FAIL: table header missing"; exit 1; }
grep -q 'wb.rescan --all'                         "$idx" || { print -u2 -r -- "FAIL: legend missing rescan --all hint"; exit 1; }
print -r -- "PASS: README header, table header, and legend all present"

# ── orphans land AFTER REPOS-registered rows ──────────────────────────
# Confirm row ordering: a → b → c → e (REPOS order), then d (orphan).
ord="$(grep -nE '^\| ' "$idx" | grep -vE '^\|[ -]+\|' | awk -F'|' '
  {
    cell=$2
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
    # strip markdown link wrapper
    sub(/^\[/, "", cell)
    sub(/\].*$/, "", cell)
    print cell
  }
')"
# first row is the table HEADER literal "Repo" — drop it
ord_clean="$(print -r -- "$ord" | grep -v '^Repo$')"
expected_ord=$'a\nb\nc\ne\nd'
if [[ "$ord_clean" != "$expected_ord" ]]; then
  print -u2 -r -- "FAIL: row order incorrect"
  print -u2 -r -- "expected:"
  print -u2 -r -- "$expected_ord"
  print -u2 -r -- "got:"
  print -u2 -r -- "$ord_clean"
  exit 1
fi
print -r -- "PASS: REPOS-registered rows first (in REPOS order), orphans last"

print -r -- "All aggregate tests passed."
