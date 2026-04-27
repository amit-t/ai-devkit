# join-workbench — Agent Prompt

You are an automation agent with full permissions. Your job is to have a collaborator (dev or QA) join an existing workbench repo, clone any additional code repos they need, and record their role as a codeowner. Runtime Context is at the bottom.

**You have bypass permissions. Do the work. Ask the user only the questions below.**

---

## Config (edit here if repo slugs change)

```
RALPH_REPO_SLUG="ai-ralph"
RALPH_LOCAL_DIR="${TOOLS_PARENT}/ai-ralph"   # sibling of ai-devkit
```

After the comprehensive Step 0 below installs ralph globally, also verify it supports workspace mode:

```bash
ralph --help 2>&1 | grep -q -- '--workspace' || {
  echo "Installed ralph does not support --workspace. Update ai-ralph and re-run install.sh:"
  echo "  cd ${RALPH_LOCAL_DIR} && git pull && bash install.sh"
  exit 1
}

---

## Step 0 — Preflight

Run before any clone. Fail fast.

### 0a — Required CLIs

```bash
for c in git gh rsync python3; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing CLI: $c"; exit 1; }
done
```

### 0b — gh auth + account selection

```bash
gh auth status
```

If not authenticated, stop and instruct:

```bash
gh auth login
```

Then re-run `join.wb <url>`.

If authenticated:

```bash
GH_USER="$(gh api user -q .login)"
```

Show user:

```
GitHub CLI authenticated as: @${GH_USER}
Workbench URL: ${WB_URL}
Join this workbench as @${GH_USER}? [Y/n]
```

If **n**:

1. List known accounts:
   ```bash
   gh auth status 2>&1 | grep -E "Logged in to github.com account"
   ```
2. Ask:
   ```
   Options:
     [s] Switch to another already-logged-in account
     [l] Login a new account
     [q] Quit
   ```
3. For `s`: `gh auth switch` interactively. Re-resolve `GH_USER`.
4. For `l`: `gh auth login`, then `gh auth switch` to the new one. Re-resolve `GH_USER`.
5. For `q`: exit 0 with message "Aborted. Re-run join.wb when ready."

Re-confirm:

```
Proceeding as @${GH_USER}. OK? [Y/n]
```

Loop until confirmed. `JOINER=${GH_USER}`.

### 0c — Repo access check

Before cloning, verify the joiner can reach `WB_URL`:

```bash
gh repo view "${WB_URL}" >/dev/null 2>&1 || {
  echo "Cannot access ${WB_URL} as @${JOINER}."
  echo "Either the repo is private and this account lacks access,"
  echo "or the URL is wrong. Fix one of:"
  echo "  - ask initiator to add @${JOINER} as collaborator"
  echo "  - switch accounts (re-run join.wb and pick a different gh account)"
  exit 1
}
```

### 0d — Codeowner note

Tell user:

```
Note: @${JOINER} will be appended to the CODEOWNERS * line on this workbench.
```

### 0e — Org selection (for ai-ralph source)

Build the menu from the devkit org list:

```bash
orgs.wb show
```

Produces numbered list (configured orgs + devkit's auto-detected origin org + a final "Personal" slot). `1..N-1` map directly to the printed org slug; `N` prompts for a personal GitHub handle.

Fallback if `orgs.wb` missing:

```bash
. "${DEVKIT_DIR}/lib/orgs.sh"
devkit_orgs_show
mapfile -t ORGS < <(devkit_orgs_list)
```

Store chosen value as `ORG`. More orgs can be added via `orgs.wb add <slug>`.

### 0f — ai-ralph install (once per machine)

Check global install:

```bash
if command -v ralph >/dev/null 2>&1 && command -v ralph-enable >/dev/null 2>&1; then
  echo "ai-ralph already installed globally — skipping install."
  RALPH_INSTALLED=1
else
  RALPH_INSTALLED=0
