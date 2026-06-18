#!/usr/bin/env zsh
# versioncheck-launch.zsh — prefix-aware version-check nudge for devkit launchers.
#
# The launchers (init/join/update.zsh) must source the version-check lib that
# matches THIS install's command prefix. A `--prefix per.` install drops the lib
# into ~/.local/share/per-wb-versioncheck/ (whose upstream-owner default and
# upgrade-command match the personal fork). Sourcing the unprefixed lib on a
# prefixed machine pulls in the OTHER twin's lib — wrong upstream owner (it
# checks the company remote) and an unprefixed banner command (`wb.upgrade`
# instead of `per.wb.upgrade`).
#
# Prefix resolution (first match wins; mirrors lib/ralph-cmd.zsh):
#   1. env DEVKIT_CMD_PREFIX             authoritative, even when set to empty
#   2. <devkit-root>/.devkit-cmd-prefix  per-install marker written by install.zsh
#   3. ""                                unprefixed / twin install
#
# Parity-safe: this file is identical across forks. Each fork's install.zsh
# writes its own marker (personal -> "per.", twin -> ""), so the same code
# resolves correctly on both.
#
# Usage:
#   DEVKIT_ROOT=<clone-root> source <root>/lib/versioncheck-launch.zsh
#   _wb_launch_versioncheck <devkit|wb|ralph>
# The caller may pre-export WB_TEMPLATE_VERSION_FILE (update.zsh does, for `wb`).

_wb_launch_versioncheck() {
  local tool="${1:?usage: _wb_launch_versioncheck <tool>}"
  local root="${DEVKIT_ROOT:-${0:A:h:h}}"

  local prefix=""
  if [[ -n "${DEVKIT_CMD_PREFIX+set}" ]]; then
    prefix="$DEVKIT_CMD_PREFIX"
  elif [[ -f "$root/.devkit-cmd-prefix" ]]; then
    prefix="$(tr -d '[:space:]' < "$root/.devkit-cmd-prefix")"
  fi

  # Derive the version-check state-dir tag (mirrors install.zsh: "per." -> "per-").
  local tag=""
  if [[ -n "$prefix" ]]; then
    local ns="${${prefix%%.*}//[^A-Za-z0-9]/}"
    ns="${ns:l}"
    [[ -n "$ns" ]] && tag="${ns}-"
  fi

  local libvc="${HOME}/.local/share/${tag}wb-versioncheck/version-check.sh"
  # Fall back to the unprefixed lib if the tagged one is absent.
  [[ -f "$libvc" ]] || libvc="${HOME}/.local/share/wb-versioncheck/version-check.sh"
  [[ -f "$libvc" ]] || return 0

  # shellcheck disable=SC1090
  _VERCHECK_LIB_DIR_OVERRIDE="${libvc:h}" source "$libvc"
  WB_CMD_PREFIX="$prefix" _wb_versioncheck "$tool" || true
}
