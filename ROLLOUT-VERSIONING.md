# Rollout — Versioning + Upgrades

This is the one-time bootstrap step for existing devs after the versioning system lands.

## Step 1 (every dev runs once)

```bash
cd ~/Projects/Tools-Utilities/ai-devkit
git pull --rebase
./install.zsh
exec zsh    # reload shell so DEVKIT_CLONE + new aliases are visible
```

## What you'll see next

- `init.wb`, `join.wb`, `update.wb` will print `[devkit] checking for updates...` once per 12h on first call.
- New: `wb.upgrade` (canonical replacement for `update.wb`). Old name still works with deprecation nag.
- New: `devkit.upgrade`, `devkit doctor`.

## Bootstrap nag

The first time a tool detects no `version.json` yet (older clones), it prints a one-time bootstrap message. Run the upgrade once, and the message goes away.
