#!/usr/bin/env bash
# Regression guard for docs/ owner-aware links.
#
# The Jekyll site under docs/ resolves owner-specific URLs at build time using
# _data/orgs.yml + _includes/links.html, keyed off site.github.owner_name.
# This script fails CI if any author re-introduces a hardcoded owner URL into
# pages or layouts, which would make the published site link to the wrong fork
# (amit-t vs Invenco-Cloud-Systems-ICS).
#
# Allowed locations for hardcoded owner URLs:
#   - docs/_data/orgs.yml      (source of truth)
#   - docs/_includes/links.html (default-owner fallback)
#   - docs/_config.yml         (fallback_owner)
#
# Anywhere else under docs/ must use {{ links.* }} from _includes/links.html.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

scan_globs=(
  'docs/*.md'
  'docs/_layouts/*.html'
  'docs/_includes/*.html'
)

# Owners whose URLs must not be hardcoded outside the allowlist.
owners_pattern='(amit-t|Invenco-Cloud-Systems-ICS)'

# URL shapes we treat as hardcoded:
#   https://github.com/<owner>/...
#   https://<owner>.github.io/...
url_pattern="https?://(github\\.com/${owners_pattern}/|${owners_pattern}\\.github\\.io/)"

allow_paths=(
  'docs/_data/orgs.yml'
  'docs/_includes/links.html'
  'docs/_config.yml'
)

violations=()

# shellcheck disable=SC2068
for glob in ${scan_globs[@]}; do
  for f in $glob; do
    [ -f "$f" ] || continue
    skip=0
    for allowed in "${allow_paths[@]}"; do
      [ "$f" = "$allowed" ] && skip=1 && break
    done
    [ $skip -eq 1 ] && continue
    if grep -nE "$url_pattern" "$f" >/dev/null 2>&1; then
      while IFS= read -r line; do
        violations+=("$f:$line")
      done < <(grep -nE "$url_pattern" "$f")
    fi
  done
done

if [ ${#violations[@]} -gt 0 ]; then
  echo "ERROR: hardcoded owner URLs found in docs/." >&2
  echo "Use {{ links.* }} from _includes/links.html instead." >&2
  echo "Update _data/orgs.yml if a new key is needed." >&2
  echo >&2
  printf '  %s\n' "${violations[@]}" >&2
  exit 1
fi

echo "docs/ link audit: OK (no hardcoded owner URLs outside _data/_includes/_config)."
