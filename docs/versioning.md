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
