#!/usr/bin/env zsh
# test-wb-context-scan-lock.zsh —
#   two concurrent setups: the second must fail with "lock contended".
#   Release the lock and re-run: second attempt must succeed.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
LIB="${REPO_ROOT}/lib/wb-context-scan.zsh"

scratch="$(mktemp -d -t wbctxscan-lock.XXXXXX)"
WB="$scratch/wb"
trap '
  if [[ -d "$WB/repos/foo/.git" || -f "$WB/repos/foo/.git" ]]; then
    git -C "$WB/repos/foo" worktree remove --force "$WB/.context-scan/foo" 2>/dev/null || true
    git -C "$WB/repos/foo" worktree prune 2>/dev/null || true
  fi
  rm -rf "$scratch"
' EXIT

mkdir -p "$WB/repos/foo" "$WB/context"
cat > "$WB/project.conf" <<'CONF'
REPOS=( "name=foo;url=x;role=service" )
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

# ── manually take the lock ───────────────────────────────────────────
mkdir -p "$WB/.context-scan"
LOCK="$WB/.context-scan/.lock"

if (( $+commands[flock] )); then
  # Hold the lock via a backgrounded subshell.
  ( exec 9>"$LOCK" && flock -n 9 && sleep 30 ) &
  holder_pid=$!
  # give the bg shell a beat to actually grab the fd lock
  sleep 0.3
else
  # mkdir-as-lock: just create the dir.
  mkdir "$LOCK"
fi

# ── attempt setup → must fail with lock-contended message ────────────
set +e
out="$(zsh "$LIB" setup "$WB" foo 2>&1)"
rc=$?
set -e

# Release the lock NOW so cleanup is clean even if asserts below fail.
if (( $+commands[flock] )); then
  kill "$holder_pid" 2>/dev/null || true
  wait "$holder_pid" 2>/dev/null || true
  rm -f "$LOCK"
else
  rm -rf "$LOCK"
fi

[[ $rc -ne 0 ]] || {
  print -u2 -r -- "FAIL: setup should fail when lock is held (rc=$rc)"
  print -u2 -r -- "out: $out"
  exit 1
}
print -r -- "$out" | grep -q 'lock contended' || {
  print -u2 -r -- "FAIL: error message should mention 'lock contended'"
  print -u2 -r -- "got: $out"
  exit 1
}
print -r -- "PASS: setup refuses to run when lock is held"

# Also verify the setup did NOT leave a worktree behind.
[[ ! -e "$WB/.context-scan/foo" ]] || {
  print -u2 -r -- "FAIL: contended setup left an orphan worktree at $WB/.context-scan/foo"
  exit 1
}
print -r -- "PASS: contended setup did not mutate worktree state"

# ── now run setup; should succeed (lock released above) ──────────────
out2="$(zsh "$LIB" setup "$WB" foo)"
print -r -- "$out2" | grep -q '^SCAN_DIR=' || {
  print -u2 -r -- "FAIL: post-release setup did not succeed"
  print -u2 -r -- "out: $out2"
  exit 1
}
SCAN_DIR="${out2#SCAN_DIR=}"
[[ -d "$SCAN_DIR" ]] || { print -u2 -r -- "FAIL: SCAN_DIR not created"; exit 1; }
print -r -- "PASS: setup succeeds after lock is released"

# clean teardown
zsh "$LIB" finalize "$WB" foo --fail-reason "lock test teardown" >/dev/null

print -r -- "All lock tests passed."
