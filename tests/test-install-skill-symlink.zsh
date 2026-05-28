#!/usr/bin/env zsh
# test-install-skill-symlink.zsh — Hermetic test for install.zsh's multi-engine
# skill symlink stanza and DEVKIT_DEFAULT_ENGINE env-var write.
#
# Asserts:
#   1. ~/.claude/skills/repo-context-scan symlinks to fake DEVKIT skill source.
#   2. ~/.devin/skills/repo-context-scan symlinks to fake DEVKIT skill source.
#   3. ~/.agents/skills/repo-context-scan symlinks to fake DEVKIT skill source.
#   4. ${DEVKIT}/.claude/skills/repo-context-scan symlink exists (internal).
#   5. ${DEVKIT}/.agents/skills/repo-context-scan symlink exists (internal).
#   6. ~/.zprofile contains export DEVKIT_DEFAULT_ENGINE="claude" when devin is
#      not on PATH.
#   7. Sub-test: when a fake devin shim is on PATH, env value is "devin".
#   8. Re-running install.zsh leaves exactly one DEVKIT_DEFAULT_ENGINE line.
#
# Hermetic: HOME is overridden to a tempdir; PATH is narrowed to /usr/bin:/bin
# (plus an optional shim dir) so the real user's environment is untouched.
#
# Run: zsh tests/test-install-skill-symlink.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
REAL_INSTALL="${REPO_ROOT}/install.zsh"

[[ -f "$REAL_INSTALL" ]] || { print -u2 "FAIL: $REAL_INSTALL not found"; exit 1; }

TMP_ROOT="$(mktemp -d -t install-skill-symlink.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# ── Build a minimal hermetic fake DEVKIT clone ───────────────────────────────
fake_devkit="$TMP_ROOT/devkit"
mkdir -p \
  "$fake_devkit/skills/repo-context-scan" \
  "$fake_devkit/lib" \
  "$fake_devkit/init-workbench" \
  "$fake_devkit/join-workbench" \
  "$fake_devkit/update-workbench" \
  "$fake_devkit/init-test-workbench" \
  "$fake_devkit/join-test-workbench" \
  "$fake_devkit/update-test-workbench" \
  "$fake_devkit/devkit-doctor" \
  "$fake_devkit/devkit-upgrade" \
  "$fake_devkit/orgs-workbench"

cp "$REAL_INSTALL" "$fake_devkit/install.zsh"

# install.zsh distributes these two lib files into ~/.local/share/wb-versioncheck.
cp "${REPO_ROOT}/lib/version-check.sh"       "$fake_devkit/lib/version-check.sh"
cp "${REPO_ROOT}/lib/bootstrap-detection.sh" "$fake_devkit/lib/bootstrap-detection.sh"

# Stub minimal entry-point zsh files. install.zsh chmods +x these.
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/init-workbench/init.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/join-workbench/join.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/update-workbench/update.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/init-test-workbench/init.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/join-test-workbench/join.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/update-test-workbench/update.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/devkit-doctor/devkit-doctor.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/devkit-upgrade/devkit-upgrade.zsh"
print -r -- '#!/usr/bin/env zsh' > "$fake_devkit/orgs-workbench/orgs.zsh"

# Mock vendored skill body so we can assert the symlink resolves to a real file.
print -r -- '# SKILL' > "$fake_devkit/skills/repo-context-scan/SKILL.md"

# ── Sub-test A: no devin on PATH → DEFAULT_ENGINE=claude ────────────────────
fake_home_a="$TMP_ROOT/home-a"
mkdir -p "$fake_home_a"

# Narrow PATH so devin is NOT visible. Keep /usr/bin:/bin for core utils
# install.zsh relies on (grep, mktemp, mv, cp, mkdir, chmod, ln, printf).
HOME="$fake_home_a" PATH="/usr/bin:/bin" zsh "$fake_devkit/install.zsh" >/dev/null

skill_src="$fake_devkit/skills/repo-context-scan"

assert_symlink_to() {
  local link="$1" expected="$2"
  [[ -L "$link" ]] || { print -u2 "FAIL: $link is not a symlink"; exit 1; }
  local resolved="${link:A}"
  if [[ "$resolved" != "${expected:A}" ]]; then
    print -u2 "FAIL: $link"
    print -u2 "  expected target: ${expected:A}"
    print -u2 "  got:             $resolved"
    exit 1
  fi
}

assert_symlink_to "$fake_home_a/.claude/skills/repo-context-scan" "$skill_src"
assert_symlink_to "$fake_home_a/.devin/skills/repo-context-scan"  "$skill_src"
assert_symlink_to "$fake_home_a/.agents/skills/repo-context-scan" "$skill_src"
print -r -- "PASS: user-side skill symlinks resolve to vendored skill source"

assert_symlink_to "$fake_devkit/.claude/skills/repo-context-scan" "$skill_src"
assert_symlink_to "$fake_devkit/.agents/skills/repo-context-scan" "$skill_src"
print -r -- "PASS: devkit-internal skill symlinks resolve to vendored skill source"

