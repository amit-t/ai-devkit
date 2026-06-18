#!/usr/bin/env zsh
# install.zsh — Install ai-devkit commands globally.
#   init.wb / join.wb / update.wb              (planning workbench)
#   init.auto.wb / join.auto.wb / update.auto.wb / adopt.auto.wb  (test-automation workbench)
#   orgs.wb                                     (shared org list)
# All four forms also get .dev (force Devin) and .cly (force Claude) variants.
#
# Usage: ./install.zsh [--yes|-y|--non-interactive] [--prefix <p>]
#
# Command-name prefix (multi-clone coexistence):
#   --prefix <p>  (or env DEVKIT_CMD_PREFIX) prepends <p> to every installed
#   command name, alias, and bin symlink, and namespaces the env vars +
#   version-check state dir so two ai-devkit clones can coexist on one machine
#   without clobbering each other. Example: `./install.zsh --prefix per.`
#   installs `per.init.wb`, `per.join.wb`, `per.wb.upgrade`, `per.devkit`, ...
#   and writes PER_DEVKIT_CLONE / PER_DEVKIT_DEFAULT_ENGINE /
#   PER_DEVKIT_CLAUDE_CMD to ~/.zprofile. On this personal fork the default
#   engine is Claude, launched through `clscb` (see lib/engine-cmd.zsh).
#   This personal fork DEFAULTS the prefix to `per.` so it never clobbers a
#   company clone's bare init.wb/join.wb. Pass `--prefix ''` for no prefix.
#
# Non-interactive mode:
#   Set env DEVKIT_NONINTERACTIVE=1, or pass --yes / -y / --non-interactive.
#   In non-interactive mode any future prompt accepts the safe default:
#     - org slug = $DEVKIT_DEFAULT_ORG (or the current git remote owner)
#     - "install ralph?" = yes
#     - "install devkit aliases?" = yes
#   Interactive TTY behaviour with neither flag/env set is unchanged.
#   The CI smoke workflow (.github/workflows/smoke-install.yml) drives the
#   non-interactive path. The script today has no prompts but new prompts
#   added later must consult DEVKIT_NONINTERACTIVE before reading stdin.

set -euo pipefail

# ── Flag parsing (non-interactive + command-name prefix) ────────────────────
DEVKIT_NONINTERACTIVE="${DEVKIT_NONINTERACTIVE:-0}"
# This personal fork defaults to the `per.` prefix so it never clobbers a
# company clone's bare init.wb/join.wb commands. Override with env
# DEVKIT_CMD_PREFIX or --prefix (pass `--prefix ''` for no prefix).
CMD_PREFIX="${DEVKIT_CMD_PREFIX:-per.}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y|--non-interactive)
      DEVKIT_NONINTERACTIVE=1
      shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || { print -u2 -r -- "--prefix needs a value"; exit 2; }
      CMD_PREFIX="$2"
      shift 2
      ;;
    --prefix=*)
      CMD_PREFIX="${1#--prefix=}"
      shift
      ;;
    -h|--help)
      sed -n '2,26p' "$0"
      exit 0
      ;;
    *)
      print -u2 -r -- "Unknown flag: $1"
      exit 2
      ;;
  esac
done
export DEVKIT_NONINTERACTIVE

# Derived from the prefix:
#   ENV_NS    env-var namespace, e.g. "per." -> "PER_"  ("" when no prefix)
#   STATE_TAG version-check state-dir tag, e.g. "per." -> "per-"  ("" when none)
ENV_NS=""
STATE_TAG=""
if [[ -n "$CMD_PREFIX" ]]; then
  ns_base="${CMD_PREFIX%%.*}"          # "per." -> "per"
  ns_base="${ns_base//[^A-Za-z0-9]/}"  # strip stray punctuation
  ENV_NS="$(printf '%s' "$ns_base" | tr '[:lower:]' '[:upper:]')_"   # PER_
  STATE_TAG="${ns_base:l}-"            # per-
fi

SCRIPT_DIR="${0:A:h}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

