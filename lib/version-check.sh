# version-check.sh — bash-portable shared library for upgrade-notification.
# Sourced from zsh today; body must remain bash-compatible (no zsh-only syntax).

_wb_compare_semver() {
  local a="${1%%-*}" b="${2%%-*}"
  local a_major="${a%%.*}"; a="${a#*.}"
  local a_minor="${a%%.*}"; local a_patch="${a#*.}"
  [[ "$a_minor" == "$a" ]] && a_patch="0"
  [[ "$a_patch" == "$a" ]] && a_patch="0"
  local b_major="${b%%.*}"; b="${b#*.}"
  local b_minor="${b%%.*}"; local b_patch="${b#*.}"
  [[ "$b_minor" == "$b" ]] && b_patch="0"
  [[ "$b_patch" == "$b" ]] && b_patch="0"
  if (( a_major < b_major )); then echo "lt"; return; fi
  if (( a_major > b_major )); then echo "gt"; return; fi
  if (( a_minor < b_minor )); then echo "lt"; return; fi
  if (( a_minor > b_minor )); then echo "gt"; return; fi
  if (( a_patch < b_patch )); then echo "lt"; return; fi
  if (( a_patch > b_patch )); then echo "gt"; return; fi
  echo "eq"
}

_wb_check_requires() {
  local constraint="$1" current="$2"
  case "$constraint" in
    '>='*)
      local floor="${constraint#>=}"
      local cmp
      cmp="$(_wb_compare_semver "$current" "$floor")"
      if [[ "$cmp" == "lt" ]]; then echo "fail"; else echo "ok"; fi
      ;;
    *)
      echo "fail"
      ;;
  esac
}
