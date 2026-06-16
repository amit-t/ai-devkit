#!/usr/bin/env zsh
# bootstrap-personal-machine.zsh — stand up the personal (amit-t) tool family on
# a fresh machine, idempotently. Safe to re-run any time to re-align aliases.
#
# What it does:
#   1. Clones the three personal repos under $BASE (skips any already present):
#        ai-devkit, ai-ralph, ai-workbench  — all via ssh host github.com-at.
#   2. Runs ai-devkit/install.zsh --prefix per.  (per.* command family + PER_ env)
#   3. Writes PER_RALPH_CLONE to ~/.zprofile (idempotent; install.zsh does not).
#   4. Sanity-checks gh identity is the personal account (amit-t).
#
# It does NOT touch the INV (unprefixed) family — that lives under
# ~/Projects/Invenco/Tools-Utilities/*-inv and is set up separately.
#
# New-machine flow is two commands:
#   git clone git@github.com-at:amit-t/ai-devkit.git ~/Projects/Tools-Utilities/ai-devkit
#   ~/Projects/Tools-Utilities/ai-devkit/scripts/bootstrap-personal-machine.zsh
#
# Then: source ~/.zprofile && source ~/.zshrc

set -euo pipefail

script_path="${0:A}"
DEVKIT_DIR="${script_path:h:h}"        # this clone's root (.../ai-devkit)
BASE="${PER_TOOLS_BASE:-${DEVKIT_DIR:h}}"   # parent dir holding the sibling repos
SSH_HOST="github.com-at"
OWNER="amit-t"
ZPROFILE="${HOME}/.zprofile"

ok()   { printf "\033[0;32m[+]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
die()  { printf "\033[0;31m[x]\033[0m %s\n" "$*" >&2; exit 1; }

# ── 1. clone siblings ───────────────────────────────────────────────────────
clone_if_missing() {
  local name="$1" dest="$BASE/$1"
  if [[ -d "$dest/.git" ]]; then
    ok "present: $dest"
  else
    ok "cloning $name -> $dest"
    git clone "git@${SSH_HOST}:${OWNER}/${name}.git" "$dest"
  fi
}
mkdir -p -- "$BASE"
clone_if_missing ai-devkit
clone_if_missing ai-ralph
clone_if_missing ai-workbench

# ── 2. install per.* family ─────────────────────────────────────────────────
ok "installing per.* command family from $BASE/ai-devkit"
(cd "$BASE/ai-devkit" && ./install.zsh --prefix per. --yes)

# ── 3. PER_RALPH_CLONE in ~/.zprofile (install.zsh does not write this) ──────
RALPH_CLONE_DIR="$BASE/ai-ralph"
if [[ -d "$RALPH_CLONE_DIR" ]]; then
  line="export PER_RALPH_CLONE=\"$RALPH_CLONE_DIR\""
  if ! grep -qF "$line" "$ZPROFILE" 2>/dev/null; then
    if [[ -f "$ZPROFILE" ]] && grep -q '^export PER_RALPH_CLONE=' "$ZPROFILE"; then
      tmp="$(mktemp)"; grep -v '^export PER_RALPH_CLONE=' "$ZPROFILE" > "$tmp"; mv "$tmp" "$ZPROFILE"
    fi
    grep -q "EXTERNAL PROJECT ALIASES" "$ZPROFILE" 2>/dev/null \
      || printf "\n# === EXTERNAL PROJECT ALIASES ===\n" >> "$ZPROFILE"
    printf "%s\n" "$line" >> "$ZPROFILE"
    ok "wrote PER_RALPH_CLONE to $ZPROFILE"
  else
    ok "PER_RALPH_CLONE already set"
  fi
fi

# ── 4. gh identity sanity (warn only; never mutate auth here) ────────────────
if (( $+commands[gh] )); then
  active="$(gh auth status --active 2>/dev/null | grep -oE 'account [^ ]+' | awk '{print $2}' | head -1 || true)"
  if [[ -n "$active" && "$active" != "$OWNER" ]]; then
    warn "active gh account is '$active', not '$OWNER'."
    warn "for personal work run: gh auth switch -u $OWNER"
  else
    ok "gh active account: ${active:-unknown}"
  fi
else
  warn "gh not installed; skip identity check"
fi

print -r --
ok "personal bootstrap complete."
print -r -- "Reload:  source ~/.zprofile && source ~/.zshrc"
print -r -- "Verify:  which per.init.wb && per.devkit doctor"