# Resolve the ralph command family (marker-driven; see lib/ralph-cmd.zsh).
# Sets RALPH_PREFIX / RALPH_BIN / RALPH_CLONE_DIR in this scope.
RALPH_CMD_LIB_ROOT="$SCRIPT_DIR" source "$SCRIPT_DIR/lib/ralph-cmd.zsh"

ok()   { printf "\033[0;32m[+]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }

# ── Versioning lib distribution ─────────────────────────────────────────────
SHARE_DIR="${HOME}/.local/share/${STATE_TAG}wb-versioncheck"
mkdir -p "$SHARE_DIR"
cp "$SCRIPT_DIR/lib/version-check.sh"        "$SHARE_DIR/"
cp "$SCRIPT_DIR/lib/bootstrap-detection.sh"  "$SHARE_DIR/"
chmod 0644 "$SHARE_DIR/version-check.sh" "$SHARE_DIR/bootstrap-detection.sh"
ok "installed lib: $SHARE_DIR/version-check.sh"

# Persist clone path so devkit-doctor / devkit-upgrade can recover the
# local version even from shells that have not sourced ~/.zprofile (issue
# #17). The env var in ~/.zprofile remains the canonical source; this
# file is a cross-session fallback that ships with the install itself.
DEVKIT_CLONE_STATE="$SHARE_DIR/devkit-clone.path"
printf '%s\n' "$SCRIPT_DIR" > "$DEVKIT_CLONE_STATE"
chmod 0644 "$DEVKIT_CLONE_STATE"
ok "persisted clone path: $DEVKIT_CLONE_STATE"

# Record this install's command prefix as a clone-local marker so the
# version-check launchers (init/join/update.zsh) resolve the correct state-dir
# tag + WB_CMD_PREFIX without re-sourcing ~/.zprofile. Empty file = unprefixed
# (twin) install. Parity-safe: each fork writes its own value.
DEVKIT_PREFIX_MARKER="$SCRIPT_DIR/.devkit-cmd-prefix"
printf '%s\n' "$CMD_PREFIX" > "$DEVKIT_PREFIX_MARKER"
chmod 0644 "$DEVKIT_PREFIX_MARKER"
ok "recorded command prefix marker: $DEVKIT_PREFIX_MARKER (${CMD_PREFIX:-<none>})"

# ── {ENV_NS}DEVKIT_CLONE in .zprofile ──────────────────────────────────────
ZPROFILE="${HOME}/.zprofile"
CLONE_VAR="${ENV_NS}DEVKIT_CLONE"
DEVKIT_LINE="export ${CLONE_VAR}=\"$SCRIPT_DIR\""
if ! grep -qF "$DEVKIT_LINE" "$ZPROFILE" 2>/dev/null; then
  # Strip any prior assignment so relocating the clone
  # does not stack stale lines in ~/.zprofile.
  if [[ -f "$ZPROFILE" ]] && grep -q "^export ${CLONE_VAR}=" "$ZPROFILE"; then
    tmp_zp="$(mktemp)"
    grep -v "^export ${CLONE_VAR}=" "$ZPROFILE" > "$tmp_zp"
    mv "$tmp_zp" "$ZPROFILE"
  fi
  if ! grep -q "EXTERNAL PROJECT ALIASES" "$ZPROFILE" 2>/dev/null; then
    printf "\n# === EXTERNAL PROJECT ALIASES ===\n" >> "$ZPROFILE"
  fi
  printf "%s\n" "$DEVKIT_LINE" >> "$ZPROFILE"
  ok "wrote ${CLONE_VAR} to $ZPROFILE"
fi

# ── Engine defaults in .zprofile ────────────────────────────────────────────
# Idempotently upsert `export VAR="VALUE"` into ~/.zprofile (strips any prior
# assignment so values don't stack across re-installs).
upsert_zprofile_export() {
  local var="$1" value="$2" line="export $1=\"$2\""
  grep -qF "$line" "$ZPROFILE" 2>/dev/null && return 0
  if [[ -f "$ZPROFILE" ]] && grep -q "^export ${var}=" "$ZPROFILE"; then
    tmp_zp="$(mktemp)"
    grep -v "^export ${var}=" "$ZPROFILE" > "$tmp_zp"
    mv "$tmp_zp" "$ZPROFILE"
  fi
  if ! grep -q "EXTERNAL PROJECT ALIASES" "$ZPROFILE" 2>/dev/null; then
    printf "\n# === EXTERNAL PROJECT ALIASES ===\n" >> "$ZPROFILE"
  fi
  printf "%s\n" "$line" >> "$ZPROFILE"
  ok "wrote ${var}=${value} to $ZPROFILE"
}

# This personal (prefixed) fork makes Claude the default engine, launched
# through the user's `clscb` wrapper (cly + precision + superpowers + caveman +
# boil). An unprefixed/twin install keeps the legacy preference: devin if it's
# on PATH (Q9 locked decision), else claude, launched as bare `claude`.
if [[ -n "$CMD_PREFIX" ]]; then
  DEFAULT_ENGINE="claude"
  DEFAULT_CLAUDE_CMD="clscb"
else
  DEFAULT_ENGINE="claude"
  (( $+commands[devin] )) && DEFAULT_ENGINE="devin"
  DEFAULT_CLAUDE_CMD="claude"
fi
upsert_zprofile_export "${ENV_NS}DEVKIT_DEFAULT_ENGINE" "$DEFAULT_ENGINE"
upsert_zprofile_export "${ENV_NS}DEVKIT_CLAUDE_CMD"      "$DEFAULT_CLAUDE_CMD"

# ── Skill symlinks (multi-engine) ──────────────────────────────────────────
# Vendored skill source lives in the devkit clone. We expose it to each
# supported engine's skills dir via idempotent symlinks (Q3 locked decision).
SKILL_SRC="${SCRIPT_DIR}/skills/repo-context-scan"
for engine_dir in "$HOME/.claude/skills" "$HOME/.devin/skills" "$HOME/.agents/skills"; do
  mkdir -p "$engine_dir"
  ln -sfn "$SKILL_SRC" "$engine_dir/repo-context-scan"
  ok "linked: $engine_dir/repo-context-scan -> $SKILL_SRC"
done

# Devkit-internal exposure: mirror the same skill under the devkit clone so
# engine-aware tooling can find it relative to DEVKIT_CLONE too.
for internal_dir in "${SCRIPT_DIR}/.claude/skills" "${SCRIPT_DIR}/.agents/skills"; do
  mkdir -p "$internal_dir"
  ln -sfn "$SKILL_SRC" "$internal_dir/repo-context-scan"
  ok "linked: $internal_dir/repo-context-scan -> $SKILL_SRC"
done

# ── Command name templating ─────────────────────────────────────────────────
# Every installed command/alias/symlink gets $CMD_PREFIX prepended (empty by
# default). cmd() returns the prefixed name.
cmd() { printf '%s%s' "$CMD_PREFIX" "$1"; }

install_cmd() {
  local name="$1" target="$2"
  ln -sf "$target" "$BIN_DIR/$name"
  chmod +x "$target" "$BIN_DIR/$name"
  ok "installed: $name → $target"
}

add_alias() {
  local alias_line="$1" marker="$2"
  if grep -qF "$marker" "${HOME}/.zshrc" 2>/dev/null; then
    ok "alias present: $marker"
  else
    printf "\n%s\n" "$alias_line" >> "${HOME}/.zshrc"
    ok "added alias: $marker"
  fi
}

# ── init.wb ─────────────────────────────────────────────────────────────────
install_cmd "$(cmd init.wb)"     "$SCRIPT_DIR/init-workbench/init.zsh"
add_alias "alias $(cmd init.wb)='$SCRIPT_DIR/init-workbench/init.zsh'"        "alias $(cmd init.wb)="
add_alias "alias $(cmd init.wb.dev)='$SCRIPT_DIR/init-workbench/init.zsh --agent devin'"   "alias $(cmd init.wb.dev)="
add_alias "alias $(cmd init.wb.cly)='$SCRIPT_DIR/init-workbench/init.zsh --agent claude'"  "alias $(cmd init.wb.cly)="

# ── join.wb ─────────────────────────────────────────────────────────────────
install_cmd "$(cmd join.wb)"     "$SCRIPT_DIR/join-workbench/join.zsh"
add_alias "alias $(cmd join.wb)='$SCRIPT_DIR/join-workbench/join.zsh'"        "alias $(cmd join.wb)="
add_alias "alias $(cmd join.wb.dev)='$SCRIPT_DIR/join-workbench/join.zsh --agent devin'"   "alias $(cmd join.wb.dev)="
add_alias "alias $(cmd join.wb.cly)='$SCRIPT_DIR/join-workbench/join.zsh --agent claude'"  "alias $(cmd join.wb.cly)="

# ── update.wb (deprecated; forwards to wb.upgrade) ─────────────────────────
# Earlier install.zsh versions installed update.wb as a symlink to
# update-workbench/update.zsh. A plain `cat > "$DEPRECATED_SHIM"` follows that
# symlink and overwrites the *real* update.zsh in the clone — corrupting the
# tree on every re-install. `rm -f` breaks the symlink first so we always
# write a fresh regular file.
DEPRECATED_SHIM="$BIN_DIR/$(cmd update.wb)"
rm -f "$DEPRECATED_SHIM"
cat > "$DEPRECATED_SHIM" <<SH
#!/usr/bin/env zsh
print -u2 -r -- "[deprecated] use '$(cmd wb.upgrade)'. Forwarding..."
exec "$SCRIPT_DIR/update-workbench/update.zsh" "\$@"
SH
chmod +x "$DEPRECATED_SHIM"
add_alias "alias $(cmd update.wb)='$DEPRECATED_SHIM'" "alias $(cmd update.wb)="
ok "installed: $(cmd update.wb) (deprecated shim -> $(cmd wb.upgrade))"

# ── wb.upgrade (canonical, replaces update.wb) ─────────────────────────────
install_cmd "$(cmd wb.upgrade)"     "$SCRIPT_DIR/update-workbench/update.zsh"
add_alias "alias $(cmd wb.upgrade)='$SCRIPT_DIR/update-workbench/update.zsh'"  "alias $(cmd wb.upgrade)="
add_alias "alias $(cmd wb.upgrade.dev)='$SCRIPT_DIR/update-workbench/update.zsh --agent devin'" "alias $(cmd wb.upgrade.dev)="
add_alias "alias $(cmd wb.upgrade.cly)='$SCRIPT_DIR/update-workbench/update.zsh --agent claude'" "alias $(cmd wb.upgrade.cly)="

# ── devkit.upgrade ──────────────────────────────────────────────────────────
install_cmd "$(cmd devkit.upgrade)"  "$SCRIPT_DIR/devkit-upgrade/devkit-upgrade.zsh"
add_alias "alias $(cmd devkit.upgrade)='$SCRIPT_DIR/devkit-upgrade/devkit-upgrade.zsh'" "alias $(cmd devkit.upgrade)="

# ── devkit doctor ───────────────────────────────────────────────────────────
DOCTOR_SHIM="$BIN_DIR/$(cmd devkit)"
cat > "$DOCTOR_SHIM" <<SH
#!/usr/bin/env zsh
case "\$1" in
  doctor)
    shift
    exec "$SCRIPT_DIR/devkit-doctor/devkit-doctor.zsh" "\$@"
    ;;
  upgrade)
    shift
    exec "$SCRIPT_DIR/devkit-upgrade/devkit-upgrade.zsh" "\$@"
    ;;
  *)
    print -u2 -r -- "Unknown subcommand: \$1"
    print -u2 -r -- "Usage: $(cmd devkit) doctor [--check-only|--fix]"
    print -u2 -r -- "       $(cmd devkit) upgrade [--check-only|--yes|--rollback]"
    exit 1
    ;;
