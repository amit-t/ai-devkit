#!/usr/bin/env zsh
# test-engine-cmd.zsh — marker-driven engine + Claude-launcher resolution.
#
# Asserts lib/engine-cmd.zsh resolves the default engine and Claude launcher
# from the .ralph-prefix marker + env overrides, and that install.zsh writes the
# matching {NS}DEVKIT_DEFAULT_ENGINE / {NS}DEVKIT_CLAUDE_CMD to ~/.zprofile.
#
# Personal (marked) fork  -> claude + clscb.
# Unmarked twin fork      -> legacy devin-then-claude + bare claude (untouched).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
LIB="$REPO_ROOT/lib/engine-cmd.zsh"

fail=0
assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    print -r -- "PASS: $label ($got)"
  else
    print -ru2 -- "FAIL: $label — got '$got', want '$want'"; fail=1
  fi
}

# Resolve the lib in a clean subshell with controlled marker/env, echo results.
# Args: ENGINE_PREFIX_OVERRIDE  EXTRA_ENV...   (override is passed as
# DEVKIT_ENGINE_PREFIX so the test never depends on the real .ralph-prefix.)
resolve() {
  local prefix="$1"; shift
  env "$@" zsh -c '
    set -euo pipefail
    DEVKIT_ENGINE_PREFIX="'"$prefix"'" source "'"$LIB"'"
    print -r -- "$DEVKIT_DEFAULT_AGENT|$DEVKIT_CLAUDE_LAUNCHER"
  '
}

print -r -- "── lib/engine-cmd.zsh resolution ──"

# Personal fork (marker "per."): claude + clscb, no env overrides.
out="$(resolve 'per.')"
assert_eq "${out%%|*}" "claude" "marked fork default engine"
assert_eq "${out##*|}" "clscb"  "marked fork Claude launcher"

# Namespaced env overrides win on the marked fork.
out="$(resolve 'per.' PER_DEVKIT_DEFAULT_ENGINE=devin PER_DEVKIT_CLAUDE_CMD=claude)"
assert_eq "${out%%|*}" "devin"  "namespaced engine override"
assert_eq "${out##*|}" "claude" "namespaced launcher override"

# Unmarked twin fork: bare claude launcher; engine respects bare env override
# (so the assertion is deterministic regardless of whether devin is installed).
out="$(resolve '' DEVKIT_DEFAULT_ENGINE=devin)"
assert_eq "${out%%|*}" "devin"  "unmarked fork honors bare engine env"
assert_eq "${out##*|}" "claude" "unmarked fork bare Claude launcher"

# Unmarked fork with no env + no devin on PATH falls back to claude.
out="$(PATH=/usr/bin:/bin resolve '')"
assert_eq "${out##*|}" "claude" "unmarked fork launcher stays bare claude"

# ── install.zsh writes the matching env to ~/.zprofile ──────────────────────
SANDBOX_HOME="$(mktemp -d 2>/dev/null || mktemp -d -t devkit-engine)"
cleanup() { rm -rf "$SANDBOX_HOME"; }
trap cleanup EXIT INT TERM

print -r -- "── install.zsh engine env writes (sandbox $SANDBOX_HOME) ──"
HOME="$SANDBOX_HOME" DEVKIT_NONINTERACTIVE=1 \
  zsh "$REPO_ROOT/install.zsh" --prefix per. >/dev/null

zp="$SANDBOX_HOME/.zprofile"
if grep -qF 'export PER_DEVKIT_DEFAULT_ENGINE="claude"' "$zp" 2>/dev/null; then
  print -r -- "PASS: install writes PER_DEVKIT_DEFAULT_ENGINE=claude"
else
  print -ru2 -- "FAIL: install did not write PER_DEVKIT_DEFAULT_ENGINE=claude"; fail=1
fi
if grep -qF 'export PER_DEVKIT_CLAUDE_CMD="clscb"' "$zp" 2>/dev/null; then
  print -r -- "PASS: install writes PER_DEVKIT_CLAUDE_CMD=clscb"
else
  print -ru2 -- "FAIL: install did not write PER_DEVKIT_CLAUDE_CMD=clscb"; fail=1
fi
# Re-install must not stack duplicate lines (idempotent upsert).
HOME="$SANDBOX_HOME" DEVKIT_NONINTERACTIVE=1 \
  zsh "$REPO_ROOT/install.zsh" --prefix per. >/dev/null
n="$(grep -c '^export PER_DEVKIT_CLAUDE_CMD=' "$zp")"
assert_eq "$n" "1" "PER_DEVKIT_CLAUDE_CMD written exactly once after re-install"

if (( fail != 0 )); then
  print -ru2 -- "── test-engine-cmd: FAIL ──"
  exit 1
fi
print -r -- "── test-engine-cmd: PASS ──"
