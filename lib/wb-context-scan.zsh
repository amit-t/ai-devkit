#!/usr/bin/env zsh
# wb-context-scan.zsh — Wrapper library for repo-context-scan skill.
#
# This is a CLI with subcommands; it is NOT meant to be sourced.
#
# Usage:
#   zsh lib/wb-context-scan.zsh setup    <WB_DIR> <name>
#   zsh lib/wb-context-scan.zsh finalize <WB_DIR> <name> [--fail-reason "..."]
#   zsh lib/wb-context-scan.zsh aggregate <WB_DIR>
#
# The library is pure deterministic shell. Agent dispatch lives in the
# orchestration layer (Phases 5/6). Between `setup` and `finalize` an
# external agent is expected to populate the SCAN_DIR with CONTEXT.md /
# CONTEXT-MAP.md / docs/adr.
#
# Locked decisions: see plan Q1, Q2, Q4, Q5, Q6, Q10, Q15+16.
#
# Lock primitive: prefer flock(1) when available; otherwise fall back to
# mkdir-as-lock (atomic on POSIX). macOS lacks flock by default — the
# mkdir path is the default-portable choice.

set -euo pipefail

# Capture the script's real path BEFORE defining functions — inside a zsh
# function $0 is the function name, not the script path.
script_path="${0:A}"
SCRIPT_DIR="${script_path:h}"
DEVKIT_DIR="${DEVKIT_DIR:-${SCRIPT_DIR:h}}"

# ─── logging helpers ─────────────────────────────────────────────────────
_ok()   { print -r --  "[+] $*"; }
_info() { print -r --  "[i] $*"; }
_warn() { print -u2 -r -- "[!] $*"; }
_err()  { print -u2 -r -- "[x] $*"; }

# ─── lock primitives ─────────────────────────────────────────────────────
# Lock path: <WB_DIR>/.context-scan/.lock
#   - flock available: use a real fd-based lock on .lock (a file)
#   - flock missing:   mkdir .lock (atomic create) as a poor-man's lock
#
# Both produce identical observable behaviour: setup() acquires the lock;
# finalize() releases it. The lock is per-WB_DIR, not per-repo, matching
# the plan's "prevent concurrent scans" requirement.

_lock_path() {
  print -r -- "${1}/.context-scan/.lock"
}

_lock_acquire() {
  local wb="$1" lock
  lock="$(_lock_path "$wb")"
  mkdir -p "${wb}/.context-scan"
  if (( $+commands[flock] )); then
    # flock-based: touch the file, take an exclusive non-blocking lock, leave
    # an fd open by writing the lock pid into the file. Release path closes fd.
    : > "$lock"
    exec 9>"$lock"
    if ! flock -n 9; then
      _err "lock contended: another wb-context-scan run is in progress (${lock})"
      return 1
    fi
    print -r -- "$$" >&9
    return 0
  else
    # mkdir-as-lock: atomic create. If it already exists, contended.
    if ! mkdir "$lock" 2>/dev/null; then
      _err "lock contended: another wb-context-scan run is in progress (${lock})"
      return 1
    fi
    print -r -- "$$" > "${lock}/owner.pid"
    return 0
  fi
}

_lock_release() {
  local wb="$1" lock
  lock="$(_lock_path "$wb")"
  if (( $+commands[flock] )); then
    [[ -f "$lock" ]] && rm -f "$lock"
    exec 9>&- 2>/dev/null || true
  else
    [[ -d "$lock" ]] && rm -rf "$lock"
  fi
  return 0
}

