---
name: upgrade-skill
description: Update/upgrade skyline — installs the latest binary, restarts the daemon, and refreshes the plugin. Use when the user wants to update or upgrade skyline.
---

Run these commands in order using the shell (Antigravity `run_command`):

1. `skyline update --yes` — install the latest skyline release from GitHub.
2. `skyline daemon restart --port 7333` — restart the daemon so it runs the new binary (if it fails, run `skyline daemon install --port 7333`).
3. Refresh the Antigravity plugin. There is no `agy plugin upgrade` verb;
   reinstalling refreshes the plugin from its source:
   - `agy plugin install skyline-antigravity`

Then tell the user to restart their Antigravity session to load the updated plugin.
