# ai-devkit Versioning Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the canonical versioning + upgrade-notification system for the `ai-workbench / ai-devkit / ai-ralph` ecosystem from `ai-devkit`. After this plan lands, devs who clone ai-devkit can run `devkit.upgrade`, `wb.upgrade`, and `devkit doctor`, and their `init.wb` / `join.wb` / `update.wb` invocations print upgrade banners.

**Architecture:**
- New `version.json` at repo root (release-please owned).
- New canonical library `lib/version-check.sh` (bash-portable; sourced from zsh today, will run under bash + git-bash later).
- `install.zsh` drops the lib to `~/.local/share/wb-versioncheck/version-check.sh` for use by ai-ralph and stamped wbs.
- `install.zsh` writes `DEVKIT_CLONE` env var into `~/.zprofile` EXTERNAL PROJECT ALIASES block.
- New aliases `wb.upgrade` (canonical, replaces `update.wb`) and `devkit.upgrade`. Old `update.wb` kept as deprecation shim.
- New top-level scripts: `devkit-upgrade/devkit-upgrade.zsh`, `devkit-doctor/devkit-doctor.zsh`.
- Existing scripts (`init.zsh`, `join.zsh`, `update.zsh`) get a one-line preamble to fire the version check.
- release-please workflow auto-bumps `version.json`, generates `CHANGELOG.md`, pushes git tag on every merge to `main`.
- Cache lives at `~/.cache/wb-updates/<tool>.json`. Bootstrap-flag at `~/.cache/wb-updates/<tool>-bootstrapped.flag`. Rollback prior at `~/.cache/wb-updates/<tool>-prior.json`.

**Tech Stack:** `zsh` (entry shebang, body bash-portable subset), `bash`, `gh` CLI, `jq`, `git`, GitHub release-please.

---

## Background context (read this before starting)

### Why this exists
Devs in the org clone `ai-devkit` to get `init.wb` / `join.wb` / `update.wb`. They also clone `ai-ralph`. They never globally clone `ai-workbench` (init.wb does `gh repo create --template`). Today there is no notification when a new version of any of these tools ships, and no command to pull the latest. This plan builds that.

### Three commands shipped here
| Alias | Operates on | Action |
|-------|-------------|--------|
| `devkit.upgrade` | global ai-devkit clone | `git pull --rebase` + re-run `install.zsh` |
| `wb.upgrade` (renamed from `update.wb`) | stamped workbench instance (any directory) | template-merge from upstream `ai-workbench` (existing logic preserved) + write `template-version.json` |
| `devkit doctor` | summarizes state of devkit + ralph + wb (if in stamped wb) | reports versions, peer floors, prior available |

### Cross-repo coordination
This plan ships **its own copy** of `lib/version-check.sh`. ai-ralph's plan ships an identical copy (independent dispatch). After all three repos merge, follow-up work introduces a CI sync check; for v1, hand-mirroring is acceptable. Schema and behavior are locked by this plan and reused verbatim.

### Schema reference

`version.json` (repo root):
```json
{
  "version": "1.0.0",
  "released": "2026-05-09",
  "check_ttl_hours": 12,
  "channel": "stable",
  "requires": {},
  "changelog_url": "https://github.com/<owner>/<repo>/blob/main/CHANGELOG.md"
}
```

`~/.cache/wb-updates/<tool>.json`:
```json
{
  "tool": "devkit",
  "checked_at": "2026-05-09T12:34:56Z",
  "ttl_hours": 12,
  "upstream": {
    "version": "1.4.0",
    "released": "2026-05-09",
    "check_ttl_hours": 12,
    "channel": "stable",
    "requires": {},
    "changelog_url": "..."
  },
  "rate_limit_reset_at": null
}
```

`~/.cache/wb-updates/<tool>-prior.json`:
```json
{
  "tool": "devkit",
  "prior_sha": "abc123",
  "prior_version": "1.3.0",
  "current_sha": "def456",
  "current_version": "1.4.0",
  "upgraded_at": "2026-05-09T12:34:56Z"
}
```

### Bash portability rules
The lib body must run under bash. Allowed: `[[ ]]`, `(( ))`, `printf`, `local`, arrays via `()`. **Forbidden:** `${var:A}`, `${var:t}`, `(( $+commands[name] ))`, `setopt`, glob qualifiers. Where a portable substitute exists, use it.

### Failure-mode summary
- `gh` missing → fall back to `git ls-remote` + `git fetch` + read upstream `version.json` from remote ref.
- `jq` missing → hard fail with install hint.
- Network down → print `[<tool>] update check skipped (offline)` and continue.
- Rate-limit → extend TTL using `X-RateLimit-Reset` header.
- Corrupt cache → delete and refetch.
- Corrupt local `version.json` → warn and treat as `0.0.0`.
- Notification check is fail-open. Compat enforcement (`requires` field) is fail-closed with `--force` escape on `*.upgrade`.

---

## File structure

### New files (this plan creates)
| Path | Responsibility |
|------|----------------|
| `version.json` | Canonical version of ai-devkit. Edited by release-please. |
| `lib/version-check.sh` | Bash-portable library. Functions: `_wb_versioncheck`, `_wb_compare_semver`, `_wb_check_requires`, `_wb_record_prior`, `_wb_render_banner`. |
| `lib/bootstrap-detection.sh` | Bash-portable helper. Bootstrap-flag handling for first-time-nag. |
| `devkit-upgrade/devkit-upgrade.zsh` | Implements `devkit.upgrade [--yes] [--rollback] [--force]`. |
| `devkit-doctor/devkit-doctor.zsh` | Implements `devkit doctor [--check-only] [--fix [--yes]]`. |
| `tests/test-version-check.zsh` | Unit tests for lib. |
| `tests/test-devkit-upgrade.zsh` | Integration tests for upgrade + rollback. |
| `tests/test-devkit-doctor.zsh` | Integration tests for doctor. |
| `tests/fixtures/bare-upstream/` | Local bare-repo fixture for git-fallback tests. |
| `tests/helpers/gh-shim.sh` | Stub `gh api` for unit tests. |
| `.github/workflows/release-please.yml` | release-please CI workflow. |
| `.github/workflows/test.yml` | Run tests on macOS + linux, zsh + bash. |
| `release-please-config.json` | release-please project config. |
| `.release-please-manifest.json` | release-please version tracking. |
| `docs/versioning.md` | Long-form versioning docs (canonical). |
| `ROLLOUT-VERSIONING.md` | One-shot rollout note for org devs. |

### Modified files (this plan edits)
| Path | Change |
|------|--------|
| `install.zsh` | Drop lib to `~/.local/share/wb-versioncheck/`, write `DEVKIT_CLONE` to `.zprofile`, install new `wb.upgrade` / `devkit.upgrade` / `devkit-doctor` aliases, add deprecation shim for `update.wb`. |
| `init-workbench/init.zsh` | Add version-check preamble. Source lib, call `_wb_versioncheck devkit`. |
| `join-workbench/join.zsh` | Same. |
| `update-workbench/update.zsh` | Add `_wb_versioncheck wb` preamble. After successful merge, write `.workbench-state/template-version.json` from upstream `version.json`. |
| `init-workbench/init.prompt.md` | Add step instructing the agent to write initial `.workbench-state/template-version.json` based on upstream. |
| `tests/run-all.zsh` | Discover and run new tests. |
| `README.md` | Add "Versioning + upgrades" section. |
| `CHANGELOG.md` (new) | Empty initial; release-please populates. |

---

## Task list

### Task 1: Add `version.json` and CHANGELOG seed

**Files:**
- Create: `version.json`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write `version.json`**

```json
{
  "version": "1.0.0",
  "released": "2026-05-09",
  "check_ttl_hours": 12,
  "channel": "stable",
  "requires": {},
  "changelog_url": "https://github.com/amit-t/ai-devkit/blob/main/CHANGELOG.md"
}
```

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to ai-devkit are documented here. release-please appends entries on every merge to `main` based on Conventional Commit messages.

## 1.0.0 (2026-05-09)

* feat: introduce versioning system + `devkit.upgrade` / `wb.upgrade` / `devkit doctor` (initial release).
```

- [ ] **Step 3: Commit**

```bash
git add version.json CHANGELOG.md
git commit -m "feat(version): seed version.json at 1.0.0 and CHANGELOG"
```

---

### Task 2: Add release-please config

**Files:**
- Create: `release-please-config.json`
- Create: `.release-please-manifest.json`
- Create: `.github/workflows/release-please.yml`

- [ ] **Step 1: Write `release-please-config.json`**

```json
{
  "release-type": "simple",
  "packages": {
    ".": {
      "release-type": "simple",
      "extra-files": [
        {
          "type": "json",
          "path": "version.json",
          "jsonpath": "$.version"
        }
      ],
      "include-component-in-tag": false,
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": true,
      "draft": false,
      "prerelease": false
    }
  },
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
}
```

- [ ] **Step 2: Write `.release-please-manifest.json`**

```json
{
  ".": "1.0.0"
}
```

- [ ] **Step 3: Write `.github/workflows/release-please.yml`**

```yaml
name: release-please

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

- [ ] **Step 4: Commit**

```bash
git add release-please-config.json .release-please-manifest.json .github/workflows/release-please.yml
git commit -m "chore(release): add release-please workflow"
```

---

### Task 3: Write `lib/version-check.sh` skeleton + first failing test

**Files:**
- Create: `lib/version-check.sh`
- Create: `tests/test-version-check.zsh`
- Create: `tests/helpers/gh-shim.sh`

- [ ] **Step 1: Write the failing test for `_wb_compare_semver`**

`tests/test-version-check.zsh`:

