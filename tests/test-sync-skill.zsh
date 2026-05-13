#!/usr/bin/env zsh
# test-sync-skill.zsh — Hermetic test for scripts/sync-skill.zsh.
#
# Run: zsh tests/test-sync-skill.zsh

set -euo pipefail

print -u2 -r -- "DEBUG: test-sync-skill starting (zsh=$ZSH_VERSION host=$(uname -s))"

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SYNC="${REPO_ROOT}/scripts/sync-skill.zsh"
print -u2 -r -- "DEBUG: SCRIPT_DIR=$SCRIPT_DIR REPO_ROOT=$REPO_ROOT SYNC=$SYNC"

[[ -f "$SYNC" ]] || { print -u2 -r -- "FAIL: $SYNC not found"; exit 1; }

# Portable mktemp (avoid -t flag — GNU vs BSD disagree on semantics).
scratch="$(mktemp -d "${TMPDIR:-/tmp}/syncskill-test.XXXXXX")" \
  || { print -u2 -r -- "FAIL: mktemp failed: $scratch"; exit 1; }
print -u2 -r -- "DEBUG: scratch=$scratch"
trap 'rm -rf "$scratch"' EXIT

fake_at_skills="$scratch/at-skills"
fake_devkit="$scratch/ai-devkit"

mkdir -p "$fake_at_skills/repo-context-scan"
print -r -- "# SKILL" > "$fake_at_skills/repo-context-scan/SKILL.md"
print -r -- "# README" > "$fake_at_skills/repo-context-scan/README.md"
print -r -- "# CTX" > "$fake_at_skills/repo-context-scan/CONTEXT-FORMAT.md"
print -u2 -r -- "DEBUG: fixtures laid down"

# Isolate from any host-side git config (CI runners ship with safe.directory
# defaults and PR-extraheader that can break in-place git operations on
# tempdir repos).
export GIT_CONFIG_GLOBAL="$scratch/.gitconfig-empty"
export GIT_CONFIG_SYSTEM=/dev/null
: > "$GIT_CONFIG_GLOBAL"

print -u2 -r -- "DEBUG: about to git init (git version: $(git --version))"
git -C "$fake_at_skills" init -q
print -u2 -r -- "DEBUG: git init done"
git -C "$fake_at_skills" -c user.email=t@t -c user.name=test add -A
print -u2 -r -- "DEBUG: git add done"
git -C "$fake_at_skills" -c user.email=t@t -c user.name=test commit -q -m "init"
print -u2 -r -- "DEBUG: git commit done"
# Use SSH host-alias form to exercise upstream_repo normalization (Q14 schema).
git -C "$fake_at_skills" remote add origin git@github.com-at:foo/bar.git
print -u2 -r -- "DEBUG: git remote add done"

mkdir -p "$fake_devkit"
print -u2 -r -- "DEBUG: about to invoke first sync"

# Capture sync-skill stdout+stderr+exit so failures surface in CI logs
# instead of silently aborting the test under set -e.
set +e
sync_out="$(AT_SKILLS_DIR="$fake_at_skills" DEVKIT_DIR="$fake_devkit" zsh "$SYNC" repo-context-scan 2>&1)"
sync_rc=$?
set -e
if (( sync_rc != 0 )); then
  print -u2 -r -- "FAIL: first sync exited rc=$sync_rc"
  print -u2 -r -- "----- sync output -----"
  print -u2 -r -- "$sync_out"
  print -u2 -r -- "----- end sync output -----"
  exit 1
fi
print -u2 -r -- "DEBUG: first sync rc=0"

# Test 1: first sync seeds files + writes .upstream with correct SHA + normalizes SSH host-alias to HTTPS.
# (Already invoked above with stderr capture for early-fail diagnostics.)
vendored="$fake_devkit/skills/repo-context-scan"
[[ -f "$vendored/SKILL.md" ]]          || { print -u2 -r -- "FAIL: SKILL.md missing after sync"; exit 1; }
[[ -f "$vendored/README.md" ]]         || { print -u2 -r -- "FAIL: README.md missing after sync"; exit 1; }
[[ -f "$vendored/CONTEXT-FORMAT.md" ]] || { print -u2 -r -- "FAIL: CONTEXT-FORMAT.md missing after sync"; exit 1; }
[[ -f "$vendored/.upstream" ]]         || { print -u2 -r -- "FAIL: .upstream missing after sync"; exit 1; }
[[ ! -d "$vendored/.git" ]]            || { print -u2 -r -- "FAIL: .git leaked into vendored copy"; exit 1; }

