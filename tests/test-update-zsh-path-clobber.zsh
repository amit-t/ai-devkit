#!/usr/bin/env zsh
# Regression test for update.zsh clobbering $PATH via zsh's special $path array.
#
# zsh exposes a lowercase tied array `path` that mirrors `$PATH`. update.zsh
# previously used `path` as the loop variable in `while IFS= read -r path`,
# which destroyed PATH on the first iteration. Every subsequent `git diff`
# inside the loop hit "command not found" (exit 127), making the script
# falsely flag every template-owned path as dirty and bailing out with
# "Uncommitted changes on template-owned paths".
#
# Fix: rename loop variable from `path` to `tpl_path` in all three while
# loops in update.zsh.
#
# This test drives a clean stamped wb through `update.zsh --dry-run` and
# asserts that the dirty-check passes (no "Uncommitted changes" line) and
# the dry-run reaches the diff stage.

set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

template_bare="$scratch/template.git"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$template_bare" "1.0.0"

stamped="$scratch/stamped"
git clone -q "$template_bare" "$stamped"
git -C "$stamped" -c user.email=t@t -c user.name=t commit --allow-empty -q -m "init"
git -C "$stamped" remote rename origin upstream

# Manifest: version.json is the only template-owned path. Clean by construction.
cat > "$stamped/.workbench-manifest.json" <<'JSON'
{
  "version": 1,
  "template_owned": ["version.json"]
}
JSON

# project.conf — WORKBENCH_TEMPLATE_UPSTREAM is required; strip trailing .git
# because update.zsh appends .git when it creates the upstream remote, and
# the remote is already present here so the URL value is informational only.
cat > "$stamped/project.conf" <<EOF
WORKBENCH_TEMPLATE_UPSTREAM="${template_bare%.git}"
EOF

cd "$stamped"
output="$("${REPO_ROOT}/update-workbench/update.zsh" --dry-run 2>&1)" || true

if grep -q "Uncommitted changes on template-owned paths" <<< "$output"; then
  print -r -- "FAIL: false dirty report — PATH was clobbered by \$path loop variable"
  print -r -- "----- update.zsh output -----"
  print -r -- "$output"
  exit 1
fi

if ! grep -q "Changes that would be pulled" <<< "$output"; then
  print -r -- "FAIL: --dry-run did not reach the diff stage"
  print -r -- "----- update.zsh output -----"
  print -r -- "$output"
  exit 1
fi

print -r -- "PASS: update.zsh --dry-run on a clean stamped wb does not falsely flag paths as dirty"