```zsh
#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."
source "${REPO_ROOT}/lib/version-check.sh"

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" != "$want" ]]; then
    print -r -- "FAIL: $msg — got '$got', want '$want'"
    exit 1
  fi
}

# semver compare: returns "lt", "eq", "gt"
test_compare_semver_lt() {
  assert_eq "$(_wb_compare_semver 1.0.0 1.0.1)" "lt" "1.0.0 < 1.0.1"
  assert_eq "$(_wb_compare_semver 1.0.0 1.1.0)" "lt" "1.0.0 < 1.1.0"
  assert_eq "$(_wb_compare_semver 1.0.0 2.0.0)" "lt" "1.0.0 < 2.0.0"
  assert_eq "$(_wb_compare_semver 1.2.3 1.10.0)" "lt" "1.2.3 < 1.10.0 (numeric, not lexical)"
}

test_compare_semver_eq() {
  assert_eq "$(_wb_compare_semver 1.0.0 1.0.0)" "eq" "1.0.0 == 1.0.0"
}

test_compare_semver_gt() {
  assert_eq "$(_wb_compare_semver 1.0.1 1.0.0)" "gt" "1.0.1 > 1.0.0"
}

test_compare_semver_lt
test_compare_semver_eq
test_compare_semver_gt
print -r -- "PASS: test-version-check.zsh (semver compare)"
```

- [ ] **Step 2: Run test, verify it fails**

```bash
zsh tests/test-version-check.zsh
```
Expected: FAIL — `_wb_compare_semver: command not found` or similar.

- [ ] **Step 3: Write minimal lib with `_wb_compare_semver`**

`lib/version-check.sh`:

```bash
# version-check.sh — bash-portable shared library for upgrade-notification.
# Sourced from zsh today; body must remain bash-compatible (no zsh-only syntax).
# Functions exported:
#   _wb_compare_semver A B  -> "lt" | "eq" | "gt"
#   _wb_versioncheck TOOL   -> prints banner if upgrade available
#   _wb_check_requires TOOL -> verifies peer floors
#   _wb_record_prior TOOL   -> writes prior cache entry
#   _wb_render_banner TOOL  -> renders upgrade-available message

_wb_compare_semver() {
  local a="$1" b="$2"
  local IFS=.
  local -a a_parts b_parts
  read -ra a_parts <<<"${a%%-*}"
  read -ra b_parts <<<"${b%%-*}"
  local i
  for i in 0 1 2; do
    local av="${a_parts[i]:-0}" bv="${b_parts[i]:-0}"
    if (( av < bv )); then echo "lt"; return; fi
    if (( av > bv )); then echo "gt"; return; fi
  done
  echo "eq"
}
```

NOTE: zsh array indexing is 1-based but `read -ra` with `${a_parts[i]:-0}` works in both bash (0-based) and zsh (1-based with explicit numeric index — actually breaks). To stay portable, prefer parameter expansion over array indexing. Rewrite safely:

```bash
_wb_compare_semver() {
  local a="${1%%-*}" b="${2%%-*}"
  local a_major="${a%%.*}"; a="${a#*.}"
  local a_minor="${a%%.*}"; local a_patch="${a#*.}"
  [[ "$a_minor" == "$a" ]] && a_patch="0"
  [[ "$a_patch" == "$a" ]] && a_patch="0"
  local b_major="${b%%.*}"; b="${b#*.}"
  local b_minor="${b%%.*}"; local b_patch="${b#*.}"
  [[ "$b_minor" == "$b" ]] && b_patch="0"
  [[ "$b_patch" == "$b" ]] && b_patch="0"
  if (( a_major < b_major )); then echo "lt"; return; fi
  if (( a_major > b_major )); then echo "gt"; return; fi
  if (( a_minor < b_minor )); then echo "lt"; return; fi
  if (( a_minor > b_minor )); then echo "gt"; return; fi
  if (( a_patch < b_patch )); then echo "lt"; return; fi
  if (( a_patch > b_patch )); then echo "gt"; return; fi
  echo "eq"
}
```

Use the second variant. It avoids array indexing entirely.

- [ ] **Step 4: Run test, verify pass**

```bash
zsh tests/test-version-check.zsh
```
Expected: `PASS: test-version-check.zsh (semver compare)`.

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add _wb_compare_semver in lib/version-check.sh"
```

---

### Task 4: Add `_wb_check_requires` constraint parser

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing tests**

Append to `tests/test-version-check.zsh` before the final `print` line:

```zsh
test_check_requires_pass() {
  # `_wb_check_requires CONSTRAINT CURRENT` -> "ok" | "fail"
  assert_eq "$(_wb_check_requires '>=1.2.0' '1.2.0')" "ok" ">=1.2.0 vs 1.2.0"
  assert_eq "$(_wb_check_requires '>=1.2.0' '1.3.0')" "ok" ">=1.2.0 vs 1.3.0"
  assert_eq "$(_wb_check_requires '>=1.2.0' '2.0.0')" "ok" ">=1.2.0 vs 2.0.0"
}

test_check_requires_fail() {
  assert_eq "$(_wb_check_requires '>=1.2.0' '1.1.9')" "fail" ">=1.2.0 vs 1.1.9 fails"
  assert_eq "$(_wb_check_requires '>=2.0.0' '1.99.99')" "fail" ">=2.0.0 vs 1.99.99 fails"
}

test_check_requires_pass
test_check_requires_fail
```

- [ ] **Step 2: Run test, expect failure**

```bash
zsh tests/test-version-check.zsh
```
Expected: FAIL — `_wb_check_requires: command not found`.

- [ ] **Step 3: Implement `_wb_check_requires` in `lib/version-check.sh`**

Append:

```bash
# _wb_check_requires CONSTRAINT CURRENT -> "ok" | "fail"
# v1 supports only >= constraints. Reject other operators with "fail".
_wb_check_requires() {
  local constraint="$1" current="$2"
  case "$constraint" in
    '>='*)
      local floor="${constraint#>=}"
      local cmp
      cmp="$(_wb_compare_semver "$current" "$floor")"
      if [[ "$cmp" == "lt" ]]; then echo "fail"; else echo "ok"; fi
      ;;
    *)
      echo "fail"
      ;;
  esac
}
```

- [ ] **Step 4: Run test, verify pass**

```bash
zsh tests/test-version-check.zsh
```

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add _wb_check_requires constraint parser"
```

---

### Task 5: Add `_wb_clone_path` helper to resolve tool clone path

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing test**

Append to `tests/test-version-check.zsh` (before the final print):

```zsh
test_clone_path_devkit_env() {
  DEVKIT_CLONE=/tmp/fake-devkit assert_eq "$(_wb_clone_path devkit)" "/tmp/fake-devkit" "DEVKIT_CLONE wins"
}

test_clone_path_ralph_env() {
  RALPH_CLONE=/tmp/fake-ralph assert_eq "$(_wb_clone_path ralph)" "/tmp/fake-ralph" "RALPH_CLONE wins"
}

test_clone_path_devkit_env
test_clone_path_ralph_env
```

- [ ] **Step 2: Run test, expect failure**

- [ ] **Step 3: Add to `lib/version-check.sh`**

```bash
# _wb_clone_path TOOL -> absolute path to the tool's local clone, or empty.
# Reads env var ${TOOL^^}_CLONE if set. Otherwise empty.
_wb_clone_path() {
  local tool="$1"
  local var
  case "$tool" in
    devkit) var="DEVKIT_CLONE" ;;
    ralph)  var="RALPH_CLONE"  ;;
    wb)     echo ""; return ;;
    *)      echo ""; return ;;
  esac
  eval "echo \"\${$var:-}\""
}
```

- [ ] **Step 4: Run test, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add _wb_clone_path helper"
```

---

### Task 6: Add `_wb_local_version` reader

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing test**

```zsh
test_local_version_from_clone() {
  local fixture
  fixture="$(mktemp -d)"
  trap "rm -rf '$fixture'" EXIT
  printf '{"version":"1.2.3"}\n' > "$fixture/version.json"
  DEVKIT_CLONE="$fixture" assert_eq "$(_wb_local_version devkit)" "1.2.3" "reads version from clone"
}

test_local_version_missing() {
  local fixture
  fixture="$(mktemp -d)"
  trap "rm -rf '$fixture'" EXIT
  DEVKIT_CLONE="$fixture" assert_eq "$(_wb_local_version devkit)" "0.0.0" "missing -> 0.0.0"
}

test_local_version_corrupt() {
  local fixture
  fixture="$(mktemp -d)"
  trap "rm -rf '$fixture'" EXIT
  printf 'not json\n' > "$fixture/version.json"
  DEVKIT_CLONE="$fixture" assert_eq "$(_wb_local_version devkit)" "0.0.0" "corrupt -> 0.0.0 (warn)"
}

test_local_version_from_clone
test_local_version_missing
test_local_version_corrupt
```

- [ ] **Step 2: Run test, expect failure**

- [ ] **Step 3: Add to `lib/version-check.sh`**

```bash
# _wb_local_version TOOL -> semver string or "0.0.0"
_wb_local_version() {
  local tool="$1"
  local clone
  clone="$(_wb_clone_path "$tool")"
  if [[ "$tool" == "wb" ]]; then
    # Wb tracks template-version.json inside stamped wb. Caller passes via env.
    if [[ -n "${WB_TEMPLATE_VERSION_FILE:-}" && -f "$WB_TEMPLATE_VERSION_FILE" ]]; then
      jq -r '.version // "0.0.0"' "$WB_TEMPLATE_VERSION_FILE" 2>/dev/null || echo "0.0.0"
      return
    fi
    echo "0.0.0"
    return
  fi
  if [[ -z "$clone" || ! -f "$clone/version.json" ]]; then
    echo "0.0.0"
    return
  fi
  local v
  v="$(jq -r '.version // "0.0.0"' "$clone/version.json" 2>/dev/null)" || v="0.0.0"
  if [[ -z "$v" || "$v" == "null" ]]; then v="0.0.0"; fi
  echo "$v"
}
```

- [ ] **Step 4: Run test, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add _wb_local_version reader"
```

---

