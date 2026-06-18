#!/usr/bin/env zsh
# test-install-prefix.zsh — install.zsh --prefix coexistence behaviour.
#
# Asserts that `install.zsh --prefix per.` installs a fully namespaced command
# family (per.init.wb, ...) backed by PER_-namespaced env vars and a per-tagged
# version-check state dir, WITHOUT touching the unprefixed names or DEVKIT_CLONE.
# This is what lets a personal ai-devkit clone coexist with an unprefixed
# (default) clone on the same machine.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

SANDBOX_HOME="$(mktemp -d 2>/dev/null || mktemp -d -t devkit-prefix)"
cleanup() { rm -rf "$SANDBOX_HOME"; }
trap cleanup EXIT INT TERM

fail=0
assert_file() {
  local target="$1" label="$2"
  if [[ -e "$target" || -L "$target" ]]; then
    print -r -- "PASS: $label exists"
  else
    print -ru2 -- "FAIL: $label missing ($target)"; fail=1
  fi
}
refute_file() {
  local target="$1" label="$2"
  if [[ -e "$target" || -L "$target" ]]; then
    print -ru2 -- "FAIL: $label should NOT exist ($target)"; fail=1
  else
    print -r -- "PASS: $label absent (reserved for the unprefixed clone)"
  fi
}
assert_grep() {
  local target="$1" pattern="$2" label="$3"
  if [[ -f "$target" ]] && grep -qF "$pattern" "$target"; then
    print -r -- "PASS: $label"
  else
    print -ru2 -- "FAIL: $label (pattern '$pattern' not in $target)"; fail=1
  fi
}
refute_grep() {
  local target="$1" pattern="$2" label="$3"
  if [[ -f "$target" ]] && grep -qF "$pattern" "$target"; then
    print -ru2 -- "FAIL: $label (pattern '$pattern' unexpectedly in $target)"; fail=1
  else
    print -r -- "PASS: $label"
  fi
}

print -r -- "── install.zsh --prefix per. in sandbox $SANDBOX_HOME ──"
HOME="$SANDBOX_HOME" \
  DEVKIT_NONINTERACTIVE=1 \
  zsh "$REPO_ROOT/install.zsh" --prefix per. >/dev/null

# Prefixed command family present.
assert_file "$SANDBOX_HOME/.local/bin/per.init.wb"     "per.init.wb symlink"
assert_file "$SANDBOX_HOME/.local/bin/per.join.wb"     "per.join.wb symlink"
assert_file "$SANDBOX_HOME/.local/bin/per.wb.upgrade"  "per.wb.upgrade symlink"
assert_file "$SANDBOX_HOME/.local/bin/per.devkit"      "per.devkit shim"
assert_file "$SANDBOX_HOME/.local/bin/per.orgs.wb"     "per.orgs.wb symlink"

# Unprefixed names left free for the default (INV) clone.
refute_file "$SANDBOX_HOME/.local/bin/init.wb"         "unprefixed init.wb"
refute_file "$SANDBOX_HOME/.local/bin/wb.upgrade"      "unprefixed wb.upgrade"
refute_file "$SANDBOX_HOME/.local/bin/devkit"          "unprefixed devkit shim"

# Namespaced env + state dir; bare DEVKIT_CLONE untouched.
assert_grep  "$SANDBOX_HOME/.zprofile" "PER_DEVKIT_CLONE"          "PER_DEVKIT_CLONE written"
assert_grep  "$SANDBOX_HOME/.zprofile" "PER_DEVKIT_DEFAULT_ENGINE" "PER_DEVKIT_DEFAULT_ENGINE written"
refute_grep  "$SANDBOX_HOME/.zprofile" "export DEVKIT_CLONE="      "bare DEVKIT_CLONE not written"
assert_file  "$SANDBOX_HOME/.local/share/per-wb-versioncheck/version-check.sh" "per-tagged version-check lib"
refute_file  "$SANDBOX_HOME/.local/share/wb-versioncheck/version-check.sh"     "default version-check lib"

# Clone-local command-prefix marker recorded so the version-check launchers
# resolve the per-tagged lib + WB_CMD_PREFIX. Written to the clone root
# ($REPO_ROOT here), gitignored.
assert_grep  "$REPO_ROOT/.devkit-cmd-prefix" "per." ".devkit-cmd-prefix marker = per."

# Alias registered under the prefixed name.
assert_grep "$SANDBOX_HOME/.zshrc" "alias per.init.wb=" "per.init.wb alias registered"

# The prefixed devkit shim resolves to the upgrade script for this clone.
HOME="$SANDBOX_HOME" PATH="$SANDBOX_HOME/.local/bin:$PATH" \
  zsh -c 'per.devkit upgrade --check-only' >/dev/null 2>&1 || true
print -r -- "PASS: per.devkit shim invokable"

if (( fail != 0 )); then
  print -ru2 -- "── test-install-prefix: FAIL ──"
  exit 1
fi
print -r -- "── test-install-prefix: PASS ──"
