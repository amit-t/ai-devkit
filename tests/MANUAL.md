# Manual real-LLM smoke test — repo-context-scan

This recipe exercises the full repo-context-scan flow end-to-end with
REAL LLM spend. **Not run in CI** (would cost money). Run before each
release that touches the scan feature.

## Prerequisites

- Working ai-devkit install (see `docs/getting-started.md`).
- One real source repo URL you have access to (used as the scan target).
- A throwaway directory on your machine for the test wb (gets deleted).
- Either `devin` or `claude` on PATH (or both — the test verifies engine
  selection).
- ~10 USD budget headroom for a real LLM scan (a single mid-sized repo).
- A throwaway personal GitHub repo (or the willingness to create one
  via `init.wb`'s `gh repo create` step).

## Step 1 — Initialize a throwaway wb with one repo

```bash
TMPWB="$(mktemp -d -t scan-smoke.XXX)"
cd "$TMPWB"
init.wb
# answer interview prompts:
#   LABEL:    scan-smoke
#   ORG:      <your personal handle or throwaway org>
#   REPOS:    name=foo;url=<real-source-repo>;role=service;stack=zsh
#   (skip / minimal answers everywhere else)
```

Wait for `init.wb` to finish. Under the hood it will:

1. Create the wb repo from the `ai-workbench` template.
2. Clone `foo` into `repos/foo/`.
3. Run `repo-context-scan` against `repos/foo` (real LLM spend here).
4. Aggregate `context/README.md`.
5. Commit everything and push.

The final banner should print the wb path and a `join.wb …` share URL.

## Step 2 — Verify the scan produced real terms

```bash
cd "$TMPWB"/wb-scan-smoke    # path printed by init.wb's final banner
head -50 context/foo/CONTEXT.md
```

Expect:

- Frontmatter with `status: scanned`, `source_commit` non-empty,
  `devkit_version` and `skill_version` populated.
- A markdown body that actually discusses the repo's domain (types,
  vocabulary, decisions). **Not** the failure stub
  ("Repo context scan did not produce output…").

## Step 3 — Verify the aggregate row

```bash
cat context/README.md
```

Expect a `# Workbench Context Index` table with a row for `foo` whose
status is `scanned` and whose `Top concepts` column is non-empty.

## Step 4 — Verify idempotency

```bash
wb.rescan foo
git status
git --no-pager log -1 --stat
```

Expect:

- `wb.rescan` self-commits an updated `generated_at` timestamp
  (devkit-owned key, always refreshed).
- The markdown body should be effectively identical to the previous
  scan. If the LLM happens to produce different prose, that's acceptable
  — the test is primarily about the **frontmatter merge preserving user
  keys**.

Optional sub-test (recommended): add a user-authored key to the
frontmatter manually, then re-run:

```bash
# Add owner: alice as a user-authored key. Use your editor of choice.
$EDITOR context/foo/CONTEXT.md   # insert `owner: alice` inside the frontmatter
wb.rescan foo
grep '^owner:' context/foo/CONTEXT.md
```

Expect: `owner: alice` survives the re-run.

## Step 5 — Force a failure stub

Detach the source repo to a SHA that won't yield anything useful, then
rescan:

```bash
cd repos/foo
git checkout --detach "$(git rev-list --max-parents=0 HEAD | tail -1)"
cd ../..
wb.rescan foo
head -20 context/foo/CONTEXT.md
```

Expect:

- Frontmatter with `status: scan-failed`, `fail_reason` populated,
  `failed_at` set, `retry_with: "wb.rescan foo"`.
- Body matches the stub template ("Repo context scan did not produce
  output. Reason recorded in frontmatter…").

Then restore the source repo and re-scan to confirm recovery:

```bash
cd repos/foo
git checkout -
cd ../..
wb.rescan foo
head -10 context/foo/CONTEXT.md
```

Expect: `status: scanned` is back; body is real domain content again.

## Step 6 — Doctor green from inside the wb

```bash
devkit doctor
```

Expect all global checks **OK** and all wb-scope checks **OK** (or
`OK no per-repo CONTEXT files` if you happened to delete `context/`
during testing). No `WARN` rows for `no stale stubs`, `aggregate README
current`, or `.context-scan/ worktree clean`.

## Cleanup

```bash
rm -rf "$TMPWB"
gh repo delete <org>/wb-scan-smoke --yes
```

## Pass criteria

- Step 2: real domain terms (not stub).
- Step 3: aggregate row present with `scanned` status and non-empty top
  concepts.
- Step 4: idempotent on the user-keys axis (and the `owner: alice`
  sub-test passes if performed).
- Step 5: stub produced on detach, then real scan restores on
  re-checkout.
- Step 6: all `devkit doctor` wb-scope checks green at the end.
