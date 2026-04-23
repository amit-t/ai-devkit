# ai-devkit

**Full docs:** https://amit-t.github.io/ai-workbench/

Global CLI for engineers and QAs. Provisions and maintains `ai-workbench` instances.

## Install (one time per machine)

```zsh
git clone https://github.com/amit-t/ai-devkit ~/Projects/Tools-Utilities/ai-devkit
cd ~/Projects/Tools-Utilities/ai-devkit
./install.zsh
source ~/.zshrc
```

Symlinks commands into `~/.local/bin/` and adds zsh aliases.

## Commands

| Command | Role | Default agent | Force variants |
|---------|------|---------------|----------------|
| `init.wb` | Initiator | Devin | `init.wb.dev`, `init.wb.cly` |
| `join.wb <workbench-url>` | Joiner | Devin | `join.wb.dev`, `join.wb.cly` |
| `update.wb` | Either | Devin (only if interactive conflict) | `update.wb.dev`, `update.wb.cly` |

## Quickstart

### Initiator (e.g. QA starting a new bundle)

```zsh
mkdir ~/workbenches/wb-example && cd ~/workbenches/wb-example
init.wb
# Devin asks: label, epics, repos, figma refs, MCPs.
# When done: gh-private repo created, workbench pushed, share URL with collaborator.
```

### Joiner (e.g. dev picking up the same bundle)

```zsh
cd ~/workbenches
join.wb https://github.com/<your-org>/wb-example
# Devin asks: additional repos to clone for your work.
# Appends to project.conf, adds you to CODEOWNERS, commits and pushes.
```

### Updates

```zsh
cd ~/workbenches/wb-example
update.wb       # pulls only template-owned files from ai-workbench; never touches your outputs
```

## Requirements

- `gh` CLI authenticated against GitHub (HTTPS or SSH with custom hostname — both supported).
- `git`, `rsync`, `python3`, `zsh`.
- `devin` CLI (default). `claude` CLI as fallback. Use `.cly` variants to force Claude.

## Layout

```
ai-devkit/
  install.zsh
  init-workbench/        # init.zsh + init.prompt.md
  join-workbench/        # join.zsh + join.prompt.md
  update-workbench/      # update.zsh + update.prompt.md (interactive only)
```

---

Part of the [ai-workbench](https://github.com/amit-t/ai-workbench) ecosystem. See the [docs site](https://amit-t.github.io/ai-workbench/) for end-to-end workflows.
