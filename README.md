# ai-devkit

Global CLI for engineers and QAs that provisions and maintains **ai-workbench** instances — self-contained bundles of repos, prompts, Figma refs, and MCP wiring that an AI agent (Devin or Claude) can drive end-to-end.

One machine-wide install. Three commands. No per-project setup.

---

## Install

```zsh
git clone https://github.com/amit-t/ai-devkit ~/Projects/Tools-Utilities/ai-devkit
cd ~/Projects/Tools-Utilities/ai-devkit
./install.zsh
source ~/.zshrc
```

The installer:

- symlinks `init.wb`, `join.wb`, `update.wb` into `~/.local/bin/`
- registers zsh aliases (including `.dev` / `.cly` agent-forcing variants)
- warns if `~/.local/bin` is not on your `PATH`

Run once per machine. After that, the commands are available from any directory.

---

## Commands

| Command                    | Role      | Default agent                              | Force variants                     |
| -------------------------- | --------- | ------------------------------------------ | ---------------------------------- |
| `init.wb`                  | Initiator | Devin (falls back to Claude)               | `init.wb.dev`, `init.wb.cly`       |
| `join.wb <workbench-url>`  | Joiner    | Devin (falls back to Claude)               | `join.wb.dev`, `join.wb.cly`       |
| `update.wb`                | Either    | Devin (only if interactive conflict)       | `update.wb.dev`, `update.wb.cly`   |

All three commands launch the configured agent with a role-specific prompt. The agent handles the interview, repo creation, templating, and git operations — the shell scripts are thin launchers.

---

## Quickstart

### 1. Initiator — start a new bundle

Typical use: a QA spinning up a workbench for a new epic.

```zsh
mkdir ~/workbenches/wb-example && cd ~/workbenches/wb-example
init.wb
```

The agent will ask for: label, epics, repos, Figma refs, and MCPs. When it's done it creates a private GitHub repo, pushes the workbench, and hands you a share URL for collaborators.

### 2. Joiner — pick up an existing bundle

Typical use: a dev joining the QA's workbench.

```zsh
cd ~/workbenches
join.wb https://github.com/<your-org>/wb-example
```

The agent clones the workbench, asks which additional repos you need for your work, appends them to `project.conf`, adds you to `CODEOWNERS`, commits, and pushes.

### 3. Updates — pull template changes safely

```zsh
cd ~/workbenches/wb-example
update.wb
```

Pulls only template-owned files from `ai-workbench`. Your outputs, configs, and local state are never touched.

---

## Requirements

- **`gh`** — authenticated against GitHub. HTTPS and SSH (including custom hostnames) both supported.
- **`git`**, **`rsync`**, **`python3`**, **`zsh`** — standard on macOS; install via your package manager on Linux.
- **`devin`** CLI (preferred) or **`claude`** CLI. Use `.cly` variants to force Claude when both are installed.

---

## Layout

```
ai-devkit/
├── install.zsh              # one-shot installer
├── init-workbench/          # init.zsh  + init.prompt.md
├── join-workbench/          # join.zsh  + join.prompt.md
└── update-workbench/        # update.zsh + update.prompt.md (interactive only)
```

Each subdirectory pairs a short zsh launcher with the prompt that drives the agent. Update a prompt, and every user of that command picks up the change on their next run.

---

## Related

Part of the [ai-workbench](https://github.com/amit-t/ai-workbench) ecosystem.
