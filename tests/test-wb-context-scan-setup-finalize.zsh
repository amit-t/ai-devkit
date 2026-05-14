#!/usr/bin/env zsh
# test-wb-context-scan-setup-finalize.zsh —
#   setup creates a sandbox worktree; finalize harvests scan output into
#   context/<name>/ with the locked frontmatter schema.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
LIB="${REPO_ROOT}/lib/wb-context-scan.zsh"
MOCK="${REPO_ROOT}/tests/fixtures/mock-scan-output"

[[ -f "$LIB" ]]            || { print -u2 -r -- "FAIL: $LIB missing"; exit 1; }
[[ -d "$MOCK" ]]           || { print -u2 -r -- "FAIL: mock-scan-output fixture missing"; exit 1; }
[[ -f "$MOCK/CONTEXT.md" ]]|| { print -u2 -r -- "FAIL: mock CONTEXT.md missing"; exit 1; }
[[ -f "$MOCK/docs/adr/0001-test.md" ]] || { print -u2 -r -- "FAIL: mock ADR missing"; exit 1; }

scratch="$(mktemp -d -t wbctxscan-sf.XXXXXX)"
WB="$scratch/wb"
trap '
  # cleanup: tear down any straggling worktrees before nuking the dir,
  # else "git worktree add" in subsequent test runs hits stale registry.
  if [[ -d "$WB/repos/foo/.git" || -f "$WB/repos/foo/.git" ]]; then
    git -C "$WB/repos/foo" worktree remove --force "$WB/.context-scan/foo" 2>/dev/null || true
    git -C "$WB/repos/foo" worktree prune 2>/dev/null || true
  fi
  rm -rf "$scratch"
' EXIT

# ── build fake wb ──────────────────────────────────────────────────────
mkdir -p "$WB/repos/foo" "$WB/scripts" "$WB/context"
: > "$WB/.gitignore"

cat > "$WB/project.conf" <<'CONF'
WORKBENCH_LABEL="test"
REPOS=(
  "name=foo;url=https://github.com/example/foo;role=service;stack=go;added_by=test"
)
CONF

# build a tiny git repo at repos/foo with one commit AND a pre-existing
# CONTEXT.md so we can verify pre-wipe in the worktree.
(
  cd "$WB/repos/foo"
  git init -q
  git config user.email "t@t"
  git config user.name "test"
  print -r -- "package main" > main.go
  print -r -- "# foo (old)"  > CONTEXT.md
  mkdir -p docs/adr
  print -r -- "# old adr" > docs/adr/0000-old.md
  git add -A
  git commit -qm "init"
)

# ── setup ──────────────────────────────────────────────────────────────
out="$(zsh "$LIB" setup "$WB" foo)"
print -r -- "$out" | grep -q '^SCAN_DIR=' || {
  print -u2 -r -- "FAIL: setup did not print SCAN_DIR=..."
  print -u2 -r -- "got: $out"
  exit 1
}
SCAN_DIR="${out#SCAN_DIR=}"

# assert: scan_dir exists, is a worktree, pre-wipe happened
[[ -d "$SCAN_DIR" ]] || { print -u2 -r -- "FAIL: SCAN_DIR not created: $SCAN_DIR"; exit 1; }
[[ -f "$SCAN_DIR/.git" ]] || { print -u2 -r -- "FAIL: SCAN_DIR is not a git worktree (no .git pointer)"; exit 1; }
[[ -f "$SCAN_DIR/main.go" ]] || { print -u2 -r -- "FAIL: worktree missing main.go from source repo"; exit 1; }
[[ ! -f "$SCAN_DIR/CONTEXT.md" ]] || { print -u2 -r -- "FAIL: worktree's CONTEXT.md not pre-wiped"; exit 1; }
[[ ! -d "$SCAN_DIR/docs/adr" ]] || { print -u2 -r -- "FAIL: worktree's docs/adr not pre-wiped"; exit 1; }
print -r -- "PASS: setup creates worktree and pre-wipes prior scan output"

# assert: lock present (mkdir-dir form — flock branch was dropped because
# fd-based flock doesn't survive the setup→finalize process boundary).
LOCK="$WB/.context-scan/.lock"
[[ -d "$LOCK" ]] || { print -u2 -r -- "FAIL: lock dir missing at $LOCK"; exit 1; }
print -r -- "PASS: setup acquired the per-WB lock"

# source repo HEAD captured for later assertion
expected_sha="$(git -C "$WB/repos/foo" rev-parse HEAD)"

# ── simulate skill output: copy mock scan output into SCAN_DIR ─────────
cp -R "$MOCK/." "$SCAN_DIR/"

# ── finalize ───────────────────────────────────────────────────────────
zsh "$LIB" finalize "$WB" foo >/dev/null

ctx="$WB/context/foo/CONTEXT.md"
[[ -f "$ctx" ]] || { print -u2 -r -- "FAIL: context/foo/CONTEXT.md not produced"; exit 1; }

# ── assert frontmatter shape ────────────────────────────────────────────
head -n 1 "$ctx" | grep -q '^---$' || { print -u2 -r -- "FAIL: harvested CONTEXT.md missing opening ---"; exit 1; }

# Pull individual fields. Frontmatter style: "key:  value" (multiple spaces).
get_field() {
  awk -v k="$1" '
    NR==1 && $0=="---" { in_block=1; next }
    in_block && $0=="---" { exit }
    in_block && $0 ~ "^"k":" {
      sub("^"k":[[:space:]]+", "", $0)
      print $0
      exit
    }
  ' "$ctx"
}

