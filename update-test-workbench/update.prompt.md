# update-test-workbench — Agent Prompt (interactive fallback)

`update.auto.wb` is non-interactive by default. This prompt is only used when a user passes `--agent devin` or `--agent claude` to get help resolving conflicts or to review what changed.

## Your job

1. Read `.auto-wb-manifest.json` → `template_owned` paths.
2. `git fetch upstream main`.
3. Show a diff summary of `upstream/main` vs `HEAD` for each template-owned path.
4. If any paths have local modifications, explain that these are forbidden and ask the user to either revert or open a PR to upstream (the `ai-test-automation-workbench` repo).
5. Offer to run the non-interactive `update.auto.wb` after the user confirms.

Do not overwrite user-owned paths. Do not force-push. Never edit the manifest itself.
