#!/usr/bin/env zsh
# test-orgs-symlink.zsh — Regression test for orgs.wb symlink resolution.
#
# Bug: orgs.zsh derived DEVKIT_ROOT from `dirname $0`, which on a PATH-installed
# symlink (e.g. ~/.local/bin/orgs.wb) resolved to ~/.local instead of the repo
# root and tried to source ~/.local/lib/orgs.sh (does not exist). Fixed by
# resolving the symlink with zsh's ${0:A}.
#
# Run: zsh tests/test-orgs-symlink.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DEVKIT_ROOT="${SCRIPT_DIR:h}"
ORGS_REAL="${DEVKIT_ROOT}/orgs-workbench/orgs.zsh"
EXPECTED_CONF="${DEVKIT_ROOT}/orgs.conf"

[[ -x "$ORGS_REAL" ]] || { print -u2 "FAIL: $ORGS_REAL not executable"; exit 1; }

TMP_ROOT="$(mktemp -d -t orgswb-test.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Mimic what install.zsh does: symlink orgs.wb into a bin/ sibling that does
# NOT have a sister lib/ dir (the failure mode Devin flagged).
mkdir -p "$TMP_ROOT/bin"
ln -sf "$ORGS_REAL" "$TMP_ROOT/bin/orgs.wb"

# `path` exercises devkit_orgs_file, which depends on DEVKIT_ROOT being correct.
got_path="$("$TMP_ROOT/bin/orgs.wb" path)"
if [[ "$got_path" != "$EXPECTED_CONF" ]]; then
  print -u2 "FAIL: orgs.wb path via symlink"
  print -u2 "  expected: $EXPECTED_CONF"
  print -u2 "  got:      $got_path"
  exit 1
fi
print "PASS: orgs.wb resolves DEVKIT_ROOT correctly when invoked via symlink"

# `auto` exercises devkit_auto_org, which runs git in DEVKIT_ROOT — a second
# witness that DEVKIT_ROOT points at the real repo, not at $TMP_ROOT.
got_auto="$("$TMP_ROOT/bin/orgs.wb" auto)"
if [[ -z "$got_auto" ]]; then
  print -u2 "FAIL: orgs.wb auto returned empty (DEVKIT_ROOT not a git repo?)"
  exit 1
fi
print "PASS: orgs.wb auto resolves to '$got_auto' via symlink"

# `list` exercises full pipeline (file read + auto append).
got_list="$("$TMP_ROOT/bin/orgs.wb" list)"
if [[ -z "$got_list" ]]; then
  print -u2 "FAIL: orgs.wb list returned empty"
  exit 1
fi
print "PASS: orgs.wb list non-empty via symlink"

# Also confirm direct invocation (no symlink) still works — guard against a
# regression where the symlink fix breaks the non-symlink path.
got_direct="$("$ORGS_REAL" path)"
if [[ "$got_direct" != "$EXPECTED_CONF" ]]; then
  print -u2 "FAIL: orgs.zsh path via direct invocation"
  print -u2 "  expected: $EXPECTED_CONF"
  print -u2 "  got:      $got_direct"
  exit 1
fi
print "PASS: orgs.zsh resolves DEVKIT_ROOT correctly when invoked directly"

print "All orgs-symlink tests passed."
