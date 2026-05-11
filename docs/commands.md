---
title: Commands
layout: default
eyebrow: Reference
subtitle: init.wb · join.wb · wb.upgrade · orgs.wb · devkit.upgrade · ralph.upgrade · devkit doctor
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

## wb.upgrade

Refresh a workbench from the template. Canonical replacement for `update.wb`.

```
wb.upgrade                    # inside a workbench directory
wb.upgrade --agent devin
wb.upgrade --agent claude
```

Pulls updates from the `ai-workbench` template upstream, applying changes to `template_owned` paths listed in `.workbench-manifest.json`. User-authored artifacts (PRDs, specs, BDD, test cases) are left untouched.

After the merge, `wb.upgrade` writes the upstream version into `.workbench-manifest.json` so `devkit doctor` can report workbench state correctly.

### update.wb (deprecated)

`update.wb` still works and runs the same flow, but prints a one-line deprecation nag pointing at `wb.upgrade`. Use the new name in scripts and docs.

## devkit.upgrade

Pull a newer release of the `ai-devkit` clone and reinstall.

```
devkit.upgrade                  # interactive
devkit.upgrade --yes            # unattended (no prompt)
devkit.upgrade --rollback       # revert one step
devkit.upgrade --force          # bypass peer-version requires
devkit.upgrade --skip-install   # pull only, do not run install.zsh
```

Flow:

1. Verifies the `ai-devkit` clone has a clean working tree and is on `main`.
2. Checks peer-version `requires` from `version.json`. If a peer is below the floor, refuses with a clear message. Use `--force` to bypass.
3. Records the prior commit + version into the per-tool cache so `--rollback` can revert.
4. `git pull --ff-only` and re-runs `install.zsh` to refresh aliases.
5. Prints the new version and a reload hint (`exec zsh`).

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Upgrade succeeded (or already current). |
| 1 | Abort by user, or `--rollback` with no prior recorded. |
| 2 | Working tree dirty, or not on `main`. |
| 3 | Peer-version requirement not satisfied (use `--force` to bypass). |

## ralph.upgrade

Same shape as `devkit.upgrade`, applied to the `ai-ralph` clone.

```
ralph.upgrade
ralph.upgrade --yes
ralph.upgrade --rollback
ralph.upgrade --force
ralph.upgrade --skip-install
```

Same exit codes as `devkit.upgrade`.

## devkit doctor

Show version state for all three tools, optionally upgrade them in dependency order.

```
devkit doctor                   # status table only
devkit doctor --check-only      # exit 4 if anything behind (CI gate)
devkit doctor --fix             # interactive upgrade in dep order
devkit doctor --fix --yes       # unattended upgrade
```

Status table shape:

```
Tool          Local    Latest   Status
ai-devkit     1.0.0    1.0.0    up to date
ai-ralph      0.9.0    1.1.0    upgrade available
ai-workbench  1.0.0    1.0.0    up to date
```

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | All up to date (or `--fix` succeeded). |
| 4 | `--check-only` and at least one tool is behind. |

`--fix` runs upgrades in this order: `ralph.upgrade`, then `devkit.upgrade`, then `wb.upgrade`. If any step fails it stops and surfaces the failing tool's exit code.

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
