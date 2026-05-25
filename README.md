# ai-devkit

Global CLI for engineers and QAs that provisions and maintains two flavors of workbench:

1. **Planning workbench** (`ai-workbench`) — PRDs, eng specs, TDDs, BDDs, test cases, ralph fix-plan. Per-epic bundle of repos + prompts + MCP wiring.
2. **Test-automation workbench** (`ai-test-automation-workbench`) — Playwright + POM + custom HTML reporter + lifecycle gate + Zephyr Scale export. Per-application test repo with `auto.wb.*` aliases and a steering library.

Both are driven end-to-end by an AI agent (Devin or Claude). One machine-wide install. Six commands. No per-project setup.

---

## Install

```zsh
git clone https://github.com/amit-t/ai-devkit ~/Projects/Tools-Utilities/ai-devkit
cd ~/Projects/Tools-Utilities/ai-devkit
./install.zsh
source ~/.zshrc
```

The installer:

- symlinks all six commands into `~/.local/bin/`
- registers zsh aliases (including `.dev` / `.cly` agent-forcing variants)
- warns if `~/.local/bin` is not on your `PATH`

Run once per machine. After that, the commands are available from any directory.

---

## Commands

### Planning workbench (`ai-workbench`)

| Command                   | Role      | Default agent                          | Force variants                   |
| ------------------------- | --------- | -------------------------------------- | -------------------------------- |
| `init.wb`                 | Initiator | Devin (falls back to Claude)           | `init.wb.dev`, `init.wb.cly`     |
| `join.wb <workbench-url>` | Joiner    | Devin (falls back to Claude)           | `join.wb.dev`, `join.wb.cly`     |
| `update.wb`               | Either    | Devin (only if interactive conflict)   | `update.wb.dev`, `update.wb.cly` |
| `wb.rescan`               | Either    | Devin (falls back to Claude)           | `--agent devin\|claude` override |

- **Auto-built repo context** — `init.wb` and `join.wb` produce
  `context/<repo>/CONTEXT.md` per registered source repo, plus an
  aggregate `context/README.md` index. Source repos are never mutated
  (scans run in a throwaway `git worktree` sandbox). Failed scans
  degrade to a stub; refresh or repair with `wb.rescan`. See
  [docs/repo-context-scan.md](docs/repo-context-scan.md).

### Test-automation workbench (`ai-test-automation-workbench`)

| Command                          | Role      | Default agent                          | Force variants                              |
| -------------------------------- | --------- | -------------------------------------- | ------------------------------------------- |
| `init.auto.wb`                   | Initiator | Devin (falls back to Claude)           | `init.auto.wb.dev`, `init.auto.wb.cly`     |
| `join.auto.wb <workbench-url>`   | Joiner    | Devin (falls back to Claude)           | `join.auto.wb.dev`, `join.auto.wb.cly`     |
| `update.auto.wb`                 | Either    | Devin (only if interactive conflict)   | `update.auto.wb.dev`, `update.auto.wb.cly` |

All commands launch the configured agent with a role-specific prompt. The agent handles the interview, repo creation, templating, and git operations; the shell scripts are thin launchers.

`orgs.wb` is a shared helper that manages the GitHub org list both flavors of `init.*` use during repo creation.

---

## Quickstart

### Planning workbench — start a new bundle

Typical use: a QA spinning up a workbench for a new epic.

```zsh
mkdir ~/workbenches/wb-example && cd ~/workbenches/wb-example
init.wb
```

The agent asks for: label, epics, repos, Figma refs, and MCPs. It creates a private GitHub repo, pushes the workbench, and hands you a share URL for collaborators.

### Test-automation workbench — stand up a new test repo

Typical use: an engineer scaffolding Playwright automation for a new application.

```zsh
cd ~/repos
init.auto.wb
```

The agent picks the org, creates the repo from the `ai-test-automation-workbench` template, clones it, and runs the in-repo `playwright-agents-bootstrap` skill that substitutes app-specific placeholders (app name, URL, auth flavor, default env/role). Inside the new repo, `source aliases.sh` activates the `auto.wb.*` devkit (lifecycle, steering, adoption, test execution).

