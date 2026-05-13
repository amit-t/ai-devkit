#!/usr/bin/env zsh
# test-wb-rescan-cli.zsh — Phase 7 integration test.
#
#   Exercises the wb.rescan CLI end-to-end:
#     ${WB_FIXTURE}/scripts/wb-rescan.sh foo-repo
#   with the agent invocation mocked via WB_SCAN_AGENT_CMD. Verifies the
#   wb-rescan.sh wrapper + lib/wb-context-scan.zsh play together:
#     - per-repo setup → mocked agent → finalize → aggregate
#     - context/<repo>/CONTEXT.md produced with correct frontmatter
#     - context/README.md aggregate has the registered row
#     - exactly one self-commit lands under context/ (no push attempted)
#
# Cross-repo wiring:
#   wb-rescan.sh lives in ai-workbench on branch `feat/repo-context-scan`
#   (Phase 5, concurrent PR). This test reads the script via `git show` from
#   the sibling clone at $AI_WORKBENCH_PATH (default:
#   ${HOME}/Projects/Tools-Utilities/ai-workbench). If the clone or branch is
#   not present the test PRINTS A CLEAR SKIP MESSAGE AND EXITS 0 so CI on
#   machines without ai-workbench checked out still passes.
#
# Hermetic: tempdir wb fixture, trap cleanup tears down worktrees so the
# git worktree registry of the inner source repo is not polluted across
# runs. No real network, no real LLM (mock injects canned scan output).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
LIB="${REPO_ROOT}/lib/wb-context-scan.zsh"
MOCK="${REPO_ROOT}/tests/fixtures/mock-scan-output"

# ── locate ai-workbench / wb-rescan.sh ────────────────────────────────────
AI_WORKBENCH_PATH="${AI_WORKBENCH_PATH:-${HOME}/Projects/Tools-Utilities/ai-workbench}"
WB_RESCAN_BRANCH="${WB_RESCAN_BRANCH:-feat/repo-context-scan}"

_skip() {
  print -r -- "SKIP: $*"
  exit 0
}

if [[ ! -d "${AI_WORKBENCH_PATH}/.git" ]]; then
  _skip "ai-workbench clone not found at ${AI_WORKBENCH_PATH} — set AI_WORKBENCH_PATH or clone ai-workbench. wb.rescan CLI integration unverified locally; CI dedicated to ai-workbench will catch regressions."
fi

if ! git -C "$AI_WORKBENCH_PATH" rev-parse --verify "${WB_RESCAN_BRANCH}" >/dev/null 2>&1; then
  _skip "branch ${WB_RESCAN_BRANCH} not present in ${AI_WORKBENCH_PATH}. Fetch it or check out the Phase 5 PR locally to exercise this test."
fi

# Required local fixtures
[[ -f "$LIB"  ]]          || { print -u2 -r -- "FAIL: missing $LIB"; exit 1; }
[[ -d "$MOCK" ]]          || { print -u2 -r -- "FAIL: mock-scan-output fixture missing at $MOCK"; exit 1; }
[[ -f "$MOCK/CONTEXT.md" ]] || { print -u2 -r -- "FAIL: $MOCK/CONTEXT.md missing"; exit 1; }
[[ -f "$MOCK/docs/adr/0001-test.md" ]] || { print -u2 -r -- "FAIL: $MOCK/docs/adr/0001-test.md missing"; exit 1; }

# ── scratch dirs ─────────────────────────────────────────────────────────
scratch="$(mktemp -d -t wb-rescan-cli.XXXXXX)"
WB="${scratch}/wb"
DEVKIT_FAKE="${scratch}/ai-devkit"

trap '
  # Cleanup: tear down any straggling worktree registered in the inner
  # source repo so the registry stays clean across runs. Errors ignored —
  # worktree may already be gone (finalize removes it on success).
  if [[ -d "$WB/repos/foo-repo/.git" || -f "$WB/repos/foo-repo/.git" ]]; then
    git -C "$WB/repos/foo-repo" worktree remove --force "$WB/.context-scan/foo-repo" 2>/dev/null || true
    git -C "$WB/repos/foo-repo" worktree prune 2>/dev/null || true
  fi
  rm -rf "$scratch"
' EXIT

# ── build fake DEVKIT_CLONE (just the bits wb-rescan.sh needs) ───────────
mkdir -p "${DEVKIT_FAKE}/lib"
mkdir -p "${DEVKIT_FAKE}/skills/repo-context-scan"
mkdir -p "${DEVKIT_FAKE}/scripts"

cp "$LIB" "${DEVKIT_FAKE}/lib/wb-context-scan.zsh"

