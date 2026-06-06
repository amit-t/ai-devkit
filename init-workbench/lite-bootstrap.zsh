#!/usr/bin/env zsh
# lite-bootstrap.zsh - deterministic Workbench Lite setup used by init.wb --lite.

set -euo pipefail

script_path="${0:A}"
SCRIPT_DIR="${script_path:h}"
DEVKIT_DIR="${SCRIPT_DIR:h}"
TOOLS_PARENT="${DEVKIT_DIR:h}"

MARKER_START="# >>> ai-devkit workbench-lite >>>"
MARKER_END="# <<< ai-devkit workbench-lite <<<"
REMEDIATION='Lite setup incomplete: rpd.p not found. Run devkit doctor or install Ralph, then rerun init.wb --lite.'
PROFILE_FILE="${WB_LITE_PROFILE:-${ZDOTDIR:-${HOME}}/.zprofile}"
PRINT_REMEDIATION=false

usage() {
  cat <<'USAGE'
lite-bootstrap.zsh - Workbench Lite setup helper.

Usage:
  lite-bootstrap.zsh --wb-dir <workbench-dir>
  lite-bootstrap.zsh --undo

Environment for tests/advanced use:
  WB_LITE_RALPH_SRC    ai-ralph checkout to install from
  WB_LITE_PROFILE      shell profile to update (default: ${ZDOTDIR:-$HOME}/.zprofile)
  WB_LITE_RALPH_REPO   clone URL if ai-ralph is missing
USAGE
}

_on_exit() {
  local rc=$?
  if (( rc != 0 )) && [[ "$PRINT_REMEDIATION" == true ]]; then
    print -u2 -r -- "$REMEDIATION"
  fi
}
trap _on_exit EXIT

_profile_without_marker() {
  local profile="$1"
  [[ -f "$profile" ]] || return 0
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    skip != 1 { print }
  ' "$profile"
}

_write_lite_profile_block() {
  local ralph_src="$1"
  local profile="$PROFILE_FILE"
  local tmp_file

  mkdir -p -- "${profile:h}"
  tmp_file="$(mktemp -t wb-lite-profile.XXXXXX)"
  _profile_without_marker "$profile" > "$tmp_file"

  {
    cat "$tmp_file"
    print -r -- ""
    print -r -- "$MARKER_START"
    print -r -- '# Workbench Lite: Ralph Devin engine + rpd/rpd.p aliases.'
    print -r -- 'export PATH="$HOME/.local/bin:$PATH"'
    print -r -- "export RALPH_CLONE=\"$ralph_src\""
    print -r -- 'if [[ -f "$RALPH_CLONE/devin/ALIASES.sh" ]]; then'
    print -r -- '  source "$RALPH_CLONE/devin/ALIASES.sh"'
    print -r -- 'fi'
    print -r -- "$MARKER_END"
  } > "$profile"

  rm -f -- "$tmp_file"
}

_undo_lite_profile_block() {
  local profile="$PROFILE_FILE"
  local tmp_file
  [[ -f "$profile" ]] || return 0
  tmp_file="$(mktemp -t wb-lite-profile.XXXXXX)"
  _profile_without_marker "$profile" > "$tmp_file"
  mv -- "$tmp_file" "$profile"
  print -r -- "Workbench Lite shell profile block removed from $profile"
}

_add_local_bin_to_current_path() {
  local bin_dir="${HOME}/.local/bin"
  if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
    export PATH="$bin_dir:$PATH"
  fi
}

_resolve_ralph_src() {
  local candidate
  for candidate in \
    "${WB_LITE_RALPH_SRC:-}" \
    "${RALPH_CLONE:-}" \
    "${TOOLS_PARENT}/ai-ralph" \
    "${HOME}/Projects/Tools-Utilities/ai-ralph"; do
    [[ -n "$candidate" && -d "$candidate" ]] && { print -r -- "${candidate:A}"; return 0; }
  done

  candidate="${TOOLS_PARENT}/ai-ralph"
  local repo_url="${WB_LITE_RALPH_REPO:-https://github.com/Invenco-Cloud-Systems-ICS/ai-ralph.git}"
  print -u2 -r -- "ai-ralph not found locally. Cloning $repo_url -> $candidate"
  git clone "$repo_url" "$candidate"
  print -r -- "${candidate:A}"
}

_install_ralph_if_needed() {
  local ralph_src="$1"
  if ! command -v ralph >/dev/null 2>&1; then
    [[ -x "$ralph_src/install.sh" || -f "$ralph_src/install.sh" ]] || {
      print -u2 -r -- "ai-ralph install.sh not found at $ralph_src/install.sh"
      return 1
    }
    print -r -- "Installing base ai-ralph from $ralph_src"
    (cd "$ralph_src" && bash ./install.sh)
    _add_local_bin_to_current_path
  fi
  command -v ralph >/dev/null 2>&1 || { print -u2 -r -- "ralph install failed"; return 1; }
}

_install_ralph_devin_if_needed() {
  local ralph_src="$1"
  if ! command -v ralph-devin >/dev/null 2>&1; then
    [[ -x "$ralph_src/devin/install_devin.sh" || -f "$ralph_src/devin/install_devin.sh" ]] || {
      print -u2 -r -- "Ralph Devin installer not found at $ralph_src/devin/install_devin.sh"
      return 1
    }
    print -r -- "Installing Ralph Devin engine from $ralph_src"
    (cd "$ralph_src" && bash ./devin/install_devin.sh)
    _add_local_bin_to_current_path
  fi
  command -v ralph-devin >/dev/null 2>&1 || { print -u2 -r -- "ralph-devin install failed"; return 1; }
}

