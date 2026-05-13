#!/usr/bin/env zsh
# test-sync-skill.zsh — Hermetic test for scripts/sync-skill.zsh.
#
# Run: zsh tests/test-sync-skill.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SYNC="${REPO_ROOT}/scripts/sync-skill.zsh"

[[ -f "$SYNC" ]] || { print -u2 -r -- "FAIL: $SYNC not found"; exit 1; }

scratch="$(mktemp -d -t syncskill-test.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT

fake_at_skills="$scratch/at-skills"
fake_devkit="$scratch/ai-devkit"

mkdir -p "$fake_at_skills/repo-context-scan"
print -r -- "# SKILL" > "$fake_at_skills/repo-context-scan/SKILL.md"
print -r -- "# README" > "$fake_at_skills/repo-context-scan/README.md"
print -r -- "# CTX" > "$fake_at_skills/repo-context-scan/CONTEXT-FORMAT.md"

git -C "$fake_at_skills" init -q
git -C "$fake_at_skills" -c user.email=t@t -c user.name=test add -A
git -C "$fake_at_skills" -c user.email=t@t -c user.name=test commit -q -m "init"
git -C "$fake_at_skills" remote add origin https://example.com/fake/skills.git

mkdir -p "$fake_devkit"

# Test 1: first sync seeds files + writes .upstream with correct SHA.
AT_SKILLS_DIR="$fake_at_skills" DEVKIT_DIR="$fake_devkit" \
  zsh "$SYNC" repo-context-scan >/dev/null

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
[[ "$got_repo" == "https://example.com/fake/skills.git" ]] || {
  print -u2 -r -- "FAIL: .upstream repo mismatch (got $got_repo)"
  exit 1
}
print -r -- "PASS: first sync vendors files and pins upstream sha"

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

print -r -- "All sync-skill tests passed."