# Copy skill .upstream pin if present so skill_version stamping works
# (success-path frontmatter assertion is robust to either presence/absence).
if [[ -f "${REPO_ROOT}/skills/repo-context-scan/.upstream" ]]; then
  cp "${REPO_ROOT}/skills/repo-context-scan/.upstream" \
     "${DEVKIT_FAKE}/skills/repo-context-scan/.upstream"
fi

# version.json drives devkit_version stamping
if [[ -f "${REPO_ROOT}/version.json" ]]; then
  cp "${REPO_ROOT}/version.json" "${DEVKIT_FAKE}/version.json"
fi

# ── build fake wb tree ───────────────────────────────────────────────────
mkdir -p "$WB/repos/foo-repo" "$WB/scripts" "$WB/context"
: > "$WB/.gitignore"

cat > "$WB/project.conf" <<'CONF'
WORKBENCH_LABEL="test"
REPOS=(
  "name=foo-repo;url=https://github.com/example/foo-repo;role=service;stack=go;added_by=test"
)
CONF

# Minimal manifest so wb tooling that probes for it does not error.
cat > "$WB/.workbench-manifest.json" <<'JSON'
{ "label": "test", "repos": [ { "name": "foo-repo" } ] }
JSON

# Source repo that wb-rescan setup will worktree from
(
  cd "$WB/repos/foo-repo"
  git init -q
  git config user.email "test@example.com"
  git config user.name "wb-rescan-cli-test"
  print -r -- "package main" > main.go
  print -r -- "# foo-repo (placeholder)" > README.md
  git add -A
  git commit -qm "init foo-repo"
)
expected_sha="$(git -C "$WB/repos/foo-repo" rev-parse HEAD)"

# Make the WB itself a git repo so the self-commit step runs (without a
# remote — any push attempt would fail and the test would catch it).
# Silence the embedded-repo advice when staging the inner repos/foo-repo
# checkout; it is noise here.
(
  cd "$WB"
  git init -q
  git config user.email "test@example.com"
  git config user.name "wb-rescan-cli-test"
  git config advice.addEmbeddedRepo false
  git add -A 2>/dev/null
  git commit -qm "init wb fixture"
)
wb_init_sha="$(git -C "$WB" rev-parse HEAD)"

# Defensive: confirm no remote configured — wb-rescan should not attempt
# a push, but if it ever does the test must catch it.
if [[ -n "$(git -C "$WB" remote)" ]]; then
  print -u2 -r -- "FAIL: WB fixture unexpectedly has a remote configured"
  exit 1
fi

# ── vendor wb-rescan.sh from ai-workbench branch ─────────────────────────
WB_RESCAN="${WB}/scripts/wb-rescan.sh"
git -C "$AI_WORKBENCH_PATH" show "${WB_RESCAN_BRANCH}:scripts/wb-rescan.sh" > "$WB_RESCAN"
chmod +x "$WB_RESCAN"
[[ -s "$WB_RESCAN" ]] || { print -u2 -r -- "FAIL: extracted wb-rescan.sh is empty"; exit 1; }

# ── run wb-rescan.sh with mocked agent ───────────────────────────────────
# WB_SCAN_AGENT_CMD is eval'd inside `(cd "$SCAN_DIR" && eval "$cmd")` so
# the path must be absolute (cwd changes to SCAN_DIR before eval).
mock_abs="${MOCK:A}"
WB_SCAN_AGENT_CMD="cp -R '${mock_abs}/.' ."

# Run from inside WB so wb-rescan resolves WB_ROOT via project.conf walk.
# Capture stdout+stderr for diagnostics on failure.
run_log="${scratch}/run.log"
set +e
(
  cd "$WB"
  DEVKIT_CLONE="$DEVKIT_FAKE" \
  WB_SCAN_AGENT_CMD="$WB_SCAN_AGENT_CMD" \
    bash "$WB_RESCAN" foo-repo
) >"$run_log" 2>&1
rc=$?
set -e

if (( rc != 0 )); then
  print -u2 -r -- "FAIL: wb-rescan.sh exited rc=$rc"
  print -u2 -r -- "--- run log ---"
  cat "$run_log" >&2
  exit 1
fi
print -r -- "PASS: wb-rescan.sh exited 0"

# ── assert: context dir + CONTEXT.md produced ────────────────────────────
ctx="${WB}/context/foo-repo/CONTEXT.md"
if [[ ! -f "$ctx" ]]; then
  print -u2 -r -- "FAIL: ${ctx} not produced"
  print -u2 -r -- "--- run log ---"
  cat "$run_log" >&2
  print -u2 -r -- "--- context tree ---"
  find "${WB}/context" >&2 2>/dev/null || true
  exit 1
fi
print -r -- "PASS: context/foo-repo/CONTEXT.md produced"

