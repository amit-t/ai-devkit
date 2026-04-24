# init-workbench — Agent Prompt

You are an automation agent with full permissions. Your job is to bootstrap a new **workbench** from the `ai-workbench` template in the user's GitHub org. The Runtime Context block at the bottom of this prompt tells you where to work.

**You have bypass permissions. Do the work. Do not ask the user to run commands manually. Do ask them the interview questions below.**

---

## Config (edit here if repo slugs change)

```
RALPH_REPO_SLUG="ai-ralph"            # repo name under selected org
WORKBENCH_TEMPLATE_SLUG="ai-workbench"
RALPH_LOCAL_DIR="${TOOLS_PARENT}/ai-ralph"   # sibling of ai-devkit
```

---

## Step 0 — Preflight

Run before interview. Fail fast with clear guidance.

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

Then re-run `init.wb`.

If authenticated, resolve active account:

```bash
GH_USER="$(gh api user -q .login)"
```

Show user:

```
GitHub CLI authenticated as: @${GH_USER}
Use this account for the new workbench repo? [Y/n]
```

If user answers **n**:

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
3. For `s`: run `gh auth switch`. Let user pick interactively. Re-resolve `GH_USER`.
4. For `l`: run `gh auth login`. After success, `gh auth switch` to the new one. Re-resolve `GH_USER`.
5. For `q`: exit 0 with message "Aborted. Re-run init.wb when ready."

Re-confirm:

```
Proceeding as @${GH_USER}. OK? [Y/n]
```

Loop 0b until user confirms. `CREATED_BY=${GH_USER}`.

### 0c — Codeowner note

Tell user:

```
Note: @${GH_USER} will be added as a CODEOWNER on the new repo.
Any joiner running join.wb will be appended to the same CODEOWNERS line.
```

### 0d — Org selection (for ai-ralph source)

Ask which GitHub org hosts `${RALPH_REPO_SLUG}` and the `${WORKBENCH_TEMPLATE_SLUG}` template.

