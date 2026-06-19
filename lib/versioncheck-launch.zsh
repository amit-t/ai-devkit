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
#
# Root resolution is robust to the caller's invocation style. DEVKIT_ROOT is the
# authoritative override, but callers historically set it via a prefix-assign on
# `source` (`DEVKIT_ROOT=X source ...`), which in zsh does NOT persist past the
# builtin — so by the time _wb_launch_versioncheck runs, DEVKIT_ROOT is unset and
# the old `${0:A:h:h}` fallback resolved `$0` to the FUNCTION NAME (not a path),
# yielding a bogus root, an empty prefix, and silent fallback to the unprefixed
# (company) lib + shared cache. We capture this file's own path HERE at source
# time — where `$0` is the sourced file — as the fallback. The lib always lives
# at <clone>/lib/versioncheck-launch.zsh, so :h:h is the correct devkit root.
_WB_VC_LAUNCH_ROOT="${0:A:h:h}"

_wb_launch_versioncheck() {
  local tool="${1:?usage: _wb_launch_versioncheck <tool>}"
  local root="${DEVKIT_ROOT:-$_WB_VC_LAUNCH_ROOT}"

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

  # Namespace the runtime cache and state dirs by the SAME tag as the lib dir.
  # The lib FILES are already split (per-wb-versioncheck vs wb-versioncheck), but
  # version-check.sh's cache (~/.cache/wb-updates/<tool>.json) and state dir
  # (~/.local/share/wb-versioncheck/) default to a SHARED, untagged location.
  # On a twin machine both forks then read/write the same wb.json, so a
  # company-side `wb` check (owner default Invenco-Cloud-Systems-ICS, its own
  # latest version + changelog) poisons the personal `per.wb.upgrade` banner —
  # wrong "update available" version and a cross-twin changelog URL — even though
  # the actual upgrade correctly targets amit-t/ai-workbench. Tagging isolates
  # each fork's cache/state. tag="" leaves the unprefixed/Invenco install on the
  # original shared paths (parity-safe).
  WB_CMD_PREFIX="$prefix" \
  WB_UPDATES_CACHE_DIR="${HOME}/.cache/${tag}wb-updates" \
  WB_STATE_DIR="${HOME}/.local/share/${tag}wb-versioncheck" \
    _wb_versioncheck "$tool" || true
}