# ── assert: frontmatter shape (status, source_repo, source_commit) ───────
head -n 1 "$ctx" | grep -q '^---$' || { print -u2 -r -- "FAIL: CONTEXT.md missing opening ---"; exit 1; }

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
  "source_repo=foo-repo"
  "source_url=https://github.com/example/foo-repo"
  "status=scanned"
)
for pair in "${want_pairs[@]}"; do
  k="${pair%%=*}"
  expected="${pair#*=}"
  got="$(get_field "$k")"
  if [[ "$got" != "$expected" ]]; then
    print -u2 -r -- "FAIL: frontmatter $k expected '$expected' got '$got'"
    print -u2 -r -- "--- frontmatter dump ---"
    head -n 20 "$ctx" >&2
    exit 1
  fi
done

got_commit="$(get_field source_commit)"
[[ "$got_commit" == "$expected_sha" ]] || {
  print -u2 -r -- "FAIL: source_commit expected $expected_sha got $got_commit"
  exit 1
}
print -r -- "PASS: frontmatter has status=scanned, source_repo=foo-repo, source_commit matches"

# ── assert: ADR harvested into context dir ───────────────────────────────
adr="${WB}/context/foo-repo/docs/adr/0001-test.md"
[[ -f "$adr" ]] || { print -u2 -r -- "FAIL: ADR not copied to $adr"; exit 1; }
grep -q 'Test ADR' "$adr" || { print -u2 -r -- "FAIL: ADR content corrupted"; exit 1; }
print -r -- "PASS: docs/adr/0001-test.md harvested"

# ── assert: aggregate README has the correct row for foo-repo ───────────
idx="${WB}/context/README.md"
[[ -f "$idx" ]] || { print -u2 -r -- "FAIL: aggregate README not produced"; exit 1; }

# Expected row uses the fixture's first three deduped concepts: Payment,
# Invoice, Refund (CustomerId is the 4th; legend says top-3).
expected_row='| [foo-repo](./foo-repo/CONTEXT.md) | service | scanned | Payment, Invoice, Refund |'
if ! grep -F -q -- "$expected_row" "$idx"; then
  print -u2 -r -- "FAIL: README row for foo-repo not found"
  print -u2 -r -- "expected:"
  print -u2 -r -- "  $expected_row"
  print -u2 -r -- "--- README dump ---"
  cat "$idx" >&2
  exit 1
fi
print -r -- "PASS: aggregate README has correct row for foo-repo"

grep -q '^# Workbench Context Index' "$idx" || { print -u2 -r -- "FAIL: README missing header"; exit 1; }

# ── assert: exactly ONE new commit lands under context/ ──────────────────
commits_after="$(git -C "$WB" rev-list --count HEAD)"
commits_before="$(git -C "$WB" rev-list --count "$wb_init_sha")"
new_commits=$(( commits_after - commits_before ))
if (( new_commits != 1 )); then
  print -u2 -r -- "FAIL: expected exactly 1 new commit, got $new_commits"
  print -u2 -r -- "--- git log ---"
  git -C "$WB" log --oneline >&2
  exit 1
fi

# Subject sanity-check
subject="$(git -C "$WB" log -1 --format=%s)"
case "$subject" in
  "chore: rescan context for"*) ;;
  *) print -u2 -r -- "FAIL: commit subject '$subject' does not start with 'chore: rescan context for'"; exit 1 ;;
esac
print -r -- "PASS: single commit made with subject '$subject'"

# ── assert: commit ONLY touches context/ ─────────────────────────────────
touched="$(git -C "$WB" show --stat --name-only --format= HEAD | sort -u | grep -v '^$' || true)"
non_context="$(print -r -- "$touched" | grep -v '^context/' || true)"
if [[ -n "$non_context" ]]; then
  print -u2 -r -- "FAIL: commit touched paths outside context/:"
  print -u2 -r -- "$non_context"
  exit 1
fi
print -r -- "PASS: commit touched only context/"

# ── assert: no push attempted (no remote → push would error noisily) ─────
# wb-rescan.sh does not call `git push` — it prints a hint. Confirm the
# remote list is still empty and the run log does NOT contain 'git push'
# evidence (the hint string itself contains 'git push', so we look for
# push-error chatter or a refs/remotes update).
if [[ -n "$(git -C "$WB" remote)" ]]; then
  print -u2 -r -- "FAIL: WB unexpectedly grew a remote during run"
  exit 1
fi
if grep -qE "fatal: 'origin' does not appear to be a git repository|error: failed to push" "$run_log"; then
  print -u2 -r -- "FAIL: run log shows wb-rescan tried to push"
  cat "$run_log" >&2
  exit 1
fi
print -r -- "PASS: no push attempted"

print -r -- "All wb-rescan CLI integration tests passed."
