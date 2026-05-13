# WSL2 Port — ai-devkit (Wave 1 / foundation)

**Master plan:** `/Users/amittiwari/.claude/plans/all-scripts-in-workbench-glowing-iverson.md` (lives in the user's plan dir; this file is the repo-local slice for the Claude session driving ai-devkit's WSL port work)
**Wave:** 1 of 3 — **foundation**. Wave 2 (ai-ralph) and Wave 3 (ai-workbench) are downstream and depend on this wave's lib changes.
**Locked decisions:** WSL2 Ubuntu only target; `apt install zsh` required on WSL; `ubuntu-latest` CI = WSL proxy; sequential repos + phased PRs; non-breaking for existing macOS/zsh users.

---

## Scope (this repo only)

ai-devkit owns the shared library that ralph and wb source. It is the foundation: its lib changes unblock downstream waves.

In scope:
- `.gitattributes` — force LF (kill CRLF at clone time on Windows hosts)
- `.github/workflows/lint.yml` — new workflow (bash -n + zsh -n + shellcheck)
- `.github/workflows/smoke-install.yml` — new workflow (fresh-fresh `devkit install` on ubuntu-latest)
- `devkit-doctor/devkit-doctor.zsh` — add `check_wsl_mnt_path` warn when `$PWD` starts with `/mnt/`
- `lib/version-check.sh`, `lib/orgs.sh`, `lib/bootstrap-detection.sh` — touch only if shellcheck surfaces real bash-5 / WSL break (audit suggests none)
- `tests/unit/lib_orgs_portability.bats` — pin behaviour of `devkit_orgs_list` / `devkit_orgs_remove`
- `tests/integration/smoke-install.zsh` — local equivalent of CI smoke
- `README.md` — one-line "Running on WSL2: `sudo apt install zsh jq gh git`"

