#!/usr/bin/env zsh
# orgs.zsh — CLI for managing the devkit org list.
#
# Usage:
#   orgs.wb                  # same as `list`
#   orgs.wb list             # print all orgs (gh + configured + auto-detected)
#   orgs.wb show             # numbered menu (same format init/join use)
#   orgs.wb add <slug>       # append slug to orgs.conf
#   orgs.wb remove <slug>    # remove slug from orgs.conf
#   orgs.wb auto             # print auto-detected org only
#   orgs.wb gh               # print orgs from `gh api user/orgs` only
#   orgs.wb path             # print path to orgs.conf
#   orgs.wb edit             # open orgs.conf in $EDITOR

set -euo pipefail

# Resolve real script path even when invoked via PATH symlink
# (~/.local/bin/orgs.wb → repo/orgs-workbench/orgs.zsh). `${0:A}` follows
# symlinks and yields the absolute path so DEVKIT_ROOT lands inside the
# repo, not in ~/.local where install.zsh's symlink lives.
SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
DEVKIT_ROOT="${SCRIPT_DIR:h}"
# shellcheck source=../lib/orgs.sh
. "$DEVKIT_ROOT/lib/orgs.sh"

cmd="${1:-list}"
shift || true

case "$cmd" in
  list|ls) devkit_orgs_list ;;
  show)    devkit_orgs_show ;;
  add)     devkit_orgs_add "${1:-}" ;;
  remove|rm) devkit_orgs_remove "${1:-}" ;;
  auto)    devkit_auto_org ;;
  gh)      devkit_gh_orgs ;;
  path)    devkit_orgs_file ;;
  edit)    "${EDITOR:-vi}" "$(devkit_orgs_file)" ;;
  -h|--help|help)
    cat <<USAGE
orgs.wb — manage ai-devkit org list

Commands:
  list              Print all orgs (gh-discovered + configured + auto-detected)
  show              Print numbered menu (as init.wb / join.wb present it)
  add <slug>        Append a new org to orgs.conf
  remove <slug>     Remove an org from orgs.conf
  auto              Print the auto-detected org (from devkit's origin remote)
  gh                Print orgs the current gh user is a member of
  path              Print path to orgs.conf
  edit              Open orgs.conf in \$EDITOR

Org sources, in display order:
  1. gh api user/orgs   (dynamic, primary)
  2. orgs.conf          (user-curated additions)
  3. devkit's origin    (auto-detected, always included)
USAGE
    ;;
  *) echo "Unknown command: $cmd (try: orgs.wb --help)" >&2; exit 1 ;;
esac