esac
SH
chmod +x "$DOCTOR_SHIM"
ok "installed: $(cmd devkit) (subcommand wrapper)"

# ── init.auto.wb (test-automation workbench) ────────────────────────────────
install_cmd "$(cmd init.auto.wb)"   "$SCRIPT_DIR/init-test-workbench/init.zsh"
add_alias "alias $(cmd init.auto.wb)='$SCRIPT_DIR/init-test-workbench/init.zsh'"                 "alias $(cmd init.auto.wb)="
add_alias "alias $(cmd init.auto.wb.dev)='$SCRIPT_DIR/init-test-workbench/init.zsh --agent devin'"   "alias $(cmd init.auto.wb.dev)="
add_alias "alias $(cmd init.auto.wb.cly)='$SCRIPT_DIR/init-test-workbench/init.zsh --agent claude'"  "alias $(cmd init.auto.wb.cly)="

# ── join.auto.wb ────────────────────────────────────────────────────────────
install_cmd "$(cmd join.auto.wb)"   "$SCRIPT_DIR/join-test-workbench/join.zsh"
add_alias "alias $(cmd join.auto.wb)='$SCRIPT_DIR/join-test-workbench/join.zsh'"                 "alias $(cmd join.auto.wb)="
add_alias "alias $(cmd join.auto.wb.dev)='$SCRIPT_DIR/join-test-workbench/join.zsh --agent devin'"   "alias $(cmd join.auto.wb.dev)="
add_alias "alias $(cmd join.auto.wb.cly)='$SCRIPT_DIR/join-test-workbench/join.zsh --agent claude'"  "alias $(cmd join.auto.wb.cly)="

