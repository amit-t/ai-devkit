#!/usr/bin/env zsh
# install.zsh — Install ai-devkit commands globally.
#   init.wb / join.wb / update.wb (+ .dev / .cly variants)
#
# Usage: ./install.zsh [--yes|-y|--non-interactive]
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

# ── Flag parsing (non-interactive support) ──────────────────────────────────
DEVKIT_NONINTERACTIVE="${DEVKIT_NONINTERACTIVE:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y|--non-interactive)
      DEVKIT_NONINTERACTIVE=1
      shift
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      print -u2 -r -- "Unknown flag: $1"
      exit 2
      ;;
  esac
done
export DEVKIT_NONINTERACTIVE

SCRIPT_DIR="${0:A:h}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

ok()   { printf "\033[0;32m[+]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }

# ── Versioning lib distribution ─────────────────────────────────────────────
SHARE_DIR="${HOME}/.local/share/wb-versioncheck"
mkdir -p "$SHARE_DIR"
cp "$SCRIPT_DIR/lib/version-check.sh"        "$SHARE_DIR/"
cp "$SCRIPT_DIR/lib/bootstrap-detection.sh"  "$SHARE_DIR/"
chmod 0644 "$SHARE_DIR/version-check.sh" "$SHARE_DIR/bootstrap-detection.sh"
ok "installed lib: $SHARE_DIR/version-check.sh"

# ── DEVKIT_CLONE in .zprofile ──────────────────────────────────────────────
ZPROFILE="${HOME}/.zprofile"
DEVKIT_LINE="export DEVKIT_CLONE=\"$SCRIPT_DIR\""
if ! grep -qF "$DEVKIT_LINE" "$ZPROFILE" 2>/dev/null; then
  # Strip any prior DEVKIT_CLONE assignment so relocating the clone
  # does not stack stale lines in ~/.zprofile.
  if [[ -f "$ZPROFILE" ]] && grep -q '^export DEVKIT_CLONE=' "$ZPROFILE"; then
    tmp_zp="$(mktemp)"
    grep -v '^export DEVKIT_CLONE=' "$ZPROFILE" > "$tmp_zp"
    mv "$tmp_zp" "$ZPROFILE"
  fi
  if ! grep -q "EXTERNAL PROJECT ALIASES" "$ZPROFILE" 2>/dev/null; then
    printf "\n# === EXTERNAL PROJECT ALIASES ===\n" >> "$ZPROFILE"
  fi
  printf "%s\n" "$DEVKIT_LINE" >> "$ZPROFILE"
  ok "wrote DEVKIT_CLONE to $ZPROFILE"
fi

# ── DEVKIT_DEFAULT_ENGINE in .zprofile ─────────────────────────────────────
# Prefer devin if it's on PATH (Q9 locked decision), else claude.
DEFAULT_ENGINE="claude"
(( $+commands[devin] )) && DEFAULT_ENGINE="devin"
ENGINE_LINE="export DEVKIT_DEFAULT_ENGINE=\"$DEFAULT_ENGINE\""
if ! grep -qF "$ENGINE_LINE" "$ZPROFILE" 2>/dev/null; then
  # Strip any prior DEVKIT_DEFAULT_ENGINE assignment so the value
  # doesn't stack stale lines in ~/.zprofile.
  if [[ -f "$ZPROFILE" ]] && grep -q '^export DEVKIT_DEFAULT_ENGINE=' "$ZPROFILE"; then
    tmp_zp="$(mktemp)"
    grep -v '^export DEVKIT_DEFAULT_ENGINE=' "$ZPROFILE" > "$tmp_zp"
    mv "$tmp_zp" "$ZPROFILE"
  fi
  if ! grep -q "EXTERNAL PROJECT ALIASES" "$ZPROFILE" 2>/dev/null; then
    printf "\n# === EXTERNAL PROJECT ALIASES ===\n" >> "$ZPROFILE"
  fi
  printf "%s\n" "$ENGINE_LINE" >> "$ZPROFILE"
  ok "wrote DEVKIT_DEFAULT_ENGINE=$DEFAULT_ENGINE to $ZPROFILE"
fi

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
install_cmd "init.wb"     "$SCRIPT_DIR/init-workbench/init.zsh"
add_alias "alias init.wb='$SCRIPT_DIR/init-workbench/init.zsh'"        "alias init.wb="
add_alias "alias init.wb.dev='$SCRIPT_DIR/init-workbench/init.zsh --agent devin'"   "alias init.wb.dev="
add_alias "alias init.wb.cly='$SCRIPT_DIR/init-workbench/init.zsh --agent claude'"  "alias init.wb.cly="

# ── join.wb ─────────────────────────────────────────────────────────────────
install_cmd "join.wb"     "$SCRIPT_DIR/join-workbench/join.zsh"
add_alias "alias join.wb='$SCRIPT_DIR/join-workbench/join.zsh'"        "alias join.wb="
add_alias "alias join.wb.dev='$SCRIPT_DIR/join-workbench/join.zsh --agent devin'"   "alias join.wb.dev="
add_alias "alias join.wb.cly='$SCRIPT_DIR/join-workbench/join.zsh --agent claude'"  "alias join.wb.cly="

# ── update.wb (deprecated; forwards to wb.upgrade) ─────────────────────────
# Earlier install.zsh versions installed update.wb as a symlink to
# update-workbench/update.zsh. A plain `cat > "$DEPRECATED_SHIM"` follows that
# symlink and overwrites the *real* update.zsh in the clone — corrupting the
# tree on every re-install. `rm -f` breaks the symlink first so we always
# write a fresh regular file.
DEPRECATED_SHIM="$BIN_DIR/update.wb"
rm -f "$DEPRECATED_SHIM"
cat > "$DEPRECATED_SHIM" <<SH
#!/usr/bin/env zsh
print -u2 -r -- "[deprecated] use 'wb.upgrade'. Forwarding..."
exec "$SCRIPT_DIR/update-workbench/update.zsh" "\$@"
SH
chmod +x "$DEPRECATED_SHIM"
add_alias "alias update.wb='$BIN_DIR/update.wb'" "alias update.wb="
ok "installed: update.wb (deprecated shim -> wb.upgrade)"

# ── wb.upgrade (canonical, replaces update.wb) ─────────────────────────────
install_cmd "wb.upgrade"     "$SCRIPT_DIR/update-workbench/update.zsh"
add_alias "alias wb.upgrade='$SCRIPT_DIR/update-workbench/update.zsh'"  "alias wb.upgrade="
add_alias "alias wb.upgrade.dev='$SCRIPT_DIR/update-workbench/update.zsh --agent devin'" "alias wb.upgrade.dev="
add_alias "alias wb.upgrade.cly='$SCRIPT_DIR/update-workbench/update.zsh --agent claude'" "alias wb.upgrade.cly="

# ── devkit.upgrade ──────────────────────────────────────────────────────────
install_cmd "devkit.upgrade"  "$SCRIPT_DIR/devkit-upgrade/devkit-upgrade.zsh"
add_alias "alias devkit.upgrade='$SCRIPT_DIR/devkit-upgrade/devkit-upgrade.zsh'" "alias devkit.upgrade="

# ── devkit doctor ───────────────────────────────────────────────────────────
DOCTOR_SHIM="$BIN_DIR/devkit"
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
    print -u2 -r -- "Usage: devkit doctor [--check-only|--fix]"
    print -u2 -r -- "       devkit upgrade [--check-only|--yes|--rollback]"
    exit 1
    ;;
esac
SH
chmod +x "$DOCTOR_SHIM"
ok "installed: devkit (subcommand wrapper)"

# ── orgs.wb ─────────────────────────────────────────────────────────────────
install_cmd "orgs.wb"     "$SCRIPT_DIR/orgs-workbench/orgs.zsh"
add_alias "alias orgs.wb='$SCRIPT_DIR/orgs-workbench/orgs.zsh'"        "alias orgs.wb="

# ── PATH check ──────────────────────────────────────────────────────────────
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  warn "$BIN_DIR not in PATH"
  printf "   Add to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
fi

# ── Ralph probe ─────────────────────────────────────────────────────────────
# init.wb / join.wb install ralph on demand. We just warn here so users see it
# now rather than later. Do NOT auto-install: ralph install touches ~/.ralph/
# and should be a deliberate step the user sees during init.wb.
if (( ! $+commands[ralph] )); then
  warn "ralph is not installed yet"
  printf "   init.wb / join.wb will install it from ai-ralph at first run.\n"
elif ! ralph --help 2>&1 | grep -q -- '--workspace'; then
  warn "ralph is installed but does not support --workspace mode"
  printf "   Update ai-ralph and re-run its install.sh:\n"
  printf "     cd \$HOME/Projects/Tools-Utilities/ai-ralph && git pull && bash install.sh\n"
fi

ok "done — run: source ~/.zshrc"
