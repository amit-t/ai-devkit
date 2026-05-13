#!/usr/bin/env zsh
# sync-skill.zsh — Vendor refresh from a local at-skills clone into ai-devkit.
#
# Usage:
#   zsh scripts/sync-skill.zsh                  # sync all KNOWN_SKILLS
#   zsh scripts/sync-skill.zsh repo-context-scan
#
# Env overrides:
#   AT_SKILLS_DIR  Path to local at-skills clone. Default: sibling of devkit clone.
#   DEVKIT_DIR     Path to ai-devkit clone. Default: derived from script location.

set -euo pipefail

script_path="${0:A}"
DEVKIT_DIR="${DEVKIT_DIR:-${script_path:h:h}}"

KNOWN_SKILLS=(repo-context-scan)

ok()   { print -r -- "[+] $*"; }
info() { print -r -- "[i] $*"; }
err()  { print -u2 -r -- "[!] $*"; }

# --git-common-dir returns <main-toplevel>/.git from both worktree and main checkout.
main_git_dir="$(git -C "$DEVKIT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || print "")"
if [[ -n "$main_git_dir" ]]; then
  MAIN_TOPLEVEL="${main_git_dir:h}"
else
  MAIN_TOPLEVEL="$DEVKIT_DIR"
fi

: ${AT_SKILLS_DIR:=${MAIN_TOPLEVEL:h}/at-skills}

if [[ ! -d "$AT_SKILLS_DIR/.git" ]]; then
  err "AT_SKILLS_DIR not found or not a git clone: $AT_SKILLS_DIR"
  err ""
  err "Clone it next to ai-devkit, e.g.:"
  err "  git clone git@github.com:amit-t/skills.git ${MAIN_TOPLEVEL:h}/at-skills"
  err ""
  err "Or set AT_SKILLS_DIR to your existing clone:"
  err "  AT_SKILLS_DIR=/path/to/skills zsh scripts/sync-skill.zsh"
  exit 1
fi

if (( ! $+commands[rsync] )); then
  err "rsync not found in PATH"
  exit 1
fi

if (( $# > 0 )); then
  skills=("$@")
else
  skills=("${KNOWN_SKILLS[@]}")
fi

raw_repo="$(git -C "$AT_SKILLS_DIR" remote get-url origin 2>/dev/null || print 'https://github.com/amit-t/skills')"

# Normalize to canonical HTTPS form (per Q14 .upstream schema):
#   git@github.com[-alias]:owner/repo(.git)?           -> https://github.com/owner/repo
#   ssh://git@github.com[-alias][:port]/owner/repo(.git)? -> https://github.com/owner/repo
#   https://github.com/owner/repo(.git)?               -> https://github.com/owner/repo
upstream_repo="$raw_repo"
if [[ "$upstream_repo" == git@github.com*:*/* ]]; then
  upstream_repo="${upstream_repo#git@github.com*:}"
  upstream_repo="https://github.com/${upstream_repo%.git}"
elif [[ "$upstream_repo" == ssh://git@github.com*/*/* ]]; then
  upstream_repo="${upstream_repo#ssh://git@github.com*/}"
  upstream_repo="https://github.com/${upstream_repo%.git}"
else
  upstream_repo="${upstream_repo%.git}"
fi

upstream_sha="$(git -C "$AT_SKILLS_DIR" rev-parse HEAD)"
synced_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
synced_by="$(git config user.name 2>/dev/null || print -r -- "${USER:-unknown}")"

mkdir -p "${DEVKIT_DIR}/skills"

for skill in "${skills[@]}"; do
  src="${AT_SKILLS_DIR}/${skill}"
  dst="${DEVKIT_DIR}/skills/${skill}"

  if [[ ! -d "$src" ]]; then
    err "Skill '${skill}' not present in ${AT_SKILLS_DIR}"
    exit 1
  fi

  mkdir -p "$dst"
  info "syncing ${skill} <- ${src}"
  rsync -a --delete --exclude='.git' --exclude='.upstream' "${src}/" "${dst}/"

  {
    print -r -- "upstream_repo: ${upstream_repo}"
    print -r -- "upstream_sha:  ${upstream_sha}"
    print -r -- "synced_at:     ${synced_at}"
    print -r -- "synced_by:     ${synced_by}"
  } > "${dst}/.upstream"

  ok "synced ${skill} @ ${upstream_sha:0:12}"
done
