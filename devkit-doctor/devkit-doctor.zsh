#!/usr/bin/env zsh
# devkit-doctor — show versioning state of devkit + ralph (+ wb if in stamped wb).
#
# Usage:
#   devkit doctor              # interactive report
#   devkit doctor --check-only # exit non-zero if any tool stale OR structural FAIL
#   devkit doctor --fix        # interactive upgrade in dep order + repair global health
#   devkit doctor --fix --yes  # unattended upgrade

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LIB_DIR="${SCRIPT_DIR}/../lib"
DEVKIT_DIR="${SCRIPT_DIR:h}"

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
devkit doctor — show or repair version + structural health state.

Usage:
  devkit doctor              # interactive report
  devkit doctor --check-only # exit non-zero if any tool stale OR critical health FAIL
  devkit doctor --fix        # interactive upgrade in dep order + repair global health
  devkit doctor --fix --yes  # unattended upgrade

Health checks (in addition to version rows):
  Global:
    repo-context-scan vendored   FAIL counts toward --check-only exit nonzero
    engine symlinks intact       FAIL counts
    wb-context-scan lib          FAIL counts
    DEVKIT_DEFAULT_ENGINE set    WARN only
    engine available             WARN only
  WB-scope (only when cwd is a stamped workbench):
    context/ exists, matches project.conf, no stale stubs,
    aggregate README current, .context-scan/ worktree clean — all WARN-only.

  --fix repairs deterministic global checks; WB-scope --fix prints suggested
  wb.rescan commands (advisory, never auto-rescans).
USAGE
      exit 0 ;;
    *) print -r -- "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

_detect_wb_root() {
  local d="${PWD:A}"
  while [[ -n "$d" && "$d" != "/" && "$d" != "$HOME" ]]; do
    if [[ -f "$d/.workbench-manifest.json" && -f "$d/project.conf" ]]; then
      print -r -- "$d"
      return 0
    fi
    d="${d:h}"
  done
  return 1
}

is_stamped_wb=false
WB_ROOT=""
if WB_ROOT="$(_detect_wb_root 2>/dev/null)" && [[ -n "$WB_ROOT" ]]; then
  is_stamped_wb=true
