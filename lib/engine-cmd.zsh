#!/usr/bin/env zsh
# engine-cmd.zsh — marker-driven resolver for the AI engine + Claude launcher.
#
# Source this lib (don't execute it). It sets, in the caller's scope:
#   DEVKIT_DEFAULT_AGENT    resolved default engine ("claude" or "devin"); only
#                           meaningful when the caller has no explicit --agent.
#   DEVKIT_CLAUDE_LAUNCHER  the command/alias used to start Claude (e.g.
#                           "claude" or "clscb").
# It also defines the function:
#   devkit_fire_claude <prompt>   launch Claude via DEVKIT_CLAUDE_LAUNCHER.
#
# Parity-safe by construction: identical code ships in both twin forks; only the
# committed <devkit-root>/.ralph-prefix marker differs. On the PERSONAL fork
# (marker present, e.g. "per.") the default engine is Claude, launched through
# `clscb` — the user's enriched Claude launcher. An UNMARKED twin fork keeps the
# legacy devin-then-claude PATH fallback and the bare `claude` launcher, so it
# is completely unaffected.
#
# Default-engine resolution (used only when the caller has no --agent):
#   1. env ${NS}DEVKIT_DEFAULT_ENGINE   (NS derived from the marker, e.g. PER_)
#   2. env DEVKIT_DEFAULT_ENGINE
#   3. personal fork (marker non-empty) -> "claude"
#   4. devin if on PATH, else claude    (legacy fallback; unmarked twin)
#
# Claude-launcher resolution:
#   1. env ${NS}DEVKIT_CLAUDE_CMD
#   2. env DEVKIT_CLAUDE_CMD
#   3. personal fork (marker non-empty) -> "clscb"
#   4. "claude"
#
# The launcher MUST be a bare command/alias name (not a full command line):
#   - if it resolves on PATH it is invoked directly with
#     --dangerously-skip-permissions appended;
#   - otherwise it is treated as an interactive-shell alias/function (e.g.
#     `clscb`, which already adds --dangerously-skip-permissions) and run
#     through `zsh -ic` so the user's rc-defined alias/function resolves.

# Devkit root: when sourced, $0 is unreliable, so derive from this lib's own
# location (lib/ -> root = parent of its dir). A caller may export
# ENGINE_CMD_LIB_ROOT to override (used by tests). Mirrors lib/ralph-cmd.zsh.
if [[ -n "${ENGINE_CMD_LIB_ROOT:-}" ]]; then
  _engine_cmd_root="${ENGINE_CMD_LIB_ROOT:A}"
else
  _engine_cmd_root="${${(%):-%x}:A:h:h}"
fi

# Fork marker: env override (authoritative if SET, even empty) > marker file > ""
if [[ -n "${DEVKIT_ENGINE_PREFIX+x}" ]]; then
  _engine_cmd_prefix="$DEVKIT_ENGINE_PREFIX"
elif [[ -f "$_engine_cmd_root/.ralph-prefix" ]]; then
  _engine_cmd_prefix="$(tr -d '[:space:]' < "$_engine_cmd_root/.ralph-prefix")"
else
  _engine_cmd_prefix=""
fi

# Env-var namespace from the marker: "per." -> "PER_"  ("" when no marker).
_engine_cmd_ns=""
if [[ -n "$_engine_cmd_prefix" ]]; then
  _engine_cmd_nsbase="${_engine_cmd_prefix%%.*}"
  _engine_cmd_nsbase="${_engine_cmd_nsbase//[^A-Za-z0-9]/}"
  _engine_cmd_ns="${(U)_engine_cmd_nsbase}_"
fi

# ── Default engine ──────────────────────────────────────────────────────────
_engine_cmd_envvar="${_engine_cmd_ns}DEVKIT_DEFAULT_ENGINE"
if [[ -n "${(P)_engine_cmd_envvar:-}" ]]; then
  DEVKIT_DEFAULT_AGENT="${(P)_engine_cmd_envvar}"
elif [[ -n "${DEVKIT_DEFAULT_ENGINE:-}" ]]; then
  DEVKIT_DEFAULT_AGENT="${DEVKIT_DEFAULT_ENGINE}"
elif [[ -n "$_engine_cmd_prefix" ]]; then
  DEVKIT_DEFAULT_AGENT="claude"
elif command -v devin >/dev/null 2>&1; then
  DEVKIT_DEFAULT_AGENT="devin"
else
  DEVKIT_DEFAULT_AGENT="claude"
fi

# ── Claude launcher ─────────────────────────────────────────────────────────
_engine_cmd_lvar="${_engine_cmd_ns}DEVKIT_CLAUDE_CMD"
if [[ -n "${(P)_engine_cmd_lvar:-}" ]]; then
  DEVKIT_CLAUDE_LAUNCHER="${(P)_engine_cmd_lvar}"
elif [[ -n "${DEVKIT_CLAUDE_CMD:-}" ]]; then
  DEVKIT_CLAUDE_LAUNCHER="${DEVKIT_CLAUDE_CMD}"
elif [[ -n "$_engine_cmd_prefix" ]]; then
  DEVKIT_CLAUDE_LAUNCHER="clscb"
else
  DEVKIT_CLAUDE_LAUNCHER="claude"
fi

# devkit_fire_claude <prompt> — start Claude, honoring DEVKIT_CLAUDE_LAUNCHER.
devkit_fire_claude() {
  emulate -L zsh
  local prompt="$1"
  local launcher="${DEVKIT_CLAUDE_LAUNCHER:-claude}"
  unset CLAUDECODE
  # Bare `claude` (or any PATH binary): invoke directly, add the skip-perms flag.
  if [[ "$launcher" == "claude" ]] || command -v -- "$launcher" >/dev/null 2>&1; then
    command "$launcher" --dangerously-skip-permissions "$prompt"
    return $?
  fi
  # Not on PATH -> interactive-shell alias/function (e.g. clscb, which already
  # adds --dangerously-skip-permissions). Resolve it via the user's rc files.
  if zsh -ic "whence -- ${launcher} >/dev/null 2>&1" >/dev/null 2>&1; then
    zsh -ic "${launcher} \"\$1\"" devkit-claude "$prompt"
    return $?
  fi
  print -u2 -r -- "[devkit] Claude launcher '${launcher}' not found; falling back to bare claude."
  command claude --dangerously-skip-permissions "$prompt"
}

unset _engine_cmd_root _engine_cmd_prefix _engine_cmd_ns _engine_cmd_nsbase \
      _engine_cmd_envvar _engine_cmd_lvar
