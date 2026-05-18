#!/usr/bin/env zsh
# test-update-migrations.zsh — Lock in wb.upgrade migration blocks for
# ai-workbench PRs feat/dispatch-engine-routing and feat/stub-purge-stack.
#
# Covers:
#   A. RALPH_EXECUTION_ENGINE migration — key appended with value of
#      RALPH_PLAN_ENGINE, idempotent on second run.
#   B. Stub .ralph/ purge — wb-root .ralph/ moved to .ralph.purged.<ts>/,
#      source removed, idempotent on second run.
#   C. Stub .ralph/ purge no-op — when no stub is present, no backup is
#      created.
#
# Strategy: extract the two migration blocks from update.zsh by sourcing
# update.zsh with a stub envelope is fragile (the script runs end-to-end
# against a real git repo and remote). Instead, embed the same logic here
# in a helper function and exercise it. The migration block contents
# remain a single source of truth in update.zsh; this test asserts the
# expected post-state shape that the script must produce. To guard against
# drift between update.zsh and this test, an additional check greps
# update.zsh for the two migration headers — if either header text is
# renamed in update.zsh, this test fails fast pointing at the test
# to be updated.
#
# Run: zsh tests/test-update-migrations.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DEVKIT_ROOT="${SCRIPT_DIR:h}"
UPDATE_ZSH="${DEVKIT_ROOT}/update-workbench/update.zsh"

[[ -f "$UPDATE_ZSH" ]] || { print -u2 -- "FAIL: $UPDATE_ZSH missing"; exit 1; }

# ── Drift guard: assert the migration block headers are present ─────────────
if ! grep -q 'RALPH_EXECUTION_ENGINE migration (idempotent)' "$UPDATE_ZSH"; then
  print -u2 -- "FAIL: update.zsh missing 'RALPH_EXECUTION_ENGINE migration (idempotent)' header"
  exit 1
fi
if ! grep -q 'Stub \.ralph/ purge (idempotent)' "$UPDATE_ZSH"; then
  print -u2 -- "FAIL: update.zsh missing 'Stub .ralph/ purge (idempotent)' header"
  exit 1
fi
print -- "PASS: drift guard — both migration headers present in update.zsh"