Out of scope:
- Re-implementing zsh entry points in bash (`install.zsh`, `init.zsh`, `join.zsh`, `doctor.zsh`, `update.zsh`, `orgs.zsh` stay as zsh; we require zsh on WSL)
- Adding windows-latest to CI matrix (deferred pending team-chat survey)
- Touching files outside this repo
- Replacing `jq` / `gh` (require, don't replace)

---

## Existing patterns to reuse (do NOT rewrite)

- `lib/version-check.sh:1-12` — already has explicit bash+zsh dual-sourcing via `${BASH_SOURCE[0]:-}` check + `_VERCHECK_LIB_DIR_OVERRIDE` fallback. Validate via `bash -n` and `shellcheck`; don't restructure.
- `lib/orgs.sh:18` — `${BASH_SOURCE[0]:-$0}` already resolves correctly under both shells. Pure-bash style (line 21+) works in bash 3.2+ and bash 5.x.
- `lib/bootstrap-detection.sh` — already portable. Pure bash.

---

## PRs in this wave

### PR 1a — `chore(ci): add lint matrix + .gitattributes + WSL preflight in doctor`

**Create:**
- `.gitattributes`:
  ```
  * text=auto eol=lf
  *.sh text eol=lf
  *.zsh text eol=lf
  *.py text eol=lf
  *.md text eol=lf
  *.png binary
  *.jpg binary
  ```
- `.github/workflows/lint.yml` — two jobs:
  - **shell-lint**: matrix `[ubuntu-latest, macos-latest]`. Steps:
    1. `apt-get install -y zsh shellcheck` (linux) or use `brew install` (mac — zsh is preinstalled, shellcheck via brew)
    2. `bash -n $(git ls-files '*.sh' '*.bash')`
    3. `zsh -n $(git ls-files '*.zsh')`
    4. `shellcheck -x -e SC1091 $(git ls-files '*.sh')` — start at default severity; allow source-not-found because libs reference each other at runtime
  - **doctor-syntax** (ubuntu-latest only): `apt install zsh jq gh`, source `lib/version-check.sh` from a fresh bash shell, assert functions `_wb_versioncheck`, `_wb_compare_semver`, `_wb_local_version` resolve.

**Modify:**
- `devkit-doctor/devkit-doctor.zsh` — add check function (insert under the environment-checks section):
  ```zsh
  check_wsl_mnt_path() {
    if [[ "$PWD" == /mnt/* ]]; then
      print -ru2 -- "WARNING: doctor running from /mnt/ (DrvFs). Clone repos under \$HOME instead — DrvFs is ~10x slower and breaks fsync semantics."
    fi
  }
  ```
  Add `check_wsl_mnt_path` to the list of checks invoked by the main doctor flow.

**Verification:**
- `bash -n lib/version-check.sh lib/orgs.sh lib/bootstrap-detection.sh` exits 0
- `zsh -n install.zsh init-workbench/init.zsh join-workbench/join.zsh devkit-doctor/devkit-doctor.zsh devkit-upgrade/devkit-upgrade.zsh update-workbench/update.zsh` exits 0
- `shellcheck -x -e SC1091 lib/*.sh` exits 0
- CI both matrix slots green
- Manual: `cd /mnt/c/anything && devkit doctor` shows the new WARNING (test in actual WSL or fake by `cd $(mktemp -d /mnt-test/XXXXXX)`)

**Done when:** PR merged, both CI jobs green on ubuntu-latest AND macos-latest. macos-latest must remain green (no regressions for existing macOS users).

---

### PR 1b — `fix(lib): portable-bash cleanup of shared library (any findings)`

**Conditional PR.** Only do if PR 1a's shellcheck surfaces real warnings on `lib/*.sh` that block bash 5.x under WSL. Otherwise skip directly to PR 1c.

**Create:**
- `tests/unit/lib_orgs_portability.bats`:
  - `devkit_orgs_list` outputs deduped, ordered slugs across a fixture `orgs.conf` (with `#` comments, blank lines, leading/trailing whitespace)
  - `devkit_orgs_list` appends auto-detected org if absent from file (mock `git remote get-url` via env or temp git dir)
  - `devkit_orgs_remove <slug>` is idempotent and leaves a valid file when slug absent
  - `devkit_orgs_remove` correctly preserves comments and ordering for non-removed lines

**Modify (only if needed):**
- `lib/orgs.sh` line 82-89 awk block — verify gawk + BSD awk produce identical output; refactor to portable awk subset if they don't.

**Verification:**
- All of PR 1a's gates remain green.
- `bats tests/unit/lib_orgs_portability.bats` green on both matrix slots.

**Done when:** PR merged.

---

### PR 1c — `ci(smoke): fresh-fresh devkit install + doctor + upgrade smoke`

**Create:**
- `.github/workflows/smoke-install.yml` — single job, `runs-on: ubuntu-latest`, fresh-fresh image:
  ```yaml
  steps:
    - name: Install minimum prereqs only
      run: sudo apt-get update && sudo apt-get install -y zsh jq gh git curl
    - name: Checkout into temp dir (simulate fresh clone)
      uses: actions/checkout@v4
      with:
        path: devkit-fresh
    - name: Run installer non-interactively
      env:
        DEVKIT_NONINTERACTIVE: "1"      # if installer respects this; else use --yes flag added below
        DEVKIT_DEFAULT_ORG: "amit-t"
      run: zsh devkit-fresh/install.zsh
    - name: Source devkit aliases in subshell + run doctor
      run: zsh -c 'source ~/.zprofile 2>/dev/null || true; devkit doctor'
    - name: Run upgrade --check-only
      run: zsh -c 'source ~/.zprofile 2>/dev/null || true; devkit upgrade --check-only || true'
  ```
- `tests/integration/smoke-install.zsh` — local runner that replicates the above flow in a temp dir.

**Modify:**
- `install.zsh` — add `--yes` / `--non-interactive` flag (env var `DEVKIT_NONINTERACTIVE=1` also works) that bypasses interactive prompts using safe defaults. ~20 lines.
- `README.md` — append section:
  ```markdown
  ## Running on WSL2

  WSL2 Ubuntu is a supported environment. Prereqs:

      sudo apt install -y zsh jq gh git curl

  Clone repos under `$HOME` (not `/mnt/c/`). DrvFs paths are 10x slower and break fsync semantics — `devkit doctor` will warn if you run from there.
  ```

**Verification:**
- CI smoke green.
- Manual: `docker run --rm -it ubuntu:22.04 bash -c 'apt update && apt install -y zsh jq gh git curl && git clone https://github.com/amit-t/ai-devkit /tmp/devkit && DEVKIT_NONINTERACTIVE=1 zsh /tmp/devkit/install.zsh && zsh -c "source ~/.zprofile; devkit doctor"'` exits 0.

**Done when:** PR merged. **Wave 2 (ai-ralph) unblocked.** Also Wave 1 PR 1c can run in parallel with Wave 2 PR 2a once PR 1b merges (or is declared no-op).

---

## Per-PR doneness gate (applied to every PR in this wave)

- [ ] `bash -n` on all `*.sh` + `*.bash` exits 0
- [ ] `zsh -n` on all `*.zsh` exits 0
- [ ] `shellcheck -x` on `lib/*.sh` exits 0 (severity = default for PR 1a; tighter later)
- [ ] Any new bats / integration tests added are green on both ubuntu-latest and macos-latest
- [ ] **macos-latest CI stays green** — non-breaking for existing users is hard rule
- [ ] Conventional Commit message; HEREDOC body; Co-Authored-By Claude line
- [ ] PR description references master plan and lists which Wave/PR

## Wave-done criterion

All three PRs merged; CI green on both matrix slots; manual docker smoke confirms `devkit install → devkit doctor` flow works end-to-end on a fresh ubuntu:22.04. At that point Wave 2 (ralph) is unblocked.

---

## Session kickoff prompt template

When you open Claude Code in this repo (`cd ~/Projects/Tools-Utilities/ai-devkit && claude`), the first prompt should be:

> Read `notes/wsl-port-plan.md` and the master plan it references. Ultrathink, enter plan mode, then execute Wave 1 PR 1a end-to-end. Boil the ocean: complete + tested + docs + verification. When done, summarise the diff and exit. I will review the PR before kicking off PR 1b.

Subsequent prompts (one per PR) follow the same pattern: name the PR, demand same standard.
