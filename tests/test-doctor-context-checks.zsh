#!/usr/bin/env zsh
# test-doctor-context-checks.zsh — Hermetic test for devkit-doctor Phase 4
# health checks (skill vendoring, engine symlinks, wb-context-scan lib presence,
# DEVKIT_DEFAULT_ENGINE env var, engine availability) and WB-scope checks
# (context/ shape, stale stubs, aggregate README freshness, .context-scan/
# worktree cleanliness).
#
# Sub-tests:
#  1. All-green global state → doctor exits 0.
#  2. Skill missing            → --check-only nonzero + "repo-context-scan vendored FAIL".
#  3. Engine symlink broken    → FAIL row.
#  4. wb-context-scan lib gone → FAIL row.
#  5. DEVKIT_DEFAULT_ENGINE unset (with everything else clean) → WARN; --check-only exits 0.
#  6. Engine binary missing    → WARN.
#  7. WB-scope: context/<repo> missing for project.conf entry → WARN with "missing".
#  8. WB-scope: scan-failed stub → WARN reporting stub count.
#  9. WB-scope: .context-scan/<repo>/ non-empty → WARN reporting stale worktree.
# 10. Default (non-check-only) output prints vendored skill SHA banner.
#
# Hermetic: all paths under TMP_ROOT, HOME overridden, WB_UPDATES_CACHE_DIR
# pre-populated to avoid network fetches.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
REAL_DOCTOR="${REPO_ROOT}/devkit-doctor/devkit-doctor.zsh"

[[ -f "$REAL_DOCTOR" ]] || { print -u2 "FAIL: $REAL_DOCTOR not found"; exit 1; }

TMP_ROOT="$(mktemp -d -t doctor-context-checks.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# ─── Build a hermetic fake DEVKIT clone ─────────────────────────────────
# Doctor resolves SCRIPT_DIR from its own location, then DEVKIT_DIR from
# SCRIPT_DIR:h. Symlink/copy real artifacts so all path lookups resolve.

build_fake_devkit() {
  local devkit="$1"
  mkdir -p \
    "$devkit/devkit-doctor" \
    "$devkit/lib" \
    "$devkit/skills/repo-context-scan" \
    "$devkit/scripts" \
    "$devkit/.claude/skills" \
    "$devkit/.agents/skills"

  # Doctor script
  cp "$REAL_DOCTOR" "$devkit/devkit-doctor/devkit-doctor.zsh"

  # Required libs
  cp "${REPO_ROOT}/lib/version-check.sh"        "$devkit/lib/"
  cp "${REPO_ROOT}/lib/bootstrap-detection.sh"  "$devkit/lib/"
  cp "${REPO_ROOT}/lib/wb-context-scan.zsh"     "$devkit/lib/"
  chmod +x "$devkit/lib/wb-context-scan.zsh"

  # Vendored skill body + .upstream pin
  print -r -- '# SKILL' > "$devkit/skills/repo-context-scan/SKILL.md"
  cat > "$devkit/skills/repo-context-scan/.upstream" <<UP
upstream_repo: https://github.com/amit-t/skills
upstream_sha:  afe1768eeb216eb14934866b48b82ab7de5753aa
synced_at:     2026-05-13T09:22:18Z
synced_by:     test
UP

  # Sync script (executable, used by --fix path; not invoked here).
  cat > "$devkit/scripts/sync-skill.zsh" <<'SH'
#!/usr/bin/env zsh
print -r -- "[stub] sync-skill.zsh invoked: $*"
SH
  chmod +x "$devkit/scripts/sync-skill.zsh"

  # Internal symlinks (matching install.zsh's stanza).
  ln -sfn "$devkit/skills/repo-context-scan" "$devkit/.claude/skills/repo-context-scan"
  ln -sfn "$devkit/skills/repo-context-scan" "$devkit/.agents/skills/repo-context-scan"

  # version.json (for any version-check side effects).
  print -r -- '{"version":"1.0.0"}' > "$devkit/version.json"
}

