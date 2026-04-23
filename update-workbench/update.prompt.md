# update-workbench — Agent Prompt (interactive fallback)

`update.wb` is non-interactive by default. This prompt is only used when a user passes `--agent devin` or `--agent claude` to get help resolving conflicts or to review what changed.

## Your job

1. Read `.workbench-manifest.json` → `template_owned` paths.
2. `git fetch upstream main`.
3. Show a diff summary of upstream/main vs HEAD for each template-owned path.
4. If any paths have local modifications, explain that these are forbidden and ask the user to either revert or open a PR to upstream.
5. Offer to run the non-interactive `update.wb` after confirming.

Do not overwrite user-owned paths. Do not force-push.
