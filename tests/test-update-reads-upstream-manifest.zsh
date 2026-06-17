#!/usr/bin/env zsh
# Regression test: update.zsh must read template_owned from the UPSTREAM
# manifest, not the stamped wb's stale local copy.
#
# Bug: a stamped wb carries a snapshot of .workbench-manifest.json from when it
# was created. update.zsh read that local copy to decide which paths to pull, so
# any path newly added to template_owned upstream (e.g. webui/**) was always one
# upgrade behind — the run that pulled the new manifest did not act on its new
# entries. Existing wbs therefore never received the new directory on a single
# upgrade.
#
# Fix: read template_owned from `git show upstream/main:.workbench-manifest.json`
# (falling back to the local file only when the upstream blob is unavailable).
#
# This test sets up an upstream whose manifest lists a path the stale local
# manifest omits, then asserts --dry-run surfaces that path in the diff stage.

set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

# ── Upstream commit 1: version.json + manifest v1 (no newfile.txt yet) ──────
template_bare="$scratch/template.git"
git init --bare -q "$template_bare"
git -C "$template_bare" symbolic-ref HEAD refs/heads/main

work="$scratch/work"
git -C "$scratch" init -q -b main work
printf '{"version":"1.0.0"}\n' > "$work/version.json"
cat > "$work/.workbench-manifest.json" <<'JSON'
{
  "version": 1,
  "template_owned": ["version.json"]
}
JSON
git -C "$work" -c user.email=t@t -c user.name=t add -A
git -C "$work" -c user.email=t@t -c user.name=t commit -q -m "upstream v1"
git -C "$work" push -q --mirror "$template_bare"
git -C "$template_bare" symbolic-ref HEAD refs/heads/main

# ── Stamp the wb NOW, so it predates newfile.txt and carries manifest v1 ────
stamped="$scratch/stamped"
git clone -q "$template_bare" "$stamped"
git -C "$stamped" remote rename origin upstream
cat > "$stamped/project.conf" <<EOF2
WORKBENCH_TEMPLATE_UPSTREAM="${template_bare%.git}"
EOF2
git -C "$stamped" -c user.email=t@t -c user.name=t add -A
git -C "$stamped" -c user.email=t@t -c user.name=t commit -q -m "add project.conf"

# ── Upstream commit 2: add newfile.txt and promote it to template_owned ─────
# The stamped wb above never saw this commit; its local manifest still omits
# newfile.txt. A correct update.zsh reads the manifest from upstream/main and
# therefore still pulls newfile.txt on the very first upgrade.
printf 'upstream content\n' > "$work/newfile.txt"
cat > "$work/.workbench-manifest.json" <<'JSON'
{
  "version": 2,
  "template_owned": ["version.json", "newfile.txt"]
}
JSON
git -C "$work" -c user.email=t@t -c user.name=t add -A
git -C "$work" -c user.email=t@t -c user.name=t commit -q -m "upstream v2: add newfile.txt"
git -C "$work" push -q --mirror "$template_bare"
git -C "$template_bare" symbolic-ref HEAD refs/heads/main

cd "$stamped"
output="$("${REPO_ROOT}/update-workbench/update.zsh" --dry-run 2>&1)" || true

if ! grep -q "Changes that would be pulled" <<< "$output"; then
  print -r -- "FAIL: --dry-run did not reach the diff stage"
  print -r -- "----- update.zsh output -----"
  print -r -- "$output"
  exit 1
fi

if ! grep -q "newfile.txt" <<< "$output"; then
  print -r -- "FAIL: newfile.txt (upstream-only template_owned path) not pulled —"
  print -r -- "      update.zsh read the stale LOCAL manifest instead of upstream."
  print -r -- "----- update.zsh output -----"
  print -r -- "$output"
  exit 1
fi

print -r -- "PASS: update.zsh reads template_owned from the upstream manifest"
