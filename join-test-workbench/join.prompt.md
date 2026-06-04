# join-test-workbench — Agent Prompt

You are an automation agent with full permissions. Your job is to join an **existing** test-automation workbench: clone it, install dependencies, and confirm setup.

**You have bypass permissions. Do the work. Ask only the interview questions below.**

Use the Runtime Context block at the bottom of this prompt to find `WB_URL` and `TARGET_CWD`.

---

## Step 0 — Preflight

### 0a — Required CLIs

```bash
for c in git gh node npm python3; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing CLI: $c"; exit 1; }
done
```

### 0b — gh auth

```bash
gh auth status
GH_USER="$(gh api user -q .login)"
```

If not authenticated: stop and instruct `gh auth login`, then re-run `join.auto.wb`.

If authenticated, confirm:

```
GitHub CLI authenticated as: @${GH_USER}. Use this account to join? [Y/n]
```

If **n**, run `gh auth switch` (or `gh auth login`) and resolve a new `GH_USER`. Loop until confirmed.

### 0c — Validate URL

Parse `${WB_URL}` to extract `ORG` and `REPO_NAME`. Accepts:

- `https://github.com/ORG/REPO`
- `https://github.com/ORG/REPO.git`
- `git@github.com:ORG/REPO.git`
- `git@<custom-host>:ORG/REPO.git`

If the URL is malformed, ask for a new one. Loop until valid.

Resolve the canonical clone URL (prefer the form `gh` is happy with for `git clone`).

### 0d — Verify repo access

Before asking the user to confirm, check that the joiner can actually see the repo:

```bash
gh api "repos/${ORG}/${REPO_NAME}" >/dev/null 2>&1
```

A 404 here is ambiguous on purpose: GitHub returns the same response whether the repo does not exist or it exists privately and the joiner has no access. Treat both the same way. If the probe fails, stop and tell the user:

```
Cannot reach ${ORG}/${REPO_NAME} as @${GH_USER}.

Two possible causes:
  - The repo does not exist (check the URL spelling).
  - The repo is private and your account does not have access.

If it is private, ask a repo admin to grant @${GH_USER} at least Read
access:
  Repo > Settings > Collaborators and teams > Add people
  Pick @${GH_USER}, role: Read (or Write if they will push branches)

Then re-run:  join.auto.wb ${WB_URL}
```

Do not proceed to Step 1 until the probe succeeds.

### 0e — Confirm

Tell the user what you're about to do:

```
Workbench will be cloned into: ${TARGET_CWD}/${REPO_NAME}/
Proceed? [Y/n]
```

---

## Step 1 — Clone the workbench

```bash
cd "${TARGET_CWD}"
gh repo clone "${ORG}/${REPO_NAME}"
cd "${REPO_NAME}"
WB_DIR="$(pwd)"
```

Pull latest:

```bash
git pull --rebase
```

---

## Step 2 — Install dependencies

The template ships `package.json` (Playwright + types). Run:

```bash
cd "${WB_DIR}"
npm install
npx playwright install chromium
```

Then run the local setup skill if it is present:

```
> run the playwright-setup skill
```

Otherwise, manually verify:

```bash
node -e "require('@playwright/test')" && echo "playwright deps OK"
test -f playwright.config.ts && echo "config OK"
```

---

## Step 3 — Tell the user

```
Joined ${ORG}/${REPO_NAME} as @${GH_USER}.

Next steps (in ${WB_DIR}):
  1. Activate the devkit:
       source aliases.sh
       auto.wb.info

  2. Sync any approved plans from the planning workbench:
       see project.conf for the bundle's sync target.

  3. Run the suite locally:
       auto.wb.test          # all tests
       auto.wb.test-smoke    # smoke subset

  4. Update the template if upstream has shipped fixes:
       update.auto.wb --dry-run
       update.auto.wb
```

---

## Voice rules

- Plain English. Short sentences.
- No em dashes.
- No buzzwords (leverage, utilize, robust, streamline, delve, unlock).
- Use code blocks for code; do not wrap code in prose.
