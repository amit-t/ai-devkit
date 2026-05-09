#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."
DOCTOR="${REPO_ROOT}/devkit-doctor/devkit-doctor.zsh"

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

upstream="$scratch/upstream.git"
clone="$scratch/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream" "1.0.0"
git clone -q "$upstream" "$clone"
ralph_clone="$scratch/ralph"
mkdir -p "$ralph_clone"
printf '{"version":"1.0.0"}\n' > "$ralph_clone/version.json"

mkdir -p "$scratch/cache"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$scratch/cache/devkit.json" <<JSON
{"tool":"devkit","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}}
JSON
cat > "$scratch/cache/ralph.json" <<JSON
{"tool":"ralph","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.0.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}}
JSON

out="$(DEVKIT_CLONE="$clone" RALPH_CLONE="$ralph_clone" WB_UPDATES_CACHE_DIR="$scratch/cache" zsh "$DOCTOR" --check-only 2>&1 || true)"
case "$out" in
  *"devkit"*"1.0.0"*"1.4.0"*) ;;
  *) print -r -- "FAIL: doctor missing devkit row — got $out"; exit 1 ;;
esac
case "$out" in
  *"ralph"*"1.0.0"*"current"*) ;;
  *) print -r -- "FAIL: doctor missing ralph current row — got $out"; exit 1 ;;
esac

print -r -- "PASS: doctor renders status table"