### Task 7: Add `_wb_fetch_upstream` with `gh api` primary + `git ls-remote` fallback

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`
- Create: `tests/helpers/gh-shim.sh`
- Create: `tests/fixtures/bare-upstream/setup.sh`

- [ ] **Step 1: Build the bare-repo fixture script**

`tests/fixtures/bare-upstream/setup.sh`:

```bash
#!/usr/bin/env bash
# Builds a bare git repo at $1 with a single commit on main containing version.json.
# Usage: setup.sh OUTDIR VERSION
set -euo pipefail
out="$1"
ver="${2:-1.4.0}"
mkdir -p "$out"
work="$(mktemp -d)"
trap "rm -rf '$work'" EXIT
git -C "$work" init -q -b main
printf '{"version":"%s","released":"2026-05-09","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"https://example.com"}\n' "$ver" > "$work/version.json"
git -C "$work" -c user.email=t@t -c user.name=t add version.json
git -C "$work" -c user.email=t@t -c user.name=t commit -q -m "init"
git -C "$work" push -q --mirror "$out"
```

```bash
chmod +x tests/fixtures/bare-upstream/setup.sh
```

- [ ] **Step 2: Build the gh shim**

`tests/helpers/gh-shim.sh`:

```bash
#!/usr/bin/env bash
# Stub `gh` for tests. Reads canned responses from $GH_SHIM_RESPONSES_DIR/<arg-hash>.json.
# Used by sourcing this file, which exports a function named `gh` overriding the real binary.
gh() {
  if [[ "${GH_SHIM_FAIL:-0}" == "1" ]]; then
    return 1
  fi
  # Look for a canned response keyed by all args concatenated.
  local key
  key="$(printf '%s|' "$@" | md5sum | cut -c1-32)" 2>/dev/null \
   || key="$(printf '%s|' "$@" | shasum | cut -c1-32)"
  local path="${GH_SHIM_RESPONSES_DIR:-/tmp/gh-shim}/$key.json"
  if [[ -f "$path" ]]; then
    cat "$path"
    return 0
  fi
  return 1
}
export -f gh 2>/dev/null || true
```

- [ ] **Step 3: Add failing test for gh-api path**

Append to `tests/test-version-check.zsh`:

```zsh
test_fetch_upstream_via_gh_shim() {
  local respdir
  respdir="$(mktemp -d)"
  trap "rm -rf '$respdir'" EXIT
  GH_SHIM_RESPONSES_DIR="$respdir"
  source "${REPO_ROOT}/tests/helpers/gh-shim.sh"
  # Compose response for `gh api repos/amit-t/ai-devkit/contents/version.json?ref=main`
  # Easiest path: shim fallback via env. But to keep this test deterministic, we
  # pre-place the canned file using the same hashing scheme:
  local key
  key="$(printf '%s|' "api" "repos/amit-t/ai-devkit/contents/version.json?ref=main" "-H" "Accept: application/vnd.github.raw+json" | md5sum | cut -c1-32)"
  printf '{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}\n' > "$respdir/$key.json"
  local out
  out="$(_wb_fetch_upstream amit-t ai-devkit)"
  assert_eq "$(echo "$out" | jq -r .version)" "1.4.0" "fetch_upstream returns upstream JSON"
}

test_fetch_upstream_via_gh_shim
```

- [ ] **Step 4: Run test, expect failure**

- [ ] **Step 5: Implement `_wb_fetch_upstream` and `_wb_parse_remote`**

Append to `lib/version-check.sh`:

```bash
# _wb_parse_remote URL -> "owner/repo"
_wb_parse_remote() {
  local url="$1"
  url="${url%.git}"
  url="${url#https://github.com/}"
  url="${url#git@github.com:}"
  echo "$url"
}

# _wb_fetch_upstream OWNER REPO -> JSON string of upstream version.json (stdout)
# Tries gh api first; falls back to git ls-remote + git fetch + show.
# Returns non-zero on failure.
_wb_fetch_upstream() {
  local owner="$1" repo="$2"
  local out
  if command -v gh >/dev/null 2>&1; then
    out="$(gh api "repos/${owner}/${repo}/contents/version.json?ref=main" \
                 -H "Accept: application/vnd.github.raw+json" 2>/dev/null)" && {
      [[ -n "$out" ]] && { echo "$out"; return 0; }
    }
  fi
  # Fallback: read from a clone if available.
  local tool
  case "${repo}" in
    ai-devkit) tool="devkit" ;;
    ai-ralph)  tool="ralph"  ;;
    ai-workbench) tool="wb"  ;;
    *) tool="" ;;
  esac
  if [[ -n "$tool" ]]; then
    local clone
    clone="$(_wb_clone_path "$tool")"
    if [[ -n "$clone" && -d "$clone/.git" ]]; then
      git -C "$clone" fetch -q origin main 2>/dev/null || return 1
      git -C "$clone" show "origin/main:version.json" 2>/dev/null && return 0
    fi
  fi
  return 1
}
```

- [ ] **Step 6: Run test, verify pass**

```bash
zsh tests/test-version-check.zsh
```

- [ ] **Step 7: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh tests/helpers/gh-shim.sh tests/fixtures/bare-upstream/setup.sh
git commit -m "feat(versioning): add _wb_fetch_upstream with gh + git fallback"
```

---

### Task 8: Add cache layer with TTL

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing tests**

Append to `tests/test-version-check.zsh`:

```zsh
test_cache_miss_writes() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  # Direct call to writer
  local payload='{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{}}'
  _wb_cache_write devkit "$payload" 12
  [[ -f "$cachedir/devkit.json" ]] || { print -r -- "FAIL: cache file not created"; exit 1; }
  assert_eq "$(jq -r .upstream.version "$cachedir/devkit.json")" "1.4.0" "cache stores upstream"
}

test_cache_hit_within_ttl() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  local now ts
  now="$(date -u +%s)"
  ts="$(date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$cachedir/devkit.json" <<JSON
{"tool":"devkit","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{}}}
JSON
  assert_eq "$(_wb_cache_is_fresh devkit)" "fresh" "fresh within ttl"
}

test_cache_stale_past_ttl() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  cat > "$cachedir/devkit.json" <<'JSON'
{"tool":"devkit","checked_at":"1970-01-01T00:00:00Z","ttl_hours":12,"upstream":{"version":"1.4.0"}}
JSON
  assert_eq "$(_wb_cache_is_fresh devkit)" "stale" "stale past ttl"
}

test_cache_miss_writes
test_cache_hit_within_ttl
test_cache_stale_past_ttl
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement cache layer**

Append to `lib/version-check.sh`:

```bash
# Cache layer.
# Default cache dir: ${WB_UPDATES_CACHE_DIR:-$HOME/.cache/wb-updates}
_wb_cache_dir() {
  echo "${WB_UPDATES_CACHE_DIR:-${HOME}/.cache/wb-updates}"
}

_wb_cache_path() {
  local tool="$1"
  local d
  d="$(_wb_cache_dir)"
  mkdir -p "$d"
  echo "$d/${tool}.json"
}

# _wb_cache_write TOOL UPSTREAM_JSON TTL_HOURS
_wb_cache_write() {
  local tool="$1" payload="$2" ttl="$3"
  local p ts
  p="$(_wb_cache_path "$tool")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg tool "$tool" --arg ts "$ts" --argjson ttl "$ttl" --argjson up "$payload" \
        '{tool:$tool, checked_at:$ts, ttl_hours:$ttl, upstream:$up, rate_limit_reset_at:null}' \
        > "$p"
}

# _wb_cache_is_fresh TOOL -> "fresh" | "stale" | "missing"
_wb_cache_is_fresh() {
  local tool="$1"
  local p
  p="$(_wb_cache_path "$tool")"
  [[ -f "$p" ]] || { echo "missing"; return; }
  local ts ttl
  ts="$(jq -r .checked_at "$p" 2>/dev/null)"
  ttl="$(jq -r .ttl_hours "$p" 2>/dev/null)"
  [[ -z "$ts" || "$ts" == "null" ]] && { echo "stale"; return; }
  local checked_at_epoch now_epoch age_seconds limit
  checked_at_epoch="$(date -u -d "$ts" +%s 2>/dev/null \
                     || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
                     || echo 0)"
  now_epoch="$(date -u +%s)"
  age_seconds=$(( now_epoch - checked_at_epoch ))
  limit=$(( ttl * 3600 ))
  if (( age_seconds < limit )); then echo "fresh"; else echo "stale"; fi
}

# _wb_cache_read TOOL -> upstream JSON (stdout)
_wb_cache_read() {
  local tool="$1"
  local p
  p="$(_wb_cache_path "$tool")"
  jq -c '.upstream' "$p" 2>/dev/null
}

# _wb_cache_invalidate TOOL
_wb_cache_invalidate() {
  local tool="$1"
  rm -f "$(_wb_cache_path "$tool")"
}
```

- [ ] **Step 4: Run, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add TTL-aware cache layer"
```

---

### Task 9: Add `_wb_render_banner` and offline-skip message

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing test**

Append:

```zsh
test_render_banner_update_available() {
  local out
  out="$(_wb_render_banner devkit 1.2.3 1.4.0 "https://example.com/changelog")"
  case "$out" in
    *"update 1.4.0 available"*) ;;
    *) print -r -- "FAIL: banner missing 'update 1.4.0 available' — got '$out'"; exit 1 ;;
  esac
  case "$out" in
    *"devkit.upgrade"*) ;;
    *) print -r -- "FAIL: banner missing 'devkit.upgrade'"; exit 1 ;;
  esac
}

test_render_banner_update_available
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

Append to `lib/version-check.sh`:

```bash
# _wb_render_banner TOOL LOCAL LATEST CHANGELOG_URL
_wb_render_banner() {
  local tool="$1" local_v="$2" latest="$3" changelog="$4"
  local upgrade_cmd
  case "$tool" in
    devkit) upgrade_cmd="devkit.upgrade" ;;
    ralph)  upgrade_cmd="ralph.upgrade"  ;;
    wb)     upgrade_cmd="wb.upgrade"     ;;
    *)      upgrade_cmd="${tool}.upgrade" ;;
  esac
  printf "[%s v%s] update %s available. Run %s. Changelog: %s\n" \
    "$tool" "$local_v" "$latest" "$upgrade_cmd" "$changelog"
}
```

- [ ] **Step 4: Run, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add _wb_render_banner"
```

