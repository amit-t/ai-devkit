#!/usr/bin/env zsh
# join.zsh — Launcher for join-test-workbench. Clones an existing test-automation
# workbench instance, adds the joiner to CODEOWNERS, optionally installs npm /
# Playwright browsers, commits, pushes.
#
# Usage:
#   join.auto.wb <workbench-url>
#   join.auto.wb <workbench-url> --agent devin
#   join.auto.wb <workbench-url> --agent claude

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROMPT_FILE="${SCRIPT_DIR}/join.prompt.md"

WB_URL=""
AGENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
join.auto.wb — Join an existing test-automation workbench from its GitHub URL.

  join.auto.wb <url>                 Use Devin (fallback Claude).
  join.auto.wb <url> --agent devin   Force Devin.
  join.auto.wb <url> --agent claude  Force Claude.

Sibling commands:
  init.auto.wb     Initiate a new test-automation workbench.
  update.auto.wb   Pull template-owned updates into the current repo.
USAGE
      exit 0 ;;
    *)
      [[ -z "$WB_URL" ]] && WB_URL="$1" || { echo "Unexpected arg: $1" >&2; exit 1; }
      shift ;;
  esac
done

[[ -n "$WB_URL" ]] || { echo "Usage: join.auto.wb <workbench-url>" >&2; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { echo "join.prompt.md not found at $PROMPT_FILE" >&2; exit 1; }

# Pick agent
if [[ -z "$AGENT" ]]; then
  if command -v devin >/dev/null 2>&1; then AGENT="devin"
  elif command -v claude >/dev/null 2>&1; then AGENT="claude"
  else echo "Neither devin nor claude CLI found." >&2; exit 1; fi
fi

DEVKIT_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_PARENT="$(dirname "$DEVKIT_DIR")"

FULL_PROMPT="$(cat "$PROMPT_FILE")

---
# Runtime Context

TARGET_CWD=$(pwd)
WB_URL=${WB_URL}
AGENT=${AGENT}
DEVKIT_DIR=${DEVKIT_DIR}
TOOLS_PARENT=${TOOLS_PARENT}
RUN_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
"

case "$AGENT" in
  devin)
    PROMPT_TMP="$(mktemp -t join-auto-wb-prompt.XXXXXX)"
    printf "%s" "$FULL_PROMPT" > "$PROMPT_TMP"
    devin --permission-mode dangerous --prompt-file "$PROMPT_TMP"
    rm -f "$PROMPT_TMP"
    ;;
  claude)
    unset CLAUDECODE
    claude --dangerously-skip-permissions "$FULL_PROMPT"
    ;;
  *) echo "Invalid agent: $AGENT" >&2; exit 1 ;;
esac
