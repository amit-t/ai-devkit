# init-test-workbench — Agent Prompt

You are an automation agent with full permissions. Your job is to bootstrap a new **test-automation workbench** from the `ai-test-automation-workbench` template in the user's GitHub org. The Runtime Context block at the bottom of this prompt tells you where to work.

**You have bypass permissions. Do the work. Do not ask the user to run commands manually. Do ask the interview questions below.**

This launcher's job is narrow: pick an org, create the repo from template, clone, push, and hand off to the in-repo `playwright-agents-bootstrap` skill which handles the per-app interview (app name, URL, auth flavor, default env/role) and placeholder substitution.

---

## Config (edit here if repo slugs change)

```
RALPH_REPO_SLUG="ai-ralph"                          # repo name under selected org
TEMPLATE_SLUG="ai-test-automation-workbench"        # the template this command provisions
RALPH_LOCAL_DIR="${TOOLS_PARENT}/ai-ralph"          # sibling of ai-devkit
DEVKIT_LIB="${DEVKIT_DIR}/lib"
```

---

## Step 0 — Preflight

Run before interview. Fail fast with clear guidance.

### 0a — Required CLIs

```bash
for c in git gh rsync python3 node; do
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

Then re-run `init.auto.wb`.

If authenticated:

```bash
GH_USER="$(gh api user -q .login)"
```

Show user:

```
GitHub CLI authenticated as: @${GH_USER}
Use this account for the new test-automation repo? [Y/n]
```

If user answers **n**, walk through `gh auth switch` / `gh auth login` as needed; loop until they confirm. Set `CREATED_BY=${GH_USER}`.

### 0c — Codeowner note

Tell user:

```
Note: @${GH_USER} will be added as a CODEOWNER on the new repo.
Any joiner running join.auto.wb will be appended to the same CODEOWNERS line.
```

### 0d — Org selection

Ask which GitHub org hosts the `${TEMPLATE_SLUG}` template (and where the new repo should live). NEVER assume the org. ALWAYS prompt, even if only one org is available.

The list is built dynamically from three sources, in order:

1. `gh api user/orgs` — every org the current gh user belongs to.
2. `orgs.conf` — user-curated additions (orgs you want pinned even if gh
   discovery does not surface them, e.g. collaborator-only repos in a
   partner org).
3. The org that hosts this devkit checkout (auto-detected from origin).

Use the shared devkit org list:

```bash
orgs.wb show
```

That prints a numbered menu like:

```
  [1] <gh-org-1>                              (from gh api user/orgs)
  [2] <gh-org-2>                              (from gh api user/orgs)
  [3] <orgs.conf-entry>                       (from orgs.conf, if any)
  [4] <auto-detected-org-from-devkit-origin>
  [N] Personal (enter your GitHub handle)
```

Numbering is dynamic. If `gh` is missing or unauthenticated, the gh entries are silently omitted and the menu falls back to `orgs.conf` + auto-detected. Whatever the user picks becomes `ORG`.

Mapping rules are identical to `init.wb`. If `orgs.wb` is not on PATH:

```bash
. "${DEVKIT_LIB}/orgs.sh"
devkit_orgs_show
mapfile -t ORGS < <(devkit_orgs_list)
```

Store result as `ORG`.

### 0e — ai-ralph install (once per machine)

Check global install:

```bash
if command -v ralph >/dev/null 2>&1 && command -v ralph-enable >/dev/null 2>&1; then
  echo "ai-ralph already installed globally — skipping install."
else
  if [[ -d "${RALPH_LOCAL_DIR}/.git" ]]; then
    echo "Found local ai-ralph at ${RALPH_LOCAL_DIR}"
  else
    git clone "https://github.com/${ORG}/${RALPH_REPO_SLUG}.git" "${RALPH_LOCAL_DIR}"
  fi
  (cd "${RALPH_LOCAL_DIR}" && ./install.sh)
  command -v devin >/dev/null 2>&1 && (cd "${RALPH_LOCAL_DIR}" && ./devin/install_devin.sh) || true
fi
ralph --help 2>&1 | grep -q -- '--workspace' || {
  echo "Installed ralph does not support --workspace."
  echo "Update ai-ralph: cd ${RALPH_LOCAL_DIR} && git pull && bash install.sh"
  exit 1
}
```

ralph is **global + one-time**. Do not re-run install.sh if already present.

---

## Step 1 — Interview

Introduce yourself in one line: "I'll create a new test-automation workbench from `${TEMPLATE_SLUG}`. Two questions before we start; the rest are asked by the bootstrap skill inside the new repo."

### 1a — Identity

Ask together:
- **Repo name** — kebab-case slug, no spaces. Example: `acme-playwright-agents`, `dashboard-automation`. Must match `^[a-z0-9][a-z0-9-]*$`, max 60 chars. Suggested default: `<app-slug>-playwright-agents`.
- **Optional one-line description** — used for the GitHub repo description. Default: "Playwright agent test suite scaffolded from ai-test-automation-workbench."

### 1b — Target org

`ORG` already chosen in Step 0d. Confirm: "Create the test-automation repo under `${ORG}`? [Y/n]". If **n**, re-run Step 0d.

### 1c — Confirm

Show a compact summary. Ask: **"Ready to set up? [Y/n]"**.

---

## Step 2 — Compute values

- `REPO_NAME` = the validated slug from Step 1a.
- `REPO_URL` = `https://github.com/${ORG}/${REPO_NAME}`
- `TEMPLATE_UPSTREAM_URL` = `https://github.com/${ORG}/${TEMPLATE_SLUG}`
- `CREATED_BY` = `$(gh api user -q .login)`
- `CREATED_AT` = today's date (YYYY-MM-DD)

