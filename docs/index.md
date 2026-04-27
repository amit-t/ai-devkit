---
title: Home
layout: default
---
{% include links.html %}

## What ai-devkit Gives You

- **One-shot workbench bootstrap** — `init.wb` creates a private workbench repo from the `ai-workbench` template, wires CODEOWNERS, registers code repos, renders manifests.
- **Collaborator onboarding** — `join.wb <url>` clones the workbench, appends the joiner to CODEOWNERS, registers any extra repos they bring.
- **Template refresh** — `update.wb` pulls template-owned skill / config updates without touching your authored outputs.
- **Org list management** — `orgs.wb` (list/add/remove/show) keeps a machine-local GitHub org list. The org hosting your devkit checkout is auto-included.
- **Preflight hygiene** — both `init.wb` and `join.wb` verify required CLIs, confirm the active `gh` account, and offer switch / login flows before touching remote resources.
- **ai-ralph bootstrap** — on first run per machine, devkit clones and installs [`ai-ralph`]({{ links.ai_ralph_repo }}), then scopes `ralph-enable` to the new workbench only (never into sibling service repos).

## Three Repos, One Story

| Repo | Role |
|------|------|
| [`ai-devkit`]({{ links.ai_devkit_repo }}) | Global CLI. Provides `init.wb`, `join.wb`, `update.wb`, `orgs.wb`. |
| [`ai-workbench`]({{ links.ai_workbench_repo }}) | Template. `gh repo create --template` stamps an instance per bundle. |
| [`ai-ralph`]({{ links.ai_ralph_repo }}) | Autonomous AI loop (Claude Code, Devin, Codex). Enabled per workbench. |

## Quick Paths

- **Install the CLI?** Start at [Getting started]({{ '/getting-started.html' | relative_url }}).
- **Command reference?** See [Commands]({{ '/commands.html' | relative_url }}).
- **Manage GitHub orgs?** See [Orgs]({{ '/orgs.html' | relative_url }}).

## Typical Flow

```
install.zsh          → registers init.wb / join.wb / update.wb / orgs.wb globally
init.wb              → preflight → create wb-<label> repo → clone code repos → render manifests → ralph-enable
join.wb <url>        → preflight → clone workbench → add joiner to CODEOWNERS → register extra repos
update.wb            → pull template-owned updates into existing workbench
orgs.wb add <slug>   → expand machine-local GitHub org menu
```

## License

See repo license files.