Build the menu dynamically from the devkit org list (configured + auto-detected from devkit's origin). Use the `orgs.wb` utility:

```bash
orgs.wb show
```

That prints a numbered menu like:

```
  [1] Invenco-Cloud-Systems-ICS
  [2] <auto-detected-org-from-devkit-origin>
  [N] Personal (enter your GitHub handle)
```

The final "Personal" slot is always last. Selections `1..N-1` map directly to the printed org slug; selection `N` prompts "Enter personal GitHub handle (e.g. amit-t):" and sets `ORG="<handle>"`.

If `orgs.wb` is not on PATH (fresh machine, devkit installed but shell not reloaded), fall back to sourcing the library directly:

```bash
. "${DEVKIT_DIR}/lib/orgs.sh"
devkit_orgs_show
# read configured list for mapping:
mapfile -t ORGS < <(devkit_orgs_list)
```

Store chosen value as `ORG`. Use this for both `ai-ralph` source and the workbench template (so Step 1e can default to this ORG — skip the 1e prompt if user already picked here; confirm instead).

To add more orgs later, the user runs: `orgs.wb add <slug>`.

### 0e — ai-ralph install (once per machine)

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
2. Run base install (Claude engine):
   ```bash
   cd "${RALPH_LOCAL_DIR}"
   ./install.sh
   ```
3. Optionally install Devin engine if `devin` CLI is on PATH:
   ```bash
   command -v devin >/dev/null 2>&1 && ./devin/install_devin.sh || true
   ```
4. Verify `ralph-enable` now resolves. If `~/.local/bin` is not on PATH, warn user to add:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

`ralph` install is **global + one-time**. Do NOT run `./install.sh` again if already installed. `ralph-enable` in Step 3.x scopes ralph to the workbench only.

---

## Step 1 — Interview

Introduce yourself in one line: "I'll set up a new workbench from the ai-workbench template. A few quick questions."

### 1a — Identity

Ask together:
- **Workspace label** — short, kebab-case, lowercase. Example: `example`, `example-refresh`. If blank, derive from primary epic ID + today's date (`wb-<epic-lower>-YYYYMMDD`).
- **Primary Jira epic ID** (e.g. `EPIC-001`).
- **Additional epic IDs** (comma-separated, optional).

### 1b — Repos to register

Loop until the user says "done":
- Repo name (short slug)
- Repo git URL
- Role — `service` | `automation-tests` | `shared-lib` | `infra`
- Stack hint (short free text, e.g. "node-nest", "playwright", "python-fastapi")

**Constraint:** at least one repo must be registered during init. For a QA initiator, that is typically just the `automation-tests` repo. More can be added later by the joiner.

### 1c — Design references (optional)

- Figma URL(s), one per line.
- Design system reference (URL or doc pointer).

### 1d — MCP servers (optional)

Ask: "Enable Atlassian (Jira) MCP? [y/N]"
Ask: "Enable Figma MCP? [y/N]"

Only enable the user's chosen set.

### 1e — Target org

`ORG` already chosen in Step 0d. Confirm: "Create the workbench under `${ORG}`? [Y/n]". If **n**, re-run Step 0d.

### 1f — Confirm

Show a compact summary. Ask: **"Ready to set up? [Y/n]"**.

---

## Step 2 — Compute values

- `LABEL` = normalized kebab-case label.
- `REPO_NAME` = `wb-${LABEL}` (must match `^wb-[a-z0-9][a-z0-9-]*$`, max 60 chars).
- `REPO_URL` = `https://github.com/${ORG}/${REPO_NAME}`
- `TEMPLATE_UPSTREAM_URL` = `https://github.com/${ORG}/ai-workbench`
- `CREATED_BY` = `$(gh api user -q .login)`
- `CREATED_AT` = today's date (YYYY-MM-DD)
- `GIT_URL_PREFIX`:
  - HTTPS: `https://github.com`
  - SSH: `git@github.com`
  - SSH with alias: `git@<custom-host>` — detect via `~/.ssh/config` + `gh auth status`

If `REPO_NAME` already exists under the org, stop and ask for a new label.

---

## Step 3 — Execute

Run these steps in order. Announce each step as it runs.

### 3.1 — Pre-flight (already done in Step 0)

Skip — Step 0 covered CLI presence, gh auth, and account selection. `CREATED_BY` is set.

### 3.2 — Create workbench repo from template

```bash
cd "${TARGET_CWD}/.."
gh repo create ${ORG}/${REPO_NAME} \
  --template ${ORG}/ai-workbench \
  --private \
  --clone
```

If the created directory is nested incorrectly, move it to `${TARGET_CWD}` or to `$(dirname ${TARGET_CWD})/${REPO_NAME}` so the user's intended path holds the workbench. If `TARGET_CWD` already equals `${REPO_NAME}`, use it in place.

Set `WB_DIR` to the final path.

### 3.2b — Tag repo with `ai-workbench` topic

Tag the new repo so org-wide tooling (for example, the weekly steering-overlay aggregator in the template repo) can discover every stamped workbench across the org by topic.

```bash
gh repo edit "${ORG}/${REPO_NAME}" --add-topic ai-workbench
```

`--add-topic` is idempotent. Re-running on a repo that already has the topic is a no-op and does not fail. Safe to retry after a failed stamp.

Verify:

```bash
gh repo view "${ORG}/${REPO_NAME}" --json repositoryTopics
```

The output must include `ai-workbench` in `repositoryTopics`. The topic is the stable contract for discovery, so do not skip this step even if the template repo moves orgs later.

### 3.3 — Add upstream remote to the template

```bash
cd "${WB_DIR}"
git remote add upstream "${TEMPLATE_UPSTREAM_URL}.git" 2>/dev/null || true
```

### 3.4 — Clone registered code repos into repos/

For each (name, url, role, stack) gathered in Step 1b:

```bash
mkdir -p "${WB_DIR}/repos"
git clone "${url}" "${WB_DIR}/repos/${name}"
```

### 3.5 — Render project.conf from template

Read `${WB_DIR}/project.conf.template`. Substitute:

| Placeholder | Value |
|-------------|-------|
| `{{LABEL}}` | `${LABEL}` |
| `{{REPO_URL}}` | `${REPO_URL}` |
| `{{TEMPLATE_UPSTREAM_URL}}` | `${TEMPLATE_UPSTREAM_URL}` |
| `{{CREATED_BY}}` | `${CREATED_BY}` |
| `{{CREATED_AT}}` | `${CREATED_AT}` |
| `{{ORG}}` | `${ORG}` |
| `{{EPICS_BASH_ARRAY}}` | quoted space-separated list, e.g. `"EPIC-001" "EPIC-002"` |
| `{{REPOS_BASH_ENTRIES}}` | one line per repo, two-space indented: `  "name=X;url=Y;role=Z;stack=S;added_by=${CREATED_BY}"` |

Write result to `${WB_DIR}/project.conf`. Keep `project.conf.template` in place — it is template-owned and `update.wb` will refresh it.

### 3.6 — Render EPIC-PIPELINE.md from template

Read `${WB_DIR}/EPIC-PIPELINE.md.template`.

For each epic in scope, generate an H2 section:

```markdown
## EPIC <ID> — <title-if-known-else-blank>
Status: draft
Jira: https://<your-jira-domain>.atlassian.net/browse/<ID>
Context: product/context-library/epics/<ID>.md

### PRDs
| PRD | Status | Spec | BDD | TDD | ERD | Test Spec | fix_plan repos | Exec |
|-----|--------|------|-----|-----|-----|-----------|----------------|------|

### Notes
-
```

Substitute `{{EPIC_SECTIONS}}` with the concatenation, `{{LABEL}}`, `{{CREATED_AT}}`, `{{CREATED_BY}}`. Write result to `${WB_DIR}/EPIC-PIPELINE.md`. Keep the `.template` file in place — it is template-owned.

### 3.7 — Render .github/CODEOWNERS

```bash
cat > "${WB_DIR}/.github/CODEOWNERS" <<EOF
# Auto-managed by ai-devkit. Initiator and joiners appended to the \`*\` line.
# Manual edits below this header survive updates.

*  @${CREATED_BY}
EOF
```

### 3.8 — MCP config

If at least one MCP was enabled in 1d:

```bash
cp "${WB_DIR}/.mcp.json.template" "${WB_DIR}/.mcp.json"
```

Edit `.mcp.json` to remove servers the user did not enable. Preserve `${ENV_VAR}` refs — never write literal tokens.

If none enabled, write a minimal `.mcp.json`:

```json
{ "mcpServers": {} }
```

`.mcp.json` is gitignored — do not commit it.

### 3.9 — Seed epic context from Jira (if Atlassian MCP enabled)

For each epic ID, if Atlassian MCP is enabled, call its `get_issue` tool and write `${WB_DIR}/product/context-library/epics/<ID>.md` with the epic's summary, description, acceptance criteria, linked issues, and metadata frontmatter.

If Atlassian MCP is not enabled, create empty stubs:

```markdown
---
id: <ID>
title: TODO
status: TODO
jira_url: https://<your-jira-domain>.atlassian.net/browse/<ID>
pulled_at: <CREATED_AT>
---

## Summary
TODO — paste from Jira.
```

### 3.10 — Symlink skills into agent dirs

```bash
cd "${WB_DIR}"
mkdir -p .claude/skills .agents/skills .devin/skills
for dir in .claude/skills .agents/skills .devin/skills; do
  for skill in skills/*/; do
    name="$(basename "$skill")"
    ln -sfn "../../skills/$name" "$dir/$name"
  done
done
```

### 3.10b — Enable ai-ralph in the workbench only

<!-- TODO(ai-ralph-workspace-mode): Rewrite this step once ai-ralph's "workspace mode"
     PR merges. Trigger phrase: "ralph workspace mode is ready". When fired, re-read
     ai-ralph README/docs (under ${RALPH_LOCAL_DIR}) for the new enable flow and
     update this step to match. -->

Scope: `${WB_DIR}` ONLY. Do NOT run this inside any sibling repo under `repos/*`.

```bash
cd "${WB_DIR}"
if [[ ! -d .ralph ]]; then
  ralph-enable --non-interactive 2>/dev/null || ralph-enable-ci
else
  echo ".ralph/ already present — skipping ralph-enable."
fi
```

If `ralph-enable` prompts interactively and the agent cannot answer, fall back to `ralph-enable-ci` (non-interactive, sensible defaults). The `.ralph/` config, `.ralphrc`, and `.gitignore` entries will be picked up by the Step 3.12 commit.

### 3.11 — Source aliases (note only)

Tell the user to run:

```bash
echo 'source ${WB_DIR}/aliases.sh' >> ~/.zshrc
source ~/.zshrc
```

### 3.12 — Commit and push

```bash
cd "${WB_DIR}"
git add .
git commit -m "feat: initialize workbench ${REPO_NAME} from ai-workbench template"
git push origin main
```

### 3.13 — Print summary

```
── Workbench initialized ────────────────────────────
  Label:      ${LABEL}
  Repo:       ${REPO_URL}
  Path:       ${WB_DIR}
  Epics:      <list>
  Code repos: <list with roles>
  MCPs:       <list or none>
  CODEOWNERS: @${CREATED_BY}

── Share with your counterpart ──────────────────────
  join.wb ${REPO_URL}

── Next steps ───────────────────────────────────────
  1. source ${WB_DIR}/aliases.sh (and add to ~/.zshrc)
  2. cd ${WB_DIR} && claude  (or devin)
  3. /epic-intake <FIRST-EPIC-ID>
```

---

## Rules

- Never commit `.mcp.json` (it is gitignored).
- Never force-push.
- Never edit files listed under `template_owned` in `.workbench-manifest.json` — they come from the template and are updated via `update.wb`.
- If any step fails, stop, report the error clearly, and leave the workbench in a recoverable state.
