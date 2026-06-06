---
title: Getting Started
layout: default
eyebrow: Setup
subtitle: Clone, install, first workbench.
---
{% include links.html %}

## Prerequisites

| CLI | Purpose |
|-----|---------|
| `git` | Version control |
| `gh` | GitHub CLI — repo creation, auth, API calls |
| `rsync` | Template-owned file sync during `update.wb` |
| `python3` | Manifest rendering |

Optional but recommended:

- [`ai-ralph`]({{ links.ai_ralph_repo }}) — installed automatically by `init.wb` / `join.wb` on first run per machine.
- `devin` or `claude` CLI — drives the interview agent. Devin by default, Claude as fallback.

## Install

```bash
git clone {{ links.ai_devkit_clone }} ~/Projects/Tools-Utilities/ai-devkit
cd ~/Projects/Tools-Utilities/ai-devkit
./install.zsh
```

`install.zsh` symlinks the workbench commands into `~/.local/bin/` and appends aliases to `~/.zshrc`:

| Command | Alias Variants | Purpose |
|---------|----------------|---------|
| `init.wb` | `init.wb.dev`, `init.wb.cly` | Create new workbench |
| `join.wb` | `join.wb.dev`, `join.wb.cly` | Join existing workbench |
| `wb.upgrade` | `wb.upgrade.dev`, `wb.upgrade.cly` | Pull template updates (replaces `update.wb`) |
| `update.wb` | (deprecated) | Old name for `wb.upgrade`; still works, prints a nag |
| `orgs.wb` | (none) | Manage GitHub org list |
| `devkit.upgrade` | (none) | Pull a newer `ai-devkit` release and reinstall |
| `ralph.upgrade` | (none) | Pull a newer `ai-ralph` release and reinstall |
| `devkit doctor` | (none) | Show version state for all three tools; offers `--fix` |

The `.dev` variants force the Devin agent, `.cly` variants force Claude.

Ensure `~/.local/bin` is on `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"   # add to ~/.zshrc if missing
source ~/.zshrc
```

### One-time bootstrap (existing clones)

If you cloned `ai-devkit` before the versioning release, run the bootstrap step once so the new aliases (`devkit.upgrade`, `ralph.upgrade`, `wb.upgrade`, `devkit doctor`) become available:

```bash
cd ~/Projects/Tools-Utilities/ai-devkit
git pull
./install.zsh
exec zsh
```

`install.zsh` is idempotent: re-running it will not duplicate alias lines or `DEVKIT_CLONE` exports. After `exec zsh`, the new commands are on PATH and the first run of any tool will perform a one-time version-check banner. See [Versioning + upgrades]({{ '/versioning.html' | relative_url }}) for details.

## First Workbench

```bash
mkdir -p ~/work && cd ~/work
init.wb
```

`init.wb` runs preflight (CLI checks, `gh` account confirmation, org picker, `ai-ralph` install if needed), then interviews you for:

- workspace label (kebab-case)
- Jira epic IDs
- code repos to register (name / url / role / stack)
- design references (optional)
- MCP servers to enable (Atlassian / Figma / none)

Then it creates `${ORG}/workbench-<label>` (legacy workbenches use the older `wb-<label>` prefix and remain fully supported), clones registered code repos into `repos/`, renders `project.conf` + `EPIC-PIPELINE.md`, writes CODEOWNERS, runs Ralph setup, commits, pushes.

For the Lite fast path, run:

```bash
init.wb --lite
```

Lite mode also installs `ralph-devin`, exposes `rpd` and `rpd.p` in the zsh login profile, enables Ralph in each `repos/<app>/`, and writes `WB_LITE_*` defaults into `project.conf`. Check it from a fresh shell with `command -v ralph-devin`, `command -v rpd`, and `command -v rpd.p`. To remove only the Lite shell profile block, run `init.wb --lite --undo`.

Output:

```
── Workbench initialized ────────────────────────────
  Label:      example
  Repo:       https://github.com/<org>/wb-example
  Path:       ~/work/wb-example
  ...
── Share with your counterpart ──────────────────────
  join.wb https://github.com/<org>/wb-example
```

## After init: explore context/

After `init.wb` finishes, your new workbench has a `context/` directory
with one `CONTEXT.md` per registered source repo, plus an aggregate
`context/README.md` index.

These files are devkit-generated domain summaries — they help agents
(and you) understand each repo at a glance without grepping the source.
Open them with your editor or skim the index:

```bash
cat context/README.md
cat context/<repo>/CONTEXT.md
```

A scan can fail (no HEAD in source, LLM crash, lock contention, etc.) —
failed scans leave a stub with `status: scan-failed` in the
frontmatter. Re-run with `wb.rescan <repo>` (or `wb.rescan --all`). See
[Repo Context Scan]({{ '/repo-context-scan.html' | relative_url }}) for
the full feature reference.

## Joining Someone Else's Workbench

```bash
cd ~/work
join.wb https://github.com/<org>/wb-example
```

Preflight runs, you get appended to CODEOWNERS, any extra repos you bring get registered into `project.conf`.

## Next Steps

- [Commands]({{ '/commands.html' | relative_url }}) — full CLI reference
- [Versioning + upgrades]({{ '/versioning.html' | relative_url }}): `devkit.upgrade`, `ralph.upgrade`, `wb.upgrade`, `devkit doctor`
- [Repo Context Scan]({{ '/repo-context-scan.html' | relative_url }}) — auto-built per-repo CONTEXT.md and `wb.rescan` recovery
- [Orgs]({{ '/orgs.html' | relative_url }}) — machine-local GitHub org list
- [ai-workbench docs]({{ links.ai_workbench_pages }}) — what lives inside the workbench template
- [ai-ralph README]({{ links.ai_ralph_repo }}) — autonomous loop engines
