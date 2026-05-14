#!/usr/bin/env zsh
# Regression test for cmd_aggregate exiting non-zero when a CONTEXT.md has no
# `**bold**` concepts.
#
# `_extract_top_concepts` ran a `grep -oE '\*\*[^*]+\*\*' | sed | awk | head |
# paste | sed` pipeline. When grep found zero matches it exited 1, which
# `set -o pipefail` propagated through the command substitution, which `set -e`
# converted into a hard abort inside cmd_aggregate. Net effect: any workbench
# whose latest scan produced no bold concepts (a totally legitimate outcome —
# e.g. an early/sparse repo) saw `wb.rescan: aggregate failed` and a non-zero
# exit on every run, leaving `context/README.md` un-regenerated.
#
# Fix: tolerate the empty pipeline via `... || true` at the end of the
# substitution. `_extract_top_concepts` already coerces an empty result to
# `—`, so the trailing dash row is the correct fallback.

set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

wb="$scratch/wb"
mkdir -p "$wb/context/foo" "$wb/repos"
cat > "$wb/project.conf" <<'EOF'
REPOS=(
  "name=foo;url=local;role=service;stack=test;added_by=t"
)
EOF

# CONTEXT.md with no **bold** anywhere — the pre-fix bug scenario.
cat > "$wb/context/foo/CONTEXT.md" <<'EOF'
---
generated_by: ai-devkit/repo-context-scan
status: scanned
source_repo: foo
---
# Repo context for foo

Sparse repo with no domain terms identified yet. Re-run after content lands.
EOF

if ! zsh "$REPO_ROOT/lib/wb-context-scan.zsh" aggregate "$wb"; then
  print -r -- "FAIL: cmd_aggregate exited non-zero on a scanned CONTEXT.md without **bold** concepts"
  exit 1
fi

if [[ ! -f "$wb/context/README.md" ]]; then
  print -r -- "FAIL: aggregate did not produce context/README.md"
  exit 1
fi

if ! grep -q '| \[foo\](./foo/CONTEXT.md) | service | scanned | — |' "$wb/context/README.md"; then
  print -r -- "FAIL: aggregate row missing or wrong for the no-concepts case"
  print -r -- "----- generated README.md -----"
  cat "$wb/context/README.md"
  exit 1
fi

print -r -- "PASS: aggregate tolerates a scanned CONTEXT.md with no **bold** concepts"