# ── update.auto.wb ──────────────────────────────────────────────────────────
install_cmd "$(cmd update.auto.wb)" "$SCRIPT_DIR/update-test-workbench/update.zsh"
add_alias "alias $(cmd update.auto.wb)='$SCRIPT_DIR/update-test-workbench/update.zsh'"                "alias $(cmd update.auto.wb)="
add_alias "alias $(cmd update.auto.wb.dev)='$SCRIPT_DIR/update-test-workbench/update.zsh --agent devin'"  "alias $(cmd update.auto.wb.dev)="
add_alias "alias $(cmd update.auto.wb.cly)='$SCRIPT_DIR/update-test-workbench/update.zsh --agent claude'" "alias $(cmd update.auto.wb.cly)="

# ── adopt.auto.wb (archive + recreate branches from template) ───────────────
install_cmd "$(cmd adopt.auto.wb)"  "$SCRIPT_DIR/adopt-test-workbench/adopt.zsh"
add_alias "alias $(cmd adopt.auto.wb)='$SCRIPT_DIR/adopt-test-workbench/adopt.zsh'"                "alias $(cmd adopt.auto.wb)="
add_alias "alias $(cmd adopt.auto.wb.dev)='$SCRIPT_DIR/adopt-test-workbench/adopt.zsh --agent devin'"  "alias $(cmd adopt.auto.wb.dev)="
add_alias "alias $(cmd adopt.auto.wb.cly)='$SCRIPT_DIR/adopt-test-workbench/adopt.zsh --agent claude'" "alias $(cmd adopt.auto.wb.cly)="

