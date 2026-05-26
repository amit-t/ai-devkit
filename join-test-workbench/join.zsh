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

# Parse <ORG>/<REPO> from WB_URL. Accepts:
#   https://github.com/ORG/REPO[.git]
#   git@github.com:ORG/REPO.git
#   git@<custom-host>:ORG/REPO.git
parse_org_repo() {
  local url="$1" path
  path="${url#*://*/}"          # strip scheme://host/
  path="${path#*:}"             # strip user@host:
  path="${path%.git}"           # strip .git
  ORG="${path%%/*}"
  REPO_NAME="${path#*/}"
  REPO_NAME="${REPO_NAME%%/*}"  # keep only first sub-segment
  [[ -n "$ORG" && -n "$REPO_NAME" && "$ORG" != "$path" ]]
}

ORG=""; REPO_NAME=""
if ! parse_org_repo "$WB_URL"; then
  cat >&2 <<EOF
join.auto.wb: could not parse <ORG>/<REPO> from URL: $WB_URL
Expected one of:
  https://github.com/ORG/REPO[.git]
  git@github.com:ORG/REPO.git
EOF
  exit 1
fi

# Pre-flight: probe the repo with the joiner's gh credentials. A 404 means
# the repo either does not exist or is private and out of reach. Bail with
# a clear message instead of spinning up an agent that will fail at clone.
# Only run the probe when gh is installed and authenticated; otherwise the
# in-prompt Step 0b will handle the unauthed case.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if ! gh api "repos/${ORG}/${REPO_NAME}" >/dev/null 2>&1; then
    GH_USER="$(gh api user -q .login 2>/dev/null || echo '?')"
    cat >&2 <<EOF
join.auto.wb: cannot resolve ${ORG}/${REPO_NAME} as @${GH_USER}.

Two possible causes:
  - The repo does not exist (typo in the URL).
  - The repo is private and your account does not have access.

If it is private, ask a repo admin to grant @${GH_USER} at least Write
access (Read works for the clone, but Write is needed to push the
CODEOWNERS update; otherwise the flow falls back to opening a PR).

Then re-run:  join.auto.wb ${WB_URL}
EOF
    exit 1
  fi
fi

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
