#!/usr/bin/env zsh
# update.zsh — Pull template-owned files from ai-workbench upstream into this
# workbench instance. Strictly one-way. Never touches user-owned paths.
#
# Usage:
#   update.wb                          # run inside a workbench instance
#   update.wb --dry-run                # show what would change
#   update.wb --agent devin            # run Devin for interactive conflict resolution
#   update.wb --agent claude           # run Claude for interactive conflict resolution
#
# Exit codes:
#   0 success
#   1 not inside a workbench
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
update.wb — Pull template-owned files from ai-workbench upstream.

  update.wb               Non-interactive update (no agent).
  update.wb --dry-run     Preview changes only.
  update.wb --agent devin  Interactive conflict resolution via Devin.
  update.wb --agent claude Interactive conflict resolution via Claude.
USAGE
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# ── Locate workbench root ───────────────────────────────────────────────────
_find_wb_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/.workbench-manifest.json" && -f "$dir/project.conf" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

WB_DIR="$(_find_wb_root)" || {
  echo "Not inside a workbench (no .workbench-manifest.json found in any parent)." >&2
  exit 1
}

cd "$WB_DIR"

source ./project.conf
UPSTREAM_URL="${WORKBENCH_TEMPLATE_UPSTREAM:-}"
[[ -n "$UPSTREAM_URL" ]] || { echo "WORKBENCH_TEMPLATE_UPSTREAM not set in project.conf" >&2; exit 1; }

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
with open('.workbench-manifest.json') as f: m = json.load(f)
for p in m.get('template_owned', []):
    print(p)
PYEOF
)"

if [[ -z "$TEMPLATE_PATHS" ]]; then
  echo "No template_owned paths in manifest — nothing to do."
  exit 0
fi

# ── Check for local edits on template_owned paths ────────────────────────────
DIRTY=""
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  # Expand globs; git checkout accepts pathspecs.
  # Use git diff to see if the pathspec has uncommitted changes.
  if git diff --quiet -- "$path" 2>/dev/null && git diff --cached --quiet -- "$path" 2>/dev/null; then
    continue
  fi
  DIRTY="$DIRTY\n  $path"
done <<< "$TEMPLATE_PATHS"

if [[ -n "$DIRTY" ]]; then
  printf "Uncommitted changes on template-owned paths:%b\n" "$DIRTY" >&2
  echo "Commit or stash them, or open a PR upstream for the improvements, then retry." >&2
  exit 2
fi

# ── Dry run? ─────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  echo "Changes that would be pulled from upstream/main for template_owned paths:"
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    git diff --stat upstream/main -- "$path" || true
  done <<< "$TEMPLATE_PATHS"
  exit 0
fi

# ── Apply ────────────────────────────────────────────────────────────────────
echo "Pulling template-owned paths..."
UPDATED=()
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if git checkout upstream/main -- "$path" 2>/dev/null; then
    UPDATED+=("$path")
  else
    echo "  (skipped / not present) $path"
  fi
done <<< "$TEMPLATE_PATHS"

# Re-stage and check diff
git add -A
if git diff --cached --quiet; then
  echo "Already up to date."
  exit 0
fi

UPSTREAM_SHA="$(git rev-parse --short upstream/main)"
git commit -m "chore: sync template-owned files from ai-workbench@${UPSTREAM_SHA}"

echo "Pushing..."
git push origin HEAD || { echo "push failed" >&2; exit 4; }

echo ""
echo "── Template sync complete ──"
printf "  upstream sha: %s\n  paths updated: %d\n" "$UPSTREAM_SHA" "${#UPDATED[@]}"
