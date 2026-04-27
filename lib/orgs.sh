#!/usr/bin/env bash
# orgs.sh — Shared library for managing the devkit org list.
#
# Sources:
#   1. orgs.conf  (user-editable, one slug per line, `#` comments OK)
#   2. auto-detected org from devkit repo's origin remote (always included)
#
# Functions:
#   devkit_orgs_file          — prints path to orgs.conf
#   devkit_auto_org           — prints auto-detected org from devkit's origin
#   devkit_orgs_list          — prints union (configured + auto), deduped,
#                               file order preserved, auto appended if missing
#   devkit_orgs_add <slug>    — append slug to orgs.conf if not already present
#   devkit_orgs_remove <slug> — strip slug from orgs.conf
#   devkit_orgs_show          — prints numbered menu (what init/join use)

# Resolve devkit root from this file's location: lib/orgs.sh → repo root
__DEVKIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEVKIT_ROOT="$(dirname "$__DEVKIT_LIB_DIR")"

devkit_orgs_file() {
  printf '%s\n' "${DEVKIT_ROOT}/orgs.conf"
}

devkit_auto_org() {
  local url
  url="$(git -C "$DEVKIT_ROOT" remote get-url origin 2>/dev/null || true)"
  [[ -z "$url" ]] && return 0

  # Strip protocol/host, trailing .git, then take first path segment.
  # Handles: https://github.com/ORG/repo(.git), git@github.com:ORG/repo(.git),
  # git@custom-host:ORG/repo.git
  local path="${url#*://*/}"
  path="${path#*:}"
  path="${path%.git}"
  printf '%s\n' "${path%%/*}"
}

devkit_orgs_list() {
  local file auto line seen=""
  file="$(devkit_orgs_file)"
  auto="$(devkit_auto_org)"

  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"                 # strip comments
      line="${line#"${line%%[![:space:]]*}"}"  # ltrim
      line="${line%"${line##*[![:space:]]}"}"  # rtrim
      [[ -z "$line" ]] && continue
      case ":$seen:" in *":$line:"*) continue ;; esac
      seen="$seen:$line"
      printf '%s\n' "$line"
    done < "$file"
  fi

  if [[ -n "$auto" ]]; then
    case ":$seen:" in *":$auto:"*) : ;; *) printf '%s\n' "$auto" ;; esac
  fi
}

devkit_orgs_add() {
  local slug="$1" file
  [[ -z "$slug" ]] && { echo "usage: devkit_orgs_add <slug>" >&2; return 2; }
  file="$(devkit_orgs_file)"
  [[ -f "$file" ]] || : > "$file"

  if devkit_orgs_list | grep -qxF "$slug"; then
    echo "already present: $slug"
    return 0
  fi
  printf '%s\n' "$slug" >> "$file"
  echo "added: $slug"
}

devkit_orgs_remove() {
  local slug="$1" file tmp
  [[ -z "$slug" ]] && { echo "usage: devkit_orgs_remove <slug>" >&2; return 2; }
  file="$(devkit_orgs_file)"
  [[ -f "$file" ]] || { echo "no orgs.conf yet"; return 0; }

  tmp="$(mktemp)"
  awk -v s="$slug" '
    {
      line=$0; sub(/#.*/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
      if (line==s) next
      print
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "removed (if present): $slug"
}

devkit_orgs_show() {
  local i=0 org
  while IFS= read -r org; do
    i=$((i+1))
    printf '  [%d] %s\n' "$i" "$org"
  done < <(devkit_orgs_list)
  i=$((i+1))
  printf '  [%d] Personal (enter GitHub handle)\n' "$i"
}
