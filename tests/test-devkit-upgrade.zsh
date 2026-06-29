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

# ── Test 4: Rollback round-trip ───────────────────────────────────────────────
scratch4="$(mktemp -d)"
upstream4="$scratch4/upstream.git"
clone4="$scratch4/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream4" "1.0.0"
git clone -q "$upstream4" "$clone4"

work4="$(mktemp -d)"
git clone -q "$upstream4" "$work4"
printf '{"version":"1.1.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"x"}\n' > "$work4/version.json"
git -C "$work4" -c user.email=t@t -c user.name=t commit -aq -m "bump"
git -C "$work4" push -q origin main

DEVKIT_CLONE="$clone4" \
  WB_UPDATES_CACHE_DIR="$scratch4/cache" \
  zsh "$UPGRADE" --yes --skip-install

DEVKIT_CLONE="$clone4" \
  WB_UPDATES_CACHE_DIR="$scratch4/cache" \
  zsh "$UPGRADE" --rollback --skip-install

v="$(jq -r .version "$clone4/version.json")"
[[ "$v" == "1.0.0" ]] || { print -r -- "FAIL: rollback did not restore 1.0.0 (got $v)"; rm -rf "$scratch4" "$work4"; exit 1; }
rm -rf "$scratch4" "$work4"
print -r -- "PASS: devkit-upgrade rollback round-trip"

# ── Test 5: Peer-requires block + --force bypass ──────────────────────────────
scratch5="$(mktemp -d)"
upstream5="$scratch5/upstream.git"
clone5="$scratch5/clone"
ralph_clone="$scratch5/ralph"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream5" "1.0.0"
git clone -q "$upstream5" "$clone5"
mkdir -p "$ralph_clone"
printf '{"version":"0.5.0"}\n' > "$ralph_clone/version.json"

work5="$(mktemp -d)"
git clone -q "$upstream5" "$work5"
printf '{"version":"1.1.0","check_ttl_hours":12,"channel":"stable","requires":{"ralph":">=1.0.0"},"changelog_url":"x"}\n' > "$work5/version.json"
git -C "$work5" -c user.email=t@t -c user.name=t commit -aq -m "bump"
git -C "$work5" push -q origin main

set +e
DEVKIT_CLONE="$clone5" \
  RALPH_CLONE="$ralph_clone" \
  WB_UPDATES_CACHE_DIR="$scratch5/cache" \
  zsh "$UPGRADE" --yes --skip-install
rc=$?
set -e
[[ "$rc" -eq 3 ]] || { print -r -- "FAIL: expected exit 3 on peer-floor block, got $rc"; rm -rf "$scratch5" "$work5"; exit 1; }

DEVKIT_CLONE="$clone5" \
  RALPH_CLONE="$ralph_clone" \
  WB_UPDATES_CACHE_DIR="$scratch5/cache" \
  zsh "$UPGRADE" --yes --force --skip-install

v="$(jq -r .version "$clone5/version.json")"
[[ "$v" == "1.1.0" ]] || { print -r -- "FAIL: --force did not allow upgrade (got $v)"; rm -rf "$scratch5" "$work5"; exit 1; }
rm -rf "$scratch5" "$work5"
print -r -- "PASS: devkit-upgrade peer-requires block + --force"

# ── Test 6: DEVKIT_CLONE unset — silent-death regression (PR #57 port) ─────────
# With DEVKIT_CLONE unset the script must still resolve its clone via the
# SCRIPT_DIR fallback and export DEVKIT_CLONE so lib/version-check.sh helpers
# (_wb_local_version, _wb_record_prior) see the real clone. Before the fix an
# unset DEVKIT_CLONE made _wb_local_version report 0.0.0 (phantom upgrade) and
# the bare _wb_record_prior return 1 — a silent `set -e` exit right after the
# confirm prompt. We vendor the upgrade script + lib into a committed clone and
# run with `env -u DEVKIT_CLONE`, with discovery + state-file fallbacks disabled
# so the SCRIPT_DIR path is the only thing that can save it.