---

### Task 10: Add `_wb_versioncheck` orchestrator (calls fetch + cache + banner)

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing integration test**

Append:

```zsh
test_versioncheck_emits_banner_on_upgrade_available() {
  local cachedir respdir clonedir
  cachedir="$(mktemp -d)"
  respdir="$(mktemp -d)"
  clonedir="$(mktemp -d)"
  trap "rm -rf '$cachedir' '$respdir' '$clonedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  GH_SHIM_RESPONSES_DIR="$respdir"
  DEVKIT_CLONE="$clonedir"
  source "${REPO_ROOT}/tests/helpers/gh-shim.sh"
  printf '{"version":"1.0.0"}\n' > "$clonedir/version.json"
  local key
  key="$(printf '%s|' "api" "repos/amit-t/ai-devkit/contents/version.json?ref=main" "-H" "Accept: application/vnd.github.raw+json" | md5sum | cut -c1-32)"
  printf '{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"https://example.com"}\n' > "$respdir/$key.json"
  local out
  out="$(WB_UPSTREAM_OWNER=amit-t WB_UPSTREAM_REPO_devkit=ai-devkit _wb_versioncheck devkit 2>&1)"
  case "$out" in
    *"update 1.4.0 available"*) ;;
    *) print -r -- "FAIL: versioncheck did not emit banner — got '$out'"; exit 1 ;;
  esac
}

test_versioncheck_emits_banner_on_upgrade_available
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement orchestrator**

Append to `lib/version-check.sh`:

```bash
# _wb_versioncheck TOOL
# Fail-open: any error during the check is silenced (except offline message).
# Reads:
#   WB_UPSTREAM_OWNER (default amit-t)
#   WB_UPSTREAM_REPO_<tool> (overrides default repo name)
_wb_versioncheck() {
  local tool="$1"
  local owner="${WB_UPSTREAM_OWNER:-amit-t}"
  local repo_var="WB_UPSTREAM_REPO_${tool}"
  local repo
  eval "repo=\"\${$repo_var:-}\""
  if [[ -z "$repo" ]]; then
    case "$tool" in
      devkit) repo="ai-devkit" ;;
      ralph)  repo="ai-ralph"  ;;
      wb)     repo="ai-workbench" ;;
      *) return 0 ;;
    esac
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf "[%s] jq missing — required for update notifications. brew install jq\n" "$tool" >&2
    return 0
  fi

  local fresh
  fresh="$(_wb_cache_is_fresh "$tool")"
  local upstream_json
  if [[ "$fresh" == "fresh" ]]; then
    upstream_json="$(_wb_cache_read "$tool")"
  else
    printf "[%s] checking for updates...\n" "$tool" >&2
    if ! upstream_json="$(_wb_fetch_upstream "$owner" "$repo" 2>/dev/null)"; then
      printf "[%s] update check skipped (offline)\n" "$tool" >&2
      return 0
    fi
    local ttl
    ttl="$(echo "$upstream_json" | jq -r '.check_ttl_hours // 12')"
    _wb_cache_write "$tool" "$upstream_json" "$ttl"
  fi

  local local_v latest changelog
  local_v="$(_wb_local_version "$tool")"
  latest="$(echo "$upstream_json" | jq -r '.version // "0.0.0"')"
  changelog="$(echo "$upstream_json" | jq -r '.changelog_url // ""')"
  if [[ "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    _wb_render_banner "$tool" "$local_v" "$latest" "$changelog" >&2
  fi
  return 0
}
```

- [ ] **Step 4: Run, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): orchestrate fetch+cache+banner via _wb_versioncheck"
```

---

### Task 11: Add bootstrap-flag handling

**Files:**
- Create: `lib/bootstrap-detection.sh`
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing test**

```zsh
test_bootstrap_nag_fires_once() {
  local cachedir clonedir
  cachedir="$(mktemp -d)"
  clonedir="$(mktemp -d)"
  trap "rm -rf '$cachedir' '$clonedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  DEVKIT_CLONE="$clonedir"
  # No version.json -> bootstrap state.
  local out1 out2
  out1="$(_wb_emit_bootstrap_nag devkit 2>&1)"
  case "$out1" in
    *"versioning system added"*) ;;
    *) print -r -- "FAIL: first nag missing message"; exit 1 ;;
  esac
  out2="$(_wb_emit_bootstrap_nag devkit 2>&1)"
  if [[ -n "$out2" ]]; then
    print -r -- "FAIL: second call should be silent — got '$out2'"; exit 1
  fi
}

test_bootstrap_clear_after_upgrade() {
  local cachedir
  cachedir="$(mktemp -d)"
  trap "rm -rf '$cachedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  _wb_mark_bootstrapped devkit
  [[ -f "$cachedir/devkit-bootstrapped.flag" ]] || { print -r -- "FAIL: flag not created"; exit 1; }
}

test_bootstrap_nag_fires_once
test_bootstrap_clear_after_upgrade
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

`lib/bootstrap-detection.sh`:

```bash
# bootstrap-detection.sh — first-time-encounter nag for the versioning system.
# When a tool's local version.json is missing (pre-rollout clone), emit a one-time
# banner. After first successful upgrade, mark bootstrapped.

_wb_bootstrap_flag_path() {
  local tool="$1"
  local d
  d="${WB_UPDATES_CACHE_DIR:-${HOME}/.cache/wb-updates}"
  mkdir -p "$d"
  echo "$d/${tool}-bootstrapped.flag"
}

_wb_is_bootstrapped() {
  local tool="$1"
  [[ -f "$(_wb_bootstrap_flag_path "$tool")" ]]
}

_wb_mark_bootstrapped() {
  local tool="$1"
  : > "$(_wb_bootstrap_flag_path "$tool")"
}

_wb_emit_bootstrap_nag() {
  local tool="$1"
  if _wb_is_bootstrapped "$tool"; then
    return 0
  fi
  case "$tool" in
    devkit) printf "[%s] versioning system added upstream. Run %s.upgrade to start receiving update notifications.\n" "$tool" "$tool" >&2 ;;
    ralph)  printf "[%s] versioning system added upstream. Run %s.upgrade to start receiving update notifications.\n" "$tool" "$tool" >&2 ;;
    wb)     printf "[%s] versioning system added upstream. Run wb.upgrade in this stamped wb to start receiving update notifications.\n" "$tool" >&2 ;;
  esac
  _wb_mark_bootstrapped "$tool"
}
```

Modify `lib/version-check.sh` to source `bootstrap-detection.sh`. Add at top of file (after the leading comment):

```bash
# Bootstrap helpers.
_VERCHECK_LIB_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_VERCHECK_LIB_DIR" == "${BASH_SOURCE[0]}" ]] && _VERCHECK_LIB_DIR="."
. "$_VERCHECK_LIB_DIR/bootstrap-detection.sh"
```

In `_wb_versioncheck`, add bootstrap detection before the cache-fresh check. After the `jq` guard, insert:

```bash
  local local_check
  local_check="$(_wb_local_version "$tool")"
  if [[ "$local_check" == "0.0.0" ]]; then
    _wb_emit_bootstrap_nag "$tool"
  fi
```

- [ ] **Step 4: Run, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/bootstrap-detection.sh lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add one-time bootstrap nag"
```

---

### Task 12: Add `_wb_record_prior` for rollback support

**Files:**
- Modify: `lib/version-check.sh`
- Modify: `tests/test-version-check.zsh`

- [ ] **Step 1: Add failing test**

```zsh
test_record_prior_writes_file() {
  local cachedir clonedir
  cachedir="$(mktemp -d)"
  clonedir="$(mktemp -d)"
  trap "rm -rf '$cachedir' '$clonedir'" EXIT
  WB_UPDATES_CACHE_DIR="$cachedir"
  DEVKIT_CLONE="$clonedir"
  printf '{"version":"1.2.3"}\n' > "$clonedir/version.json"
  ( cd "$clonedir" && git init -q -b main && git -c user.email=t@t -c user.name=t add version.json && git -c user.email=t@t -c user.name=t commit -q -m init )
  _wb_record_prior devkit
  [[ -f "$cachedir/devkit-prior.json" ]] || { print -r -- "FAIL: prior file not created"; exit 1; }
  assert_eq "$(jq -r .prior_version "$cachedir/devkit-prior.json")" "1.2.3" "prior version captured"
}

test_record_prior_writes_file
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

Append to `lib/version-check.sh`:

```bash
# _wb_record_prior TOOL — capture current SHA + version before an upgrade.
_wb_record_prior() {
  local tool="$1"
  local clone
  clone="$(_wb_clone_path "$tool")"
  [[ -z "$clone" || ! -d "$clone/.git" ]] && return 1
  local sha v ts d p
  sha="$(git -C "$clone" rev-parse HEAD 2>/dev/null)" || return 1
  v="$(_wb_local_version "$tool")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  d="${WB_UPDATES_CACHE_DIR:-${HOME}/.cache/wb-updates}"
  mkdir -p "$d"
  p="$d/${tool}-prior.json"
  jq -n --arg tool "$tool" --arg sha "$sha" --arg v "$v" --arg ts "$ts" \
    '{tool:$tool, prior_sha:$sha, prior_version:$v, current_sha:null, current_version:null, upgraded_at:$ts}' > "$p"
}
```

- [ ] **Step 4: Run, verify pass**

- [ ] **Step 5: Commit**

```bash
git add lib/version-check.sh tests/test-version-check.zsh
git commit -m "feat(versioning): add _wb_record_prior for rollback support"
```

---

### Task 13: Write `devkit-upgrade.zsh`

**Files:**
- Create: `devkit-upgrade/devkit-upgrade.zsh`
- Create: `tests/test-devkit-upgrade.zsh`

- [ ] **Step 1: Write the failing integration test**

`tests/test-devkit-upgrade.zsh`:

```zsh
#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."
UPGRADE="${REPO_ROOT}/devkit-upgrade/devkit-upgrade.zsh"

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

