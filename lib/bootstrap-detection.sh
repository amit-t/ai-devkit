# bootstrap-detection.sh — first-time-encounter nag for the versioning system.
# shellcheck shell=bash

_wb_bootstrap_flag_path() {
  local tool="$1"
  local d
  d="${WB_UPDATES_CACHE_DIR:-${HOME}/.cache/wb-updates}"
  mkdir -p "$d"
  echo "$d/${tool}-bootstrapped.flag"
}

_wb_is_bootstrapped() {
  local tool="$1"
  [[ -f "$(_wb_bootstrap_flag_path "$tool")" ]]
}

_wb_mark_bootstrapped() {
  local tool="$1"
  : > "$(_wb_bootstrap_flag_path "$tool")"
}

_wb_emit_bootstrap_nag() {
  local tool="$1"
  if _wb_is_bootstrapped "$tool"; then
    return 0
  fi
  # Prefix the upgrade command on a namespaced install (e.g. `--prefix per.`)
  # so the nag names the command the caller has on PATH (per.wb.upgrade), not
  # the unprefixed alias that belongs to the other twin. WB_CMD_PREFIX is set
  # by the caller; unset == no prefix (unchanged for the twin/Invenco install).
  local p="${WB_CMD_PREFIX:-}"
  case "$tool" in
    wb)     printf "[%s] versioning system added upstream. Run %swb.upgrade in this stamped wb to start receiving update notifications.\n" "$tool" "$p" >&2 ;;
    *)      printf "[%s] versioning system added upstream. Run %s%s.upgrade to start receiving update notifications.\n" "$tool" "$p" "$tool" >&2 ;;
  esac
  _wb_mark_bootstrapped "$tool"
}
