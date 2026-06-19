#!/usr/bin/env zsh
# test-versioncheck-launch.zsh — lib/versioncheck-launch.zsh resolves the
# command prefix (env DEVKIT_CMD_PREFIX > .devkit-cmd-prefix marker > "") and
# sources the matching state-dir lib, passing WB_CMD_PREFIX through.
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."

pass() { print -r -- "PASS: $*"; }
fail() { print -ru2 -- "FAIL: $*"; exit 1; }

SANDBOX="$(mktemp -d)"
trap "rm -rf '$SANDBOX'" EXIT

# Stub version-check libs under a fake HOME. Each stub redefines _wb_versioncheck
# to echo which lib was sourced + the WB_CMD_PREFIX it was handed.
FAKE_HOME="$SANDBOX/home"
mk_stub() {  # $1 = tag-label, $2 = state-dir-name
  local dir="$FAKE_HOME/.local/share/$2"
  mkdir -p "$dir"
  cat > "$dir/version-check.sh" <<STUB
_wb_versioncheck() { print -r -- "LIB=$1 PREFIX=\${WB_CMD_PREFIX:-} TOOL=\${1} CACHE=\${WB_UPDATES_CACHE_DIR:-} STATE=\${WB_STATE_DIR:-}"; }
STUB
}
mk_stub per  per-wb-versioncheck
mk_stub plain wb-versioncheck

FAKE_ROOT="$SANDBOX/devkit"
mkdir -p "$FAKE_ROOT/lib"

# run the resolver in a clean subshell with controlled env
run() {  # env-assignments... -- expects to set DEVKIT_ROOT/marker beforehand
  HOME="$FAKE_HOME" "$@" zsh -c '
    source "'"$REPO_ROOT"'/lib/versioncheck-launch.zsh"
    _wb_launch_versioncheck wb
  ' 2>&1
}

PER_CACHE="$FAKE_HOME/.cache/per-wb-updates"
PER_STATE="$FAKE_HOME/.local/share/per-wb-versioncheck"
PLAIN_CACHE="$FAKE_HOME/.cache/wb-updates"
PLAIN_STATE="$FAKE_HOME/.local/share/wb-versioncheck"

# A. marker = "per." (no env) -> per-tagged lib + WB_CMD_PREFIX=per. + per-tagged
#    cache/state (so a company-side wb check can't poison the personal banner).
print 'per.' > "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env -u DEVKIT_CMD_PREFIX DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=per PREFIX=per. TOOL=wb CACHE=$PER_CACHE STATE=$PER_STATE" ]] \
  || fail "marker per. -> $out"
pass "marker .devkit-cmd-prefix=per. -> per-tagged lib + prefix + per-tagged cache/state"

# B. marker empty -> plain lib + empty prefix + SHARED (untagged) cache/state
#    (twin / Invenco parity: unprefixed install keeps the original paths).
print '' > "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env -u DEVKIT_CMD_PREFIX DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=plain PREFIX= TOOL=wb CACHE=$PLAIN_CACHE STATE=$PLAIN_STATE" ]] \
  || fail "empty marker -> $out"
pass "empty marker -> plain lib + no prefix + untagged cache/state (INV parity)"

# C. env DEVKIT_CMD_PREFIX=per. overrides absent marker
rm -f "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env DEVKIT_CMD_PREFIX=per. DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=per PREFIX=per. TOOL=wb CACHE=$PER_CACHE STATE=$PER_STATE" ]] \
  || fail "env prefix per. -> $out"
pass "env DEVKIT_CMD_PREFIX=per. -> per-tagged lib + per-tagged cache/state (no marker present)"

# D. env DEVKIT_CMD_PREFIX='' (authoritative) beats marker=per.
print 'per.' > "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env DEVKIT_CMD_PREFIX= DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=plain PREFIX= TOOL=wb CACHE=$PLAIN_CACHE STATE=$PLAIN_STATE" ]] \
  || fail "empty env overrides marker -> $out"
pass "empty env DEVKIT_CMD_PREFIX overrides marker=per. -> plain lib + untagged cache/state"

# E. cache isolation: per-tagged and untagged installs resolve DIFFERENT cache
#    files, so a company `wb` check can never poison the personal banner.
[[ "$PER_CACHE" != "$PLAIN_CACHE" && "$PER_STATE" != "$PLAIN_STATE" ]] \
  || fail "per/plain cache or state dirs collide"
pass "per-tagged and untagged cache/state dirs are disjoint (no cross-twin poisoning)"

# F. Regression: the lib must self-resolve its root from the .devkit-cmd-prefix
#    marker even when DEVKIT_ROOT does NOT reach the function — exactly the real
#    launcher path, where `DEVKIT_ROOT=X source lib` prefix-assigns on the zsh
#    `source` builtin and the assignment does not persist to the later
#    _wb_launch_versioncheck call. Pre-fix this fell back to the function name via
#    `$0` and silently loaded the plain (company) lib.
#
#    Stage the lib + marker inside FAKE_ROOT so the lib's source-time
#    `${0:A:h:h}` self-path lands on FAKE_ROOT and finds the per. marker.
mkdir -p "$FAKE_ROOT/lib"
cp "$REPO_ROOT/lib/versioncheck-launch.zsh" "$FAKE_ROOT/lib/versioncheck-launch.zsh"
print 'per.' > "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(HOME="$FAKE_HOME" zsh -c '
  # Faithfully mimic update.zsh: prefix-assign DEVKIT_ROOT on the source builtin
  # (does NOT persist in zsh), then call the function on a separate line.
  DEVKIT_ROOT="'"$FAKE_ROOT"'" source "'"$FAKE_ROOT"'/lib/versioncheck-launch.zsh"
  _wb_launch_versioncheck wb
' 2>&1)"
[[ "$out" == "LIB=per PREFIX=per. TOOL=wb CACHE=$PER_CACHE STATE=$PER_STATE" ]] \
  || fail "prefix-assign-on-source path resolved wrong lib -> $out"
pass "lib self-resolves root via marker when DEVKIT_ROOT does not persist (real launcher path)"

print -r -- "PASS: test-versioncheck-launch.zsh"