build_fake_home() {
  local home_dir="$1" skill_src="$2"
  mkdir -p \
    "$home_dir/.claude/skills" \
    "$home_dir/.devin/skills" \
    "$home_dir/.agents/skills"
  ln -sfn "$skill_src" "$home_dir/.claude/skills/repo-context-scan"
  ln -sfn "$skill_src" "$home_dir/.devin/skills/repo-context-scan"
  ln -sfn "$skill_src" "$home_dir/.agents/skills/repo-context-scan"

  # .zprofile present with DEVKIT_DEFAULT_ENGINE (display only; doctor reads
  # the live env var, not the file — env is set inline per invocation).
  cat > "$home_dir/.zprofile" <<ZP
export DEVKIT_DEFAULT_ENGINE="claude"
ZP
}

# Pre-populate the version-check cache so doctor does NOT hit the network.
populate_cache() {
  local cache_dir="$1"
  mkdir -p "$cache_dir"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$cache_dir/devkit.json" <<JSON
{"tool":"devkit","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.0.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}}
JSON
  cat > "$cache_dir/ralph.json" <<JSON
{"tool":"ralph","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.0.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}}
JSON
  cat > "$cache_dir/wb.json" <<JSON
{"tool":"wb","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.0.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}}
JSON
}

# A fake "claude" engine binary so the engine-available check passes.
build_fake_engine_shim() {
  local shim_dir="$1"
  mkdir -p "$shim_dir"
  print -r -- '#!/usr/bin/env zsh' > "$shim_dir/claude"
  print -r -- 'exit 0'             >> "$shim_dir/claude"
  chmod +x "$shim_dir/claude"
}

# Fake ralph clone (doctor calls _wb_local_version which reads version.json).
build_fake_ralph() {
  local ralph_dir="$1"
  mkdir -p "$ralph_dir"
  print -r -- '{"version":"1.0.0"}' > "$ralph_dir/version.json"
}

# Run doctor with hermetic env. Returns its stdout+stderr; exit captured by caller.
run_doctor() {
  local devkit="$1" home_dir="$2" cache_dir="$3" shim_dir="$4"
  local ralph_dir="$5"
  shift 5
  HOME="$home_dir" \
  PATH="$shim_dir:/usr/bin:/bin" \
  DEVKIT_CLONE="$devkit" \
  RALPH_CLONE="$ralph_dir" \
  WB_UPDATES_CACHE_DIR="$cache_dir" \
  DEVKIT_DEFAULT_ENGINE="claude" \
    zsh "$devkit/devkit-doctor/devkit-doctor.zsh" "$@" 2>&1
}

# Variant for explicit env overrides (Sub-tests 5, 6).
run_doctor_env() {
  local devkit="$1" home_dir="$2" cache_dir="$3" shim_dir="$4"
  local ralph_dir="$5" engine_override="$6"
  shift 6
  if [[ -n "$engine_override" ]]; then
    HOME="$home_dir" \
    PATH="$shim_dir:/usr/bin:/bin" \
    DEVKIT_CLONE="$devkit" \
    RALPH_CLONE="$ralph_dir" \
    WB_UPDATES_CACHE_DIR="$cache_dir" \
    DEVKIT_DEFAULT_ENGINE="$engine_override" \
      zsh "$devkit/devkit-doctor/devkit-doctor.zsh" "$@" 2>&1
  else
    # Explicitly unset DEVKIT_DEFAULT_ENGINE — env -i would nuke everything,
    # so we use env -u to surgically remove just that var.
    HOME="$home_dir" \
    PATH="$shim_dir:/usr/bin:/bin" \
    DEVKIT_CLONE="$devkit" \
    RALPH_CLONE="$ralph_dir" \
    WB_UPDATES_CACHE_DIR="$cache_dir" \
      env -u DEVKIT_DEFAULT_ENGINE zsh "$devkit/devkit-doctor/devkit-doctor.zsh" "$@" 2>&1
  fi
}

# ─── Shared baseline fixtures (rebuilt per sub-test as needed) ──────────
baseline() {
  local label="$1"
  local root="$TMP_ROOT/$label"
  mkdir -p "$root"
  local devkit="$root/devkit"
  local home_dir="$root/home"
  local cache="$root/cache"
  local shim="$root/shim"
  local ralph="$root/ralph"
  build_fake_devkit "$devkit"
  build_fake_home "$home_dir" "$devkit/skills/repo-context-scan"
  populate_cache "$cache"
  build_fake_engine_shim "$shim"
  build_fake_ralph "$ralph"
  print -r -- "$root"
}

# ─── Sub-test 1: all-green ──────────────────────────────────────────────
root1="$(baseline t1)"
out1="$(run_doctor "$root1/devkit" "$root1/home" "$root1/cache" "$root1/shim" "$root1/ralph" --check-only)" || {
  print -u2 "FAIL: sub-test 1 expected exit 0, got nonzero"
  print -u2 -r -- "$out1"
  exit 1
}
case "$out1" in
  *"repo-context-scan vendored"*"OK"*) ;;
  *) print -u2 "FAIL: sub-test 1 missing 'repo-context-scan vendored OK'"; print -u2 -r -- "$out1"; exit 1 ;;
esac
case "$out1" in
  *"engine symlinks intact"*"OK"*"5/5 resolve"*) ;;
  *) print -u2 "FAIL: sub-test 1 missing '5/5 resolve'"; print -u2 -r -- "$out1"; exit 1 ;;
