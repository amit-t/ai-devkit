#!/usr/bin/env zsh
# join.zsh — Launcher for join-workbench. Clones an existing workbench instance,
# runs a Devin (or Claude) interview to gather any extra repos the joiner wants,
# appends to project.conf, adds the joiner to CODEOWNERS, commits, pushes.
#
# Usage:
#   join.wb <workbench-url>
#   join.wb <workbench-url> --agent devin
#   join.wb <workbench-url> --agent claude

set -euo pipefail

# ── Version-check preamble ──────────────────────────────────────────────────
LIBVC="${HOME}/.local/share/wb-versioncheck/version-check.sh"
if [[ -f "$LIBVC" ]]; then
  # shellcheck disable=SC1090
  _VERCHECK_LIB_DIR_OVERRIDE="${LIBVC:h}" . "$LIBVC"
  _wb_versioncheck devkit || true
fi

SCRIPT_DIR="${0:A:h}"
PROMPT_FILE="${SCRIPT_DIR}/join.prompt.md"

WB_URL=""
AGENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
join.wb — Join an existing workbench from its GitHub URL.

  join.wb <url>                 Use Devin (fallback Claude).
  join.wb <url> --agent devin   Force Devin.
  join.wb <url> --agent claude  Force Claude.
USAGE
      exit 0 ;;
    *)
      [[ -z "$WB_URL" ]] && WB_URL="$1" || { echo "Unexpected arg: $1" >&2; exit 1; }
      shift ;;
  esac
done

[[ -n "$WB_URL" ]] || { echo "Usage: join.wb <workbench-url>" >&2; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { echo "join.prompt.md not found at $PROMPT_FILE" >&2; exit 1; }

# Pick agent (marker-driven default; see lib/engine-cmd.zsh)
source "${SCRIPT_DIR:h}/lib/engine-cmd.zsh"
if [[ -z "$AGENT" ]]; then AGENT="$DEVKIT_DEFAULT_AGENT"; fi

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
    PROMPT_TMP="$(mktemp -t join-wb-prompt.XXXXXX)"
    printf "%s" "$FULL_PROMPT" > "$PROMPT_TMP"
    devin --permission-mode dangerous --prompt-file "$PROMPT_TMP"
    rm -f "$PROMPT_TMP"
    ;;
  claude)
    devkit_fire_claude "$FULL_PROMPT"
    ;;
  *) echo "Invalid agent: $AGENT" >&2; exit 1 ;;
esac
