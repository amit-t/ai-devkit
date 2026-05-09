#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."
_VERCHECK_LIB_DIR_OVERRIDE="${REPO_ROOT}/lib"
source "${REPO_ROOT}/lib/version-check.sh"

_compute_key() {
  if command -v md5sum >/dev/null 2>&1; then
    printf '%s|' "$@" | md5sum | cut -c1-32
  elif command -v md5 >/dev/null 2>&1; then
    printf '%s|' "$@" | md5 -q | cut -c1-32
  else
    printf '%s|' "$@" | shasum | cut -c1-32
  fi
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" != "$want" ]]; then
    print -r -- "FAIL: $msg — got '$got', want '$want'"
    exit 1
  fi
}

test_compare_semver_lt() {
  assert_eq "$(_wb_compare_semver 1.0.0 1.0.1)" "lt" "1.0.0 < 1.0.1"
  assert_eq "$(_wb_compare_semver 1.0.0 1.1.0)" "lt" "1.0.0 < 1.1.0"
  assert_eq "$(_wb_compare_semver 1.0.0 2.0.0)" "lt" "1.0.0 < 2.0.0"
  assert_eq "$(_wb_compare_semver 1.2.3 1.10.0)" "lt" "1.2.3 < 1.10.0 (numeric, not lexical)"
}

test_compare_semver_eq() {
  assert_eq "$(_wb_compare_semver 1.0.0 1.0.0)" "eq" "1.0.0 == 1.0.0"
}

test_compare_semver_gt() {
  assert_eq "$(_wb_compare_semver 1.0.1 1.0.0)" "gt" "1.0.1 > 1.0.0"
}

test_compare_semver_lt
test_compare_semver_eq
test_compare_semver_gt

test_check_requires_pass() {
  assert_eq "$(_wb_check_requires '>=1.2.0' '1.2.0')" "ok" ">=1.2.0 vs 1.2.0"
  assert_eq "$(_wb_check_requires '>=1.2.0' '1.3.0')" "ok" ">=1.2.0 vs 1.3.0"
  assert_eq "$(_wb_check_requires '>=1.2.0' '2.0.0')" "ok" ">=1.2.0 vs 2.0.0"
}

test_check_requires_fail() {
  assert_eq "$(_wb_check_requires '>=1.2.0' '1.1.9')" "fail" ">=1.2.0 vs 1.1.9 fails"
  assert_eq "$(_wb_check_requires '>=2.0.0' '1.99.99')" "fail" ">=2.0.0 vs 1.99.99 fails"
}

test_check_requires_pass
test_check_requires_fail

test_clone_path_devkit_env() {
  local result
  result="$(DEVKIT_CLONE=/tmp/fake-devkit _wb_clone_path devkit)"
  assert_eq "$result" "/tmp/fake-devkit" "DEVKIT_CLONE wins"
}

test_clone_path_ralph_env() {
  local result
  result="$(RALPH_CLONE=/tmp/fake-ralph _wb_clone_path ralph)"
  assert_eq "$result" "/tmp/fake-ralph" "RALPH_CLONE wins"
}

test_clone_path_devkit_env
test_clone_path_ralph_env

test_local_version_from_clone() {
  local fixture result
  fixture="$(mktemp -d)"
  trap "rm -rf '$fixture'" EXIT
  printf '{"version":"1.2.3"}\n' > "$fixture/version.json"
  result="$(DEVKIT_CLONE="$fixture" _wb_local_version devkit)"
  assert_eq "$result" "1.2.3" "reads version from clone"
}

test_local_version_missing() {
  local fixture result
  fixture="$(mktemp -d)"
  trap "rm -rf '$fixture'" EXIT
  result="$(DEVKIT_CLONE="$fixture" _wb_local_version devkit)"
  assert_eq "$result" "0.0.0" "missing -> 0.0.0"
}

test_local_version_corrupt() {
  local fixture result
  fixture="$(mktemp -d)"
  trap "rm -rf '$fixture'" EXIT
  printf 'not json\n' > "$fixture/version.json"
  result="$(DEVKIT_CLONE="$fixture" _wb_local_version devkit 2>/dev/null)"
  assert_eq "$result" "0.0.0" "corrupt -> 0.0.0 (warn)"
}

test_local_version_from_clone
test_local_version_missing
test_local_version_corrupt

test_fetch_upstream_via_gh_shim() {
  local respdir
  respdir="$(mktemp -d)"
  trap "rm -rf '$respdir'" EXIT
  GH_SHIM_RESPONSES_DIR="$respdir"
  source "${REPO_ROOT}/tests/helpers/gh-shim.sh"
  local key
  key="$(_compute_key "api" "repos/amit-t/ai-devkit/contents/version.json?ref=main" "-H" "Accept: application/vnd.github.raw+json")"
  printf '{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}\n' > "$respdir/$key.json"
  local out
  out="$(_wb_fetch_upstream amit-t ai-devkit)"
  assert_eq "$(echo "$out" | jq -r .version)" "1.4.0" "fetch_upstream returns upstream JSON"
}