esac
case "$out1" in
  *"wb-context-scan lib"*"OK"*) ;;
  *) print -u2 "FAIL: sub-test 1 missing 'wb-context-scan lib OK'"; print -u2 -r -- "$out1"; exit 1 ;;
esac
print -r -- "PASS: sub-test 1 — all-green global health, exit 0"

# ─── Sub-test 2: skill SKILL.md deleted ─────────────────────────────────
root2="$(baseline t2)"
rm -f "$root2/devkit/skills/repo-context-scan/SKILL.md"
set +e
out2="$(run_doctor "$root2/devkit" "$root2/home" "$root2/cache" "$root2/shim" "$root2/ralph" --check-only)"
exit2=$?
set -e
if (( exit2 == 0 )); then
  print -u2 "FAIL: sub-test 2 expected nonzero exit, got 0"
  print -u2 -r -- "$out2"
  exit 1
fi
case "$out2" in
  *"repo-context-scan vendored"*"FAIL"*) ;;
  *) print -u2 "FAIL: sub-test 2 missing 'repo-context-scan vendored FAIL'"; print -u2 -r -- "$out2"; exit 1 ;;
esac
print -r -- "PASS: sub-test 2 — missing SKILL.md → FAIL + nonzero exit"

# ─── Sub-test 3: broken engine symlink ──────────────────────────────────
root3="$(baseline t3)"
# Unlink the ~/.claude/skills symlink, replace with a dangling link.
rm -f "$root3/home/.claude/skills/repo-context-scan"
ln -s "$TMP_ROOT/nonexistent-target" "$root3/home/.claude/skills/repo-context-scan"
set +e
out3="$(run_doctor "$root3/devkit" "$root3/home" "$root3/cache" "$root3/shim" "$root3/ralph" --check-only)"
exit3=$?
set -e
if (( exit3 == 0 )); then
  print -u2 "FAIL: sub-test 3 expected nonzero exit, got 0"
  print -u2 -r -- "$out3"
  exit 1
fi
case "$out3" in
  *"engine symlinks intact"*"FAIL"*) ;;
  *) print -u2 "FAIL: sub-test 3 missing 'engine symlinks intact FAIL'"; print -u2 -r -- "$out3"; exit 1 ;;
