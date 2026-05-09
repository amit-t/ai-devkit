#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

# Build a fake template upstream + a fake stamped wb that has 'upstream' remote.
template_bare="$scratch/template.git"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$template_bare" "1.4.0"

stamped="$scratch/stamped"
git clone -q "$template_bare" "$stamped"
git -C "$stamped" remote rename origin upstream
git -C "$stamped" -c init.defaultBranch=main init -q 2>/dev/null || true

mkdir -p "$stamped/.workbench-state"
touch "$stamped/.workbench-manifest.json" "$stamped/project.conf"

# Drive only the stamp logic (we are not running update.zsh end-to-end here).
git -C "$stamped" fetch -q upstream main
git -C "$stamped" show "upstream/main:version.json" \
  | jq '. + {stamped_at: (now|todate)}' \
  > "$stamped/.workbench-state/template-version.json"

[[ -f "$stamped/.workbench-state/template-version.json" ]] || { print -r -- "FAIL: template-version.json not written"; exit 1; }
v="$(jq -r .version "$stamped/.workbench-state/template-version.json")"
[[ "$v" == "1.4.0" ]] || { print -r -- "FAIL: stamped version mismatch (got $v)"; exit 1; }

print -r -- "PASS: update writes template-version.json"