fi

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
  state="$(WB_TEMPLATE_VERSION_FILE="${WB_ROOT}/.workbench-state/template-version.json" fetch_tool_state wb)"
  local_v="${state%%|*}"
  latest="${state##*|}"
  render_row "wb" "$local_v" "$latest"
  if [[ "$latest" != "?" && "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    stale=$(( stale + 1 ))
  fi
fi

# ─── Health checks (Phase 4) ─────────────────────────────────────────────
# Separate counter for structural FAILs that --check-only should treat as
# non-zero-exit-worthy alongside version staleness.
health_fail=0
# Track wb-scope WARN signals so --fix can render the advisory block.
wb_warn_messages=()

render_check() {
  local label="$1" check_status="$2" detail="$3"
  printf "  %-32s %-7s %s\n" "$label" "$check_status" "$detail"
}

# Check 1 — repo-context-scan vendored
SKILL_DIR="${DEVKIT_DIR}/skills/repo-context-scan"
SKILL_MD="${SKILL_DIR}/SKILL.md"
SKILL_UPSTREAM="${SKILL_DIR}/.upstream"
check1_status=""
check1_detail=""
skill_sha_short=""
skill_synced_at=""
if [[ -f "$SKILL_UPSTREAM" ]]; then
  skill_sha_short="$(grep '^upstream_sha:' "$SKILL_UPSTREAM" 2>/dev/null | awk '{print $2}' | cut -c1-12)"
  skill_synced_at="$(grep '^synced_at:' "$SKILL_UPSTREAM" 2>/dev/null | awk '{print $2}')"
fi
if [[ -f "$SKILL_MD" ]]; then
  check1_status="OK"
  if [[ -n "$skill_sha_short" ]]; then
    check1_detail="sha ${skill_sha_short}"
  else
    check1_detail="present (no .upstream pin)"
  fi
else
  check1_status="FAIL"
  check1_detail="missing: ${SKILL_MD}"
  health_fail=$(( health_fail + 1 ))
fi

# Check 2 — engine symlinks intact
check2_status=""
check2_detail=""
typeset -a symlinks_to_check
symlinks_to_check=(
  "${HOME}/.claude/skills/repo-context-scan"
  "${HOME}/.devin/skills/repo-context-scan"
  "${HOME}/.agents/skills/repo-context-scan"
  "${DEVKIT_DIR}/.claude/skills/repo-context-scan"
  "${DEVKIT_DIR}/.agents/skills/repo-context-scan"
)
typeset -a broken_links
ok_count=0
for link in "${symlinks_to_check[@]}"; do
  if [[ -L "$link" ]] && [[ -e "$link" ]]; then
    ok_count=$(( ok_count + 1 ))
  else
    broken_links+=("$link")
  fi
done
total_links=${#symlinks_to_check[@]}
if (( ${#broken_links[@]} == 0 )); then
  check2_status="OK"
  check2_detail="${ok_count}/${total_links} resolve"
else
  check2_status="FAIL"
  # First broken link only — keep detail string compact.
  check2_detail="${ok_count}/${total_links} resolve; broken: ${broken_links[1]}"
  health_fail=$(( health_fail + 1 ))
fi

# Check 3 — wb-context-scan lib
WB_LIB="${DEVKIT_DIR}/lib/wb-context-scan.zsh"
check3_status=""
check3_detail=""
if [[ -r "$WB_LIB" ]]; then
  if [[ -x "$WB_LIB" ]]; then
    check3_status="OK"
    check3_detail="${WB_LIB}"
  else
    check3_status="FAIL"
    check3_detail="not executable: ${WB_LIB}"
    health_fail=$(( health_fail + 1 ))
  fi
else
  check3_status="FAIL"
  check3_detail="missing: ${WB_LIB}"
  health_fail=$(( health_fail + 1 ))
fi

# Check 4 — DEVKIT_DEFAULT_ENGINE set (WARN-only)
check4_status=""
check4_detail=""
if [[ -n "${DEVKIT_DEFAULT_ENGINE:-}" ]]; then
  check4_status="OK"
  check4_detail="${DEVKIT_DEFAULT_ENGINE}"
else
  check4_status="WARN"
  check4_detail="not set; re-run install.zsh or source ~/.zprofile"
fi

# Check 5 — engine available (WARN-only)
check5_status=""
check5_detail=""
engine_name="${DEVKIT_DEFAULT_ENGINE:-claude}"
if (( $+commands[$engine_name] )); then
  check5_status="OK"
  check5_detail="${engine_name} -> ${commands[$engine_name]}"
else
  check5_status="WARN"
  check5_detail="${engine_name} not on PATH"
fi

print -r --
print -r -- "CHECK                            STATUS  DETAIL"
render_check "repo-context-scan vendored"   "$check1_status" "$check1_detail"
render_check "engine symlinks intact"       "$check2_status" "$check2_detail"
render_check "wb-context-scan lib"          "$check3_status" "$check3_detail"
render_check "DEVKIT_DEFAULT_ENGINE set"    "$check4_status" "$check4_detail"
render_check "engine available"             "$check5_status" "$check5_detail"

# ─── Vendored skill SHA banner (non-check-only output) ───────────────────
if ! $CHECK_ONLY; then
  print -r --
  if [[ -f "$SKILL_UPSTREAM" && -n "$skill_sha_short" ]]; then
    if [[ -n "$skill_synced_at" ]]; then
      printf "Vendored skill: repo-context-scan @ %s   (synced %s)\n" \
        "$skill_sha_short" "$skill_synced_at"
    else
      printf "Vendored skill: repo-context-scan @ %s\n" "$skill_sha_short"
    fi
  else
    print -r -- "Vendored skill: (not installed)"
  fi
fi

# ─── WB-scope checks (only when cwd is a stamped workbench) ──────────────
if $is_stamped_wb; then
  print -r --
  print -r -- "WB-CHECK                         STATUS  DETAIL"

  # WB-Check 1 — context/ exists
  ctx_root="${WB_ROOT}/context"
  wb1_status=""
  wb1_detail=""
  if [[ -d "$ctx_root" ]]; then
    subdir_count="$(find "$ctx_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    wb1_status="OK"
    wb1_detail="${subdir_count} subdirs"
  else
    wb1_status="WARN"
    wb1_detail="context/ missing"
    wb_warn_messages+=("context/ directory absent — run wb.rescan --all to create it.")
  fi
  render_check "context/ exists" "$wb1_status" "$wb1_detail"

  # WB-Check 2 — context/ matches project.conf
  wb2_status=""
  wb2_detail=""
  typeset -a repos_in_conf
  repos_in_conf=()
  # Source project.conf inside subshell to harvest REPOS entries safely.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    repos_in_conf+=("$line")
  done < <(zsh -c "
    set +e
    source '${WB_ROOT}/project.conf' 2>/dev/null
    for entry in \"\${REPOS[@]}\"; do
      name=''
      for kv in \${(s.;.)entry}; do
        case \"\$kv\" in
          name=*) name=\${kv#name=} ;;
        esac
      done
      [[ -n \"\$name\" ]] && print -r -- \"\$name\"
    done
  ")
  typeset -A conf_set
  for r in "${repos_in_conf[@]}"; do
    conf_set[$r]=1
  done
  typeset -a orphans missing
  orphans=()
  missing=()
  if [[ -d "$ctx_root" ]]; then
    for d in "$ctx_root"/*(N/); do
      nm="${d:t}"
      if [[ -z "${conf_set[$nm]+x}" ]]; then
        orphans+=("$nm")
      fi
    done
  fi
  for r in "${repos_in_conf[@]}"; do
    if [[ ! -d "${ctx_root}/${r}" ]]; then
      missing+=("$r")
    fi
  done
  if (( ${#orphans[@]} == 0 && ${#missing[@]} == 0 )); then
    wb2_status="OK"
    wb2_detail="clean"
  else
    wb2_status="WARN"
    wb2_detail="${#orphans[@]} orphans, ${#missing[@]} missing"
    if (( ${#missing[@]} > 0 )); then
      wb_warn_messages+=("Missing context for: ${missing[*]} — run: wb.rescan <repo>")
    fi
    if (( ${#orphans[@]} > 0 )); then
      wb_warn_messages+=("Orphan context dirs: ${orphans[*]} — remove or re-add to project.conf.")
    fi
  fi
  render_check "context/ matches project.conf" "$wb2_status" "$wb2_detail"

  # WB-Check 3 — no stale stubs
  wb3_status=""
  wb3_detail=""
  typeset -a stub_repos
  stub_repos=()
  if [[ -d "$ctx_root" ]]; then
    for d in "$ctx_root"/*(N/); do
      cm="${d}/CONTEXT.md"
      [[ -f "$cm" ]] || continue
      if awk '
        NR==1 && $0=="---" { in_block=1; next }
        in_block && $0=="---" { exit }
        in_block && /^status:[[:space:]]+scan-failed/ { found=1; exit }
        END { exit !found }
      ' "$cm" 2>/dev/null; then
        stub_repos+=("${d:t}")
      fi
    done
  fi
  if (( ${#stub_repos[@]} == 0 )); then
    wb3_status="OK"
    wb3_detail="none"
  else
    wb3_status="WARN"
    wb3_detail="${#stub_repos[@]} stubs: ${stub_repos[*]}"
    wb_warn_messages+=("Stale stubs: ${stub_repos[*]} — run: wb.rescan <repo>")
  fi
  render_check "no stale stubs" "$wb3_status" "$wb3_detail"

  # WB-Check 4 — aggregate README current
  wb4_status=""
  wb4_detail=""
  readme="${ctx_root}/README.md"
  if [[ ! -f "$readme" ]]; then
    if [[ -d "$ctx_root" ]] && find "$ctx_root" -mindepth 2 -maxdepth 2 \
        \( -name CONTEXT.md -o -name CONTEXT-MAP.md \) 2>/dev/null | grep -q .; then
      wb4_status="WARN"
      wb4_detail="README.md missing"
      wb_warn_messages+=("Aggregate README missing — run: wb.rescan --aggregate-only")
    else
      wb4_status="OK"
      wb4_detail="no context yet"
    fi
  else
    # Find the newest per-repo CONTEXT.md / CONTEXT-MAP.md.
    newest_ctx_mtime=0
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      m="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
      if (( m > newest_ctx_mtime )); then
        newest_ctx_mtime=$m
      fi
    done < <(find "$ctx_root" -mindepth 2 -maxdepth 2 \
              \( -name CONTEXT.md -o -name CONTEXT-MAP.md \) 2>/dev/null)
    readme_mtime="$(stat -f %m "$readme" 2>/dev/null || stat -c %Y "$readme" 2>/dev/null || echo 0)"
    if (( newest_ctx_mtime == 0 )); then
      wb4_status="OK"
      wb4_detail="no per-repo CONTEXT files"
    elif (( readme_mtime >= newest_ctx_mtime )); then
      wb4_status="OK"
      wb4_detail="current"
    else
      stale_by=$(( newest_ctx_mtime - readme_mtime ))
      wb4_status="WARN"
      wb4_detail="stale by ${stale_by}s"
      wb_warn_messages+=("README.md stale by ${stale_by}s — run: wb.rescan --aggregate-only")
    fi
  fi
  render_check "aggregate README current" "$wb4_status" "$wb4_detail"

  # WB-Check 5 — .context-scan/ worktree clean
  wb5_status=""
  wb5_detail=""
  scan_root="${WB_ROOT}/.context-scan"
  if [[ ! -d "$scan_root" ]]; then
    wb5_status="OK"
    wb5_detail="absent"
  else
    typeset -a stale_worktrees
    stale_worktrees=()
    for d in "$scan_root"/*(N/); do
      # Ignore lock dir; we only care about per-repo worktree dirs.
      [[ "${d:t}" == ".lock" ]] && continue
      stale_worktrees+=("${d:t}")
    done
    if (( ${#stale_worktrees[@]} == 0 )); then
      wb5_status="OK"
      wb5_detail="clean"
    else
      wb5_status="WARN"
      wb5_detail="${#stale_worktrees[@]} stale worktree(s): ${stale_worktrees[*]}"
      wb_warn_messages+=("Stale worktrees in .context-scan/: ${stale_worktrees[*]} — remove with: rm -rf .context-scan/<n>")
    fi
  fi
  render_check ".context-scan/ worktree clean" "$wb5_status" "$wb5_detail"
fi

# ─── Exit / --fix handling ───────────────────────────────────────────────
total_bad=$(( stale + health_fail ))

if (( total_bad > 0 )); then
  if $CHECK_ONLY; then
    exit 4
  fi
  if $FIX; then
    fix_args=()
    $YES && fix_args+=("--yes")
    print -r -- ""

    # Repair global structural issues first — deterministic, no version churn.
    if [[ "$check1_status" == "FAIL" ]]; then
      print -r -- "Repairing: repo-context-scan vendored"
      if [[ -x "${DEVKIT_DIR}/scripts/sync-skill.zsh" ]]; then
        zsh "${DEVKIT_DIR}/scripts/sync-skill.zsh" repo-context-scan || \
          print -u2 -r -- "  sync-skill.zsh failed; see output above."
      else
        print -u2 -r -- "  ${DEVKIT_DIR}/scripts/sync-skill.zsh not found or not executable."
      fi
    fi
    if [[ "$check2_status" == "FAIL" ]]; then
      print -r -- "Repairing: engine symlinks intact (re-running install.zsh — idempotent)"
      if [[ -x "${DEVKIT_DIR}/install.zsh" ]]; then
        zsh "${DEVKIT_DIR}/install.zsh" >/dev/null || \
          print -u2 -r -- "  install.zsh failed; see output above."
      else
        print -u2 -r -- "  ${DEVKIT_DIR}/install.zsh not found or not executable."
      fi
    fi
    if [[ "$check3_status" == "FAIL" && -r "$WB_LIB" ]]; then
      print -r -- "Repairing: wb-context-scan lib (chmod +x)"
      chmod +x "$WB_LIB" || print -u2 -r -- "  chmod +x failed on ${WB_LIB}"
    fi

    # Version upgrades cascade after structural repairs.
    if (( stale > 0 )); then
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
fi

# WB-scope --fix is informational only (Q12 locked decision).
if $FIX && $is_stamped_wb && (( ${#wb_warn_messages[@]} > 0 )); then
  print -r --
  print -r -- "WB-scope fixes are advisory. Suggested commands:"
  for msg in "${wb_warn_messages[@]}"; do
    print -r -- "  - ${msg}"
  done
fi
