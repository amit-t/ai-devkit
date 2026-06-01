#!/usr/bin/env zsh
# test-graphify-prompt-wiring.zsh — Lock the init/join prompts wiring `wb.graphify`.
#
# Asserts:
#   1. init.prompt.md carries a graphify step that resolves GRAPHIFY_MODE
#      and invokes scripts/graphify-repos.sh (--install-skill + --all).
#   2. join.prompt.md carries the same step for joiner-added repos.
#   3. Both honor GRAPHIFY_MODE=manual by short-circuiting auto-run.
#   4. Both pass --no-install through when WB_GRAPHIFY_NO_INSTALL is set.

set -e

REPO_ROOT="${0:A:h:h}"
INIT="$REPO_ROOT/init-workbench/init.prompt.md"
JOIN="$REPO_ROOT/join-workbench/join.prompt.md"

[[ -f $INIT ]] || { print -u2 "FAIL: $INIT missing"; exit 1 }
[[ -f $JOIN ]] || { print -u2 "FAIL: $JOIN missing"; exit 1 }

assert_in() {
  local file="$1" pat="$2" label="$3"
  if ! grep -qE -- "$pat" "$file"; then
    print -u2 "FAIL: $label — pattern not found in $file: $pat"
    exit 1
  fi
  print "PASS: $label"
}

# init.prompt.md
assert_in "$INIT" 'graphify-repos\.sh --install-skill' \
  'init.prompt.md invokes graphify-repos.sh --install-skill'
assert_in "$INIT" 'graphify-repos\.sh --all' \
  'init.prompt.md invokes graphify-repos.sh --all'
assert_in "$INIT" 'GRAPHIFY_MODE' \
  'init.prompt.md resolves GRAPHIFY_MODE'
assert_in "$INIT" 'WB_GRAPHIFY_NO_INSTALL' \
  'init.prompt.md threads WB_GRAPHIFY_NO_INSTALL'
assert_in "$INIT" 'manual' \
  'init.prompt.md handles GRAPHIFY_MODE=manual branch'

# join.prompt.md
assert_in "$JOIN" 'graphify-repos\.sh --install-skill' \
  'join.prompt.md invokes graphify-repos.sh --install-skill'
assert_in "$JOIN" 'graphify-repos\.sh --all' \
  'join.prompt.md invokes graphify-repos.sh --all'
assert_in "$JOIN" 'GRAPHIFY_MODE' \
  'join.prompt.md resolves GRAPHIFY_MODE'
assert_in "$JOIN" 'WB_GRAPHIFY_NO_INSTALL' \
  'join.prompt.md threads WB_GRAPHIFY_NO_INSTALL'
assert_in "$JOIN" 'manual' \
  'join.prompt.md handles GRAPHIFY_MODE=manual branch'

# Step ordering: graphify must come AFTER context-scan aggregate (so context
# is built first), BEFORE the final commit (so the SKILL.md + flag flips land
# in the initial commit).
init_agg_ln=$(grep -n 'wb-context-scan.zsh" aggregate' "$INIT" | head -1 | cut -d: -f1)
init_gph_ln=$(grep -n 'graphify-repos.sh' "$INIT" | head -1 | cut -d: -f1)
init_commit_ln=$(grep -n 'git commit -m' "$INIT" | head -1 | cut -d: -f1)
if [[ -z "$init_agg_ln" || -z "$init_gph_ln" || -z "$init_commit_ln" ]]; then
  print -u2 "FAIL: init.prompt.md ordering check could not find all anchor lines"
  exit 1
fi
(( init_agg_ln < init_gph_ln )) || { print -u2 "FAIL: init.prompt.md — graphify must come AFTER aggregate"; exit 1 }
(( init_gph_ln < init_commit_ln )) || { print -u2 "FAIL: init.prompt.md — graphify must come BEFORE git commit"; exit 1 }
print "PASS: init.prompt.md graphify step is between aggregate and commit"

join_agg_ln=$(grep -n 'wb-context-scan.zsh" aggregate' "$JOIN" | head -1 | cut -d: -f1)
join_gph_ln=$(grep -n 'graphify-repos.sh' "$JOIN" | head -1 | cut -d: -f1)
if [[ -z "$join_agg_ln" || -z "$join_gph_ln" ]]; then
  print -u2 "FAIL: join.prompt.md ordering check could not find anchor lines"
  exit 1
fi
(( join_agg_ln < join_gph_ln )) || { print -u2 "FAIL: join.prompt.md — graphify must come AFTER aggregate"; exit 1 }
print "PASS: join.prompt.md graphify step follows aggregate"

print ""
print "All graphify-prompt-wiring tests passed."
