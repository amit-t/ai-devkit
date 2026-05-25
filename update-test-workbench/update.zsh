#!/usr/bin/env zsh
# update.zsh — Pull template-owned files from ai-test-automation-workbench
# upstream into this derived test repo. Strictly one-way. Never touches
# user-owned paths.
#
# Reads `.auto-wb-manifest.json` and `project.conf` (key: `TEMPLATE_UPSTREAM_URL`)
# from the current workbench root, fetches `upstream/main`, and runs
# `git checkout` against each `template_owned` path.
#
# Usage:
#   update.auto.wb                       # run inside a derived test repo
#   update.auto.wb --dry-run             # show what would change
#   update.auto.wb --agent devin         # interactive conflict resolution via Devin
#   update.auto.wb --agent claude        # interactive conflict resolution via Claude
#
# Exit codes:
#   0 success
#   1 not inside a test workbench
#   2 dirty workbench (uncommitted changes on template-owned paths)
#   3 fetch failed
#   4 merge/checkout error

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROMPT_FILE="${SCRIPT_DIR}/update.prompt.md"

DRY_RUN=false
AGENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --agent)   AGENT="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
update.auto.wb — Pull template-owned files from ai-test-automation-workbench upstream.

  update.auto.wb               Non-interactive update (no agent).
  update.auto.wb --dry-run     Preview changes only.
  update.auto.wb --agent devin   Interactive conflict resolution via Devin.
  update.auto.wb --agent claude  Interactive conflict resolution via Claude.

Reads `.auto-wb-manifest.json` to know which paths upstream owns and
`project.conf` (key: TEMPLATE_UPSTREAM_URL) to find the upstream remote.
USAGE
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# ── Steering drift nag ──────────────────────────────────────────────────────
# Walk steering.local/**/*.md, classify each override, and print a one-line
# nag pointing at the template repo so users promote proven overrides.
# Silent when steering.local/ is missing or contains no .md files.
_print_steering_drift_nag() {
  local wb_dir="$1"
  local upstream="$2"
  local steering_dir="${wb_dir}/steering.local"

  [[ -d "$steering_dir" ]] || return 0

  local count_add=0 count_super=0 count_remove=0
  local f base
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    base="${f:t}"
    if [[ "$base" == *.removed.md ]]; then
      (( count_remove++ ))
      continue
    fi
    if awk '/^---[[:space:]]*$/{c++; next} c==1' "$f" 2>/dev/null \
         | grep -qE '^supersedes:'; then
      (( count_super++ ))
    else
      (( count_add++ ))
    fi
  done < <(find "$steering_dir" -type f -name '*.md' 2>/dev/null)

  local total=$(( count_add + count_super + count_remove ))
  (( total == 0 )) && return 0

  local template_path="${upstream%.git}"
  template_path="${template_path#https://github.com/}"
  template_path="${template_path#git@github.com:}"
  local template_url="https://github.com/${template_path}"

  echo ""
  echo "${total} local steering overrides in this workbench (${count_add} add, ${count_super} supersede, ${count_remove} remove). Review with \`auto.wb.steering-refresh\` and \`auto.wb.steering-overlays --list\`. Promote proven overrides upstream via PR to ${template_url}."
}

# ── Locate workbench root ───────────────────────────────────────────────────
# Marker: .auto-wb-manifest.json + project.conf at the same level.
_find_wb_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/.auto-wb-manifest.json" && -f "$dir/project.conf" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

WB_DIR="$(_find_wb_root)" || {
  echo "Not inside a test-automation workbench." >&2
  echo "Looked for .auto-wb-manifest.json + project.conf in this directory and every parent; found none." >&2
  echo "If you meant the planning-side workbench (.workbench-manifest.json), use \`update.wb\` instead." >&2
  exit 1
}

cd "$WB_DIR"

# project.conf is bash-sourced; ignore any embedded local declarations.
source ./project.conf
UPSTREAM_URL="${TEMPLATE_UPSTREAM_URL:-}"
[[ -n "$UPSTREAM_URL" ]] || { echo "TEMPLATE_UPSTREAM_URL not set in project.conf" >&2; exit 1; }

# ── Ensure upstream remote exists ────────────────────────────────────────────
if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "Adding upstream remote: $UPSTREAM_URL"
  git remote add upstream "${UPSTREAM_URL}.git"
