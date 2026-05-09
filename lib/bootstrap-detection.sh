# bootstrap-detection.sh — first-time-encounter nag for the versioning system.

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
  case "$tool" in
    devkit) printf "[%s] versioning system added upstream. Run %s.upgrade to start receiving update notifications.\n" "$tool" "$tool" >&2 ;;
    ralph)  printf "[%s] versioning system added upstream. Run %s.upgrade to start receiving update notifications.\n" "$tool" "$tool" >&2 ;;
    wb)     printf "[%s] versioning system added upstream. Run wb.upgrade in this stamped wb to start receiving update notifications.\n" "$tool" >&2 ;;
    *)      printf "[%s] versioning system added upstream. Run %s.upgrade to start receiving update notifications.\n" "$tool" "$tool" >&2 ;;
  esac
  _wb_mark_bootstrapped "$tool"
}