# Vendors devkit-upgrade/ + lib/ into $1 (a clone) and commits them so the tree
# is clean and the vendored devkit-upgrade.zsh resolves $CLONE via SCRIPT_DIR/..
_vendor_clone() {
  local dst="$1"
  mkdir -p "$dst/devkit-upgrade" "$dst/lib"
  cp "${REPO_ROOT}/devkit-upgrade/devkit-upgrade.zsh" "$dst/devkit-upgrade/"
  cp "${REPO_ROOT}/lib/version-check.sh" "${REPO_ROOT}/lib/bootstrap-detection.sh" "$dst/lib/"
  git -C "$dst" -c user.email=t@t -c user.name=t add devkit-upgrade lib
  git -C "$dst" -c user.email=t@t -c user.name=t commit -qm "vendor upgrade + lib"
}

# 6a: already-current clone -> "already at X", exit 0 (no phantom upgrade).
scratch6="$(mktemp -d)"; state6="$(mktemp -d)"
upstream6="$scratch6/upstream.git"; clone6="$scratch6/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream6" "1.0.0"
git clone -q "$upstream6" "$clone6"
_vendor_clone "$clone6"

set +e
out6="$(env -u DEVKIT_CLONE -u PER_DEVKIT_CLONE \
  WB_DISABLE_DISCOVERY=1 WB_STATE_DIR="$state6" \
  WB_UPDATES_CACHE_DIR="$scratch6/cache" \
  zsh "$clone6/devkit-upgrade/devkit-upgrade.zsh" --yes --skip-install 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || { print -r -- "FAIL: unset-clone already-current exit $rc (silent death?)\n$out6"; rm -rf "$scratch6" "$state6"; exit 1; }
[[ "$out6" == *"already at 1.0.0"* ]] || { print -r -- "FAIL: expected 'already at 1.0.0', got:\n$out6"; rm -rf "$scratch6" "$state6"; exit 1; }
rm -rf "$scratch6" "$state6"
print -r -- "PASS: devkit-upgrade DEVKIT_CLONE unset, already-current (no phantom upgrade)"

# 6b: real delta -> prompts/installs, completes, writes prior cache, exit 0.
scratch7="$(mktemp -d)"; state7="$(mktemp -d)"
upstream7="$scratch7/upstream.git"; clone7="$scratch7/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream7" "1.0.0"
git clone -q "$upstream7" "$clone7"
_vendor_clone "$clone7"

work7="$(mktemp -d)"
git clone -q "$upstream7" "$work7"
printf '{"version":"1.1.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"x"}\n' > "$work7/version.json"
git -C "$work7" -c user.email=t@t -c user.name=t commit -aq -m "bump"
git -C "$work7" push -q origin main

set +e
out7="$(env -u DEVKIT_CLONE -u PER_DEVKIT_CLONE \
  WB_DISABLE_DISCOVERY=1 WB_STATE_DIR="$state7" \
  WB_UPDATES_CACHE_DIR="$scratch7/cache" \
  zsh "$clone7/devkit-upgrade/devkit-upgrade.zsh" --yes --skip-install 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || { print -r -- "FAIL: unset-clone delta exit $rc (silent death?)\n$out7"; rm -rf "$scratch7" "$state7" "$work7"; exit 1; }
new_v="$(jq -r .version "$clone7/version.json")"
[[ "$new_v" == "1.1.0" ]] || { print -r -- "FAIL: unset-clone delta not on 1.1.0 (got $new_v)\n$out7"; rm -rf "$scratch7" "$state7" "$work7"; exit 1; }
[[ "$out7" == *"upgraded 1.0.0 -> 1.1.0"* ]] || { print -r -- "FAIL: missing completion line:\n$out7"; rm -rf "$scratch7" "$state7" "$work7"; exit 1; }
[[ -f "$scratch7/cache/devkit-prior.json" ]] || { print -r -- "FAIL: unset-clone prior cache not written"; rm -rf "$scratch7" "$state7" "$work7"; exit 1; }
prior_v="$(jq -r .prior_version "$scratch7/cache/devkit-prior.json")"
[[ "$prior_v" == "1.0.0" ]] || { print -r -- "FAIL: prior_version should be 1.0.0 not phantom 0.0.0 (got $prior_v)"; rm -rf "$scratch7" "$state7" "$work7"; exit 1; }
rm -rf "$scratch7" "$state7" "$work7"
print -r -- "PASS: devkit-upgrade DEVKIT_CLONE unset, real delta (upgrades, prior cache correct)"