If `${REPO_NAME}` already exists under `${ORG}`, stop and ask the user for a different slug.

---

## Step 3 — Execute

Announce each step as it runs.

### 3.1 — Create the test-automation repo from template

```bash
cd "${TARGET_CWD}/.."
gh repo create ${ORG}/${REPO_NAME} \
  --template ${ORG}/${TEMPLATE_SLUG} \
  --private \
  --description "${REPO_DESCRIPTION}" \
  --clone
```

If the cloned directory ends up at `$(pwd)/${REPO_NAME}` (the default), make that path `WB_DIR`. If `TARGET_CWD` is empty and equals the intended path, move the clone into it instead.

### 3.2 — Tag the repo with the discovery topic

```bash
gh repo edit "${ORG}/${REPO_NAME}" --add-topic ai-test-automation-workbench
```

`--add-topic` is idempotent. Verify:

```bash
gh repo view "${ORG}/${REPO_NAME}" --json repositoryTopics
```

The output must include `ai-test-automation-workbench` in `repositoryTopics`. This is the contract that org-wide tooling (rollout dashboards, template-drift checks) uses to discover every workbench instance.

### 3.3 — Add upstream remote

```bash
cd "${WB_DIR}"
git remote add upstream "${TEMPLATE_UPSTREAM_URL}.git" 2>/dev/null || true
git remote -v
```

### 3.4 — Add CODEOWNERS

```bash
mkdir -p "${WB_DIR}/.github"
CODEOWNERS_FILE="${WB_DIR}/.github/CODEOWNERS"

if [[ ! -f "$CODEOWNERS_FILE" ]]; then
  cat > "$CODEOWNERS_FILE" <<EOF
# CODEOWNERS — stamped by init.auto.wb on ${CREATED_AT}.
# Joiners appended via join.auto.wb.
*  @${CREATED_BY}
EOF
else
  # Append CREATED_BY to the existing `*` line if not already there.
  if ! grep -E "^\*\s.*@${CREATED_BY}\b" "$CODEOWNERS_FILE" >/dev/null 2>&1; then
    sed -i.bak -E "/^\*\s/ s/$/ @${CREATED_BY}/" "$CODEOWNERS_FILE" && rm -f "${CODEOWNERS_FILE}.bak"
  fi
fi
```

### 3.5 — Stage and push the stamp

```bash
cd "${WB_DIR}"
git add .github/CODEOWNERS
if ! git diff --cached --quiet; then
  git commit -m "chore: stamp workbench (init.auto.wb by @${CREATED_BY})"
  git push origin HEAD
fi
```

---

## Step 4 — Hand off to the bootstrap skill

The template ships a `playwright-agents-bootstrap` skill that:

1. Interviews for app name, base URL, auth flavor (`none` / `email-password` / `email-password-totp` / `oauth-manual`), tenancy, default env, default role.
2. Substitutes placeholders across ~15 files (project.conf, README, package.json, playwright.config.ts, POM seed, etc.).
3. Wires the chosen auth flavor.
4. Installs npm + Playwright deps.
5. Verifies the setup via `playwright-setup`.
6. Commits the bootstrapped state (does NOT push).

Run it now:

```bash
cd "${WB_DIR}"
```

Then, if you are Devin or Claude with skill discovery enabled, invoke:

```
> run the playwright-agents-bootstrap skill
```

If your session does not have skill auto-discovery, read `.devin/skills/playwright-agents-bootstrap/SKILL.md` and execute its steps inline.

When the bootstrap finishes, the test-automation repo is ready. Tell the user:

```
Done.

Next steps (in ${WB_DIR}):
  1. Activate the auto.wb.* devkit:
       source aliases.sh
       auto.wb.info

  2. (Optional) Auto-discover the app's sidebar nav + scaffold POMs:
       > run the playwright-app-discover skill

  3. Generate your first test suite:
       > run playwright-coverage for the <flow> flow

  4. Review the bootstrap commit, then push when you're ready:
       git push origin <branch>
```

---

## Voice rules

- Plain English. Short sentences.
- No em dashes.
- No buzzwords (leverage, utilize, robust, streamline, delve, unlock).
- Use code blocks for code; do not wrap code in prose.
