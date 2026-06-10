#!/usr/bin/env zsh
set -euo pipefail

fail() { print -r -- "  ✗ $*" >&2; exit 1; }
pass() { print -r -- "  ✓ $*"; }

script_path=${0:A}
repo_root=${script_path:h:h}
origin_url=$(git -C "$repo_root" remote get-url origin)
repo_slug=${origin_url:t}
repo_name=${repo_slug%.git}
workflow="$repo_root/.github/workflows/release-please.yml"
expected="    if: github.repository == 'amit-t/${repo_name}'"

print -r -- "-- release-please origin-only test --"

[[ -f "$workflow" ]] || fail "missing $workflow"
grep -Fxq "$expected" "$workflow" \
  || fail "release-please job must be guarded with: $expected"
pass "release-please job is guarded to amit-t/${repo_name}"
