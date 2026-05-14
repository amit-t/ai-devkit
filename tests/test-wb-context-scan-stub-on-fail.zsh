#!/usr/bin/env zsh
# test-wb-context-scan-stub-on-fail.zsh —
#   finalize with --fail-reason writes a stub CONTEXT.md carrying
#   status=scan-failed and the locked failure-only frontmatter keys.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
LIB="${REPO_ROOT}/lib/wb-context-scan.zsh"

scratch="$(mktemp -d -t wbctxscan-stub.XXXXXX)"
WB="$scratch/wb"
trap '
  if [[ -d "$WB/repos/foo/.git" || -f "$WB/repos/foo/.git" ]]; then
    git -C "$WB/repos/foo" worktree remove --force "$WB/.context-scan/foo" 2>/dev/null || true
    git -C "$WB/repos/foo" worktree prune 2>/dev/null || true
  fi
  rm -rf "$scratch"
' EXIT

# ── build fake wb ───────────────────────────────────────────────────────
mkdir -p "$WB/repos/foo" "$WB/context"
cat > "$WB/project.conf" <<'CONF'
REPOS=(
  "name=foo;url=https://github.com/example/foo;role=service;stack=go;added_by=test"
)
CONF

(
  cd "$WB/repos/foo"
  git init -q
  git config user.email "t@t"
  git config user.name "test"
  print -r -- "package main" > main.go
  git add -A
  git commit -qm init
)

# ── setup, then finalize WITHOUT producing any scan output ─────────────
zsh "$LIB" setup "$WB" foo >/dev/null
# Note: do NOT drop CONTEXT.md into SCAN_DIR.
zsh "$LIB" finalize "$WB" foo --fail-reason "test crash" >/dev/null

ctx="$WB/context/foo/CONTEXT.md"
[[ -f "$ctx" ]] || { print -u2 -r -- "FAIL: stub CONTEXT.md not produced"; exit 1; }

get_field() {
  awk -v k="$1" '
    NR==1 && $0=="---" { in_block=1; next }
    in_block && $0=="---" { exit }
    in_block && $0 ~ "^"k":" {
      sub("^"k":[[:space:]]+", "", $0)
      print $0
      exit
    }
  ' "$ctx"
}

want_pairs=(
  "status=scan-failed"
  "fail_reason=\"test crash\""
  "retry_with=\"wb.rescan foo\""
  "source_repo=foo"
  "source_url=https://github.com/example/foo"
)
for pair in "${want_pairs[@]}"; do
  k="${pair%%=*}"
  expected="${pair#*=}"
  got="$(get_field "$k")"
  [[ "$got" == "$expected" ]] || {
    print -u2 -r -- "FAIL: stub frontmatter $k: expected '$expected', got '$got'"
    print -u2 -r -- "--- frontmatter dump ---"
    head -n 20 "$ctx" >&2
    exit 1
  }
done

# source_commit and devkit_version should be populated too (success-style fields)
got_commit="$(get_field source_commit)"
[[ -n "$got_commit" && "$got_commit" != "no-head" ]] || {
  print -u2 -r -- "FAIL: source_commit should be real sha even on fail, got '$got_commit'"
  exit 1
}

got_failed_at="$(get_field failed_at)"
print -r -- "$got_failed_at" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || {
  print -u2 -r -- "FAIL: failed_at not ISO-8601 Z: '$got_failed_at'"
  exit 1
}

print -r -- "PASS: stub has correct failure-path frontmatter"

# ── body matches stub template ─────────────────────────────────────────
grep -q '^# foo (scan failed)$'         "$ctx" || { print -u2 -r -- "FAIL: stub heading missing"; exit 1; }
grep -q 'Repo context scan did not'     "$ctx" || { print -u2 -r -- "FAIL: stub body para missing"; exit 1; }
grep -q 'wb.rescan foo'                 "$ctx" || { print -u2 -r -- "FAIL: stub body missing rescan hint"; exit 1; }
grep -q 'rm -rf context/foo'            "$ctx" || { print -u2 -r -- "FAIL: stub body missing structural-failure hint"; exit 1; }
print -r -- "PASS: stub body matches template"

# ── idempotency: second finalize call with same args overwrites cleanly ─
# Sleep 1s to make sure failed_at changes (ISO-8601 second resolution).
sleep 1
zsh "$LIB" setup    "$WB" foo >/dev/null
zsh "$LIB" finalize "$WB" foo --fail-reason "test crash" >/dev/null
[[ -f "$ctx" ]] || { print -u2 -r -- "FAIL: second finalize lost the stub"; exit 1; }
new_failed_at="$(get_field failed_at)"
[[ "$new_failed_at" != "$got_failed_at" ]] || {
  print -u2 -r -- "FAIL: second finalize did not refresh failed_at (still '$new_failed_at')"
  exit 1
}
print -r -- "PASS: finalize idempotent across runs (failed_at refreshed)"

# ── third finalize without --fail-reason and without output should still stub
sleep 1
zsh "$LIB" setup    "$WB" foo >/dev/null
zsh "$LIB" finalize "$WB" foo >/dev/null
new_status="$(get_field status)"
[[ "$new_status" == "scan-failed" ]] || {
  print -u2 -r -- "FAIL: finalize w/o output and w/o --fail-reason should still mark scan-failed (got '$new_status')"
  exit 1
}
print -r -- "PASS: missing scan output → stub even without --fail-reason"

# ── defensive merge on stub path: inject user key, re-fail, preserve key
tmp_inject="$(mktemp)"
awk '
  /^---$/ {
    seen++
    if (seen==2) {
      print "owner:          alice"
      print
      next
    }
  }
  { print }
' "$ctx" > "$tmp_inject"
mv "$tmp_inject" "$ctx"

sleep 1
zsh "$LIB" setup    "$WB" foo >/dev/null
zsh "$LIB" finalize "$WB" foo --fail-reason "second crash" >/dev/null

got_owner="$(get_field owner)"
[[ "$got_owner" == "alice" ]] || {
  print -u2 -r -- "FAIL: stub-path defensive merge dropped user-authored 'owner' (got '$got_owner')"
  print -u2 -r -- "--- frontmatter dump ---"
  head -n 25 "$ctx" >&2
  exit 1
}
new_reason="$(get_field fail_reason)"
[[ "$new_reason" == '"second crash"' ]] || {
  print -u2 -r -- "FAIL: stub-path merge did not overwrite fail_reason (got '$new_reason')"
  exit 1
}
print -r -- "PASS: stub-path preserves user keys while refreshing devkit-owned"

print -r -- "All stub-on-fail tests passed."