esac
print -r -- "PASS: sub-test 3 — broken engine symlink → FAIL + nonzero exit"

# ─── Sub-test 4: wb-context-scan lib missing ────────────────────────────
root4="$(baseline t4)"
rm -f "$root4/devkit/lib/wb-context-scan.zsh"
set +e
out4="$(run_doctor "$root4/devkit" "$root4/home" "$root4/cache" "$root4/shim" "$root4/ralph" --check-only)"
exit4=$?
set -e
if (( exit4 == 0 )); then
  print -u2 "FAIL: sub-test 4 expected nonzero exit, got 0"
  print -u2 -r -- "$out4"
  exit 1
fi
case "$out4" in
  *"wb-context-scan lib"*"FAIL"*) ;;
  *) print -u2 "FAIL: sub-test 4 missing 'wb-context-scan lib FAIL'"; print -u2 -r -- "$out4"; exit 1 ;;
esac
print -r -- "PASS: sub-test 4 — missing lib → FAIL + nonzero exit"

# ─── Sub-test 5: DEVKIT_DEFAULT_ENGINE unset (WARN only, --check-only OK) ─
root5="$(baseline t5)"
set +e
out5="$(run_doctor_env "$root5/devkit" "$root5/home" "$root5/cache" "$root5/shim" "$root5/ralph" "" --check-only)"
exit5=$?
set -e
case "$out5" in
  *"DEVKIT_DEFAULT_ENGINE set"*"WARN"*"not set"*) ;;
  *) print -u2 "FAIL: sub-test 5 missing 'DEVKIT_DEFAULT_ENGINE set WARN ... not set'"; print -u2 -r -- "$out5"; exit 1 ;;
esac
if (( exit5 != 0 )); then
  print -u2 "FAIL: sub-test 5 expected exit 0 (WARN doesn't count), got $exit5"
  print -u2 -r -- "$out5"
  exit 1
fi
print -r -- "PASS: sub-test 5 — DEVKIT_DEFAULT_ENGINE unset → WARN, exit 0"

# ─── Sub-test 6: engine binary missing ─────────────────────────────────
root6="$(baseline t6)"
# Point at a binary that doesn't exist on PATH.
set +e
out6="$(run_doctor_env "$root6/devkit" "$root6/home" "$root6/cache" "$root6/shim" "$root6/ralph" "nosuchbinary42" --check-only)"
exit6=$?
set -e
case "$out6" in
  *"engine available"*"WARN"*"nosuchbinary42"*"not on PATH"*) ;;
  *) print -u2 "FAIL: sub-test 6 missing 'engine available WARN nosuchbinary42 not on PATH'"; print -u2 -r -- "$out6"; exit 1 ;;
esac
if (( exit6 != 0 )); then
  print -u2 "FAIL: sub-test 6 expected exit 0 (WARN doesn't count), got $exit6"
  print -u2 -r -- "$out6"
  exit 1
fi
print -r -- "PASS: sub-test 6 — missing engine binary → WARN, exit 0"

# ─── Sub-test 7: WB-scope missing context dir ──────────────────────────
root7="$(baseline t7)"
wb7="$root7/wb"
mkdir -p "$wb7/context" "$wb7/.workbench-state"
# Stamped WB: needs .workbench-manifest.json + project.conf.
print -r -- '{}' > "$wb7/.workbench-manifest.json"
cat > "$wb7/project.conf" <<CONF
REPOS=(
  "name=a;role=app;url=https://example.com/a"
)
CONF
# Note: context/a/ is intentionally absent → "1 missing".
set +e
out7="$(cd "$wb7" && run_doctor "$root7/devkit" "$root7/home" "$root7/cache" "$root7/shim" "$root7/ralph")"
exit7=$?
set -e
case "$out7" in
  *"context/ matches project.conf"*"WARN"*"1 missing"*) ;;
  *) print -u2 "FAIL: sub-test 7 missing 'context/ matches project.conf WARN ... 1 missing'"; print -u2 -r -- "$out7"; exit 1 ;;
