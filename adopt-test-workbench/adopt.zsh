#!/usr/bin/env zsh
# adopt.zsh — Launcher for adopt-test-workbench. Starts a Devin (or Claude)
# session with adopt.prompt.md. The agent walks the user through archiving
# and recreating selected branches of an existing repo from the
# ai-automation-workbench template.
#
# DESTRUCTIVE. Backs up selected branches as backup/<branch>-<YYYY-MM-DD>
# first, then deletes them on origin and recreates from the template.
# The prompt requires the user to type the repo name verbatim before any
# delete happens.
#
# Usage:
#   adopt.auto.wb <repo-url>                       # Devin by default; Claude if devin missing
#   adopt.auto.wb <repo-url> --agent devin         # force Devin
#   adopt.auto.wb <repo-url> --agent claude        # force Claude
#   adopt.auto.wb <repo-url> --dry-run             # show the plan; never deletes
#
# Sibling commands:
#   init.auto.wb     Create a new test-automation workbench from template.
#   join.auto.wb     Clone an existing workbench and onboard yourself.
#   update.auto.wb   Pull template-owned updates into the current workbench.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROMPT_FILE="${SCRIPT_DIR}/adopt.prompt.md"

REPO_URL=""
AGENT=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help)
      cat <<'USAGE'
adopt.auto.wb — Adopt an existing repo into the test-automation workbench
                template by archiving + recreating selected branches.

  adopt.auto.wb <repo-url>                Use Devin (fallback Claude).
  adopt.auto.wb <repo-url> --agent devin  Force Devin.
  adopt.auto.wb <repo-url> --agent claude Force Claude.
  adopt.auto.wb <repo-url> --dry-run      Print the plan; never delete.

DESTRUCTIVE. The agent will:
  1. List current branches and protection state.
  2. Ask which branches to archive + recreate (default: main, develop).
  3. Require you to type the repo name verbatim as confirmation.
  4. Push backup/<branch>-<YYYY-MM-DD> for each selected branch.
  5. Delete the selected branches on origin.
  6. Recreate them from the ai-automation-workbench template.
  7. Hand off to the playwright-agents-bootstrap skill.

Sibling commands:
  init.auto.wb     Create a brand-new workbench repo from template.
  join.auto.wb     Clone an existing workbench and onboard yourself.
  update.auto.wb   Pull template-owned updates into the current workbench.
USAGE
      exit 0 ;;
    *)
      [[ -z "$REPO_URL" ]] && REPO_URL="$1" || { echo "Unexpected arg: $1" >&2; exit 1; }
      shift ;;
  esac
done

[[ -n "$REPO_URL" ]] || { echo "Usage: adopt.auto.wb <repo-url> [--agent devin|claude] [--dry-run]" >&2; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { echo "adopt.prompt.md not found at $PROMPT_FILE" >&2; exit 1; }

# ── Pick agent ─────────────────────────────────────────────────────────────
if [[ -z "$AGENT" ]]; then
  if command -v devin >/dev/null 2>&1; then
    AGENT="devin"
  elif command -v claude >/dev/null 2>&1; then
    AGENT="claude"
  else
    echo "Neither devin nor claude CLI found. Install one." >&2
    exit 1
  fi
fi

case "$AGENT" in
  devin)  command -v devin  >/dev/null 2>&1 || { echo "devin CLI not found"  >&2; exit 1; } ;;
  claude) command -v claude >/dev/null 2>&1 || { echo "claude CLI not found" >&2; exit 1; } ;;
  *) echo "Invalid agent: $AGENT (use devin or claude)" >&2; exit 1 ;;
esac

# ── Build the prompt with runtime context ──────────────────────────────────
DEVKIT_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_PARENT="$(dirname "$DEVKIT_DIR")"

FULL_PROMPT="$(cat "$PROMPT_FILE")

---
# Runtime Context

TARGET_CWD=$(pwd)
REPO_URL=${REPO_URL}
DRY_RUN=${DRY_RUN}
AGENT=${AGENT}
DEVKIT_DIR=${DEVKIT_DIR}
TOOLS_PARENT=${TOOLS_PARENT}
RUN_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TODAY=$(date -u +"%Y-%m-%d")
"

# ── Fire the agent ─────────────────────────────────────────────────────────
case "$AGENT" in
  devin)
    echo "→ Starting Devin (interactive, dangerous permissions)..."
    PROMPT_TMP="$(mktemp -t adopt-auto-wb-prompt.XXXXXX)"
    printf "%s" "$FULL_PROMPT" > "$PROMPT_TMP"
    devin --permission-mode dangerous --prompt-file "$PROMPT_TMP"
    rm -f "$PROMPT_TMP"
    ;;
  claude)
    echo "→ Starting Claude (dangerously-skip-permissions, non-interactive)..."
    unset CLAUDECODE
    claude --dangerously-skip-permissions "$FULL_PROMPT"
    ;;
esac