_verify_lite_aliases() {
  local profile="$PROFILE_FILE"
  HOME="$HOME" zsh -l -c "source ${(q)profile}; command -v ralph-devin >/dev/null && command -v rpd >/dev/null && command -v rpd.p >/dev/null" >/dev/null 2>&1 || {
    print -u2 -r -- "rpd.p not found after sourcing $profile"
    return 1
  }
}

_lite_defaults_block() {
  cat <<'DEFAULTS'
# --- Workbench Lite defaults ---
WB_LITE_PRD_AGENT="codex"
WB_LITE_SPEC_AGENT="codex"
WB_LITE_GRILL_AGENT="codex"
WB_LITE_CHECKPOINT_AGENT="codex"
WB_LITE_PLAN_AGENT="codex"      # forward-compat; v1 plan delegates to ralph-plan
WB_LITE_RALPH_AGENT="rpd.p"     # user-facing mnemonic; wrapper execs ralph-devin --parallel N
WB_LITE_GRILL_MODE="ask"        # ask | auto | live
WB_LITE_DEFAULT_TASKS="5"
WB_LITE_PLAN_MODE="delegate"    # delegate (ralph-plan) | synthesize
WB_LITE_AGENT_INVOKE="stdin"    # stdin | argv
DEFAULTS
}

_seed_lite_defaults() {
  local wb_dir="$1"
  local conf="$wb_dir/project.conf"
  [[ -f "$conf" ]] || { print -u2 -r -- "project.conf not found at $conf"; return 1; }

  if grep -qF '# --- Workbench Lite defaults ---' "$conf"; then
    return 0
  fi

  {
    print -r -- ""
    _lite_defaults_block
  } >> "$conf"
}

_repo_names_from_project_conf() {
  local wb_dir="$1"
  local conf="$wb_dir/project.conf"
  local -a REPOS

  REPOS=()
  source "$conf"

  local entry part repo_name
  for entry in "${REPOS[@]}"; do
    repo_name=""
    for part in ${(ps:;:)entry}; do
      if [[ "$part" == name=* ]]; then
        repo_name="${part#name=}"
        break
      fi
    done
    [[ -n "$repo_name" ]] && print -r -- "$repo_name"
  done
}

_enable_lite_repo() {
  local repo_dir="$1"
  [[ -d "$repo_dir" ]] || { print -u2 -r -- "registered repo missing: $repo_dir"; return 1; }

  # Prefer the modern ai-ralph form required by Workbench Lite. Fall back only
  # for older installs that still expose ralph-enable as a standalone wrapper.
  local enable_out enable_err
  enable_out="$(mktemp -t wb-lite-ralph-enable.out.XXXXXX)"
  enable_err="$(mktemp -t wb-lite-ralph-enable.err.XXXXXX)"

  if (cd "$repo_dir" && ralph enable >"$enable_out" 2>"$enable_err"); then
    cat "$enable_out"
    cat "$enable_err" >&2
    rm -f -- "$enable_out" "$enable_err"
    return 0
  fi

  if command -v ralph-enable >/dev/null 2>&1; then
    rm -f -- "$enable_out" "$enable_err"
    print -u2 -r -- "ralph enable failed in $repo_dir; retrying legacy ralph-enable --non-interactive"
    (cd "$repo_dir" && ralph-enable --non-interactive)
    return $?
  fi

  cat "$enable_out"
  cat "$enable_err" >&2
  rm -f -- "$enable_out" "$enable_err"
  return 1
}

_enable_lite_repos() {
  local wb_dir="$1"
  local repo_name repo_dir
  local found=false

  while IFS= read -r repo_name; do
    [[ -n "$repo_name" ]] || continue
    found=true
    repo_dir="$wb_dir/repos/$repo_name"
    _enable_lite_repo "$repo_dir"
    [[ -d "$repo_dir/.ralph" ]] || { print -u2 -r -- "ralph enable did not create $repo_dir/.ralph"; return 1; }
  done < <(_repo_names_from_project_conf "$wb_dir")

  if [[ "$found" != true ]]; then
    print -u2 -r -- "project.conf REPOS is empty; Workbench Lite needs at least one app repo"
    return 1
  fi

  [[ ! -d "$wb_dir/.ralph" ]] || { print -u2 -r -- "Workbench Lite must not create a workbench-root .ralph"; return 1; }
}

_lite_bootstrap() {
  local wb_dir="$1"
  wb_dir="${wb_dir:A}"
  [[ -d "$wb_dir" ]] || { print -u2 -r -- "workbench dir not found: $wb_dir"; return 1; }

  PRINT_REMEDIATION=true
  _add_local_bin_to_current_path

  local ralph_src
  ralph_src="$(_resolve_ralph_src)"
  _install_ralph_if_needed "$ralph_src"
  _install_ralph_devin_if_needed "$ralph_src"
  _write_lite_profile_block "$ralph_src"
  _verify_lite_aliases
  _enable_lite_repos "$wb_dir"
  _seed_lite_defaults "$wb_dir"

  print -r -- "Workbench Lite setup complete for $wb_dir"
}

main() {
  local wb_dir=""
  local undo=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --wb-dir)
        wb_dir="${2:-}"
        shift 2
        ;;
      --undo)
        undo=true
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        print -u2 -r -- "Unknown flag: $1"
        usage >&2
        return 1
        ;;
    esac
  done

  if [[ "$undo" == true ]]; then
    _undo_lite_profile_block
    return 0
  fi

  [[ -n "$wb_dir" ]] || { print -u2 -r -- "--wb-dir is required"; usage >&2; return 1; }
  _lite_bootstrap "$wb_dir"
}

main "$@"