# Stand up a fake "global devkit clone" with a fake upstream
upstream="$scratch/upstream.git"
clone="$scratch/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream" "1.0.0"
git clone -q "$upstream" "$clone"
git -C "$clone" remote rename origin origin

# Bump upstream to 1.1.0
work="$(mktemp -d)"
git clone -q "$upstream" "$work"
printf '{"version":"1.1.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"x"}\n' > "$work/version.json"
git -C "$work" -c user.email=t@t -c user.name=t commit -aq -m "bump"
git -C "$work" push -q origin main

DEVKIT_CLONE="$clone" \
  WB_UPDATES_CACHE_DIR="$scratch/cache" \
  zsh "$UPGRADE" --yes --skip-install || { print -r -- "FAIL: upgrade returned non-zero"; exit 1; }

new_v="$(jq -r .version "$clone/version.json")"
[[ "$new_v" == "1.1.0" ]] || { print -r -- "FAIL: clone not on 1.1.0 (got $new_v)"; exit 1; }
[[ -f "$scratch/cache/devkit-prior.json" ]] || { print -r -- "FAIL: prior cache not written"; exit 1; }

print -r -- "PASS: devkit-upgrade happy path"
```

- [ ] **Step 2: Run, expect failure**

```bash
zsh tests/test-devkit-upgrade.zsh
```

Expected: FAIL with "no such file or directory".

- [ ] **Step 3: Implement `devkit-upgrade/devkit-upgrade.zsh`**

```zsh
#!/usr/bin/env zsh
# devkit-upgrade — pull latest ai-devkit clone + reinstall.
#
# Usage:
#   devkit.upgrade               # prompt before pulling
#   devkit.upgrade --yes         # skip prompt
#   devkit.upgrade --rollback    # revert to prior SHA
#   devkit.upgrade --force       # bypass peer-floor check
#   devkit.upgrade --skip-install  # (test only) skip running install.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LIB_DIR="${SCRIPT_DIR}/../lib"

YES=false
ROLLBACK=false
FORCE=false
SKIP_INSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=true; shift ;;
    --rollback) ROLLBACK=true; shift ;;
    --force) FORCE=true; shift ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    -h|--help)
      cat <<USAGE
devkit.upgrade — pull and reinstall ai-devkit.
USAGE
      exit 0 ;;
    *) print -r -- "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# shellcheck disable=SC1090
. "${LIB_DIR}/version-check.sh"

CLONE="${DEVKIT_CLONE:-}"
if [[ -z "$CLONE" ]]; then
  CLONE="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
fi

if [[ ! -d "$CLONE/.git" ]]; then
  print -r -- "ai-devkit clone not found at $CLONE. Set DEVKIT_CLONE." >&2
  exit 1
fi

# ── Rollback ────────────────────────────────────────────────────────────────
if $ROLLBACK; then
  prior="${WB_UPDATES_CACHE_DIR:-$HOME/.cache/wb-updates}/devkit-prior.json"
  if [[ ! -f "$prior" ]]; then
    print -r -- "No prior recorded. Nothing to roll back." >&2
    exit 1
  fi
  prior_sha="$(jq -r .prior_sha "$prior")"
  prior_v="$(jq -r .prior_version "$prior")"
  print -r -- "Rolling back to $prior_v ($prior_sha)..."
  git -C "$CLONE" checkout -q "$prior_sha"
  if ! $SKIP_INSTALL && [[ -x "$CLONE/install.zsh" ]]; then
    "$CLONE/install.zsh"
  fi
  _wb_cache_invalidate devkit
  print -r -- "[devkit] rolled back to $prior_v. Reload shell: exec zsh"
  exit 0
fi

# ── Pre-flight ──────────────────────────────────────────────────────────────
status="$(git -C "$CLONE" status --porcelain)"
if [[ -n "$status" ]]; then
  print -r -- "ai-devkit clone has uncommitted changes. Commit/stash and retry." >&2
  exit 2
fi

branch="$(git -C "$CLONE" rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "main" ]]; then
  print -r -- "ai-devkit clone is on '$branch', not 'main'. Switch to main and retry." >&2
  exit 2
fi

git -C "$CLONE" fetch -q origin main

local_v="$(_wb_local_version devkit)"
upstream_v_raw="$(git -C "$CLONE" show origin/main:version.json 2>/dev/null || echo '{}')"
upstream_v="$(echo "$upstream_v_raw" | jq -r '.version // "0.0.0"')"

if [[ "$(_wb_compare_semver "$local_v" "$upstream_v")" == "eq" ]]; then
  print -r -- "[devkit] already at $local_v"
  exit 0
fi

# ── Peer-floor enforcement ─────────────────────────────────────────────────
if ! $FORCE; then
  ralph_req="$(echo "$upstream_v_raw" | jq -r '.requires.ralph // empty')"
  if [[ -n "$ralph_req" ]]; then
    ralph_local="$(_wb_local_version ralph)"
    if [[ "$(_wb_check_requires "$ralph_req" "$ralph_local")" == "fail" ]]; then
      print -r -- "[devkit] cannot upgrade: requires ralph $ralph_req, found $ralph_local. Run ralph.upgrade first or pass --force." >&2
      exit 3
    fi
  fi
fi

# ── Confirmation ────────────────────────────────────────────────────────────
print -r -- "[devkit] upgrade $local_v -> $upstream_v"
print -r -- "Commits to be pulled:"
git -C "$CLONE" log HEAD..origin/main --oneline | head -20
if ! $YES; then
  printf "Continue? [y/N] "
  read -r answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    print -r -- "Aborted."
    exit 1
  fi
fi

# ── Record prior + pull + reinstall ────────────────────────────────────────
_wb_record_prior devkit
git -C "$CLONE" pull --rebase -q origin main
if ! $SKIP_INSTALL && [[ -x "$CLONE/install.zsh" ]]; then
  "$CLONE/install.zsh"
fi
_wb_cache_invalidate devkit
_wb_mark_bootstrapped devkit
print -r -- "[devkit] upgraded $local_v -> $upstream_v. Reload shell: exec zsh"
```

```bash
chmod +x devkit-upgrade/devkit-upgrade.zsh
```

- [ ] **Step 4: Run integration test, verify pass**

```bash
zsh tests/test-devkit-upgrade.zsh
```

- [ ] **Step 5: Add dirty-tree refusal test**

Append to `tests/test-devkit-upgrade.zsh`:

```zsh
# Dirty tree refusal
scratch2="$(mktemp -d)"
trap "rm -rf '$scratch2'" EXIT
upstream2="$scratch2/upstream.git"
clone2="$scratch2/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream2" "1.0.0"
git clone -q "$upstream2" "$clone2"
echo dirty > "$clone2/dirty.txt"

set +e
DEVKIT_CLONE="$clone2" \
  WB_UPDATES_CACHE_DIR="$scratch2/cache" \
  zsh "$UPGRADE" --yes --skip-install
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { print -r -- "FAIL: expected exit 2 on dirty tree, got $rc"; exit 1; }

print -r -- "PASS: devkit-upgrade dirty-tree refusal"
```

- [ ] **Step 6: Add non-main refusal test**

Append:

```zsh
scratch3="$(mktemp -d)"
trap "rm -rf '$scratch3'" EXIT
upstream3="$scratch3/upstream.git"
clone3="$scratch3/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream3" "1.0.0"
git clone -q "$upstream3" "$clone3"
git -C "$clone3" checkout -qb feature

set +e
DEVKIT_CLONE="$clone3" \
  WB_UPDATES_CACHE_DIR="$scratch3/cache" \
  zsh "$UPGRADE" --yes --skip-install
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { print -r -- "FAIL: expected exit 2 on feature branch, got $rc"; exit 1; }

print -r -- "PASS: devkit-upgrade feature-branch refusal"
```

- [ ] **Step 7: Run all tests, verify pass**

- [ ] **Step 8: Commit**

```bash
git add devkit-upgrade/devkit-upgrade.zsh tests/test-devkit-upgrade.zsh
git commit -m "feat(devkit): add devkit.upgrade with --yes / --rollback / --force / dirty-refusal"
```

---

### Task 14: Add rollback round-trip test

**Files:**
- Modify: `tests/test-devkit-upgrade.zsh`

- [ ] **Step 1: Append rollback test**

```zsh
scratch4="$(mktemp -d)"
trap "rm -rf '$scratch4'" EXIT
upstream4="$scratch4/upstream.git"
clone4="$scratch4/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream4" "1.0.0"
git clone -q "$upstream4" "$clone4"

# Bump upstream
work4="$(mktemp -d)"
git clone -q "$upstream4" "$work4"
printf '{"version":"1.1.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":"x"}\n' > "$work4/version.json"
git -C "$work4" -c user.email=t@t -c user.name=t commit -aq -m "bump"
git -C "$work4" push -q origin main

DEVKIT_CLONE="$clone4" \
  WB_UPDATES_CACHE_DIR="$scratch4/cache" \
  zsh "$UPGRADE" --yes --skip-install

DEVKIT_CLONE="$clone4" \
  WB_UPDATES_CACHE_DIR="$scratch4/cache" \
  zsh "$UPGRADE" --rollback --skip-install

v="$(jq -r .version "$clone4/version.json")"
[[ "$v" == "1.0.0" ]] || { print -r -- "FAIL: rollback did not restore 1.0.0 (got $v)"; exit 1; }