# Verify the resolved target actually points at the SKILL.md we wrote — proves
# the link is functional, not just syntactically present.
[[ -f "$fake_home_a/.claude/skills/repo-context-scan/SKILL.md" ]] \
  || { print -u2 "FAIL: SKILL.md not reachable through ~/.claude symlink"; exit 1; }
print -r -- "PASS: SKILL.md reachable through ~/.claude/skills symlink"

zprofile_a="$fake_home_a/.zprofile"
[[ -f "$zprofile_a" ]] || { print -u2 "FAIL: $zprofile_a not created"; exit 1; }
if ! grep -qFx 'export DEVKIT_DEFAULT_ENGINE="claude"' "$zprofile_a"; then
  print -u2 "FAIL: expected DEVKIT_DEFAULT_ENGINE=claude in $zprofile_a"
  print -u2 "  contents:"
  print -u2 -r -- "$(< $zprofile_a)"
  exit 1
fi
print -r -- "PASS: ~/.zprofile contains DEVKIT_DEFAULT_ENGINE=claude (no devin on PATH)"

# ── Sub-test B: idempotency — re-run, no duplicate env lines ────────────────
HOME="$fake_home_a" PATH="/usr/bin:/bin" zsh "$fake_devkit/install.zsh" >/dev/null

clone_count="$(grep -c '^export DEVKIT_CLONE=' "$zprofile_a" || true)"
engine_count="$(grep -c '^export DEVKIT_DEFAULT_ENGINE=' "$zprofile_a" || true)"
[[ "$clone_count"  == "1" ]] || { print -u2 "FAIL: DEVKIT_CLONE appears $clone_count times in $zprofile_a"; exit 1; }
[[ "$engine_count" == "1" ]] || { print -u2 "FAIL: DEVKIT_DEFAULT_ENGINE appears $engine_count times in $zprofile_a"; exit 1; }
print -r -- "PASS: re-running install.zsh leaves exactly one of each env line"

# Symlinks still resolve after the second run.
assert_symlink_to "$fake_home_a/.claude/skills/repo-context-scan" "$skill_src"
assert_symlink_to "$fake_home_a/.devin/skills/repo-context-scan"  "$skill_src"
assert_symlink_to "$fake_home_a/.agents/skills/repo-context-scan" "$skill_src"
print -r -- "PASS: symlinks still resolve after re-run"

# ── Sub-test C: fake devin shim on PATH → DEFAULT_ENGINE=devin ──────────────
fake_home_b="$TMP_ROOT/home-b"
mkdir -p "$fake_home_b"

shim_bin="$TMP_ROOT/shim-bin"
mkdir -p "$shim_bin"
print -r -- '#!/usr/bin/env zsh' > "$shim_bin/devin"
print -r -- 'exit 0'              >> "$shim_bin/devin"
chmod +x "$shim_bin/devin"

HOME="$fake_home_b" PATH="$shim_bin:/usr/bin:/bin" zsh "$fake_devkit/install.zsh" >/dev/null

zprofile_b="$fake_home_b/.zprofile"
if ! grep -qFx 'export DEVKIT_DEFAULT_ENGINE="devin"' "$zprofile_b"; then
  print -u2 "FAIL: expected DEVKIT_DEFAULT_ENGINE=devin in $zprofile_b"
  print -u2 "  contents:"
  print -u2 -r -- "$(< $zprofile_b)"
  exit 1
fi
print -r -- "PASS: ~/.zprofile contains DEVKIT_DEFAULT_ENGINE=devin (devin shim on PATH)"

# ── Sub-test D: stale-engine line is stripped, not stacked ──────────────────
# Manually corrupt the env line, re-run, assert exactly one (correct) line.
fake_home_c="$TMP_ROOT/home-c"
mkdir -p "$fake_home_c"
print -r -- '# === EXTERNAL PROJECT ALIASES ===' > "$fake_home_c/.zprofile"
print -r -- 'export DEVKIT_DEFAULT_ENGINE="stale"' >> "$fake_home_c/.zprofile"

HOME="$fake_home_c" PATH="/usr/bin:/bin" zsh "$fake_devkit/install.zsh" >/dev/null

# grep -c exits 1 when matches=0; trailing || true keeps set -e happy.
stale_count="$(grep -c '^export DEVKIT_DEFAULT_ENGINE="stale"' "$fake_home_c/.zprofile" || true)"
fresh_count="$(grep -c '^export DEVKIT_DEFAULT_ENGINE="claude"' "$fake_home_c/.zprofile" || true)"
total_count="$(grep -c '^export DEVKIT_DEFAULT_ENGINE=' "$fake_home_c/.zprofile" || true)"
[[ "$stale_count" == "0" ]] || { print -u2 "FAIL: stale DEVKIT_DEFAULT_ENGINE line not stripped"; exit 1; }
[[ "$fresh_count" == "1" ]] || { print -u2 "FAIL: expected one claude line, got $fresh_count"; exit 1; }
[[ "$total_count" == "1" ]] || { print -u2 "FAIL: expected exactly one DEVKIT_DEFAULT_ENGINE line, got $total_count"; exit 1; }
print -r -- "PASS: stale DEVKIT_DEFAULT_ENGINE line stripped, replaced by fresh"

print -r -- "All install-skill-symlink tests passed."
