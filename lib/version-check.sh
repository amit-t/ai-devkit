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

_wb_clone_path() {
  local tool="$1"
  local var
  case "$tool" in
    devkit) var="DEVKIT_CLONE" ;;
    ralph)  var="RALPH_CLONE"  ;;
    wb)     echo ""; return ;;
    *)      echo ""; return ;;
  esac
  eval "echo \"\${$var:-}\""
}

_wb_local_version() {
  local tool="$1"
  local clone
  clone="$(_wb_clone_path "$tool")"
  if [[ "$tool" == "wb" ]]; then
    if [[ -n "${WB_TEMPLATE_VERSION_FILE:-}" && -f "$WB_TEMPLATE_VERSION_FILE" ]]; then
      jq -r '.version // "0.0.0"' "$WB_TEMPLATE_VERSION_FILE" 2>/dev/null || echo "0.0.0"
      return
    fi
    echo "0.0.0"
    return
  fi
  if [[ -z "$clone" || ! -f "$clone/version.json" ]]; then
    echo "0.0.0"
    return
  fi
  local v
  v="$(jq -r '.version // "0.0.0"' "$clone/version.json" 2>/dev/null)" || v="0.0.0"
  if [[ -z "$v" || "$v" == "null" ]]; then v="0.0.0"; fi
  echo "$v"
}

_wb_parse_remote() {
  local url="$1"
  url="${url%.git}"
  url="${url#https://github.com/}"
  url="${url#git@github.com:}"
  echo "$url"
}

_wb_fetch_upstream() {
  local owner="$1" repo="$2"
  local out
  if command -v gh >/dev/null 2>&1; then
    out="$(gh api "repos/${owner}/${repo}/contents/version.json?ref=main" \
                 -H "Accept: application/vnd.github.raw+json" 2>/dev/null)" && {
      [[ -n "$out" ]] && { echo "$out"; return 0; }
    }
  fi
  local tool
  case "${repo}" in
    ai-devkit) tool="devkit" ;;
    ai-ralph)  tool="ralph"  ;;
    ai-workbench) tool="wb"  ;;
    *) tool="" ;;
  esac
  if [[ -n "$tool" ]]; then
    local clone
    clone="$(_wb_clone_path "$tool")"
    if [[ -n "$clone" && -d "$clone/.git" ]]; then
      git -C "$clone" fetch -q origin main 2>/dev/null || return 1
      git -C "$clone" show "origin/main:version.json" 2>/dev/null && return 0
    fi
  fi
  return 1
}
