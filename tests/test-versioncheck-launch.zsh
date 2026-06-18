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
_wb_versioncheck() { print -r -- "LIB=$1 PREFIX=\${WB_CMD_PREFIX:-} TOOL=\${1}"; }
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

# A. marker = "per." (no env) -> per-tagged lib + WB_CMD_PREFIX=per.
print 'per.' > "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env -u DEVKIT_CMD_PREFIX DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=per PREFIX=per. TOOL=wb" ]] || fail "marker per. -> $out"
pass "marker .devkit-cmd-prefix=per. -> per-tagged lib + WB_CMD_PREFIX=per."

# B. marker empty -> plain lib + empty prefix (twin / Invenco parity)
print '' > "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env -u DEVKIT_CMD_PREFIX DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=plain PREFIX= TOOL=wb" ]] || fail "empty marker -> $out"
pass "empty marker -> plain lib + no prefix (INV parity)"

# C. env DEVKIT_CMD_PREFIX=per. overrides absent marker
rm -f "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env DEVKIT_CMD_PREFIX=per. DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=per PREFIX=per. TOOL=wb" ]] || fail "env prefix per. -> $out"
pass "env DEVKIT_CMD_PREFIX=per. -> per-tagged lib (no marker present)"

# D. env DEVKIT_CMD_PREFIX='' (authoritative) beats marker=per.
print 'per.' > "$FAKE_ROOT/.devkit-cmd-prefix"
out="$(run env DEVKIT_CMD_PREFIX= DEVKIT_ROOT="$FAKE_ROOT")"
[[ "$out" == "LIB=plain PREFIX= TOOL=wb" ]] || fail "empty env overrides marker -> $out"
pass "empty env DEVKIT_CMD_PREFIX overrides marker=per. -> plain lib"

print -r -- "PASS: test-versioncheck-launch.zsh"