expected_sha="$(git -C "$fake_at_skills" rev-parse HEAD)"
got_sha="$(grep '^upstream_sha:' "$vendored/.upstream" | awk '{print $2}')"
[[ "$got_sha" == "$expected_sha" ]] || {
  print -u2 -r -- "FAIL: .upstream sha mismatch (got $got_sha, want $expected_sha)"
  exit 1
}

got_repo="$(grep '^upstream_repo:' "$vendored/.upstream" | awk '{print $2}')"
[[ "$got_repo" == "https://github.com/foo/bar" ]] || {
  print -u2 -r -- "FAIL: .upstream repo not normalized to canonical HTTPS (got $got_repo, want https://github.com/foo/bar)"
  exit 1
}
print -r -- "PASS: first sync vendors files, pins upstream sha, normalizes git@ host-alias to HTTPS"

# Test 2: rsync --delete removes files dropped upstream.
rm "$fake_at_skills/repo-context-scan/CONTEXT-FORMAT.md"
print -r -- "# new" > "$fake_at_skills/repo-context-scan/NEW.md"
git -C "$fake_at_skills" -c user.email=t@t -c user.name=test add -A
git -C "$fake_at_skills" -c user.email=t@t -c user.name=test commit -q -m "drop CONTEXT-FORMAT, add NEW"

AT_SKILLS_DIR="$fake_at_skills" DEVKIT_DIR="$fake_devkit" \
  zsh "$SYNC" repo-context-scan >/dev/null

[[ ! -f "$vendored/CONTEXT-FORMAT.md" ]] || { print -u2 -r -- "FAIL: CONTEXT-FORMAT.md should be gone after re-sync"; exit 1; }
[[ -f "$vendored/NEW.md" ]]              || { print -u2 -r -- "FAIL: NEW.md missing after re-sync"; exit 1; }

expected_sha2="$(git -C "$fake_at_skills" rev-parse HEAD)"
got_sha2="$(grep '^upstream_sha:' "$vendored/.upstream" | awk '{print $2}')"
[[ "$got_sha2" == "$expected_sha2" ]] || {
  print -u2 -r -- "FAIL: .upstream sha not updated after re-sync"
  exit 1
}
print -r -- "PASS: re-sync deletes removed files and updates pin"

# Test 3: idempotent — body files unchanged on repeat sync with no upstream change.
body_before="$(find "$vendored" -type f ! -name '.upstream' | sort | xargs shasum)"
AT_SKILLS_DIR="$fake_at_skills" DEVKIT_DIR="$fake_devkit" \
  zsh "$SYNC" repo-context-scan >/dev/null
body_after="$(find "$vendored" -type f ! -name '.upstream' | sort | xargs shasum)"
[[ "$body_before" == "$body_after" ]] || { print -u2 -r -- "FAIL: body files changed across idempotent sync"; exit 1; }
print -r -- "PASS: repeat sync is idempotent for body files"

# Test 4: AT_SKILLS_DIR missing fails loud with clone instructions.
set +e
out="$(AT_SKILLS_DIR="$scratch/no-such-dir" DEVKIT_DIR="$fake_devkit" zsh "$SYNC" repo-context-scan 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || { print -u2 -r -- "FAIL: missing AT_SKILLS_DIR should exit non-zero"; exit 1; }
print -r -- "$out" | grep -q "AT_SKILLS_DIR not found" || {
  print -u2 -r -- "FAIL: missing AT_SKILLS_DIR error message not present"
  print -u2 -r -- "$out"
  exit 1
}
print -r -- "$out" | grep -q "git clone" || {
  print -u2 -r -- "FAIL: missing AT_SKILLS_DIR should hint at clone command"
  exit 1
}
print -r -- "PASS: missing AT_SKILLS_DIR fails loud with clone hint"

