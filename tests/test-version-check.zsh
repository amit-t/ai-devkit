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
print -r -- "PASS: test-version-check.zsh (semver compare)"
