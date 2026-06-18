#!/usr/bin/env zsh
# init.zsh — Launcher for init-workbench. Starts a Devin (or Claude) session with
# init.prompt.md. The agent does the actual work: interview, gh repo create, clone
# repos, render templates, push.
#
# Usage:
#   init.wb                           # Devin by default; Claude if devin missing
#   init.wb --lite                    # include Workbench Lite bootstrap
#   init.wb --lite --undo             # remove Lite shell profile block
#   init.wb --agent devin             # force Devin
#   init.wb --agent claude            # force Claude
#   init.wb --cwd /path/to/empty/dir  # override target working directory

set -euo pipefail

# ── Version-check preamble (prefix-aware; see lib/versioncheck-launch.zsh) ───
_VC_LAUNCH="${0:A:h:h}/lib/versioncheck-launch.zsh"
if [[ -f "$_VC_LAUNCH" ]]; then
  DEVKIT_ROOT="${0:A:h:h}" source "$_VC_LAUNCH"
  _wb_launch_versioncheck devkit || true
fi

SCRIPT_DIR="${0:A:h}"
PROMPT_FILE="${SCRIPT_DIR}/init.prompt.md"

# ── Parse args ─────────────────────────────────────────────────────────────
AGENT=""
TARGET_CWD="$(pwd)"
LITE_MODE=false
LITE_UNDO=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)  AGENT="${2:-}"; shift 2 ;;
    --cwd)    TARGET_CWD="${2:-}"; shift 2 ;;
    --lite)   LITE_MODE=true; shift ;;
    --undo)   LITE_UNDO=true; shift ;;
    -h|--help)
      cat <<'USAGE'
init.wb — Initiate a new workbench from the ai-workbench template.

  init.wb                  Use Devin (fallback Claude).
  init.wb --lite           Include Workbench Lite bootstrap in the init agent prompt.
  init.wb --lite --undo    Remove the Workbench Lite shell profile block and exit.
  init.wb --agent devin    Force Devin.
  init.wb --agent claude   Force Claude.
  init.wb --cwd <dir>      Set target directory (default: current).
USAGE
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PROMPT_FILE" ]] || { echo "init.prompt.md not found at $PROMPT_FILE" >&2; exit 1; }
[[ -d "$TARGET_CWD" ]] || { echo "Target directory missing: $TARGET_CWD" >&2; exit 1; }

if [[ "$LITE_UNDO" == true ]]; then
  if [[ "$LITE_MODE" != true ]]; then
    echo "--undo is only valid with --lite" >&2
    exit 1
  fi
  zsh "$SCRIPT_DIR/lite-bootstrap.zsh" --undo
  exit 0
fi

# ── Pick agent ─────────────────────────────────────────────────────────────
# Marker-driven default (see lib/engine-cmd.zsh): personal fork -> claude/clscb,
# unmarked twin -> legacy devin-then-claude. Sets DEVKIT_DEFAULT_AGENT and
# DEVKIT_CLAUDE_LAUNCHER, and defines devkit_fire_claude.
source "${SCRIPT_DIR:h}/lib/engine-cmd.zsh"
if [[ -z "$AGENT" ]]; then
  AGENT="$DEVKIT_DEFAULT_AGENT"
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
LITE_MODE=${LITE_MODE}
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
    echo "→ Starting Claude via ${DEVKIT_CLAUDE_LAUNCHER} (dangerously-skip-permissions)..."
    cd "$TARGET_CWD"
    devkit_fire_claude "$FULL_PROMPT"
    ;;
esac