# Test 5: upstream_repo normalization covers ssh:// and HTTPS-with-.git forms.
# (Test 1 already covered the git@github.com-alias:owner/repo.git form.)

# 5a: ssh://git@github.com/owner/repo form -> https://github.com/owner/repo
git -C "$fake_at_skills" remote set-url origin "ssh://git@github.com/baz/qux"
AT_SKILLS_DIR="$fake_at_skills" DEVKIT_DIR="$fake_devkit" \
  zsh "$SYNC" repo-context-scan >/dev/null
got_repo_ssh="$(grep '^upstream_repo:' "$vendored/.upstream" | awk '{print $2}')"
[[ "$got_repo_ssh" == "https://github.com/baz/qux" ]] || {
  print -u2 -r -- "FAIL: ssh:// form not normalized (got $got_repo_ssh, want https://github.com/baz/qux)"
  exit 1
}

# 5b: https://github.com/owner/repo.git -> https://github.com/owner/repo (strip .git)
git -C "$fake_at_skills" remote set-url origin "https://github.com/alpha/beta.git"
AT_SKILLS_DIR="$fake_at_skills" DEVKIT_DIR="$fake_devkit" \
  zsh "$SYNC" repo-context-scan >/dev/null
got_repo_https="$(grep '^upstream_repo:' "$vendored/.upstream" | awk '{print $2}')"
[[ "$got_repo_https" == "https://github.com/alpha/beta" ]] || {
  print -u2 -r -- "FAIL: https .git suffix not stripped (got $got_repo_https, want https://github.com/alpha/beta)"
  exit 1
}
print -r -- "PASS: upstream_repo normalization handles ssh:// and https-with-.git forms"

# Test 6: empty git user.name falls back to $USER (not blank synced_by).
git -C "$fake_at_skills" remote set-url origin "https://github.com/foo/bar"
empty_name_home="$scratch/home-empty"
mkdir -p "$empty_name_home"
cat > "$empty_name_home/.gitconfig" <<'GITCFG'
[user]
	name =
	email = t@t
GITCFG
(
  cd "$empty_name_home"
  HOME="$empty_name_home" USER=testuser \
    GIT_CONFIG_GLOBAL="$empty_name_home/.gitconfig" \
    GIT_CONFIG_SYSTEM=/dev/null \
    AT_SKILLS_DIR="$fake_at_skills" DEVKIT_DIR="$fake_devkit" \
    zsh "$SYNC" repo-context-scan >/dev/null
)
got_by="$(grep '^synced_by:' "$vendored/.upstream" | awk '{print $2}')"
[[ -n "$got_by" && "$got_by" == "testuser" ]] || {
  print -u2 -r -- "FAIL: empty git user.name should fall back to \$USER (got '$got_by', want 'testuser')"
  exit 1
}
print -r -- "PASS: empty git user.name falls back to \$USER"

# Test 7: at-skills with no commits fails loud, doesn't write bogus .upstream.
no_commit_at="$scratch/at-skills-empty"
mkdir -p "$no_commit_at/repo-context-scan"
print -r -- "# x" > "$no_commit_at/repo-context-scan/SKILL.md"
git -C "$no_commit_at" init -q
git -C "$no_commit_at" remote add origin "https://github.com/foo/bar"
empty_devkit="$scratch/ai-devkit-empty"
mkdir -p "$empty_devkit"
set +e
out2="$(AT_SKILLS_DIR="$no_commit_at" DEVKIT_DIR="$empty_devkit" zsh "$SYNC" repo-context-scan 2>&1)"
rc2=$?
set -e
[[ $rc2 -ne 0 ]] || { print -u2 -r -- "FAIL: rev-parse HEAD failure should exit non-zero"; exit 1; }
print -r -- "$out2" | grep -q "Cannot read HEAD" || {
  print -u2 -r -- "FAIL: missing HEAD error message not present"
  print -u2 -r -- "$out2"
  exit 1
}
[[ ! -f "$empty_devkit/skills/repo-context-scan/.upstream" ]] || {
  print -u2 -r -- "FAIL: .upstream should not be written when HEAD missing"
  exit 1
}
print -r -- "PASS: empty at-skills HEAD fails loud, no bogus .upstream written"

print -r -- "All sync-skill tests passed."
