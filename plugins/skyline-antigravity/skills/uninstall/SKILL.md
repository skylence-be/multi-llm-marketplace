---
name: uninstall-skill
description: Fully uninstall skyline — removes MCP wiring, hooks, instructions, daemon autostart, installed plugins, helper processes, dispatchers, and the global skyline package. Use when the user wants to remove skyline.
---

Run the full uninstall flow with the shell (Antigravity `run_command`). Prefer the bundled script when available:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-${ANTIGRAVITY_PLUGIN_ROOT:-${GEMINI_PLUGIN_ROOT:-}}}" ] && [ -f "${CLAUDE_PLUGIN_ROOT:-${ANTIGRAVITY_PLUGIN_ROOT:-${GEMINI_PLUGIN_ROOT:-}}}/scripts/uninstall.sh" ]; then
  bash "${CLAUDE_PLUGIN_ROOT:-${ANTIGRAVITY_PLUGIN_ROOT:-${GEMINI_PLUGIN_ROOT:-}}}/scripts/uninstall.sh"
else
  # 1. Remove MCP wiring, hooks, and instructions from all agents.
  if command -v skyline >/dev/null 2>&1; then
    skyline agent uninstall --target=all --yes || true
    skyline daemon stop --port 7333 2>/dev/null || true
    skyline daemon uninstall --port 7333 2>/dev/null || true
    skyline uninstall --bindir "$HOME/.local/bin" 2>/dev/null || true
  fi

  # 2. End stale Claude plugin watchdogs before removing the plugin cache.
  pgrep -f '/skyline-claude/.*/monitors/daemon-watchdog.sh' 2>/dev/null | while read -r pid; do kill "$pid" 2>/dev/null || true; done

  # 3. Remove the Antigravity plugin.
  agy plugin uninstall skyline-antigravity 2>/dev/null || true

  # 4. Remove the globally installed package with whichever supported package manager owns it.
  npm uninstall -g @skylence-ai/skyline 2>/dev/null || true
  pnpm remove -g @skylence-ai/skyline 2>/dev/null || true
  yarn global remove @skylence-ai/skyline 2>/dev/null || true
  bun remove -g @skylence-ai/skyline 2>/dev/null || true

  # 5. Remove a stale skyline-owned dispatcher if package uninstall left it behind.
  if [ -e "$HOME/.local/bin/sky" ] && strings "$HOME/.local/bin/sky" 2>/dev/null | grep -Eqi 'skyline|sky-hash|skylence'; then
    rm -f "$HOME/.local/bin/sky"
  fi

  # 6. Remove Skyline-owned per-user state.
  rm -rf \
    "${XDG_CONFIG_HOME:-$HOME/.config}/skyline" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/skyline" \
    "$HOME/Library/Application Support/skyline" \
    "$HOME/Library/Caches/skyline"
fi
```

After running it, verify and report facts, not assumptions:

```bash
command -v skyline || true
command -v sky-hash || true
command -v sky || true
pgrep -af 'skyline|sky-hash' || true
test ! -e "$HOME/Library/Application Support/skyline" && echo 'application support state absent' || echo 'application support state still exists'
test ! -f "$HOME/Library/LaunchAgents/ai.skylence.skyline.daemon.7333.plist" && echo 'launchd plist absent' || echo 'launchd plist still exists'
```

A missing command or already-removed daemon is success. Do not tell the user there are manual cleanup steps unless one of the verification commands still shows a concrete remaining artifact.
