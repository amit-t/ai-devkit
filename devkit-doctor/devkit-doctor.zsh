#!/usr/bin/env zsh
# devkit-doctor — show versioning state of devkit + ralph (+ wb if in stamped wb).
#
# Usage:
#   devkit doctor              # interactive report
#   devkit doctor --check-only # exit non-zero if any tool stale
#   devkit doctor --fix        # interactive upgrade in dep order
#   devkit doctor --fix --yes  # unattended upgrade

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LIB_DIR="${SCRIPT_DIR}/../lib"

_VERCHECK_LIB_DIR_OVERRIDE="$LIB_DIR" . "${LIB_DIR}/version-check.sh"

CHECK_ONLY=false
FIX=false
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=true; shift ;;
    --fix) FIX=true; shift ;;
    --yes) YES=true; shift ;;
    -h|--help)
      cat <<USAGE
devkit doctor — show or repair version state.

Usage:
  devkit doctor              # interactive report
  devkit doctor --check-only # exit non-zero if any tool stale
  devkit doctor --fix        # interactive upgrade in dep order
  devkit doctor --fix --yes  # unattended upgrade
USAGE
      exit 0 ;;
    *) print -r -- "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

check_wsl_mnt_path() {
  if [[ "$PWD" == /mnt/* ]]; then
    print -ru2 -- "WARNING: doctor running from /mnt/ (DrvFs). Clone repos under \$HOME instead, DrvFs is ~10x slower and breaks fsync semantics."
  fi
}

is_stamped_wb=false
if [[ -f "$PWD/.workbench-manifest.json" && -f "$PWD/project.conf" ]]; then
  is_stamped_wb=true
fi

check_wsl_mnt_path

fetch_tool_state() {
  local tool="$1"
  local fresh latest local_v upstream_json
  local_v="$(_wb_local_version "$tool")"
  fresh="$(_wb_cache_is_fresh "$tool")"
  if [[ "$fresh" == "fresh" ]]; then
    upstream_json="$(_wb_cache_read "$tool")"
  else
    case "$tool" in
      devkit) upstream_json="$(_wb_fetch_upstream amit-t ai-devkit 2>/dev/null || echo '')" ;;
      ralph)  upstream_json="$(_wb_fetch_upstream amit-t ai-ralph  2>/dev/null || echo '')" ;;
      wb)     upstream_json="$(_wb_fetch_upstream amit-t ai-workbench 2>/dev/null || echo '')" ;;
    esac
    if [[ -n "$upstream_json" ]]; then
      local ttl
      ttl="$(echo "$upstream_json" | jq -r '.check_ttl_hours // 12' 2>/dev/null)"
      case "$ttl" in ''|*[!0-9]*) ttl="12" ;; esac
      _wb_cache_write "$tool" "$upstream_json" "$ttl"
    fi
  fi
  if [[ -z "${upstream_json:-}" ]]; then
    latest="?"
  else
    latest="$(echo "$upstream_json" | jq -r '.version // "?"')"
  fi
  echo "${local_v}|${latest}"
}

render_row() {
  local tool="$1" local_v="$2" latest="$3"
  local row_status
  if [[ "$latest" == "?" ]]; then
    row_status="(check failed)"
  elif [[ "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    row_status="upgrade available"
  else
    row_status="current"
  fi
  printf "  %-10s %-10s %-10s %s\n" "$tool" "$local_v" "$latest" "$row_status"
}

print -r -- "TOOL       LOCAL      LATEST     STATUS"
stale=0
for tool in devkit ralph; do
  state="$(fetch_tool_state "$tool")"
  local_v="${state%%|*}"
  latest="${state##*|}"
  render_row "$tool" "$local_v" "$latest"
  if [[ "$latest" != "?" && "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    stale=$(( stale + 1 ))
  fi
done

if $is_stamped_wb; then
  state="$(WB_TEMPLATE_VERSION_FILE="$PWD/.workbench-state/template-version.json" fetch_tool_state wb)"
  local_v="${state%%|*}"
  latest="${state##*|}"
  render_row "wb" "$local_v" "$latest"
  if [[ "$latest" != "?" && "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    stale=$(( stale + 1 ))
  fi
fi

if (( stale > 0 )); then
  if $CHECK_ONLY; then
    exit 4
  fi
  if $FIX; then
    fix_args=()
    $YES && fix_args+=("--yes")
    print -r -- ""
    print -r -- "Running upgrades in dep order: ralph -> devkit -> wb"
    if command -v ralph.upgrade >/dev/null 2>&1; then
      ralph.upgrade "${fix_args[@]}" || true
    fi
    if command -v devkit.upgrade >/dev/null 2>&1; then
      devkit.upgrade "${fix_args[@]}" || true
    fi
    if $is_stamped_wb && command -v wb.upgrade >/dev/null 2>&1; then
      wb.upgrade "${fix_args[@]}" || true
    fi
  fi
fi