### Joining either flavor

```zsh
cd ~/workbenches
join.wb https://github.com/<your-org>/wb-example                  # planning side
join.auto.wb https://github.com/<your-org>/acme-playwright-agents # test side
```

The joiner agent clones the repo, adds you to CODEOWNERS, installs deps, commits, and pushes.

### Updates — pull template changes safely

```zsh
cd ~/workbenches/wb-example         # planning instance
update.wb

cd ~/repos/acme-playwright-agents   # test-automation instance
update.auto.wb
```

`update.wb` reads `.workbench-manifest.json`. `update.auto.wb` reads `.auto-wb-manifest.json`. Each pulls only template-owned files from the corresponding upstream template. User-owned paths (your outputs, configs, local state, plans, test-cases, specs) are never touched.

---

## Requirements

- **`gh`** — authenticated against GitHub. HTTPS and SSH (including custom hostnames) both supported.
- **`git`**, **`rsync`**, **`python3`**, **`zsh`** — standard on macOS; install via your package manager on Linux.
- **`devin`** CLI (preferred) or **`claude`** CLI. Use `.cly` variants to force Claude when both are installed.

---

## Layout

```
ai-devkit/
├── install.zsh                # one-shot installer
├── init-workbench/            # init.wb  → ai-workbench template
├── join-workbench/            # join.wb
├── update-workbench/          # update.wb (interactive prompt only on conflict)
├── init-test-workbench/       # init.auto.wb  → ai-test-automation-workbench template
├── join-test-workbench/       # join.auto.wb
├── update-test-workbench/     # update.auto.wb (interactive prompt only on conflict)
├── orgs-workbench/            # orgs.wb (shared org list helper)
├── lib/                       # orgs.sh + other shared helpers
└── tests/                     # zsh regression tests (run via tests/run-all.zsh)
```

Each `*-workbench/` directory pairs a short zsh launcher with the prompt that drives the agent. Update a prompt, and every user of that command picks up the change on their next run.

---

## Tests

```zsh
zsh tests/run-all.zsh
```

Covers the regressions Devin has flagged in past runs (e.g. `orgs.wb` PATH/symlink resolution, `init.wb` Step 3.10b `.ralph/` rebuild). Add a new `tests/test-*.zsh` whenever a fix lands.

---

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

---

## Running on WSL2

WSL2 Ubuntu is a supported environment. Install the minimum prereqs:

```bash
sudo apt install -y zsh jq gh git curl
```

Clone repos under `$HOME` (not under `/mnt/c/` or any other DrvFs mount). DrvFs paths are roughly 10x slower than the WSL2 ext4 filesystem and they break fsync semantics that ralph and git rely on. The [`devkit-doctor`](devkit-doctor/devkit-doctor.zsh) preflight will warn (`check_wsl_mnt_path`) if you run `devkit doctor` from a `/mnt/` path.

The installer accepts a non-interactive mode (used by CI in `.github/workflows/smoke-install.yml`):

```bash
DEVKIT_NONINTERACTIVE=1 zsh install.zsh
# or
zsh install.zsh --yes
```

In non-interactive mode any prompt accepts the safe default (org slug falls back to `$DEVKIT_DEFAULT_ORG` or the current git remote owner, optional installs default to yes). Interactive TTY behaviour without the flag or env var is unchanged.

---

## Related

- [`ai-workbench`](https://github.com/amit-t/ai-workbench) — planning workbench template (PRDs, eng specs, TDDs).
- [`ai-test-automation-workbench`](https://github.com/Invenco-Cloud-Systems-ICS/ai-test-automation-workbench) — Playwright test-automation template (POM, lifecycle, Zephyr CSV).
- [`ai-ralph`](https://github.com/Invenco-Cloud-Systems-ICS/ai-ralph) — autonomous loop runner (used by both workbenches for long-running fix-plan execution).
