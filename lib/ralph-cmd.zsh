#!/usr/bin/env zsh
# ralph-cmd.zsh — marker-driven resolver for the ralph command family.
#
# Source this lib (don't execute it). It sets, in the caller's scope:
#   RALPH_PREFIX     resolved command prefix ("" or e.g. "per.")
#   RALPH_BIN        "${RALPH_PREFIX}ralph"
#   RALPH_CLONE_DIR  the ralph clone path for this fork
#
# Resolution order for the prefix (parity-safe — identical code in both forks,
# only the committed .ralph-prefix marker differs):
#   1. env RALPH_CMD_PREFIX, if SET (authoritative even when empty)
#   2. contents of <devkit-root>/.ralph-prefix (whitespace stripped)
#   3. "" (no prefix)
#
# Default (no marker, no env) MUST stay plain `ralph` so an unmarked twin fork
# is unaffected.
#
# Clone-dir resolution:
#   - RALPH_PREFIX non-empty  -> namespaced var, e.g. "per." -> $PER_RALPH_CLONE
#   - RALPH_PREFIX empty      -> $RALPH_CLONE
#   Falls back to "" when the chosen var is unset.

# Devkit root: when sourced, $0 is unreliable, so derive from this lib's own
# location. ${(%):-%x} expands to the path of the file currently being sourced;
# the lib lives in lib/, so root = parent of its dir. A caller may also export
# RALPH_CMD_LIB_ROOT to override (used by tests).
if [[ -n "${RALPH_CMD_LIB_ROOT:-}" ]]; then
  _ralph_cmd_root="${RALPH_CMD_LIB_ROOT:A}"
else
  _ralph_cmd_root="${${(%):-%x}:A:h:h}"
fi

# 1) env (authoritative if SET, even when empty) > 2) marker file > 3) ""
if [[ -n "${RALPH_CMD_PREFIX+x}" ]]; then
  RALPH_PREFIX="$RALPH_CMD_PREFIX"
elif [[ -f "$_ralph_cmd_root/.ralph-prefix" ]]; then
  RALPH_PREFIX="$(tr -d '[:space:]' < "$_ralph_cmd_root/.ralph-prefix")"
else
  RALPH_PREFIX=""
fi

RALPH_BIN="${RALPH_PREFIX}ralph"

# Clone dir: namespaced var when prefixed, else RALPH_CLONE. Read via zsh
# indirect expansion ${(P)name}; empty when the var is unset.
if [[ -n "$RALPH_PREFIX" ]]; then
  _ralph_cmd_ns="${RALPH_PREFIX%%.*}"            # e.g. "per." -> "per"
  _ralph_cmd_ns="${(U)_ralph_cmd_ns}_"           # -> "PER_"
  _ralph_cmd_clone_var="${_ralph_cmd_ns}RALPH_CLONE"
else
  _ralph_cmd_clone_var="RALPH_CLONE"
fi
RALPH_CLONE_DIR="${(P)_ralph_cmd_clone_var:-}"

unset _ralph_cmd_root _ralph_cmd_ns _ralph_cmd_clone_var