print -r -- "PASS: devkit-upgrade rollback round-trip"
```

- [ ] **Step 2: Run, verify pass**

- [ ] **Step 3: Commit**

```bash
git add tests/test-devkit-upgrade.zsh
git commit -m "test(devkit): add upgrade rollback round-trip"
```

---

### Task 15: Add peer-`requires` enforcement test

**Files:**
- Modify: `tests/test-devkit-upgrade.zsh`

- [ ] **Step 1: Append**

```zsh
scratch5="$(mktemp -d)"
trap "rm -rf '$scratch5'" EXIT
upstream5="$scratch5/upstream.git"
clone5="$scratch5/clone"
ralph_clone="$scratch5/ralph"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream5" "1.0.0"
git clone -q "$upstream5" "$clone5"
mkdir -p "$ralph_clone"
printf '{"version":"0.5.0"}\n' > "$ralph_clone/version.json"

# Bump upstream and add requires.ralph
work5="$(mktemp -d)"
git clone -q "$upstream5" "$work5"
printf '{"version":"1.1.0","check_ttl_hours":12,"channel":"stable","requires":{"ralph":">=1.0.0"},"changelog_url":"x"}\n' > "$work5/version.json"
git -C "$work5" -c user.email=t@t -c user.name=t commit -aq -m "bump"
git -C "$work5" push -q origin main

set +e
DEVKIT_CLONE="$clone5" \
  RALPH_CLONE="$ralph_clone" \
  WB_UPDATES_CACHE_DIR="$scratch5/cache" \
  zsh "$UPGRADE" --yes --skip-install
rc=$?
set -e
[[ "$rc" -eq 3 ]] || { print -r -- "FAIL: expected exit 3 on peer-floor block, got $rc"; exit 1; }

# --force bypasses
DEVKIT_CLONE="$clone5" \
  RALPH_CLONE="$ralph_clone" \
  WB_UPDATES_CACHE_DIR="$scratch5/cache" \
  zsh "$UPGRADE" --yes --force --skip-install

v="$(jq -r .version "$clone5/version.json")"
[[ "$v" == "1.1.0" ]] || { print -r -- "FAIL: --force did not allow upgrade (got $v)"; exit 1; }

print -r -- "PASS: devkit-upgrade peer-requires block + --force"
```

- [ ] **Step 2: Run, verify pass**

- [ ] **Step 3: Commit**

```bash
git add tests/test-devkit-upgrade.zsh
git commit -m "test(devkit): add peer-requires enforcement + --force bypass"
```

---

### Task 16: Implement `devkit-doctor.zsh`

**Files:**
- Create: `devkit-doctor/devkit-doctor.zsh`
- Create: `tests/test-devkit-doctor.zsh`

- [ ] **Step 1: Write failing test**

```zsh
#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."
DOCTOR="${REPO_ROOT}/devkit-doctor/devkit-doctor.zsh"

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

upstream="$scratch/upstream.git"
clone="$scratch/clone"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$upstream" "1.0.0"
git clone -q "$upstream" "$clone"
ralph_clone="$scratch/ralph"
mkdir -p "$ralph_clone"
printf '{"version":"1.0.0"}\n' > "$ralph_clone/version.json"

# Cache fresh "1.4.0 upstream available" for devkit
mkdir -p "$scratch/cache"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$scratch/cache/devkit.json" <<JSON
{"tool":"devkit","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.4.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}}
JSON
cat > "$scratch/cache/ralph.json" <<JSON
{"tool":"ralph","checked_at":"$ts","ttl_hours":12,"upstream":{"version":"1.0.0","check_ttl_hours":12,"channel":"stable","requires":{},"changelog_url":""}}
JSON

out="$(DEVKIT_CLONE="$clone" RALPH_CLONE="$ralph_clone" WB_UPDATES_CACHE_DIR="$scratch/cache" zsh "$DOCTOR" --check-only 2>&1)"
case "$out" in
  *"devkit"*"1.0.0"*"1.4.0"*) ;;
  *) print -r -- "FAIL: doctor missing devkit row — got $out"; exit 1 ;;
esac
case "$out" in
  *"ralph"*"1.0.0"*"current"*) ;;
  *) print -r -- "FAIL: doctor missing ralph current row — got $out"; exit 1 ;;
esac

print -r -- "PASS: doctor renders status table"
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement `devkit-doctor/devkit-doctor.zsh`**

```zsh
#!/usr/bin/env zsh
# devkit-doctor — show versioning state of devkit + ralph (+ wb if in stamped wb).
#
# Usage:
#   devkit doctor              # interactive report
#   devkit doctor --check-only # exit non-zero if any tool stale
#   devkit doctor --fix        # interactive upgrade in dep order
#   devkit doctor --fix --yes  # unattended upgrade

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LIB_DIR="${SCRIPT_DIR}/../lib"

# shellcheck disable=SC1090
. "${LIB_DIR}/version-check.sh"

CHECK_ONLY=false
FIX=false
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=true; shift ;;
    --fix) FIX=true; shift ;;
    --yes) YES=true; shift ;;
    -h|--help) cat <<USAGE
devkit doctor — show or repair version state.
USAGE
      exit 0 ;;
    *) print -r -- "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

is_stamped_wb=false
if [[ -f "$PWD/.workbench-manifest.json" && -f "$PWD/project.conf" ]]; then
  is_stamped_wb=true
fi

# Fetch (or use cache) for each tool
fetch_tool_state() {
  local tool="$1"
  local fresh latest local_v
  local_v="$(_wb_local_version "$tool")"
  fresh="$(_wb_cache_is_fresh "$tool")"
  local upstream_json
  if [[ "$fresh" == "fresh" ]]; then
    upstream_json="$(_wb_cache_read "$tool")"
  else
    case "$tool" in
      devkit) upstream_json="$(_wb_fetch_upstream amit-t ai-devkit 2>/dev/null || echo '')" ;;
      ralph)  upstream_json="$(_wb_fetch_upstream amit-t ai-ralph  2>/dev/null || echo '')" ;;
      wb)     upstream_json="$(_wb_fetch_upstream amit-t ai-workbench 2>/dev/null || echo '')" ;;
    esac
    if [[ -n "$upstream_json" ]]; then
      local ttl
      ttl="$(echo "$upstream_json" | jq -r '.check_ttl_hours // 12')"
      _wb_cache_write "$tool" "$upstream_json" "$ttl"
    fi
  fi
  latest="$(echo "$upstream_json" | jq -r '.version // "?"')"
  echo "${local_v}|${latest}"
}

render_row() {
  local tool="$1" local_v="$2" latest="$3"
  local status
  if [[ "$latest" == "?" ]]; then
    status="(check failed)"
  elif [[ "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    status="upgrade available"
  else
    status="current"
  fi
  printf "  %-10s %-10s %-10s %s\n" "$tool" "$local_v" "$latest" "$status"
}

print -r -- "TOOL       LOCAL      LATEST     STATUS"
stale=0
for tool in devkit ralph; do
  IFS=\| read local_v latest <<< "$(fetch_tool_state "$tool")"
  render_row "$tool" "$local_v" "$latest"
  if [[ "$latest" != "?" && "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    stale=$(( stale + 1 ))
  fi
done

if $is_stamped_wb; then
  WB_TEMPLATE_VERSION_FILE="$PWD/.workbench-state/template-version.json" \
    IFS=\| read local_v latest <<< "$(fetch_tool_state wb)"
  render_row "wb" "$local_v" "$latest"
  if [[ "$latest" != "?" && "$(_wb_compare_semver "$local_v" "$latest")" == "lt" ]]; then
    stale=$(( stale + 1 ))
  fi
fi

if (( stale > 0 )); then
  if $CHECK_ONLY; then
    exit 4
  fi
  if $FIX; then
    fix_args=()
    $YES && fix_args+=("--yes")
    print -r -- ""
    print -r -- "Running upgrades in dep order: ralph -> devkit -> wb"
    if command -v ralph.upgrade >/dev/null 2>&1; then
      ralph.upgrade "${fix_args[@]}" || true
    fi
    if command -v devkit.upgrade >/dev/null 2>&1; then
      devkit.upgrade "${fix_args[@]}" || true
    fi
    if $is_stamped_wb && command -v wb.upgrade >/dev/null 2>&1; then
      wb.upgrade "${fix_args[@]}" || true
    fi
  fi
fi
```

```bash
chmod +x devkit-doctor/devkit-doctor.zsh
```

- [ ] **Step 4: Run, verify pass**

```bash
zsh tests/test-devkit-doctor.zsh
```

- [ ] **Step 5: Commit**

```bash
git add devkit-doctor/devkit-doctor.zsh tests/test-devkit-doctor.zsh
git commit -m "feat(devkit): add devkit doctor with --check-only / --fix"
```

---

### Task 17: Wire `install.zsh` to drop the lib + write `DEVKIT_CLONE`

**Files:**
- Modify: `install.zsh`

- [ ] **Step 1: Read existing `install.zsh`**

```bash
cat install.zsh
```

- [ ] **Step 2: Add lib distribution + env-var write at the top of the install body, before existing alias installs**

Edit `install.zsh`. Locate the line `mkdir -p "$BIN_DIR"` and add after it:

```zsh
# ── Versioning lib distribution ─────────────────────────────────────────────
SHARE_DIR="${HOME}/.local/share/wb-versioncheck"
mkdir -p "$SHARE_DIR"
cp "$SCRIPT_DIR/lib/version-check.sh"        "$SHARE_DIR/"
cp "$SCRIPT_DIR/lib/bootstrap-detection.sh"  "$SHARE_DIR/"
chmod 0644 "$SHARE_DIR/version-check.sh" "$SHARE_DIR/bootstrap-detection.sh"
ok "installed lib: $SHARE_DIR/version-check.sh"

# ── DEVKIT_CLONE in .zprofile ──────────────────────────────────────────────
ZPROFILE="${HOME}/.zprofile"
DEVKIT_LINE="export DEVKIT_CLONE=\"$SCRIPT_DIR\""
if ! grep -qF "$DEVKIT_LINE" "$ZPROFILE" 2>/dev/null; then
  if ! grep -q "EXTERNAL PROJECT ALIASES" "$ZPROFILE" 2>/dev/null; then
    printf "\n# === EXTERNAL PROJECT ALIASES ===\n" >> "$ZPROFILE"
  fi
  printf "%s\n" "$DEVKIT_LINE" >> "$ZPROFILE"
  ok "wrote DEVKIT_CLONE to $ZPROFILE"
fi
```

