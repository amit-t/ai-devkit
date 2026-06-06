#!/usr/bin/env zsh
# test-init-lite.zsh - Workbench Lite bootstrap for init.wb --lite.

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
INIT="$REPO_ROOT/init-workbench/init.zsh"
LITE="$REPO_ROOT/init-workbench/lite-bootstrap.zsh"

fail() { print -u2 -r -- "FAIL: $*"; exit 1; }
pass() { print -r -- "PASS: $*"; }

count_fixed() {
  local needle="$1" file="$2"
  grep -cF -- "$needle" "$file" 2>/dev/null || true
}

scratch="$(mktemp -d -t init-lite.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT

fake_home="$scratch/home"
fake_ralph="$scratch/ai-ralph"
fake_wb="$scratch/workbench-example"
log="$scratch/ralph.log"
mkdir -p "$fake_home" "$fake_ralph/devin" "$fake_wb/repos/app-one" "$fake_wb/repos/app-two"

cat > "$fake_wb/project.conf" <<'CONF'
WORKBENCH_LABEL="example"
REPOS=(
  "name=app-one;url=git@github.com:org/app-one.git;role=service;stack=node;added_by=alice"
  "name=app-two;url=git@github.com:org/app-two.git;role=automation-tests;stack=playwright;added_by=alice"
)
CONF

cat > "$fake_ralph/install.sh" <<'INSTALL'
#!/usr/bin/env zsh
set -euo pipefail
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ralph" <<'RALPH'
#!/usr/bin/env zsh
set -euo pipefail
: ${WB_LITE_RALPH_LOG:=""}
if [[ -n "$WB_LITE_RALPH_LOG" ]]; then
  print -r -- "$PWD|$*" >> "$WB_LITE_RALPH_LOG"
fi
if [[ "${1:-}" == "--help" ]]; then
  print -r -- "Usage: ralph [--workspace]"
  exit 0
fi
if [[ "${1:-}" == "enable" ]]; then
  shift
  for arg in "$@"; do
    [[ "$arg" == "--workspace" ]] && { print -u2 -- "workspace mode must not be used for Lite app repos"; exit 9; }
  done
  mkdir -p .ralph
  print -r -- "prompt" > .ralph/PROMPT.md
  print -r -- "plan" > .ralph/fix_plan.md
  print -r -- "agent" > .ralph/AGENT.md
  print -r -- "RALPH_STATE=complete" > .ralph/state.env
  exit 0
fi
print -u2 -r -- "unexpected ralph args: $*"
exit 8
RALPH
chmod +x "$HOME/.local/bin/ralph"
INSTALL
chmod +x "$fake_ralph/install.sh"

cat > "$fake_ralph/devin/install_devin.sh" <<'INSTALL'
#!/usr/bin/env zsh
set -euo pipefail
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ralph-devin" <<'RALPHDEVIN'
#!/usr/bin/env zsh
print -r -- "ralph-devin $*"
RALPHDEVIN
chmod +x "$HOME/.local/bin/ralph-devin"
INSTALL
chmod +x "$fake_ralph/devin/install_devin.sh"

cat > "$fake_ralph/devin/ALIASES.sh" <<'ALIASES'
alias rpd='ralph-devin'
rpd.p() { ralph-devin --parallel "${1:?Usage: rpd.p <N> [M]}" ${2:+"$2"}; }
ALIASES

# RED target: Lite bootstrap script does machine install, PATH/aliases, per-app enable, and config seed.
HOME="$fake_home" \
PATH="/usr/bin:/bin" \
WB_LITE_RALPH_SRC="$fake_ralph" \
WB_LITE_PROFILE="$fake_home/.zprofile" \
WB_LITE_RALPH_LOG="$log" \
zsh "$LITE" --wb-dir "$fake_wb" >"$scratch/init-lite-bootstrap.out" 2>"$scratch/init-lite-bootstrap.err"

HOME="$fake_home" ZDOTDIR="$fake_home" zsh -l -c 'command -v ralph-devin >/dev/null && command -v rpd >/dev/null && command -v rpd.p >/dev/null' \
  || fail "fresh login shell did not resolve ralph-devin, rpd, and rpd.p"
pass "fresh login shell resolves ralph-devin, rpd, and rpd.p"

marker_start_count="$(count_fixed '# >>> ai-devkit workbench-lite >>>' "$fake_home/.zprofile")"
[[ "$marker_start_count" == "1" ]] || fail "expected one Lite marker after first run, got $marker_start_count"
pass "first run writes one Lite marker block"

