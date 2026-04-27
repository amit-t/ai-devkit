#!/usr/bin/env zsh
# init.zsh — Launcher for init-workbench. Starts a Devin (or Claude) session with
# init.prompt.md. The agent does the actual work: interview, gh repo create, clone
# repos, render templates, push.
#
# Usage:
#   init.wb                           # Devin by default; Claude if devin missing
#   init.wb --agent devin             # force Devin
#   init.wb --agent claude            # force Claude
#   init.wb --cwd /path/to/empty/dir  # override target working directory

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROMPT_FILE="${SCRIPT_DIR}/init.prompt.md"

# ── Parse args ─────────────────────────────────────────────────────────────
AGENT=""
TARGET_CWD="$(pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)  AGENT="${2:-}"; shift 2 ;;
    --cwd)    TARGET_CWD="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
init.wb — Initiate a new workbench from the ai-workbench template.

  init.wb                 Use Devin (fallback Claude).
  init.wb --agent devin   Force Devin.
  init.wb --agent claude  Force Claude.
  init.wb --cwd <dir>     Set target directory (default: current).
USAGE
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PROMPT_FILE" ]] || { echo "init.prompt.md not found at $PROMPT_FILE" >&2; exit 1; }
[[ -d "$TARGET_CWD" ]] || { echo "Target directory missing: $TARGET_CWD" >&2; exit 1; }

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
  devin)  command -v devin >/dev/null 2>&1 || { echo "devin CLI not found"  >&2; exit 1; } ;;
  claude) command -v claude >/dev/null 2>&1 || { echo "claude CLI not found" >&2; exit 1; } ;;
  *) echo "Invalid agent: $AGENT (use devin or claude)" >&2; exit 1 ;;
esac

# ── Build the prompt with runtime context ──────────────────────────────────
DEVKIT_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_PARENT="$(dirname "$DEVKIT_DIR")"

FULL_PROMPT="$(cat "$PROMPT_FILE")

---
# Runtime Context

TARGET_CWD=${TARGET_CWD}
INITIATOR_PWD=${TARGET_CWD}
AGENT=${AGENT}
DEVKIT_DIR=${DEVKIT_DIR}
TOOLS_PARENT=${TOOLS_PARENT}
RUN_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
"

# ── Fire the agent ─────────────────────────────────────────────────────────
case "$AGENT" in
  devin)
    echo "→ Starting Devin (interactive, dangerous permissions)..."
    cd "$TARGET_CWD"
    PROMPT_TMP="$(mktemp -t init-wb-prompt.XXXXXX)"
    printf "%s" "$FULL_PROMPT" > "$PROMPT_TMP"
    devin --permission-mode dangerous --prompt-file "$PROMPT_TMP"
    rm -f "$PROMPT_TMP"
    ;;
  claude)
    echo "→ Starting Claude (dangerously-skip-permissions, non-interactive)..."
    cd "$TARGET_CWD"
    unset CLAUDECODE
    claude --dangerously-skip-permissions "$FULL_PROMPT"
    ;;
esac
