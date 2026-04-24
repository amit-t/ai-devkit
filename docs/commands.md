---
title: Commands
layout: default
eyebrow: Reference
subtitle: init.wb · join.wb · update.wb · orgs.wb
---

## init.wb

Bootstrap a new workbench from the `ai-workbench` template.

```
init.wb                           # Devin by default; Claude fallback
init.wb --agent devin             # force Devin
init.wb --agent claude            # force Claude
init.wb --cwd /path/to/empty/dir  # override target directory
```

Runs preflight → interview → `gh repo create --template` → clones registered code repos → renders `project.conf` + `EPIC-PIPELINE.md` + `CODEOWNERS` → installs `ai-ralph` (once per machine) → scopes `ralph-enable` to the workbench only → commits + pushes.

**Preflight** (Step 0 in `init-workbench/init.prompt.md`):

- CLI presence (`git`, `gh`, `rsync`, `python3`)
- `gh auth status` + account confirmation; switch / login / quit options if wrong account active
- Codeowner notice — active `gh` login becomes CODEOWNER
- Org picker (see [Orgs]({{ '/orgs.html' | relative_url }}))
- `ai-ralph` global install if `ralph-enable` not on PATH

## join.wb

Onboard a collaborator to an existing workbench.

```
join.wb <workbench-url>
join.wb <workbench-url> --agent devin
join.wb <workbench-url> --agent claude
```

Runs preflight → clones workbench (or pulls if already local) → reads `project.conf` → prompts for extra repos to register → appends joiner to the `*` line in `CODEOWNERS` → commits + pushes.

**Preflight additions vs `init.wb`:**

- `gh repo view <url>` access probe — catches private-repo / wrong-account scenarios before any clone.
- No `ralph-enable` inside the workbench — initiator already committed `.ralph/` config; joiner only needs the global `ralph` install.

## update.wb

Refresh a workbench from the template.

```
update.wb                    # inside a workbench directory
update.wb --agent devin
update.wb --agent claude
```

Pulls updates from the `ai-workbench` template upstream, applying changes to `template_owned` paths listed in `.workbench-manifest.json`. User-authored artifacts (PRDs, specs, BDD, test cases) are left untouched.

## orgs.wb

Manage the machine-local GitHub org list used by `init.wb` / `join.wb`.

```
orgs.wb                 # list (default)
orgs.wb list            # print all orgs (configured + auto-detected)
orgs.wb show            # numbered menu (as init.wb / join.wb present it)
orgs.wb add <slug>      # append new org to orgs.conf
orgs.wb remove <slug>   # remove org from orgs.conf
orgs.wb auto            # print auto-detected org (from devkit's origin remote)
orgs.wb path            # print path to orgs.conf
orgs.wb edit            # open orgs.conf in $EDITOR
```

The org hosting your `ai-devkit` checkout (parsed from its `origin` remote) is always included in the list, even if not written to `orgs.conf`. See [Orgs]({{ '/orgs.html' | relative_url }}) for details.

## Agent Selection

All three workbench commands delegate to an interactive agent that runs the interview and executes the work under `--dangerously-skip-permissions` / dangerous-mode equivalents. Selection precedence:

1. Explicit `--agent devin` / `--agent claude`
2. Devin if `devin` CLI is on PATH
3. Claude if `claude` CLI is on PATH
4. Error otherwise

Aliases `*.wb.dev` / `*.wb.cly` pre-bind the agent.