want_pairs=(
  "generated_by=ai-devkit/repo-context-scan"
  "source_repo=foo"
  "source_url=https://github.com/example/foo"
  "status=scanned"
)
for pair in "${want_pairs[@]}"; do
  k="${pair%%=*}"
  expected="${pair#*=}"
  got="$(get_field "$k")"
  [[ "$got" == "$expected" ]] || {
    print -u2 -r -- "FAIL: frontmatter $k: expected '$expected', got '$got'"
    print -u2 -r -- "--- frontmatter dump ---"
    head -n 20 "$ctx" >&2
    exit 1
  }
done

got_commit="$(get_field source_commit)"
[[ "$got_commit" == "$expected_sha" ]] || {
  print -u2 -r -- "FAIL: source_commit expected $expected_sha got $got_commit"
  exit 1
}

got_devkit="$(get_field devkit_version)"
[[ -n "$got_devkit" ]] || { print -u2 -r -- "FAIL: devkit_version blank"; exit 1; }

got_skill="$(get_field skill_version)"
# repo-context-scan/.upstream pin lives at ${DEVKIT_DIR}/skills/...; the lib
# resolves DEVKIT_DIR to ${LIB:h:h} (repo root) by default. If the pin
# exists we expect 12 chars; if not, blank is OK.
if [[ -f "$REPO_ROOT/skills/repo-context-scan/.upstream" ]]; then
  [[ ${#got_skill} -eq 12 ]] || {
    print -u2 -r -- "FAIL: skill_version expected 12 chars, got '$got_skill' (len ${#got_skill})"
    exit 1
  }
fi

got_generated_at="$(get_field generated_at)"
print -r -- "$got_generated_at" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || {
  print -u2 -r -- "FAIL: generated_at not ISO-8601 Z: '$got_generated_at'"
  exit 1
}
print -r -- "PASS: harvested CONTEXT.md has correct success-path frontmatter"

# ── body preserved untouched ────────────────────────────────────────────
# Body starts after the second --- at line 11+. The mock body contains
# "Domain concepts" — verify it survived.
grep -q 'Domain concepts' "$ctx" || { print -u2 -r -- "FAIL: body missing 'Domain concepts'"; exit 1; }
grep -q 'Payment'         "$ctx" || { print -u2 -r -- "FAIL: body missing 'Payment'"; exit 1; }
print -r -- "PASS: body preserved through harvest"

# ── ADR copied ──────────────────────────────────────────────────────────
adr="$WB/context/foo/docs/adr/0001-test.md"
[[ -f "$adr" ]] || { print -u2 -r -- "FAIL: ADR not copied to $adr"; exit 1; }
grep -q 'Test ADR' "$adr" || { print -u2 -r -- "FAIL: ADR content corrupted"; exit 1; }
print -r -- "PASS: docs/adr harvested"

# ── worktree torn down ─────────────────────────────────────────────────
[[ ! -e "$SCAN_DIR" ]] || { print -u2 -r -- "FAIL: SCAN_DIR not removed after finalize"; exit 1; }

# Lock released
if (( $+commands[flock] )); then
  [[ ! -f "$LOCK" ]] || { print -u2 -r -- "FAIL: flock lock not cleaned up"; exit 1; }
else
  [[ ! -d "$LOCK" ]] || { print -u2 -r -- "FAIL: mkdir lock not cleaned up"; exit 1; }
fi
print -r -- "PASS: worktree removed and lock released"

# ── defensive-merge path: re-scan over existing frontmatter ────────────
# This exercises _prepend_frontmatter's merge branch. After the FIRST harvest
# (above), the file already has frontmatter — re-running setup+finalize
# must:
#   - overwrite devkit-owned keys with fresh values (e.g. generated_at)
#   - preserve user-authored keys that the library doesn't own
#
# Inject a fake user key into the existing harvested file, then re-scan.
# Note: insert the user key BEFORE the closing --- of the frontmatter.
tmp_inject="$(mktemp)"
awk '
  /^---$/ {
    seen++
    if (seen==2) {
      print "owner:          alice"
      print
      next
    }
  }
  { print }
' "$ctx" > "$tmp_inject"
mv "$tmp_inject" "$ctx"

# Capture original generated_at so we can verify it changes.
first_generated_at="$(get_field generated_at)"

# Sleep 1s so the new generated_at definitely differs (second resolution).
sleep 1

zsh "$LIB" setup    "$WB" foo >/dev/null
cp -R "$MOCK/." "$SCAN_DIR/"
zsh "$LIB" finalize "$WB" foo >/dev/null

# devkit-owned key was overwritten?
new_generated_at="$(get_field generated_at)"
[[ "$new_generated_at" != "$first_generated_at" ]] || {
  print -u2 -r -- "FAIL: re-scan did not refresh generated_at"
  print -u2 -r -- "first: $first_generated_at  new: $new_generated_at"
  exit 1
}

# user-authored key preserved?
got_owner="$(get_field owner)"
[[ "$got_owner" == "alice" ]] || {
  print -u2 -r -- "FAIL: defensive merge dropped user-authored 'owner' key (got '$got_owner')"
  print -u2 -r -- "--- frontmatter dump ---"
  head -n 25 "$ctx" >&2
  exit 1
}
print -r -- "PASS: re-scan refreshes devkit-owned keys and preserves user keys"

print -r -- "All setup/finalize tests passed."