# ─── REPOS parsing ──────────────────────────────────────────────────────
# Source project.conf inside a subshell, then for each REPOS entry split on
# `;` and `=`. Result is printed as TSV: `name<TAB>role<TAB>url`.
_parse_repos_conf() {
  local conf="$1"
  [[ -f "$conf" ]] || return 0
  zsh -c "
    set +e
    source '$conf' 2>/dev/null
    for entry in \"\${REPOS[@]}\"; do
      name=''; role=''; url=''
      # zsh-portable split on ';' into kv pairs
      for kv in \${(s.;.)entry}; do
        case \"\$kv\" in
          name=*) name=\${kv#name=} ;;
          role=*) role=\${kv#role=} ;;
          url=*)  url=\${kv#url=} ;;
        esac
      done
      [[ -n \"\$name\" ]] && printf '%s\t%s\t%s\n' \"\$name\" \"\$role\" \"\$url\"
    done
  "
}

# Return the role for a single repo name, or empty.
_repo_role() {
  local conf="$1" name="$2"
  _parse_repos_conf "$conf" | awk -F '\t' -v n="$name" '$1==n {print $2; exit}'
}

# Return the url for a single repo name, or empty.
_repo_url() {
  local conf="$1" name="$2"
  _parse_repos_conf "$conf" | awk -F '\t' -v n="$name" '$1==n {print $3; exit}'
}

# ─── metadata capture ────────────────────────────────────────────────────
# _capture_source_metadata <WB_DIR> <name>
#   prints YAML frontmatter LINES (no surrounding ---) for the success path.
#   Caller is responsible for `status`, plus failure-only keys.
_capture_source_metadata() {
  local wb="$1" name="$2"
  local generated_at source_url source_commit devkit_version skill_version
  local conf="${wb}/project.conf"
  local repo_dir="${wb}/repos/${name}"

  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # source_url: project.conf REPOS first, then origin remote, else empty.
  source_url="$(_repo_url "$conf" "$name")"
  if [[ -z "$source_url" && -d "$repo_dir/.git" ]]; then
    source_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  fi

  # source_commit: HEAD of source repo, or 'no-head' if empty/missing.
  if [[ -d "$repo_dir/.git" ]] || [[ -f "$repo_dir/.git" ]]; then
    source_commit="$(git -C "$repo_dir" rev-parse --verify HEAD 2>/dev/null || echo no-head)"
  else
    source_commit="no-head"
  fi

  # devkit_version: read version.json via jq; fall back to empty.
  if [[ -f "${DEVKIT_DIR}/version.json" ]] && (( $+commands[jq] )); then
    devkit_version="$(jq -r '.version // ""' "${DEVKIT_DIR}/version.json" 2>/dev/null || echo "")"
  else
    devkit_version=""
  fi

  # skill_version: short SHA from .upstream pin; empty if missing.
  if [[ -f "${DEVKIT_DIR}/skills/repo-context-scan/.upstream" ]]; then
    skill_version="$(grep '^upstream_sha:' "${DEVKIT_DIR}/skills/repo-context-scan/.upstream" \
                       | awk '{print $2}' | cut -c1-12)"
  else
    skill_version=""
  fi

  print -r -- "generated_by:   ai-devkit/repo-context-scan"
  print -r -- "generated_at:   ${generated_at}"
  print -r -- "source_repo:    ${name}"
  print -r -- "source_url:     ${source_url}"
  print -r -- "source_commit:  ${source_commit}"
  print -r -- "devkit_version: ${devkit_version}"
  print -r -- "skill_version:  ${skill_version}"
}

# ─── frontmatter merge ──────────────────────────────────────────────────
# Devkit-owned keys (always overwrite on merge).
_DEVKIT_OWNED_KEYS=(
  generated_by generated_at source_repo source_url source_commit
  devkit_version skill_version status fail_reason failed_at retry_with
)

# _prepend_frontmatter <file> <new-yaml-block-without-fences>
#   If <file> has no `---` frontmatter at top: prepend ---\n<new>\n---\n<body>.
#   Else: parse existing block, merge per Q15+16 rules, re-emit.
_prepend_frontmatter() {
  local file="$1"
  local new_block="$2"
  local tmp first_line
  tmp="$(mktemp)"

  [[ -f "$file" ]] || { _err "_prepend_frontmatter: $file not found"; return 1; }

  first_line="$(head -n 1 "$file")"

  if [[ "$first_line" != "---" ]]; then
    # No existing frontmatter — simple prepend.
    {
      print -r -- "---"
      print -r -- "$new_block"
      print -r -- "---"
      cat "$file"
    } > "$tmp"
    mv "$tmp" "$file"
    return 0
  fi

  # Frontmatter exists: split into existing-block + body, then merge.
  local existing_block body_offset
  existing_block="$(awk '
    NR==1 && $0=="---" { in_block=1; next }
    in_block && $0=="---" { exit }
    in_block { print }
  ' "$file")"

  # body starts at line after the SECOND ---
  body_offset="$(awk '
    NR==1 && $0=="---" { in_block=1; next }
    in_block && $0=="---" { print NR+1; exit }
  ' "$file")"

  # Merge: walk existing keys, overwrite devkit-owned ones with new values
  # (when new has them). Then append any new keys not in existing.
  local merged
  merged="$(_merge_frontmatter_blocks "$existing_block" "$new_block")"

  {
    print -r -- "---"
    print -r -- "$merged"
    print -r -- "---"
    if [[ -n "$body_offset" ]]; then
      tail -n +"$body_offset" "$file"
    fi
  } > "$tmp"
  mv "$tmp" "$file"
}

# _merge_frontmatter_blocks <existing-yaml-lines> <new-yaml-lines>
#   Merge per Q15+16: devkit-owned keys overwritten from new, user keys
#   preserved, new keys appended at end. Order preserved from existing.
_merge_frontmatter_blocks() {
  local existing="$1" new="$2"
  local -A new_kv existing_kv printed is_devkit
  local -a new_order existing_order
  local k v line

  for k in "${_DEVKIT_OWNED_KEYS[@]}"; do is_devkit[$k]=1; done

  # parse new
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" != *:* ]] && continue
    k="${line%%:*}"
    v="${line#*:}"
    # strip leading whitespace from value (loop — portable, no extendedglob)
    while [[ "$v" == [[:space:]]* ]]; do v="${v#?}"; done
    if [[ -z "${new_kv[$k]+x}" ]]; then
      new_order+=("$k")
    fi
    new_kv[$k]="$v"
  done <<< "$new"

  # parse existing
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" != *:* ]] && continue
    k="${line%%:*}"
    v="${line#*:}"
    while [[ "$v" == [[:space:]]* ]]; do v="${v#?}"; done
    if [[ -z "${existing_kv[$k]+x}" ]]; then
      existing_order+=("$k")
    fi
    existing_kv[$k]="$v"
  done <<< "$existing"

  # emit existing keys (overwriting devkit-owned with new values when present)
  for k in "${existing_order[@]}"; do
    if [[ -n "${is_devkit[$k]+x}" && -n "${new_kv[$k]+x}" ]]; then
      printf '%-15s %s\n' "${k}:" "${new_kv[$k]}"
    else
      printf '%-15s %s\n' "${k}:" "${existing_kv[$k]}"
    fi
    printed[$k]=1
  done
  # append new keys not in existing
  for k in "${new_order[@]}"; do
    if [[ -z "${printed[$k]+x}" ]]; then
      printf '%-15s %s\n' "${k}:" "${new_kv[$k]}"
    fi
  done
}

# ─── top-concept extraction ─────────────────────────────────────────────
# Walk the body of <file>, find **bolded** terms, de-dup preserving order,
# return first 3 comma-space-joined. Empty result → "—" (em-dash).
_extract_top_concepts() {
  local file="$1"
  [[ -f "$file" ]] || { print -r -- "—"; return 0; }
  local concepts
  concepts="$(grep -oE '\*\*[^*]+\*\*' "$file" 2>/dev/null \
                | sed 's/\*\*//g' \
                | awk '!seen[$0]++' \
                | head -3 \
                | paste -sd ',' - \
                | sed 's/,/, /g')"
  if [[ -z "$concepts" ]]; then
    print -r -- "—"
  else
    print -r -- "$concepts"
  fi
}

# ─── harvest one file with defensive frontmatter merge ─────────────────
# _harvest_one <src-in-worktree> <dst-in-context-dir> <new-yaml-block>
#   Copies <src> over <dst>, but if <dst> previously existed with a
#   frontmatter carrying user-authored keys, those are merged into the
#   new frontmatter (devkit-owned keys overwritten with new values).
_harvest_one() {
  local src="$1" dst="$2" new_block="$3"
  local old_frontmatter=""

  if [[ -f "$dst" ]] && [[ "$(head -n 1 "$dst")" == "---" ]]; then
    old_frontmatter="$(awk '
      NR==1 && $0=="---" { in_block=1; next }
      in_block && $0=="---" { exit }
      in_block { print }
    ' "$dst")"
  fi

  cp "$src" "$dst"

  if [[ -n "$old_frontmatter" ]]; then
    # Seed the new file with the OLD frontmatter (preserves user keys).
    # Then _prepend_frontmatter sees an existing block and merges new
    # devkit-owned values over it.
    local tmp
    tmp="$(mktemp)"
    {
      print -r -- "---"
      print -r -- "$old_frontmatter"
      print -r -- "---"
      # If <src> happened to have its own frontmatter too, strip it —
      # devkit owns the frontmatter for harvested files.
      if [[ "$(head -n 1 "$dst")" == "---" ]]; then
        awk '
          NR==1 && $0=="---" { in_block=1; next }
          in_block && $0=="---" { in_block=0; printed=1; next }
          !in_block && printed { print }
        ' "$dst"
      else
        cat "$dst"
      fi
    } > "$tmp"
    mv "$tmp" "$dst"
  fi

  _prepend_frontmatter "$dst" "$new_block"
}

# ─── stub body ──────────────────────────────────────────────────────────
_stub_body() {
  local name="$1"
  cat <<STUB
# ${name} (scan failed)

Repo context scan did not produce output. Reason recorded in frontmatter.

Re-run after fixing the underlying issue:

    wb.rescan ${name}

If the failure is structural (e.g., the source repo isn't appropriate for
scanning), remove this directory:

    rm -rf context/${name}
STUB
}

# ─── subcommand: setup ──────────────────────────────────────────────────
# setup <WB_DIR> <name>
#  1. defensive prune + rm worktree dir
#  2. mkdir worktree path
#  3. git worktree add --detach
#  4. pre-wipe CONTEXT.md, CONTEXT-MAP.md, docs/adr in worktree
#  5. flock acquire
#  6. print SCAN_DIR=<absolute-path>
cmd_setup() {
  local wb="$1" name="$2"
  [[ -n "$wb"   ]] || { _err "setup: missing <WB_DIR>"; return 2; }
  [[ -n "$name" ]] || { _err "setup: missing <name>"; return 2; }

  wb="${wb:A}"
  local repo_dir="${wb}/repos/${name}"
  local scan_dir="${wb}/.context-scan/${name}"

  [[ -d "$repo_dir/.git" || -f "$repo_dir/.git" ]] || {
    _err "setup: source repo not a git repo: ${repo_dir}"
    return 2
  }

  # Acquire lock FIRST. If contended, do NOT mutate worktree state.
  _lock_acquire "$wb" || return 1

  # Defensive: clear stale worktree registry entries first.
  git -C "$repo_dir" worktree prune 2>/dev/null || true
  # Remove any stale worktree dir (worktree add requires path to not exist).
  if [[ -e "$scan_dir" ]]; then
    git -C "$repo_dir" worktree remove --force "$scan_dir" 2>/dev/null || true
    rm -rf "$scan_dir"
  fi

  mkdir -p "${wb}/.context-scan"

  # Add the worktree detached at HEAD. If repo has no HEAD (empty repo),
  # this will fail — that's a real error, not a scan failure. Silence both
  # stdout ("Preparing worktree...") and stderr so SCAN_DIR= is the only
  # thing on stdout.
  if ! git -C "$repo_dir" worktree add --detach "$scan_dir" HEAD >/dev/null 2>&1; then
    _lock_release "$wb"
    _err "setup: git worktree add failed (empty repo or detached corruption?)"
    return 1
  fi

  # Pre-wipe expected scan outputs from the worktree (force-fresh).
  rm -f  "${scan_dir}/CONTEXT.md"
  rm -f  "${scan_dir}/CONTEXT-MAP.md"
  rm -rf "${scan_dir}/docs/adr"

  print -r -- "SCAN_DIR=${scan_dir}"
  return 0
}

# ─── subcommand: finalize ───────────────────────────────────────────────
# finalize <WB_DIR> <name> [--fail-reason "..."]
#   - if scan output present and no --fail-reason: harvest to context/<name>/,
#     prepend success frontmatter.
#   - else: write stub CONTEXT.md with failure frontmatter + body.
#   - always: tear down worktree, release lock.
# Idempotent. Always exits 0 unless catastrophic.
cmd_finalize() {
  local wb="$1" name="$2"
  [[ -n "$wb"   ]] || { _err "finalize: missing <WB_DIR>"; return 2; }
  [[ -n "$name" ]] || { _err "finalize: missing <name>"; return 2; }
  shift 2

  local fail_reason=""
  while (( $# > 0 )); do
    case "$1" in
      --fail-reason)
        shift
        fail_reason="${1:-}"
        shift || true
        ;;
      *)
        _err "finalize: unknown flag: $1"
        return 2
        ;;
    esac
  done

  wb="${wb:A}"
  local scan_dir="${wb}/.context-scan/${name}"
  local out_dir="${wb}/context/${name}"
  local repo_dir="${wb}/repos/${name}"

  mkdir -p "$out_dir"

  # Capture metadata BEFORE worktree teardown (source_commit needs the repo).
  local meta
  meta="$(_capture_source_metadata "$wb" "$name")"

  local produced_context=false produced_map=false
  [[ -f "${scan_dir}/CONTEXT.md"     ]] && produced_context=true
  [[ -f "${scan_dir}/CONTEXT-MAP.md" ]] && produced_map=true

  if [[ -z "$fail_reason" ]] && ( $produced_context || $produced_map ); then
    # ── success harvest ───────────────────────────────────────────────
    # Defensive merge: if the OUTPUT location already has frontmatter from
    # a prior harvest (possibly with user-authored keys), preserve those
    # user keys across the new overwrite. Strategy: snapshot existing
    # frontmatter, copy fresh body, then merge old-frontmatter + new-meta
    # back in via _prepend_frontmatter (which itself handles the merge).
    local block="${meta}
status:         scanned"

    if $produced_context; then
      _harvest_one "${scan_dir}/CONTEXT.md"     "${out_dir}/CONTEXT.md"     "$block"
    fi
    if $produced_map; then
      _harvest_one "${scan_dir}/CONTEXT-MAP.md" "${out_dir}/CONTEXT-MAP.md" "$block"
    fi
    if [[ -d "${scan_dir}/docs/adr" ]]; then
      mkdir -p "${out_dir}/docs/adr"
      # Copy each ADR file (don't prepend frontmatter to ADRs — they have
      # their own format per ADR-FORMAT.md).
      cp -R "${scan_dir}/docs/adr/." "${out_dir}/docs/adr/"
    fi
    _ok "finalize ${name}: scanned"
  else
    # ── stub on failure ──────────────────────────────────────────────
    local reason="${fail_reason:-scan produced no output}"
    local failed_at
    failed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local block="${meta}
status:         scan-failed
fail_reason:    \"${reason}\"
failed_at:      ${failed_at}
retry_with:     \"wb.rescan ${name}\""

    # Capture user-authored keys from a prior harvest before we overwrite.
    local old_frontmatter=""
    if [[ -f "${out_dir}/CONTEXT.md" ]] && [[ "$(head -n 1 "${out_dir}/CONTEXT.md")" == "---" ]]; then
      old_frontmatter="$(awk '
        NR==1 && $0=="---" { in_block=1; next }
        in_block && $0=="---" { exit }
        in_block { print }
      ' "${out_dir}/CONTEXT.md")"
    fi

    # Write the stub body, then if we had a prior frontmatter, seed it so
    # the merge step preserves user keys. Final prepend overlays new
    # devkit-owned values.
    _stub_body "$name" > "${out_dir}/CONTEXT.md"
    if [[ -n "$old_frontmatter" ]]; then
      local tmp
      tmp="$(mktemp)"
      {
        print -r -- "---"
        print -r -- "$old_frontmatter"
        print -r -- "---"
        cat "${out_dir}/CONTEXT.md"
      } > "$tmp"
      mv "$tmp" "${out_dir}/CONTEXT.md"
    fi
    _prepend_frontmatter "${out_dir}/CONTEXT.md" "$block"
    _warn "finalize ${name}: scan-failed (${reason})"
  fi

  # ── teardown ──────────────────────────────────────────────────────────
  # Worktree remove is idempotent: skip silently if scan_dir is gone.
  if [[ -e "$scan_dir" ]]; then
    git -C "$repo_dir" worktree remove --force "$scan_dir" 2>/dev/null || true
    rm -rf "$scan_dir"
  fi
  git -C "$repo_dir" worktree prune 2>/dev/null || true

  _lock_release "$wb"
  return 0
}

# ─── subcommand: aggregate ──────────────────────────────────────────────
# aggregate <WB_DIR>
#  Walks context/*/{CONTEXT.md,CONTEXT-MAP.md}, reads project.conf REPOS,
#  emits a fresh context/README.md per the locked schema.
cmd_aggregate() {
  local wb="$1"
  [[ -n "$wb" ]] || { _err "aggregate: missing <WB_DIR>"; return 2; }
  wb="${wb:A}"

  local conf="${wb}/project.conf"
  local ctx_root="${wb}/context"
  mkdir -p "$ctx_root"

  # Build a lookup of REPOS:  name -> role
  typeset -A repos_role
  typeset -a repos_order
  local line nm rl url
  while IFS=$'\t' read -r nm rl url; do
    [[ -z "$nm" ]] && continue
    repos_role[$nm]="$rl"
    repos_order+=("$nm")
  done < <(_parse_repos_conf "$conf")

  # Build a lookup of on-disk context dirs.
  typeset -A on_disk
  typeset -a on_disk_order
  local d nm2
  if [[ -d "$ctx_root" ]]; then
    for d in "$ctx_root"/*(N/); do
      nm2="${d:t}"
      on_disk[$nm2]=1
      on_disk_order+=("$nm2")
    done
  fi

  # Helpers to render one row.
  # NOTE: zsh `status` is a read-only special — use `row_status`.
  _row_for_existing() {
    local name="$1" role="$2" registered="$3"
    local ctx="${ctx_root}/${name}/CONTEXT.md"
    local map="${ctx_root}/${name}/CONTEXT-MAP.md"
    local link target row_status concepts display_role

    if [[ -f "$ctx" ]]; then
      target="./${name}/CONTEXT.md"
    elif [[ -f "$map" ]]; then
      target="./${name}/CONTEXT-MAP.md"
    else
      # context dir exists but neither CONTEXT.md nor CONTEXT-MAP.md
      target=""
    fi

    # status: look in frontmatter of whichever file exists
    local frontmatter_file=""
    [[ -f "$ctx" ]] && frontmatter_file="$ctx"
    [[ -z "$frontmatter_file" && -f "$map" ]] && frontmatter_file="$map"

    if [[ -n "$frontmatter_file" ]]; then
      row_status="$(awk '
        NR==1 && $0=="---" { in_block=1; next }
        in_block && $0=="---" { exit }
        in_block && /^status:[[:space:]]/ {
          sub(/^status:[[:space:]]+/, "", $0)
          print $0
          exit
        }
      ' "$frontmatter_file")"
      [[ -z "$row_status" ]] && row_status="scanned"
    else
      row_status="scanned"
    fi

    if [[ "$registered" == "yes" ]]; then
      # in REPOS: keep registered role (even if scan-failed)
      display_role="$role"
    else
      # not in REPOS: orphan (overrides status from frontmatter)
      row_status="orphan"
      display_role="(none)"
    fi

    # concepts: only meaningful when scanned
    if [[ "$row_status" == "scanned" && -n "$frontmatter_file" ]]; then
      concepts="$(_extract_top_concepts "$frontmatter_file")"
    else
      concepts="—"
    fi

    if [[ -n "$target" ]]; then
      link="[${name}](${target})"
    else
      link="$name"
    fi
    print -r -- "| ${link} | ${display_role} | ${row_status} | ${concepts} |"
  }

  _row_for_missing() {
    local name="$1" role="$2"
    print -r -- "| ${name} | ${role} | missing | — |"
  }

  # Assemble row set: registered repos first (in REPOS order), then orphans.
  local out="${ctx_root}/README.md"
  {
    print -r -- "# Workbench Context Index"
    print -r --
    print -r -- "| Repo | Role | Status | Top concepts |"
    print -r -- "|------|------|--------|--------------|"

    for nm in "${repos_order[@]}"; do
      if [[ -n "${on_disk[$nm]+x}" ]]; then
        _row_for_existing "$nm" "${repos_role[$nm]}" yes
      else
        _row_for_missing  "$nm" "${repos_role[$nm]}"
      fi
    done
    for nm in "${on_disk_order[@]}"; do
      if [[ -z "${repos_role[$nm]+x}" ]]; then
        _row_for_existing "$nm" "" no
      fi
    done

    print -r --
    print -r -- "Status values:"
    print -r -- "- \`scanned\` — CONTEXT produced normally"
    print -r -- "- \`scan-failed\` — stub on disk, retry with \`wb.rescan <repo>\`"
    print -r -- "- \`orphan\` — context dir exists, repo not in project.conf"
    print -r -- "- \`missing\` — repo in project.conf, no context dir"
    print -r --
    print -r -- "Re-scan any repo:    \`wb.rescan <repo>\`"
    print -r -- "Re-scan everything:  \`wb.rescan --all\`"
    print -r -- "Refresh index only:  \`wb.rescan --aggregate-only\`"
  } > "$out"

  _ok "aggregate ${wb}: wrote ${out:A}"
  return 0
}

# ─── dispatch ───────────────────────────────────────────────────────────
usage() {
  cat <<USAGE
wb-context-scan.zsh — wrapper library for repo-context-scan skill.

Usage:
  zsh lib/wb-context-scan.zsh setup    <WB_DIR> <name>
  zsh lib/wb-context-scan.zsh finalize <WB_DIR> <name> [--fail-reason "..."]
  zsh lib/wb-context-scan.zsh aggregate <WB_DIR>
USAGE
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    setup)     shift; cmd_setup     "$@" ;;
    finalize)  shift; cmd_finalize  "$@" ;;
    aggregate) shift; cmd_aggregate "$@" ;;
    -h|--help|help|"") usage ;;
    *) _err "unknown subcommand: $cmd"; usage; return 2 ;;
  esac
}

main "$@"
