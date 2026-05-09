#!/usr/bin/env bash
gh() {
  if [[ "${GH_SHIM_FAIL:-0}" == "1" ]]; then
    return 1
  fi
  local key
  if command -v md5sum >/dev/null 2>&1; then
    key="$(printf '%s|' "$@" | md5sum | cut -c1-32)"
  elif command -v md5 >/dev/null 2>&1; then
    key="$(printf '%s|' "$@" | md5 -q | cut -c1-32)"
  else
    key="$(printf '%s|' "$@" | shasum | cut -c1-32)"
  fi
  local response_path="${GH_SHIM_RESPONSES_DIR:-/tmp/gh-shim}/$key.json"
  if [[ -f "$response_path" ]]; then
    cat "$response_path"
    return 0
  fi
  return 1
}
export -f gh >/dev/null 2>&1 || true
