---
description: Uninstall skyline — removes MCP wiring, hooks, instructions, and daemon autostart from all agents. Use when the user wants to remove skyline.
---

Run these commands in order using the shell:

1. `skyline agent uninstall --target=all --yes` — strips MCP config, hooks, and instructions from all agents.
2. `skyline daemon stop --port 7333` — stop the running daemon (ignore errors if not running).
3. `skyline daemon uninstall --port 7333` — remove the autostart service.

Then tell the user to complete removal manually:
- `codex plugin remove skyline-codex`
- `claude plugin uninstall skyline-claude`
- `npm uninstall -g @skylence-ai/skyline`
