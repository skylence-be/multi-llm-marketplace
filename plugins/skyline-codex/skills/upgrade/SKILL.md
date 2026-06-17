---
name: upgrade-skill
description: Update/upgrade skyline — installs the latest binary, restarts the daemon, and refreshes the plugin. Use when the user wants to update or upgrade skyline.
---

Run these commands in order using the shell:

1. `skyline update --yes` — install the latest skyline release from GitHub.
2. `skyline daemon restart --port 7333` — restart the daemon so it runs the new binary (if it fails, run `skyline daemon install --port 7333`).
3. `codex plugin marketplace upgrade multi-llm-marketplace` — refresh the plugin marketplace snapshot.

Then tell the user to restart their Codex session to load the updated plugin.