# ── orgs.wb ─────────────────────────────────────────────────────────────────
install_cmd "$(cmd orgs.wb)"     "$SCRIPT_DIR/orgs-workbench/orgs.zsh"
add_alias "alias $(cmd orgs.wb)='$SCRIPT_DIR/orgs-workbench/orgs.zsh'"        "alias $(cmd orgs.wb)="

# ── PATH check ──────────────────────────────────────────────────────────────
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  warn "$BIN_DIR not in PATH"
  printf "   Add to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
fi

# ── Ralph probe ─────────────────────────────────────────────────────────────
# init.* / join.* install ralph on demand. We just warn here so users see it
# now rather than later. Do NOT auto-install: ralph install touches ~/.ralph/
# and should be a deliberate step the user sees during an init flow.
if ! command -v "$RALPH_BIN" >/dev/null 2>&1; then
  warn "$RALPH_BIN is not installed yet"
  printf "   $(cmd init.wb) / $(cmd init.auto.wb) / $(cmd join.wb) / $(cmd join.auto.wb) will install it from ai-ralph at first run.\n"
elif ! "$RALPH_BIN" --help 2>&1 | grep -q -- '--workspace'; then
  warn "$RALPH_BIN is installed but does not support --workspace mode"
  printf "   Update ai-ralph and re-run its install.sh:\n"
  printf "     cd \$HOME/Projects/Tools-Utilities/ai-ralph && git pull && bash install.sh\n"
fi

ok "done — run: source ~/.zshrc"
