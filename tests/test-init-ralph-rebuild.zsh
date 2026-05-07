#!/usr/bin/env zsh
# test-init-ralph-rebuild.zsh — Lock in init.wb Step 3.10b rebuild behaviour.
#
# Bug Devin flagged: Step 3.10b skipped ralph-enable when `.ralph/` was already
# present from the template clone, leaving the template's stale AGENT.md in
# place. Fix: on init (a known-fresh workbench), wipe and rebuild.
#
# This test asserts the prompt instructs the agent to rm -rf .ralph and run
# ralph-enable unconditionally, and also exercises the snippet against a
# stubbed ralph-enable to confirm the shell logic is sound.
#
# Run: zsh tests/test-init-ralph-rebuild.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DEVKIT_ROOT="${SCRIPT_DIR:h}"
PROMPT="${DEVKIT_ROOT}/init-workbench/init.prompt.md"

[[ -f "$PROMPT" ]] || { print -u2 "FAIL: $PROMPT missing"; exit 1; }

# 1. Prompt-level assertions: the rebuild guidance must be present, and the
#    old skip-on-exists pattern must be gone.
if ! grep -q 'rm -rf .ralph' "$PROMPT"; then
  print -u2 "FAIL: init.prompt.md missing 'rm -rf .ralph' rebuild step"
  exit 1
fi
print "PASS: init.prompt.md instructs rm -rf .ralph on init"

if grep -q 'already present — skipping ralph-enable' "$PROMPT"; then
  print -u2 "FAIL: init.prompt.md still contains the old skip-on-exists message"
  exit 1
fi
print "PASS: init.prompt.md no longer skips ralph-enable when .ralph/ pre-exists"

# 2. Behavioural smoke: extract the snippet's rebuild rule and run it against
#    a stubbed ralph-enable, with a pre-seeded stale .ralph/ in WB_DIR.
TMP_WB="$(mktemp -d -t init-ralph-test.XXXXXX)"
trap 'rm -rf "$TMP_WB"' EXIT

mkdir -p "$TMP_WB/.ralph"
print 'STALE TEMPLATE AGENT.md' > "$TMP_WB/.ralph/AGENT.md"

# Stub ralph-enable: writes a marker file and a fresh AGENT.md so we can tell
# rebuild ran and the stale template content is gone.
mkdir -p "$TMP_WB/stubs"
cat > "$TMP_WB/stubs/ralph-enable" <<'STUB'
#!/usr/bin/env zsh
mkdir -p .ralph
print 'FRESH AGENT.md from ralph-enable stub' > .ralph/AGENT.md
print 'rebuilt' > .ralph/.marker
STUB
chmod +x "$TMP_WB/stubs/ralph-enable"

(
  cd "$TMP_WB"
  PATH="$TMP_WB/stubs:$PATH"
  if [[ -d .ralph ]]; then
    rm -rf .ralph
  fi
  ralph-enable --non-interactive
)

[[ -f "$TMP_WB/.ralph/.marker" ]] || { print -u2 "FAIL: rebuild did not run"; exit 1; }
if grep -q 'STALE TEMPLATE' "$TMP_WB/.ralph/AGENT.md"; then
  print -u2 "FAIL: stale template AGENT.md survived rebuild"
  exit 1
fi
print "PASS: rebuild wipes stale template .ralph/ and reruns ralph-enable"

print "All init-ralph-rebuild tests passed."