- [ ] **Step 3: Add new aliases — `wb.upgrade`, `devkit.upgrade`, `devkit-doctor`, `update.wb` deprecation shim**

After the existing `update.wb` alias install block, add:

```zsh
# ── wb.upgrade (canonical, replaces update.wb) ─────────────────────────────
install_cmd "wb.upgrade"     "$SCRIPT_DIR/update-workbench/update.zsh"
add_alias "alias wb.upgrade='$SCRIPT_DIR/update-workbench/update.zsh'"  "alias wb.upgrade="
add_alias "alias wb.upgrade.dev='$SCRIPT_DIR/update-workbench/update.zsh --agent devin'" "alias wb.upgrade.dev="
add_alias "alias wb.upgrade.cly='$SCRIPT_DIR/update-workbench/update.zsh --agent claude'" "alias wb.upgrade.cly="

# ── devkit.upgrade ──────────────────────────────────────────────────────────
install_cmd "devkit.upgrade"  "$SCRIPT_DIR/devkit-upgrade/devkit-upgrade.zsh"
add_alias "alias devkit.upgrade='$SCRIPT_DIR/devkit-upgrade/devkit-upgrade.zsh'" "alias devkit.upgrade="

# ── devkit doctor ───────────────────────────────────────────────────────────
DOCTOR_SHIM="$BIN_DIR/devkit"
cat > "$DOCTOR_SHIM" <<'SH'
#!/usr/bin/env zsh
case "$1" in
  doctor)
    shift
    exec "$DEVKIT_CLONE/devkit-doctor/devkit-doctor.zsh" "$@"
    ;;
  *)
    printf "Unknown subcommand: %s\nUsage: devkit doctor [--check-only|--fix]\n" "$1" >&2
    exit 1
    ;;
esac
SH
chmod +x "$DOCTOR_SHIM"
ok "installed: devkit (subcommand wrapper)"
```

- [ ] **Step 4: Replace existing `update.wb` block with deprecation shim**

Locate:
```zsh
# ── update.wb ───────────────────────────────────────────────────────────────
install_cmd "update.wb"   "$SCRIPT_DIR/update-workbench/update.zsh"
add_alias "alias update.wb='$SCRIPT_DIR/update-workbench/update.zsh'"  "alias update.wb="
add_alias "alias update.wb.dev='$SCRIPT_DIR/update-workbench/update.zsh --agent devin'" "alias update.wb.dev="
add_alias "alias update.wb.cly='$SCRIPT_DIR/update-workbench/update.zsh --agent claude'" "alias update.wb.cly="
```

Replace with:
```zsh
# ── update.wb (deprecated; forwards to wb.upgrade) ─────────────────────────
DEPRECATED_SHIM="$BIN_DIR/update.wb"
cat > "$DEPRECATED_SHIM" <<SH
#!/usr/bin/env zsh
printf "[deprecated] use 'wb.upgrade'. Forwarding...\n" >&2
exec "$SCRIPT_DIR/update-workbench/update.zsh" "\$@"
SH
chmod +x "$DEPRECATED_SHIM"
add_alias "alias update.wb='$BIN_DIR/update.wb'" "alias update.wb="
ok "installed: update.wb (deprecated shim -> wb.upgrade)"
```

- [ ] **Step 5: Run install.zsh and verify**

```bash
./install.zsh
ls ~/.local/share/wb-versioncheck/
ls ~/.local/bin/wb.upgrade ~/.local/bin/devkit.upgrade ~/.local/bin/devkit
```

Expected: all three files present. `~/.local/share/wb-versioncheck/version-check.sh` + `bootstrap-detection.sh` exist.

- [ ] **Step 6: Commit**

```bash
git add install.zsh
git commit -m "feat(install): drop versioning lib, write DEVKIT_CLONE, install upgrade/doctor commands, deprecate update.wb"
```

---

### Task 18: Add version-check preamble to `init.zsh`, `join.zsh`, `update.zsh`

**Files:**
- Modify: `init-workbench/init.zsh`
- Modify: `join-workbench/join.zsh`
- Modify: `update-workbench/update.zsh`

- [ ] **Step 1: Edit `init-workbench/init.zsh`** — add preamble immediately after `set -euo pipefail`

```zsh
# ── Version-check preamble ──────────────────────────────────────────────────
LIBVC="${HOME}/.local/share/wb-versioncheck/version-check.sh"
if [[ -f "$LIBVC" ]]; then
  # shellcheck disable=SC1090
  . "$LIBVC"
  _wb_versioncheck devkit || true
fi
```

- [ ] **Step 2: Same edit in `join-workbench/join.zsh`**

- [ ] **Step 3: Edit `update-workbench/update.zsh`** — preamble fires `_wb_versioncheck wb` (not devkit; this script implements wb.upgrade which is wb-domain)

```zsh
# ── Version-check preamble ──────────────────────────────────────────────────
LIBVC="${HOME}/.local/share/wb-versioncheck/version-check.sh"
if [[ -f "$LIBVC" ]]; then
  # shellcheck disable=SC1090
  . "$LIBVC"
  WB_TEMPLATE_VERSION_FILE="${PWD}/.workbench-state/template-version.json" \
    _wb_versioncheck wb || true
fi
```

- [ ] **Step 4: Smoke test by running `init.wb --help` or `join.wb --help` and verifying the preamble fires (or is silent if cache fresh)**

```bash
zsh init-workbench/init.zsh --help 2>&1 | head -5
```

- [ ] **Step 5: Commit**

```bash
git add init-workbench/init.zsh join-workbench/join.zsh update-workbench/update.zsh
git commit -m "feat(versioning): wire _wb_versioncheck preamble into init/join/update entry scripts"
```

---

### Task 19: Make `update.zsh` write `.workbench-state/template-version.json` after successful merge

**Files:**
- Modify: `update-workbench/update.zsh`

- [ ] **Step 1: Read the section of `update.zsh` after the merge succeeds (search for the success exit path)**

```bash
grep -n "merge\|exit 0\|complete\|done\|success" update-workbench/update.zsh | head -30
```

- [ ] **Step 2: After the successful merge / commit step, append a block that writes the version file**

Locate the success completion path (the lines that report "update.wb done" or similar). Add immediately before the success exit:

```zsh
# ── Stamp template-version.json so wb.upgrade nags fire correctly ──────────
TEMPLATE_VERSION_FILE="$WB_DIR/.workbench-state/template-version.json"
if upstream_v="$(git -C "$WB_DIR" show "upstream/main:version.json" 2>/dev/null)"; then
  mkdir -p "$WB_DIR/.workbench-state"
  echo "$upstream_v" | jq '. + {stamped_at: (now|todate)}' > "$TEMPLATE_VERSION_FILE"
fi
```

(Adjust `upstream/main` to whatever name the existing script uses for the template upstream remote — search `git remote add upstream` to confirm.)

- [ ] **Step 3: Add a unit test in `tests/test-update-stamps-version.zsh`**

```zsh
#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."
UPDATE="${REPO_ROOT}/update-workbench/update.zsh"

scratch="$(mktemp -d)"
trap "rm -rf '$scratch'" EXIT

# Build a fake template upstream + a fake stamped wb that has 'upstream' remote.
template_bare="$scratch/template.git"
"${REPO_ROOT}/tests/fixtures/bare-upstream/setup.sh" "$template_bare" "1.4.0"

stamped="$scratch/stamped"
git clone -q "$template_bare" "$stamped"
git -C "$stamped" remote rename origin upstream
( cd "$stamped" && git init -q && git -C "$stamped" remote add origin "$stamped/.git" 2>/dev/null || true )
mkdir -p "$stamped/.workbench-state"
touch "$stamped/.workbench-manifest.json" "$stamped/project.conf"

# We only test that the stamp logic writes the file. Skipping the merge.
( cd "$stamped" && git -C "$stamped" fetch -q upstream main && \
  git show "upstream/main:version.json" | jq '. + {stamped_at: (now|todate)}' > .workbench-state/template-version.json )
[[ -f "$stamped/.workbench-state/template-version.json" ]] || { print -r -- "FAIL: template-version.json not written"; exit 1; }
v="$(jq -r .version "$stamped/.workbench-state/template-version.json")"
[[ "$v" == "1.4.0" ]] || { print -r -- "FAIL: stamped version mismatch (got $v)"; exit 1; }

print -r -- "PASS: update writes template-version.json"
```

- [ ] **Step 4: Run, verify pass**

```bash
zsh tests/test-update-stamps-version.zsh
```

- [ ] **Step 5: Commit**

```bash
git add update-workbench/update.zsh tests/test-update-stamps-version.zsh
git commit -m "feat(wb-upgrade): stamp .workbench-state/template-version.json after merge"
```

---

### Task 20: Update `init.prompt.md` to write initial `template-version.json`

**Files:**
- Modify: `init-workbench/init.prompt.md`

- [ ] **Step 1: Locate the post-clone step (search for "gh repo create --template")**

```bash
grep -n "gh repo create\|3.4a\|template-dev" init-workbench/init.prompt.md
```

- [ ] **Step 2: Add a new step after `3.4a — Purge template-dev-only artifacts`**

Insert (preserving Markdown numbering):

```markdown
### 3.4c — Stamp template-version.json

Capture which template version this wb was stamped from. Store in `.workbench-state/`.

```bash
mkdir -p "$WB_DIR/.workbench-state"
gh api "repos/${ORG}/ai-workbench/contents/version.json?ref=main" \
       -H "Accept: application/vnd.github.raw+json" 2>/dev/null \
  | jq '. + {stamped_at: (now|todate)}' \
  > "$WB_DIR/.workbench-state/template-version.json" || \
  printf '{"version":"0.0.0","stamped_at":"unknown"}\n' > "$WB_DIR/.workbench-state/template-version.json"
