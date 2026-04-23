#!/usr/bin/env zsh
# install.zsh — Install ai-devkit commands globally.
#   init.wb / join.wb / update.wb (+ .dev / .cly variants)
#
# Usage: ./install.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

ok()   { printf "\033[0;32m[+]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }

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

# ── update.wb ───────────────────────────────────────────────────────────────
install_cmd "update.wb"   "$SCRIPT_DIR/update-workbench/update.zsh"
add_alias "alias update.wb='$SCRIPT_DIR/update-workbench/update.zsh'"  "alias update.wb="
add_alias "alias update.wb.dev='$SCRIPT_DIR/update-workbench/update.zsh --agent devin'" "alias update.wb.dev="
add_alias "alias update.wb.cly='$SCRIPT_DIR/update-workbench/update.zsh --agent claude'" "alias update.wb.cly="

# ── PATH check ──────────────────────────────────────────────────────────────
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  warn "$BIN_DIR not in PATH"
  printf "   Add to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
fi

ok "done — run: source ~/.zshrc"