fi

# ── Fetch upstream main ──────────────────────────────────────────────────────
echo "Fetching upstream..."
git fetch upstream main --quiet || { echo "fetch failed" >&2; exit 3; }

# ── Read template_owned from manifest ────────────────────────────────────────
TEMPLATE_PATHS="$(python3 - <<'PYEOF'
import json
with open('.auto-wb-manifest.json') as f: m = json.load(f)
for p in m.get('template_owned', []):
    print(p)
PYEOF
)"

if [[ -z "$TEMPLATE_PATHS" ]]; then
  echo "No template_owned paths in manifest — nothing to do."
  exit 0
fi

# ── Check for local edits on template_owned paths ────────────────────────────
# NOTE: zsh has a special tied variable `$path` that mirrors `$PATH`. Using
# `read -r path` would clobber `$PATH` and break every later `git` call inside
# the loop. Use a distinct name (`wb_path`) to dodge the gotcha.
DIRTY=""
while IFS= read -r wb_path; do
  [[ -z "$wb_path" ]] && continue
  if git diff --quiet -- "$wb_path" 2>/dev/null && git diff --cached --quiet -- "$wb_path" 2>/dev/null; then
    continue
  fi
  DIRTY="$DIRTY\n  $wb_path"
done <<< "$TEMPLATE_PATHS"

if [[ -n "$DIRTY" ]]; then
  printf "Uncommitted changes on template-owned paths:%b\n" "$DIRTY" >&2
  echo "Commit or stash them, or open a PR upstream for the improvements, then retry." >&2
  exit 2
fi

# ── Optional agent-driven preview ────────────────────────────────────────────
if [[ -n "$AGENT" ]] && [[ -f "$PROMPT_FILE" ]]; then
  echo "→ Launching ${AGENT} for interactive review..."
  case "$AGENT" in
    devin)
      command -v devin >/dev/null 2>&1 || { echo "devin CLI not found" >&2; exit 1; }
      PROMPT_TMP="$(mktemp -t update-auto-wb-prompt.XXXXXX)"
      cat "$PROMPT_FILE" > "$PROMPT_TMP"
      devin --permission-mode dangerous --prompt-file "$PROMPT_TMP"
      rm -f "$PROMPT_TMP"
      exit 0
      ;;
    claude)
      command -v claude >/dev/null 2>&1 || { echo "claude CLI not found" >&2; exit 1; }
      unset CLAUDECODE
      claude --dangerously-skip-permissions "$(cat "$PROMPT_FILE")"
      exit 0
      ;;
    *) echo "Invalid agent: $AGENT" >&2; exit 1 ;;
  esac
fi

# ── Dry run? ─────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  echo "Changes that would be pulled from upstream/main for template_owned paths:"
  while IFS= read -r wb_path; do
    [[ -z "$wb_path" ]] && continue
    git diff --stat upstream/main -- "$wb_path" || true
  done <<< "$TEMPLATE_PATHS"
  exit 0
fi

# ── Apply ────────────────────────────────────────────────────────────────────
echo "Pulling template-owned paths..."
UPDATED=()
while IFS= read -r wb_path; do
  [[ -z "$wb_path" ]] && continue
  if git checkout upstream/main -- "$wb_path" 2>/dev/null; then
    UPDATED+=("$wb_path")
  else
    echo "  (skipped / not present) $wb_path"
  fi
done <<< "$TEMPLATE_PATHS"

# Re-stage and check diff
git add -A
if git diff --cached --quiet; then
  echo "Already up to date."
  _print_steering_drift_nag "$WB_DIR" "$UPSTREAM_URL"
  exit 0
fi

UPSTREAM_SHA="$(git rev-parse --short upstream/main)"
git commit -m "chore: sync template-owned files from ai-test-automation-workbench@${UPSTREAM_SHA}"

echo "Pushing..."
git push origin HEAD || { echo "push failed" >&2; exit 4; }

echo ""
echo "── Template sync complete ──"
printf "  upstream sha: %s\n  paths updated: %d\n" "$UPSTREAM_SHA" "${#UPDATED[@]}"

_print_steering_drift_nag "$WB_DIR" "$UPSTREAM_URL"
