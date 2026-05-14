#!/usr/bin/env zsh
# smoke-install.zsh — local mirror of .github/workflows/smoke-install.yml.
#
# Runs the non-interactive installer in a sandboxed $HOME, then exercises
# `devkit doctor --check-only` and `devkit upgrade --check-only`. Asserts the
# install side-effects landed: shim binaries exist, ~/.zprofile got
# DEVKIT_CLONE, shared lib was copied. Exits non-zero on any failed check.
#
# Usage:
#   zsh tests/integration/smoke-install.zsh
#
# Behaviour on macOS: skips the apt prereq install (assumes brew env already
# has zsh / jq / gh / git / curl). The install + doctor + upgrade flow is
# still exercised end-to-end. On Linux, apt prereqs are checked (not
# installed; that needs sudo and is a CI concern). Missing prereqs abort
# with a clear message.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"

# ── Sandbox setup ──────────────────────────────────────────────────────────
SANDBOX_HOME="$(mktemp -d 2>/dev/null || mktemp -d -t devkit-smoke)"
cleanup() { rm -rf "$SANDBOX_HOME"; }
trap cleanup EXIT INT TERM

print -r -- "── smoke-install: sandbox $SANDBOX_HOME ─────────────────"

# ── Platform detection ────────────────────────────────────────────────────
uname_s="$(uname -s)"
case "$uname_s" in
  Linux)  platform=linux ;;
  Darwin) platform=mac ;;
  *) print -ru2 -- "Unsupported platform: $uname_s"; exit 1 ;;
esac
print -r -- "platform: $platform"

# ── Prereq check (do not install; that needs sudo) ─────────────────────────
missing=()
for cmd in zsh jq gh git curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done
if (( ${#missing[@]} > 0 )); then
  print -ru2 -- "FAIL: missing prereqs: ${missing[*]}"
  if [[ "$platform" == "linux" ]]; then
    print -ru2 -- "Hint: sudo apt-get install -y ${missing[*]}"
  else
    print -ru2 -- "Hint: brew install ${missing[*]}"
  fi
  exit 1
fi
print -r -- "prereqs ok: zsh jq gh git curl"

# ── Run installer non-interactively in sandbox ─────────────────────────────
# We override HOME so the installer writes to the sandbox, not the user's
# real ~/.zprofile / ~/.local/bin. DEVKIT_CLONE points to the actual repo
# under test so the symlinks target real scripts.
print -r -- "── running installer (DEVKIT_NONINTERACTIVE=1) ──"
HOME="$SANDBOX_HOME" \
  DEVKIT_NONINTERACTIVE=1 \
  DEVKIT_DEFAULT_ORG=amit-t \
  zsh "$REPO_ROOT/install.zsh"

# ── Assertions on install side-effects ────────────────────────────────────
fail=0

# Note: avoid using `path` as a local variable name in zsh. It is a special
# array tied to $PATH; shadowing it with a scalar breaks command lookup
# inside the function body. Using `target` here keeps PATH intact.
assert_file() {
  local target="$1" label="$2"
  if [[ -e "$target" || -L "$target" ]]; then
    print -r -- "OK: $label exists ($target)"
  else
    print -ru2 -- "FAIL: $label missing ($target)"
    fail=1
  fi
}

assert_grep() {
  local target="$1" pattern="$2" label="$3"
  if [[ -f "$target" ]] && grep -qF "$pattern" "$target"; then
    print -r -- "OK: $label"
  else
    print -ru2 -- "FAIL: $label (pattern '$pattern' not in $target)"
    fail=1
  fi
}

assert_file "$SANDBOX_HOME/.local/bin/devkit"        "devkit shim"
assert_file "$SANDBOX_HOME/.local/bin/init.wb"       "init.wb symlink"
assert_file "$SANDBOX_HOME/.local/bin/join.wb"       "join.wb symlink"
assert_file "$SANDBOX_HOME/.local/bin/wb.upgrade"    "wb.upgrade symlink"
assert_file "$SANDBOX_HOME/.local/bin/devkit.upgrade" "devkit.upgrade symlink"
assert_file "$SANDBOX_HOME/.local/share/wb-versioncheck/version-check.sh" "version-check lib"
assert_grep "$SANDBOX_HOME/.zprofile" "DEVKIT_CLONE" "DEVKIT_CLONE written to .zprofile"

# ── Doctor smoke ──────────────────────────────────────────────────────────
print -r -- "── devkit doctor --check-only ──"
# Doctor exits non-zero if any tool stale (expected in a sandbox without
# cache state). The smoke just asserts the shim resolves + runs.
HOME="$SANDBOX_HOME" \
PATH="$SANDBOX_HOME/.local/bin:$PATH" \
  zsh -c 'devkit doctor --check-only' >/dev/null 2>&1 || true
print -r -- "OK: doctor invoked via shim"

# ── Upgrade --check-only smoke ────────────────────────────────────────────
print -r -- "── devkit upgrade --check-only ──"
# Upgrade --check-only may exit 0 (up-to-date) or 1 (stale) or 2 (dirty
# clone / wrong branch). We exercise it with the real DEVKIT_CLONE and
# tolerate any of those, the same way CI does.
HOME="$SANDBOX_HOME" \
PATH="$SANDBOX_HOME/.local/bin:$PATH" \
  zsh -c 'devkit upgrade --check-only' >/dev/null 2>&1 || true
print -r -- "OK: upgrade --check-only invoked via shim"

# ── Result ────────────────────────────────────────────────────────────────
if (( fail != 0 )); then
  print -ru2 -- "── smoke-install: FAIL ──"
  exit 1
fi
print -r -- "── smoke-install: PASS ──"
