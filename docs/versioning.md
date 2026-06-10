---
title: Versioning + Upgrades
layout: default
eyebrow: Reference
subtitle: Update notifications, in-place upgrades, rollback, and doctor.
---
{% include links.html %}

## What you get

Three things ship together as the versioning system across `ai-devkit`,
`ai-ralph`, and `ai-workbench`:

1. **Update notifications.** Each tool prints a one-line banner once per
   12 hours when a newer version exists upstream. The banner runs before
   your command, never blocks it, and is silent when you are current.
2. **In-place upgrades.** A small set of upgrade commands pulls the
   latest tag from `main`, reinstalls, and reports the new version.
3. **A status command.** `devkit doctor` shows the version state of all
   three tools at a glance and offers a guided fix.

## Where versions live

Every repo carries a `version.json` at its root. Example:

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

`release-please` bumps this file on every merge to `main` based on
Conventional Commit messages (`feat:`, `fix:`, `BREAKING CHANGE:`), so
the version that ships is the one users actually see.

Release authority is the `amit-t/*` origin repo only. Mirror remotes such
as `Invenco-Cloud-Systems-ICS/*` do not run release-please. After origin
opens and merges the release PR, sync that bump commit, tag, and GitHub
release into each mirror.

## The three upgrade commands

| Command | Repo it upgrades | Typical use |
|---------|------------------|-------------|
| `devkit.upgrade` | `ai-devkit` clone | Get newer `init.wb`, `join.wb`, `update.wb`, `orgs.wb`. |
| `ralph.upgrade`  | `ai-ralph` clone  | Get newer autonomous-loop runtime (Claude / Devin / Codex). |
| `wb.upgrade`     | The current workbench | Refresh template-owned files inside a workbench (canonical replacement for `update.wb`). |

Each command:

1. Verifies the working tree is clean and on `main`.
2. Checks the peer-version `requires` field before pulling.
3. Pulls, reinstalls, and prints the new version.
4. Records the prior commit so `--rollback` can revert one step.

`update.wb` still works but prints a deprecation nag pointing at
`wb.upgrade`. Use the new name in scripts and docs.

## devkit doctor

```bash
devkit doctor
```

Prints a status table for all three tools:

| Tool | Local | Latest | Status |
|------|-------|--------|--------|
| `ai-devkit`   | 1.0.0 | 1.0.0 | up to date |
| `ai-ralph`    | 0.9.0 | 1.1.0 | upgrade available |
| `ai-workbench` | 1.0.0 | 1.0.0 | up to date |

Useful flags:

- `--check-only` exits non-zero (code 4) when anything is behind. Good
  for CI gates that should block until the dev runs an upgrade.
- `--fix` runs the upgrades in dependency order: `ralph` first, then
  `devkit`, then `wb`.
- `--fix --yes` runs the same flow without prompting (unattended).

## Rollback

Each successful upgrade records the prior commit SHA and version into a
small per-tool cache file. To revert one step:

```bash
devkit.upgrade --rollback
ralph.upgrade --rollback
```

Rollback restores the previous SHA, reinstalls from that commit, and
restores the prior `version.json`. Only the most recent upgrade is
reversible (one step back, not a full history).

`wb.upgrade` does not expose `--rollback` because workbench updates flow
through the existing `update.wb` template-merge path; revert by
reverting the merge commit inside the workbench repo.

## One-time bootstrap (existing devs)

If your `ai-devkit` clone predates the versioning release, run the
bootstrap step once:

```bash
cd ~/Projects/Tools-Utilities/ai-devkit
git pull
./install.zsh
exec zsh
```

`install.zsh` writes `DEVKIT_CLONE` into `~/.zprofile` (idempotent and
relocation-safe), installs the new aliases (`devkit.upgrade`,
`ralph.upgrade`, `wb.upgrade`, `devkit doctor`), and seeds the cache.
`exec zsh` reloads the shell so the new aliases are on PATH.

The first run of any tool after bootstrap may print a one-time
"bootstrap nag" if no `version.json` is detected locally. Run the
upgrade once and the nag goes away.

## Compatibility checks

A tool can declare peer-version requirements in its `version.json`:

```json
"requires": { "ralph": ">=1.2.0" }
```

If the peer is below the floor, the upgrade is blocked and you see:

```
[devkit] cannot upgrade: requires ralph >=1.2.0, found 1.1.0.
        Run ralph.upgrade first or pass --force.
```

`--force` bypasses the floor for advanced cases (testing a pre-release,
recovering from a broken peer install). Default behaviour blocks so
that incompatible combinations are not silently produced.

## Failure modes

The upgrade commands fail loudly and predictably:

| Situation | What happens |
|-----------|--------------|
| Working tree dirty | Refused. Commit or stash, then retry. Exit 2. |
| Not on `main`      | Refused. Switch to `main`, then retry. Exit 2. |
| Peer-requires not met | Refused with the offending peer + floor printed. Exit 3. Use `--force` to bypass. |
| Offline (no network) | Notification check is skipped silently. Cache TTL keeps you from spamming retries. Upgrade itself surfaces the underlying `git fetch` error. |
| `gh` not on PATH | Notification check falls back to `git fetch` + `git show <ref>:version.json`. Upgrade itself does not require `gh`. |
| `--rollback` with no prior recorded | Refused with a clear message. Exit 1. |
| `devkit doctor --check-only` finds anything behind | Exit 4 (CI-friendly). |

## doctor + upgrade in CI

`devkit doctor --check-only` is the canonical CI gate. Pair it with a
job that fails the build when anything is behind, so PR authors are
nudged to run the upgrade locally before pushing.

```yaml
- name: devkit doctor
  run: devkit doctor --check-only
```

## Related

- [Getting Started]({{ '/getting-started.html' | relative_url }}): install + first workbench.
- [Commands]({{ '/commands.html' | relative_url }}): full CLI reference, including the new aliases.
- [`ai-ralph`]({{ links.ai_ralph_repo }}): autonomous loop runtime.
- [`ai-workbench`]({{ links.ai_workbench_pages }}): template the workbench is stamped from.
