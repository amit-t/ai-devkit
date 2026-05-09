#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."
UPGRADE="${REPO_ROOT}/devkit-upgrade/devkit-upgrade.zsh"

# ── Test 1: Happy-path upgrade ────────────────────────────────────────────────
scratch="$(mktemp -d)"
upstream="$scratch/upstream.git"
clone="$scratch/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream" "1.0.0"
git clone -q "$upstream" "$clone"

work="$(mktemp -d)"
git clone -q "$upstream" "$work"
printf '{"version":"1.1.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"x"}\n' > "$work/version.json"
git -C "$work" -c user.email=t@t -c user.name=t commit -aq -m "bump"
git -C "$work" push -q origin main

DEVKIT_CLONE="$clone" \
  WB_UPDATES_CACHE_DIR="$scratch/cache" \
  zsh "$UPGRADE" --yes --skip-install || { print -r -- "FAIL: upgrade returned non-zero"; exit 1; }

new_v="$(jq -r .version "$clone/version.json")"
[[ "$new_v" == "1.1.0" ]] || { print -r -- "FAIL: clone not on 1.1.0 (got $new_v)"; exit 1; }
[[ -f "$scratch/cache/devkit-prior.json" ]] || { print -r -- "FAIL: prior cache not written"; exit 1; }

rm -rf "$scratch" "$work"
print -r -- "PASS: devkit-upgrade happy path"

# ── Test 2: Dirty-tree refusal ────────────────────────────────────────────────
scratch2="$(mktemp -d)"
upstream2="$scratch2/upstream.git"
clone2="$scratch2/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream2" "1.0.0"
git clone -q "$upstream2" "$clone2"
print -r -- "dirty" > "$clone2/dirty.txt"

set +e
DEVKIT_CLONE="$clone2" \
  WB_UPDATES_CACHE_DIR="$scratch2/cache" \
  zsh "$UPGRADE" --yes --skip-install
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { print -r -- "FAIL: expected exit 2 on dirty tree, got $rc"; rm -rf "$scratch2"; exit 1; }
rm -rf "$scratch2"
print -r -- "PASS: devkit-upgrade dirty-tree refusal"

# ── Test 3: Non-main branch refusal ───────────────────────────────────────────
scratch3="$(mktemp -d)"
upstream3="$scratch3/upstream.git"
clone3="$scratch3/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream3" "1.0.0"
git clone -q "$upstream3" "$clone3"
git -C "$clone3" checkout -qb feature

set +e
DEVKIT_CLONE="$clone3" \
  WB_UPDATES_CACHE_DIR="$scratch3/cache" \
  zsh "$UPGRADE" --yes --skip-install
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { print -r -- "FAIL: expected exit 2 on feature branch, got $rc"; rm -rf "$scratch3"; exit 1; }
rm -rf "$scratch3"
print -r -- "PASS: devkit-upgrade feature-branch refusal"