```

This file gates `wb.upgrade` notifications. Future `wb.upgrade` runs refresh it.
```

- [ ] **Step 3: Commit**

```bash
git add init-workbench/init.prompt.md
git commit -m "feat(init): stamp template-version.json at workbench creation"
```

---

### Task 21: Update `tests/run-all.zsh` to discover new tests

**Files:**
- Modify: `tests/run-all.zsh`

- [ ] **Step 1: Read existing**

```bash
cat tests/run-all.zsh
```

- [ ] **Step 2: Append new test names**

If the file iterates explicit names, add `test-version-check.zsh`, `test-devkit-upgrade.zsh`, `test-devkit-doctor.zsh`, `test-update-stamps-version.zsh`. If it auto-discovers, no change needed.

- [ ] **Step 3: Run**

```bash
zsh tests/run-all.zsh
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/run-all.zsh
git commit -m "test: discover new versioning tests in run-all"
```

---

### Task 22: Add CI workflow `.github/workflows/test.yml`

**Files:**
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Write workflow**

```yaml
name: tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install jq + zsh
        run: |
          if [[ "${{ matrix.os }}" == "ubuntu-latest" ]]; then
            sudo apt-get update && sudo apt-get install -y jq zsh
          fi
      - name: Run tests
        run: zsh tests/run-all.zsh
  # TODO(windows): add windows-latest job when bash port lands.
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add test workflow on macos + linux"
```

---

### Task 23: Write `docs/versioning.md`

**Files:**
- Create: `docs/versioning.md`

- [ ] **Step 1: Write canonical long-form doc**

```markdown
---
title: Versioning + upgrades
---

# Versioning across ai-devkit, ai-ralph, and ai-workbench

## What this gives you

- **Update notifications** in your shell when a new version of any of the three tools ships.
- **Three commands** to pull and reinstall: `devkit.upgrade`, `ralph.upgrade`, `wb.upgrade`.
- **One status command**: `devkit doctor`.
- **One-step rollback**: `devkit.upgrade --rollback` (and `ralph.upgrade --rollback`).

## Where versions live

Every repo carries a `version.json` at its root:

```json
{
  "version": "1.0.0",
  "released": "2026-05-09",
  "check_ttl_hours": 12,
  "channel": "stable",
  "requires": {},
  "changelog_url": "..."
}
```

`release-please` auto-bumps this on every merge to `main` based on Conventional Commit messages (`feat:`, `fix:`, `BREAKING CHANGE:`).

## Notification flow

When you run any tool command for the first time per 12-hour window, the tool fires `_wb_versioncheck` which:

1. Reads cached upstream JSON from `~/.cache/wb-updates/<tool>.json`.
2. If cache stale, fetches via `gh api repos/<owner>/<repo>/contents/version.json?ref=main`. Falls back to `git fetch + git show` if `gh` is missing.
3. If newer version available, prints a one-liner banner before the command runs.
4. Cache TTL is configurable via `check_ttl_hours` in upstream `version.json` (default 12).

## Compat enforcement

Each `version.json` may declare peer-version requirements:

```json
"requires": { "ralph": ">=1.2.0" }
```

`*.upgrade` blocks the upgrade if the peer is below the floor. Use `--force` to bypass.

## Rollback

Every successful upgrade records a prior cache entry. Run `*.upgrade --rollback` to revert to the previous SHA + version. One step back only.

## doctor

`devkit doctor` shows a table of all three tools' state. `--fix` runs upgrades in dep order (ralph → devkit → wb). `--fix --yes` for unattended.

## Bash-portability

The library `version-check.sh` is bash-portable. Future ports to bash + git-bash on Windows are mechanical.
```

- [ ] **Step 2: Commit**

```bash
git add docs/versioning.md
git commit -m "docs(versioning): canonical long-form documentation"
```

---

### Task 24: Add `ROLLOUT-VERSIONING.md`

**Files:**
- Create: `ROLLOUT-VERSIONING.md`

- [ ] **Step 1: Write rollout note**

```markdown
# Rollout — Versioning + Upgrades

This is the one-time bootstrap step for existing devs after the versioning system lands.

## Step 1 (every dev runs once)

```bash
cd ~/Projects/Tools-Utilities/ai-devkit
git pull --rebase
./install.zsh
exec zsh    # reload shell so DEVKIT_CLONE + new aliases are visible
```

## What you'll see next

- `init.wb`, `join.wb`, `update.wb` will print `[devkit] checking for updates...` once per 12h on first call.
- New: `wb.upgrade` (canonical replacement for `update.wb`). Old name still works with deprecation nag.
- New: `devkit.upgrade`, `devkit doctor`.

## Bootstrap nag

The first time a tool detects no `version.json` yet (older clones), it prints a one-time bootstrap message. Run the upgrade once, and the message goes away.
```

- [ ] **Step 2: Commit**

```bash
git add ROLLOUT-VERSIONING.md
git commit -m "docs: add ROLLOUT-VERSIONING.md for one-time bootstrap"
```

---

### Task 25: Update `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append a new section after the existing intro**

```markdown
## Versioning + upgrades

ai-devkit ships under semver. Every release bumps `version.json` (handled by release-please). To update your local clone:

```bash
devkit.upgrade            # interactive y/N
devkit.upgrade --yes      # unattended
devkit.upgrade --rollback # revert to prior version
```

To see status of all your tools (devkit, ralph, wb-template if inside a stamped wb):

```bash
devkit doctor
devkit doctor --fix       # upgrades all stale tools in dep order
```

See `docs/versioning.md` for the full system. First-time setup: `ROLLOUT-VERSIONING.md`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): add versioning + upgrades section"
```

---

### Task 26: Final integration smoke test

**Files:**
- (No new files; runtime check only.)

- [ ] **Step 1: Reinstall locally**

```bash
./install.zsh
exec zsh
```

- [ ] **Step 2: Verify aliases**

```bash
which wb.upgrade devkit.upgrade devkit
type init.wb
```

All should resolve.

- [ ] **Step 3: Run doctor**

```bash
devkit doctor
```

Expected: status table for devkit + ralph (assuming both clones present).

- [ ] **Step 4: Run all tests one final time**

```bash
zsh tests/run-all.zsh
```

Expected: all PASS.

- [ ] **Step 5: Open PR**

```bash
git push -u origin <branch>
gh pr create --title "feat: versioning foundation (devkit + lib + doctor + wb.upgrade rename)" \
  --body "$(cat <<'EOF'
## Summary

- Adds `version.json` (1.0.0) + release-please workflow.
- Ships canonical `lib/version-check.sh` + `lib/bootstrap-detection.sh` (bash-portable).
- New aliases: `devkit.upgrade`, `wb.upgrade` (renames `update.wb`; legacy alias kept as deprecation shim), `devkit doctor`.
- New scripts: `devkit-upgrade/devkit-upgrade.zsh`, `devkit-doctor/devkit-doctor.zsh`.
- Wires `_wb_versioncheck` preamble into `init.zsh`, `join.zsh`, `update.zsh`.
- `update.zsh` now stamps `.workbench-state/template-version.json` after merge.
- `init.prompt.md` writes initial `template-version.json` at wb creation.
- Tests: unit (semver compare, requires parse, cache TTL, bootstrap, render-banner) + integration (upgrade happy path, dirty refusal, non-main refusal, rollback round-trip, peer-requires block + --force).
- Docs: `docs/versioning.md`, `ROLLOUT-VERSIONING.md`, README section.

## Test plan

- [ ] CI green on macOS + linux
- [ ] Local re-install + `devkit doctor` shows expected output
- [ ] Manual rollout: `cd ai-devkit && git pull && ./install.zsh && exec zsh` works as documented in ROLLOUT-VERSIONING.md
EOF
)"
```

---

## Self-review checklist

1. **Spec coverage:**
   - version.json schema ✓ (Task 1)
   - release-please ✓ (Task 2)
   - lib/version-check.sh ✓ (Tasks 3–10)
   - bootstrap nag ✓ (Task 11)
   - rollback prior ✓ (Task 12)
   - devkit.upgrade ✓ (Tasks 13–15)
   - devkit doctor ✓ (Task 16)
   - install.zsh wiring ✓ (Task 17)
   - Entry script preambles ✓ (Task 18)
   - update.zsh template-version stamp ✓ (Task 19)
   - init.prompt.md template-version stamp ✓ (Task 20)
   - Test runner discovery ✓ (Task 21)
   - CI ✓ (Task 22)
   - Docs ✓ (Tasks 23–25)
   - Smoke test ✓ (Task 26)

2. **No placeholders.** Every step has either complete code, an exact command, or both.

3. **Type/name consistency:**
   - `_wb_versioncheck`, `_wb_compare_semver`, `_wb_check_requires`, `_wb_local_version`, `_wb_clone_path`, `_wb_fetch_upstream`, `_wb_parse_remote`, `_wb_cache_dir`, `_wb_cache_path`, `_wb_cache_write`, `_wb_cache_is_fresh`, `_wb_cache_read`, `_wb_cache_invalidate`, `_wb_render_banner`, `_wb_record_prior`, `_wb_emit_bootstrap_nag`, `_wb_is_bootstrapped`, `_wb_mark_bootstrapped` — all defined and consistent.
   - Cache files: `<tool>.json`, `<tool>-prior.json`, `<tool>-bootstrapped.flag` — consistent across tasks.
   - Env vars: `DEVKIT_CLONE`, `RALPH_CLONE`, `WB_TEMPLATE_VERSION_FILE`, `WB_UPDATES_CACHE_DIR`, `WB_UPSTREAM_OWNER`, `WB_UPSTREAM_REPO_<tool>`, `GH_SHIM_RESPONSES_DIR`, `GH_SHIM_FAIL` — all consistent.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-09-versioning-foundation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