# ── Migration helpers (mirror of update.zsh logic) ──────────────────────────
# These are functional replicas of the two new blocks in update.zsh, sharing
# the same WB_DIR contract. Keep them byte-for-byte equivalent to the
# script (modulo the leading `local` keyword, which would require a function
# scope in the host script — already true in update.zsh).
_migrate_exec_engine() {
  local WB_DIR="$1"
  if [[ -f "${WB_DIR}/project.conf" ]]; then
    if ! grep -q '^RALPH_EXECUTION_ENGINE=' "${WB_DIR}/project.conf"; then
      local _plan_engine
      _plan_engine="$(grep '^RALPH_PLAN_ENGINE=' "${WB_DIR}/project.conf" 2>/dev/null \
                        | head -1 \
                        | sed -E 's/^RALPH_PLAN_ENGINE="?([^"]*)"?.*/\1/' || true)"
      [[ -z "$_plan_engine" ]] && _plan_engine="devin"
      cat >> "${WB_DIR}/project.conf" <<EOF

# Added by wb.upgrade $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Execution engine for wb.ralph-dispatch (loop / execute phase). Initially set
# to match RALPH_PLAN_ENGINE so behavior is preserved; flip to "devin" for cheap
# parallel workers in workspace mode, or mix engines (plan with one, exec with
# another). Valid values: claude | devin | codex.
RALPH_EXECUTION_ENGINE="$_plan_engine"
EOF
    fi
  fi
}

_migrate_stub_ralph_purge() {
  local WB_DIR="$1"
  if [[ -f "${WB_DIR}/project.conf" && -d "${WB_DIR}/.ralph" ]]; then
    local _ts _backup
    _ts="$(date +%s)"
    _backup="${WB_DIR}/.ralph.purged.${_ts}"
    mv "${WB_DIR}/.ralph" "$_backup"
  fi
}

# ── Migration A: RALPH_EXECUTION_ENGINE append + idempotent ─────────────────
TMP_A="$(mktemp -d -t wb-mig-a.XXXXXX)"
trap 'rm -rf "$TMP_A" "${TMP_B:-}" "${TMP_C:-}"' EXIT

cat > "${TMP_A}/project.conf" <<'PCONF'
WB_LABEL="test"
RALPH_PLAN_ENGINE="claude"
PCONF

_migrate_exec_engine "$TMP_A"

if ! grep -q '^RALPH_EXECUTION_ENGINE="claude"' "${TMP_A}/project.conf"; then
  print -u2 -- "FAIL: Migration A did not append RALPH_EXECUTION_ENGINE=claude"
  print -u2 -- "  project.conf contents:"
  cat "${TMP_A}/project.conf" >&2
  exit 1
fi
print -- "PASS: Migration A — RALPH_EXECUTION_ENGINE appended with RALPH_PLAN_ENGINE value"

# Run again — must NOT double-append.
_migrate_exec_engine "$TMP_A"
exec_count="$(grep -c '^RALPH_EXECUTION_ENGINE=' "${TMP_A}/project.conf")"
if (( exec_count != 1 )); then
  print -u2 -- "FAIL: Migration A not idempotent — RALPH_EXECUTION_ENGINE appears $exec_count times after second run"
  exit 1
fi
print -- "PASS: Migration A idempotent (one RALPH_EXECUTION_ENGINE line after re-run)"

# Edge case: missing RALPH_PLAN_ENGINE → default to "devin".
TMP_A2="$(mktemp -d -t wb-mig-a2.XXXXXX)"
print 'WB_LABEL="test"' > "${TMP_A2}/project.conf"
_migrate_exec_engine "$TMP_A2"
if ! grep -q '^RALPH_EXECUTION_ENGINE="devin"' "${TMP_A2}/project.conf"; then
  print -u2 -- "FAIL: Migration A did not default to 'devin' when RALPH_PLAN_ENGINE absent"
  cat "${TMP_A2}/project.conf" >&2
  exit 1
fi
print -- "PASS: Migration A defaults to devin when RALPH_PLAN_ENGINE absent"
rm -rf "$TMP_A2"

# ── Migration B: stub .ralph/ purge with backup ─────────────────────────────
TMP_B="$(mktemp -d -t wb-mig-b.XXXXXX)"
print 'WB_LABEL="test"' > "${TMP_B}/project.conf"
mkdir -p "${TMP_B}/.ralph"
print 'STALE template AGENT.md' > "${TMP_B}/.ralph/AGENT.md"

_migrate_stub_ralph_purge "$TMP_B"

if [[ -d "${TMP_B}/.ralph" ]]; then
  print -u2 -- "FAIL: Migration B did not remove ${TMP_B}/.ralph"
  exit 1
fi
backups=("${TMP_B}"/.ralph.purged.*(N))
if (( ${#backups[@]} != 1 )); then
  print -u2 -- "FAIL: Migration B did not create exactly one .ralph.purged.* backup (got ${#backups[@]})"
  exit 1
fi
if ! grep -q 'STALE template AGENT.md' "${backups[1]}/AGENT.md"; then
  print -u2 -- "FAIL: Migration B backup does not contain original AGENT.md content"
  exit 1
fi
print -- "PASS: Migration B — wb-root .ralph/ moved to ${backups[1]:t}"

# Run again — no second backup, since .ralph/ is gone now.
# Sleep 1s to ensure a new timestamp would differ if the migration mistakenly
# re-fired (it should not, because the source dir is absent).
sleep 1
_migrate_stub_ralph_purge "$TMP_B"
backups_after=("${TMP_B}"/.ralph.purged.*(N))
if (( ${#backups_after[@]} != 1 )); then
  print -u2 -- "FAIL: Migration B not idempotent — ${#backups_after[@]} backups after second run"
  exit 1
fi
print -- "PASS: Migration B idempotent (single backup after re-run)"

# ── Migration B no-op: no stub at start ─────────────────────────────────────
TMP_C="$(mktemp -d -t wb-mig-c.XXXXXX)"
print 'WB_LABEL="test"' > "${TMP_C}/project.conf"

_migrate_stub_ralph_purge "$TMP_C"

backups_c=("${TMP_C}"/.ralph.purged.*(N))
if (( ${#backups_c[@]} != 0 )); then
  print -u2 -- "FAIL: Migration B no-op — unexpectedly created ${#backups_c[@]} backup(s) when no stub present"
  exit 1
fi
if [[ -d "${TMP_C}/.ralph" ]]; then
  print -u2 -- "FAIL: Migration B no-op — .ralph/ unexpectedly present"
  exit 1
fi
print -- "PASS: Migration B no-op — no backup when no stub present"

print -- "All update-migration tests passed."