for app in app-one app-two; do
  [[ -d "$fake_wb/repos/$app/.ralph" ]] || fail "$app missing repo-local .ralph"
  grep -q '^RALPH_STATE=complete$' "$fake_wb/repos/$app/.ralph/state.env" || fail "$app missing complete state marker"
  grep -q "repos/$app|enable$" "$log" || fail "$app was not enabled with plain 'ralph enable'"
done
[[ ! -d "$fake_wb/.ralph" ]] || fail "Lite bootstrap created forbidden workbench-root .ralph"
pass "per-app ralph enable runs without root .ralph"

expected_defaults='WB_LITE_PRD_AGENT="codex"
WB_LITE_SPEC_AGENT="codex"
WB_LITE_GRILL_AGENT="codex"
WB_LITE_CHECKPOINT_AGENT="codex"
WB_LITE_PLAN_AGENT="codex"      # forward-compat; v1 plan delegates to ralph-plan
WB_LITE_RALPH_AGENT="rpd.p"     # user-facing mnemonic; wrapper execs ralph-devin --parallel N
WB_LITE_GRILL_MODE="ask"        # ask | auto | live
WB_LITE_DEFAULT_TASKS="5"
WB_LITE_PLAN_MODE="delegate"    # delegate (ralph-plan) | synthesize
WB_LITE_AGENT_INVOKE="stdin"    # stdin | argv'
if ! grep -qF -- '# --- Workbench Lite defaults ---' "$fake_wb/project.conf"; then
  fail "project.conf missing Workbench Lite defaults header"
fi
if ! grep -qF -- "$expected_defaults" "$fake_wb/project.conf"; then
  print -u2 -r -- "$fake_wb/project.conf contents:"
  print -u2 -r -- "$(< "$fake_wb/project.conf")"
  fail "project.conf Lite defaults block drifted"
fi
pass "project.conf includes exact Lite defaults"

HOME="$fake_home" \
PATH="/usr/bin:/bin" \
WB_LITE_RALPH_SRC="$fake_ralph" \
WB_LITE_PROFILE="$fake_home/.zprofile" \
WB_LITE_RALPH_LOG="$log" \
zsh "$LITE" --wb-dir "$fake_wb" >"$scratch/init-lite-bootstrap-rerun.out" 2>"$scratch/init-lite-bootstrap-rerun.err"

marker_rerun_count="$(count_fixed '# >>> ai-devkit workbench-lite >>>' "$fake_home/.zprofile")"
defaults_rerun_count="$(count_fixed '# --- Workbench Lite defaults ---' "$fake_wb/project.conf")"
[[ "$marker_rerun_count" == "1" ]] || fail "rerun duplicated Lite profile marker ($marker_rerun_count)"
[[ "$defaults_rerun_count" == "1" ]] || fail "rerun duplicated Lite defaults ($defaults_rerun_count)"
pass "rerun is idempotent for PATH marker and config defaults"

HOME="$fake_home" \
PATH="/usr/bin:/bin" \
WB_LITE_PROFILE="$fake_home/.zprofile" \
zsh "$INIT" --lite --undo >"$scratch/init-lite-undo.out" 2>"$scratch/init-lite-undo.err"

undo_count="$(count_fixed '# >>> ai-devkit workbench-lite >>>' "$fake_home/.zprofile")"
[[ "$undo_count" == "0" ]] || fail "--lite --undo left marker block behind"
pass "init.wb --lite --undo removes marker block"

stub_bin="$scratch/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/claude" <<'CLAUDE'
#!/usr/bin/env zsh
print -r -- "$*" > "$CAPTURE_PROMPT"
CLAUDE
chmod +x "$stub_bin/claude"
: > "$scratch/captured-prompt"
HOME="$fake_home" \
ZDOTDIR="$fake_home" \
PATH="$stub_bin:/usr/bin:/bin" \
CAPTURE_PROMPT="$scratch/captured-prompt" \
zsh "$INIT" --lite --agent claude --cwd "$scratch" >"$scratch/init-lite-launch.out" 2>"$scratch/init-lite-launch.err"

grep -q 'LITE_MODE=true' "$scratch/captured-prompt" || fail "launcher prompt missing LITE_MODE=true"
grep -q 'zsh "${DEVKIT_DIR}/init-workbench/lite-bootstrap.zsh" --wb-dir "${WB_DIR}"' "$scratch/captured-prompt" || fail "launcher prompt missing Lite bootstrap call"
grep -q 'If Runtime Context has `LITE_MODE=true`, skip this step' "$scratch/captured-prompt" || fail "launcher prompt does not skip root .ralph step in Lite mode"
pass "init.wb --lite passes Lite mode instructions to agent prompt"

print -r -- "All init-lite tests passed."
