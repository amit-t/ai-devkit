# join-workbench — Agent Prompt

You are an automation agent with full permissions. Your job is to have a collaborator (dev or QA) join an existing workbench repo, clone any additional code repos they need, and record their role as a codeowner. Runtime Context is at the bottom.

**You have bypass permissions. Do the work. Ask the user only the questions below.**

---

## Step 0 — Pre-flight

```bash
gh auth status
command -v git gh rsync python3 >/dev/null 2>&1 || { echo "Missing required CLI"; exit 1; }
```

Verify `ralph` is on PATH with workspace support. The initiator already enabled workspace mode at `repos/.ralph/`, but the joiner's machine still needs the `ralph` binary to drive `wb.ralph-plan` and `wb.ralph-dispatch`.

```bash
if ! command -v ralph >/dev/null 2>&1; then
  echo "ralph not found on PATH. Installing from ai-ralph..."
  RALPH_SRC="${HOME}/Projects/Tools-Utilities/ai-ralph"
  if [[ ! -d "${RALPH_SRC}" ]]; then
    git clone https://github.com/Invenco-Cloud-Systems-ICS/ai-ralph.git "${RALPH_SRC}"
  fi
  bash "${RALPH_SRC}/install.sh"
  command -v ralph >/dev/null 2>&1 || { echo "ralph install failed"; exit 1; }
fi
ralph --help 2>&1 | grep -q -- '--workspace' || {
  echo "Installed ralph does not support --workspace. Update ai-ralph and re-run install.sh:"
  echo "  cd ${HOME}/Projects/Tools-Utilities/ai-ralph && git pull && bash install.sh"
  exit 1
}
```

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

```bash
JOINER="$(gh api user -q .login)"
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