esac
print -r -- "PASS: sub-test 7 — missing context dir for REPOS entry → 1 missing"

# ─── Sub-test 8: stale stub ─────────────────────────────────────────────
root8="$(baseline t8)"
wb8="$root8/wb"
mkdir -p "$wb8/context/a" "$wb8/.workbench-state"
print -r -- '{}' > "$wb8/.workbench-manifest.json"
cat > "$wb8/project.conf" <<CONF
REPOS=(
  "name=a;role=app;url=https://example.com/a"
)
CONF
cat > "$wb8/context/a/CONTEXT.md" <<MD
---
status:         scan-failed
fail_reason:    "test failure"
---
# a (scan failed)
MD
# Make README.md fresh to avoid noise on WB-Check 4.
touch "$wb8/context/README.md"
sleep 1
# README must be newer than CONTEXT.md for WB-4 to pass cleanly.
touch "$wb8/context/README.md"
set +e
out8="$(cd "$wb8" && run_doctor "$root8/devkit" "$root8/home" "$root8/cache" "$root8/shim" "$root8/ralph")"
exit8=$?
set -e
case "$out8" in
  *"no stale stubs"*"WARN"*"1 stubs"*"a"*) ;;
  *) print -u2 "FAIL: sub-test 8 missing 'no stale stubs WARN 1 stubs a'"; print -u2 -r -- "$out8"; exit 1 ;;
esac
print -r -- "PASS: sub-test 8 — scan-failed stub → WB-Check 3 reports 1 stub"

# ─── Sub-test 9: non-empty .context-scan/ ──────────────────────────────
root9="$(baseline t9)"
wb9="$root9/wb"
mkdir -p "$wb9/context/a" "$wb9/.workbench-state" "$wb9/.context-scan/foo"
print -r -- '{}' > "$wb9/.workbench-manifest.json"
cat > "$wb9/project.conf" <<CONF
REPOS=(
  "name=a;role=app;url=https://example.com/a"
)
CONF
print -r -- "leftover" > "$wb9/.context-scan/foo/file"
# Provide a CONTEXT.md and current README so other WB-checks are clean.
cat > "$wb9/context/a/CONTEXT.md" <<MD
---
status:         scanned
---
# a
MD
touch "$wb9/context/README.md"
sleep 1
touch "$wb9/context/README.md"
set +e
out9="$(cd "$wb9" && run_doctor "$root9/devkit" "$root9/home" "$root9/cache" "$root9/shim" "$root9/ralph")"
exit9=$?
set -e
case "$out9" in
  *".context-scan/ worktree clean"*"WARN"*"1 stale worktree"*"foo"*) ;;
  *) print -u2 "FAIL: sub-test 9 missing '.context-scan/ worktree clean WARN 1 stale worktree foo'"; print -u2 -r -- "$out9"; exit 1 ;;
esac
print -r -- "PASS: sub-test 9 — leftover .context-scan/foo → stale worktree reported"

# ─── Sub-test 10: vendored skill SHA banner appears in non-check-only ──
root10="$(baseline t10)"
set +e
out10="$(run_doctor "$root10/devkit" "$root10/home" "$root10/cache" "$root10/shim" "$root10/ralph")"
exit10=$?
set -e
case "$out10" in
  *"Vendored skill: repo-context-scan @ afe1768eeb21"*) ;;
  *) print -u2 "FAIL: sub-test 10 missing 'Vendored skill: repo-context-scan @ afe1768eeb21'"; print -u2 -r -- "$out10"; exit 1 ;;
esac
print -r -- "PASS: sub-test 10 — vendored skill SHA banner present in default output"

print -r -- "All doctor-context-checks tests passed."