fi
```

If `RALPH_INSTALLED=0`:

1. Locate or clone:
   ```bash
   if [[ -d "${RALPH_LOCAL_DIR}/.git" ]]; then
     echo "Found local ai-ralph at ${RALPH_LOCAL_DIR}"
   else
     git clone "https://github.com/${ORG}/${RALPH_REPO_SLUG}.git" "${RALPH_LOCAL_DIR}"
   fi
   ```
2. Run base install:
   ```bash
   cd "${RALPH_LOCAL_DIR}"
   ./install.sh
   ```
3. Optional Devin engine:
   ```bash
   command -v devin >/dev/null 2>&1 && ./devin/install_devin.sh || true
   ```
4. Verify `ralph-enable` resolves. If missing, warn to add `~/.local/bin` to PATH.

Initiator already enabled the ralph workspace at `repos/.ralph/` (init.wb Step 3.4b). The joiner needs the global ralph install so `wb.ralph-plan` / `wb.ralph-dispatch` work on this machine. Step 4b below will re-verify with `scripts/ralph-enable-check.sh` and bootstrap the workspace if a joiner pulled an older workbench predating Step 3.4b.

---

## Step 1 — Clone the workbench

```bash
cd "${TARGET_CWD}"
git clone "${WB_URL}"
```

Derive `WB_DIR` = the cloned directory name (repo slug, e.g. `wb-payments-pi3`).

```bash
cd "${WB_DIR}"
```

If the repo already exists locally at this path, `cd` into it and `git pull --rebase` instead of cloning.

Read `project.conf`. Capture:
- `WORKBENCH_LABEL`
- `WORKBENCH_TEMPLATE_UPSTREAM`
- `EPICS` array
- `REPOS` array (existing entries and their roles)

---

## Step 2 — Ensure upstream remote is present

```bash
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "${WORKBENCH_TEMPLATE_UPSTREAM}.git"
fi
```

This is needed so `update.wb` works for this collaborator too.

---

## Step 3 — Interview

Introduce: "You're joining workbench `${WORKBENCH_LABEL}`. Epics in scope: `${EPICS[*]}`. The following code repos are already registered:"

Print the existing `REPOS` entries in a table (name, url, role, added_by).

Ask: "Do you need to add any more code repos for your part of the work? [y/N]"

If yes, loop until done:
- Repo name (slug)
- Git URL
- Role — `service` | `automation-tests` | `shared-lib` | `infra`
- Stack hint

For each, require that the name is not already in `REPOS` (if it is, skip with a note).

Ask: "Do you want to re-clone any of the existing repos locally? [y/N]"

If yes, clone those into `repos/{name}/`.

---

## Step 4 — Clone the new repos

For each new repo:

```bash
git clone "${url}" "${WB_DIR}/repos/${name}"
```

---

## Step 4b — Verify ralph workspace is enabled

The initiator should have run `ralph enable --workspace` during `init.wb`. If a joiner pulled an older workbench predating that step, bootstrap workspace mode now (idempotent):

```bash
mkdir -p "${WB_DIR}/repos"
"${WB_DIR}/scripts/ralph-enable-check.sh" >/dev/null 2>&1 || {
  echo "Ralph workspace not enabled yet. Bootstrapping at ${WB_DIR}/repos/..."
  (cd "${WB_DIR}/repos" && ralph enable --workspace --non-interactive --skip-tasks)
  grep -q '^WORKSPACE_MODE=true' "${WB_DIR}/repos/.ralphrc" || {
    echo "ralph enable --workspace did not set WORKSPACE_MODE=true; abort"
    exit 1
  }
  "${WB_DIR}/scripts/ralph-enable-check.sh"
}
```

---

## Step 5 — Append to project.conf

Use `${WB_DIR}/scripts/register-repo.sh` for each new entry:

```bash
cd "${WB_DIR}"
./scripts/register-repo.sh "${name}" "${url}" "${role}" "${stack}"
```

This appends the entry idempotently and clones if needed. If `register-repo.sh` is absent for some reason, append manually via python as shown in its body.

---

## Step 6 — Add joiner to CODEOWNERS

`JOINER` already resolved in Step 0.

```bash
cd "${WB_DIR}"
if ! grep -qE "^\\*\\s.*@${JOINER}\\b" .github/CODEOWNERS; then
  # BSD sed (macOS)
  sed -i '' -E "s|^(\\*\\s+.*)$|\\1 @${JOINER}|" .github/CODEOWNERS
fi
```

---

## Step 7 — Copy MCP template if .mcp.json is missing locally

```bash
if [[ ! -f .mcp.json && -f .mcp.json.template ]]; then
  cp .mcp.json.template .mcp.json
  # Strip disabled servers (those with _enabled_by_default: false) unless the user opts in
fi
```

Ask the joiner which MCPs they want enabled. Never write literal tokens — use `${ENV_VAR}` refs.

---

## Step 8 — Commit and push

```bash
cd "${WB_DIR}"
git add project.conf .github/CODEOWNERS
git diff --quiet && git diff --cached --quiet || \
  git commit -m "chore: @${JOINER} joined — added repos $(printf '%s ' ${added_repos[@]})"
git push origin main
```

---

## Step 9 — Print summary

```
── Joined workbench ${WORKBENCH_LABEL} ──────────────
  Path:           ${WB_DIR}
  Your GH user:   @${JOINER}
  New repos:      <list or none>
  CODEOWNERS:     @initiator @${JOINER}
  Upstream:       ${WORKBENCH_TEMPLATE_UPSTREAM}

── Next steps ───────────────────────────────────────
  1. source ${WB_DIR}/aliases.sh
  2. Pull template updates any time: update.wb
  3. Read EPIC-PIPELINE.md to see what's in flight
  4. Start working: claude  (or devin)
```

---

## Rules

- Never commit `.mcp.json`.
- Never force-push.
- Never edit `template_owned` paths.
- If a step fails, stop, report clearly, and leave the clone in a recoverable state.