test_fetch_upstream_via_gh_shim

test_cache_miss_writes() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  local payload='{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{}}'
  _wb_cache_write devkit "$payload" 12
  [[ -f "$cachedir/devkit.json" ]] || { print -r -- "FAIL: cache file not created"; exit 1; }
  assert_eq "$(jq -r .upstream.version "$cachedir/devkit.json")" "1.4.0" "cache stores upstream"
}

test_cache_hit_within_ttl() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  local now ts
  now="$(date -u +%s)"
  ts="$(date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$cachedir/devkit.json" <<JSON
{"tool":"devkit","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{}}}
JSON
  assert_eq "$(_wb_cache_is_fresh devkit)" "fresh" "fresh within ttl"
}

test_cache_stale_past_ttl() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  cat > "$cachedir/devkit.json" <<'JSON'
{"tool":"devkit","checked_at":"1970-01-01T00:00:00Z","ttl_hours":12,"upstream":{"version":"1.4.0"}}
JSON
  assert_eq "$(_wb_cache_is_fresh devkit)" "stale" "stale past ttl"
}

test_cache_miss_writes
test_cache_hit_within_ttl
test_cache_stale_past_ttl

test_render_banner_update_available() {
  local out
  out="$(_wb_render_banner devkit 1.2.3 1.4.0 "https://example.com/changelog")"
  case "$out" in
    *"update 1.4.0 available"*) ;;
    *) print -r -- "FAIL: banner missing 'update 1.4.0 available' — got '$out'"; exit 1 ;;
  esac
  case "$out" in
    *"devkit.upgrade"*) ;;
    *) print -r -- "FAIL: banner missing 'devkit.upgrade'"; exit 1 ;;
  esac
}

test_render_banner_update_available

test_versioncheck_emits_banner_on_upgrade_available() {
  local cachedir respdir clonedir
  cachedir="$(mktemp -d)"
  respdir="$(mktemp -d)"
  clonedir="$(mktemp -d)"
  trap "rm -rf '$cachedir' '$respdir' '$clonedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  GH_SHIM_RESPONSES_DIR="$respdir"
  DEVKIT_CLONE="$clonedir"
  source "${REPO_ROOT}/tests/helpers/gh-shim.sh"
  printf '{"version":"1.0.0"}\n' > "$clonedir/version.json"
  local key
  key="$(_compute_key "api" "repos/amit-t/ai-devkit/contents/version.json?ref=main" "-H" "Accept: application/vnd.github.raw+json")"
  printf '{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"https://example.com"}\n' > "$respdir/$key.json"
  local out
  out="$(WB_UPSTREAM_OWNER=amit-t WB_UPSTREAM_REPO_devkit=ai-devkit _wb_versioncheck devkit 2>&1)"
  case "$out" in
    *"update 1.4.0 available"*) ;;
    *) print -r -- "FAIL: versioncheck did not emit banner — got '$out'"; exit 1 ;;
  esac
}

test_versioncheck_emits_banner_on_upgrade_available

test_bootstrap_nag_fires_once() {
  local cachedir clonedir
  cachedir="$(mktemp -d)"
  clonedir="$(mktemp -d)"
  trap "rm -rf '$cachedir' '$clonedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  DEVKIT_CLONE="$clonedir"
  local out1 out2
  out1="$(_wb_emit_bootstrap_nag devkit 2>&1)"
  case "$out1" in
    *"versioning system added"*) ;;
    *) print -r -- "FAIL: first nag missing message"; exit 1 ;;
  esac
  out2="$(_wb_emit_bootstrap_nag devkit 2>&1)"
  if [[ -n "$out2" ]]; then
    print -r -- "FAIL: second call should be silent — got '$out2'"; exit 1
  fi
}

test_bootstrap_clear_after_upgrade() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  _wb_mark_bootstrapped devkit
  [[ -f "$cachedir/devkit-bootstrapped.flag" ]] || { print -r -- "FAIL: flag not created"; exit 1; }
}

test_bootstrap_nag_fires_once
test_bootstrap_clear_after_upgrade

test_record_prior_writes_file() {
  local cachedir clonedir
  cachedir="$(mktemp -d)"
  clonedir="$(mktemp -d)"
  trap "rm -rf '$cachedir' '$clonedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  DEVKIT_CLONE="$clonedir"
  printf '{"version":"1.2.3"}\n' > "$clonedir/version.json"
  ( cd "$clonedir" && git init -q -b main && git -c user.email=t@t -c user.name=t add version.json && git -c user.email=t@t -c user.name=t commit -q -m init )
  _wb_record_prior devkit
  [[ -f "$cachedir/devkit-prior.json" ]] || { print -r -- "FAIL: prior file not created"; exit 1; }
  assert_eq "$(jq -r .prior_version "$cachedir/devkit-prior.json")" "1.2.3" "prior version captured"
}

test_record_prior_writes_file
print -r -- "PASS: test-version-check.zsh (semver compare)"
