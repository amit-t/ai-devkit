#!/usr/bin/env zsh
# devkit-upgrade — pull latest ai-devkit clone + reinstall.
#
# Usage:
#   devkit.upgrade               # prompt before pulling
#   devkit.upgrade --yes         # skip prompt
#   devkit.upgrade --check-only  # report stale state, exit 1 if stale, no changes
#   devkit.upgrade --rollback    # revert to prior SHA
#   devkit.upgrade --force       # bypass peer-floor check
#   devkit.upgrade --skip-install  # (test only) skip running install.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LIB_DIR="${SCRIPT_DIR}/../lib"

YES=false
ROLLBACK=false
FORCE=false
SKIP_INSTALL=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=true; shift ;;
    --check-only) CHECK_ONLY=true; shift ;;
    --rollback) ROLLBACK=true; shift ;;
    --force) FORCE=true; shift ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    -h|--help)
      cat <<USAGE
devkit.upgrade — pull and reinstall ai-devkit.
USAGE
      exit 0 ;;
    *) print -r -- "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

_VERCHECK_LIB_DIR_OVERRIDE="$LIB_DIR" . "${LIB_DIR}/version-check.sh"

CLONE="${DEVKIT_CLONE:-}"
if [[ -z "$CLONE" ]]; then
  CLONE="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
fi

if [[ ! -d "$CLONE/.git" ]]; then
  print -r -- "ai-devkit clone not found at $CLONE. Set DEVKIT_CLONE." >&2
  exit 1
fi

if $ROLLBACK; then
  prior="${WB_UPDATES_CACHE_DIR:-$HOME/.cache/wb-updates}/devkit-prior.json"
  if [[ ! -f "$prior" ]]; then
    print -r -- "No prior recorded. Nothing to roll back." >&2
    exit 1
  fi
  prior_sha="$(jq -r .prior_sha "$prior")"
  prior_v="$(jq -r .prior_version "$prior")"
  print -r -- "Rolling back to $prior_v ($prior_sha)..."
  git -C "$CLONE" checkout -q "$prior_sha"
  if ! $SKIP_INSTALL && [[ -x "$CLONE/install.zsh" ]]; then
    "$CLONE/install.zsh"
  fi
  _wb_cache_invalidate devkit
  print -r -- "[devkit] rolled back to $prior_v. Reload shell: exec zsh"
  exit 0
fi

git_status="$(git -C "$CLONE" status --porcelain)"
if [[ -n "$git_status" ]]; then
  print -r -- "ai-devkit clone has uncommitted changes. Commit/stash and retry." >&2
  exit 2
fi

branch="$(git -C "$CLONE" rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "main" ]]; then
  print -r -- "ai-devkit clone is on '$branch', not 'main'. Switch to main and retry." >&2
  exit 2
fi

git -C "$CLONE" fetch -q origin main

local_v="$(_wb_local_version devkit)"
upstream_v_raw="$(git -C "$CLONE" show origin/main:version.json 2>/dev/null || echo '{}')"
upstream_v="$(print -r -- "$upstream_v_raw" | jq -r '.version // "0.0.0"')"

if [[ "$(_wb_compare_semver "$local_v" "$upstream_v")" == "eq" ]]; then
  print -r -- "[devkit] already at $local_v"
  exit 0
fi

# --check-only: report state, do not pull or reinstall.
if $CHECK_ONLY; then
  print -r -- "[devkit] stale: local $local_v, upstream $upstream_v"
  exit 1
fi

if ! $FORCE; then
  ralph_req="$(print -r -- "$upstream_v_raw" | jq -r '.requires.ralph // empty')"
  if [[ -n "$ralph_req" ]]; then
    ralph_local="$(_wb_local_version ralph)"
    if [[ "$(_wb_check_requires "$ralph_req" "$ralph_local")" == "fail" ]]; then
      print -r -- "[devkit] cannot upgrade: requires ralph $ralph_req, found $ralph_local. Run ralph.upgrade first or pass --force." >&2
      exit 3
    fi
  fi
fi

print -r -- "[devkit] upgrade $local_v -> $upstream_v"
print -r -- "Commits to be pulled:"
git -C "$CLONE" log HEAD..origin/main --oneline | head -20
if ! $YES; then
  printf "Continue? [y/N] "
  read -r answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    print -r -- "Aborted."
    exit 1
  fi
fi

_wb_record_prior devkit
git -C "$CLONE" pull --rebase -q origin main
if ! $SKIP_INSTALL && [[ -x "$CLONE/install.zsh" ]]; then
  "$CLONE/install.zsh"
fi
_wb_cache_invalidate devkit
_wb_mark_bootstrapped devkit
print -r -- "[devkit] upgraded $local_v -> $upstream_v. Reload shell: exec zsh"
