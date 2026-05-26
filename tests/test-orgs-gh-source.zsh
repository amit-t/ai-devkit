#!/usr/bin/env zsh
# test-orgs-gh-source.zsh — Verify that `gh api user/orgs` is the primary
# org-discovery source in lib/orgs.sh, with graceful fallback when gh is
# missing or unauthenticated.
#
# Behaviour under test:
#   1. devkit_gh_orgs prints non-empty when gh is on PATH and authed.
#   2. devkit_gh_orgs prints empty (exit 0) when gh is NOT on PATH.
#   3. devkit_orgs_list includes everything from devkit_gh_orgs.
#   4. devkit_orgs_list dedups: an org that appears in BOTH gh and auto
#      shows up exactly once.
#
# Run: zsh tests/test-orgs-gh-source.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DEVKIT_ROOT="${SCRIPT_DIR:h}"
. "$DEVKIT_ROOT/lib/orgs.sh"

fail() { print -u2 "FAIL: $*"; exit 1; }
pass() { print "PASS: $*"; }

# ── 1. devkit_gh_orgs returns non-empty when gh is authed ──────────────────
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh_orgs="$(devkit_gh_orgs)"
  if [[ -z "$gh_orgs" ]]; then
    fail "devkit_gh_orgs empty despite gh being authed"
  fi
  pass "devkit_gh_orgs returned $(printf '%s' "$gh_orgs" | wc -l | tr -d ' ') org(s)"
else
  print "SKIP: gh not authenticated; cannot verify dynamic discovery"
fi

# ── 2. devkit_gh_orgs gracefully empty without gh on PATH ──────────────────
# Shadow gh with an empty PATH to simulate "gh not installed".
out_no_gh="$(PATH=/usr/bin:/bin devkit_gh_orgs 2>&1 || true)"
# /usr/bin and /bin should not have gh on most setups; on a system where
# it does, this is a no-op and the test below still holds (the call
# either returns empty or returns the orgs cleanly).
if command -v gh >/dev/null 2>&1; then
  # Sanity: confirm gh actually disappears when we strip PATH.
  PATH=/usr/bin:/bin command -v gh >/dev/null 2>&1 && {
    print "SKIP: gh visible even under stripped PATH; cannot test missing-gh path"
  } || {
    [[ -z "$out_no_gh" ]] || fail "devkit_gh_orgs printed '$out_no_gh' when gh was unavailable"
    pass "devkit_gh_orgs cleanly empty when gh is not on PATH"
  }
fi

# ── 3. devkit_orgs_list is a superset of devkit_gh_orgs ────────────────────
gh_orgs="$(devkit_gh_orgs)"
list_orgs="$(devkit_orgs_list)"
if [[ -n "$gh_orgs" ]]; then
  while IFS= read -r org; do
    [[ -z "$org" ]] && continue
    if ! print -r -- "$list_orgs" | grep -qxF "$org"; then
      fail "devkit_orgs_list missing '$org' from devkit_gh_orgs"
    fi
  done <<< "$gh_orgs"
  pass "devkit_orgs_list contains every entry from devkit_gh_orgs"
fi

# ── 4. Dedup: every org in list_orgs appears exactly once ──────────────────
dup="$(print -r -- "$list_orgs" | sort | uniq -d | head -1)"
if [[ -n "$dup" ]]; then
  fail "devkit_orgs_list contains duplicate: $dup"
fi
pass "devkit_orgs_list has no duplicates"

# ── 5. orgs.wb gh subcommand wired correctly ───────────────────────────────
got="$("$DEVKIT_ROOT/orgs-workbench/orgs.zsh" gh)"
if [[ -n "$gh_orgs" && "$got" != "$gh_orgs" ]]; then
  fail "orgs.wb gh output differs from devkit_gh_orgs"
fi
pass "orgs.wb gh produces same output as devkit_gh_orgs"

print "All orgs-gh-source tests passed."
