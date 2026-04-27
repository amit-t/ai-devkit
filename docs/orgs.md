---
title: Orgs
layout: default
eyebrow: Reference
subtitle: Machine-local GitHub org list for workbench bootstrap.
---

## Why

`init.wb` and `join.wb` need to know which GitHub org to create / clone repos under, and where `ai-ralph` lives. Rather than prompting for a free-text org every time, devkit keeps a small list in `orgs.conf` + auto-includes the org that hosts your `ai-devkit` checkout.

## Sources

The menu shown by `init.wb` Step 0d (and `join.wb` Step 0e) is the union of:

1. **Configured orgs** — lines in `orgs.conf` at the devkit root. Seeded with `Invenco-Cloud-Systems-ICS`.
2. **Auto-detected org** — parsed from `git remote get-url origin` inside the devkit checkout. Always included, never duplicated. Cannot be removed via `orgs.wb remove` (it will reappear).
3. **Personal** — always the last numbered slot. Picking it prompts for a GitHub handle at runtime.

## CLI

```
orgs.wb                 # list (default)
orgs.wb list            # one org per line
orgs.wb show            # numbered menu
orgs.wb add <slug>      # append to orgs.conf
orgs.wb remove <slug>   # remove line from orgs.conf
orgs.wb auto            # print auto-detected org only
orgs.wb path            # absolute path to orgs.conf
orgs.wb edit            # open orgs.conf in $EDITOR
```

### Example

```
$ orgs.wb show
  [1] Invenco-Cloud-Systems-ICS
  [2] amit-t
  [3] Personal (enter GitHub handle)

$ orgs.wb auto
amit-t

$ orgs.wb add acme-corp
added: acme-corp

$ orgs.wb show
  [1] Invenco-Cloud-Systems-ICS
  [2] acme-corp
  [3] amit-t
  [4] Personal (enter GitHub handle)
```

## orgs.conf Format

Plain text, one org slug per line. `#` starts a comment.

```
# ai-devkit org list
# One GitHub org slug per line. `#` starts a comment.
# The org that hosts this devkit checkout is always included automatically.

Invenco-Cloud-Systems-ICS
```

Edit directly or via `orgs.wb add / remove / edit`.

## Library

Both the CLI and the agent prompts consume `lib/orgs.sh`, which exposes:

| Function | Purpose |
|----------|---------|
| `devkit_orgs_file` | Path to `orgs.conf` |
| `devkit_auto_org` | Parse `origin` remote of devkit checkout |
| `devkit_orgs_list` | Print union (configured + auto), deduped |
| `devkit_orgs_add <slug>` | Append if missing |
| `devkit_orgs_remove <slug>` | Strip from file |
| `devkit_orgs_show` | Numbered menu (as init/join render) |

Agent prompts source it directly when `orgs.wb` isn't on `PATH`:

```bash
. "${DEVKIT_DIR}/lib/orgs.sh"
devkit_orgs_show
mapfile -t ORGS < <(devkit_orgs_list)
```
