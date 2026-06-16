#!/usr/bin/env bash
set -u

run_optional() {
  "$@" 2>/dev/null || true
}

# Remove MCP wiring, hooks, and instructions while the skyline CLI is still available.
if command -v skyline >/dev/null 2>&1; then
  run_optional skyline agent uninstall --target=all --yes
  run_optional skyline daemon stop --port 7333
  run_optional skyline daemon uninstall --port 7333
  run_optional skyline uninstall --bindir "$HOME/.local/bin"
fi

# End stale Claude plugin watchdogs before plugin cache removal.
pgrep -f '/skyline-claude/.*/monitors/daemon-watchdog.sh' 2>/dev/null | while read -r pid; do kill "$pid" 2>/dev/null || true; done

# Remove the Antigravity plugin via the agy CLI.
if command -v agy >/dev/null 2>&1; then
  agy plugin uninstall skyline-antigravity 2>/dev/null || true
fi

# Remove the global package for the package managers we support. These are best effort:
# only the manager that owns the package should actually remove anything.
if command -v npm >/dev/null 2>&1; then
  npm uninstall -g @skylence-ai/skyline 2>/dev/null || true
fi
if command -v pnpm >/dev/null 2>&1; then
  pnpm remove -g @skylence-ai/skyline 2>/dev/null || true
fi
if command -v yarn >/dev/null 2>&1; then
  yarn global remove @skylence-ai/skyline 2>/dev/null || true
fi
if command -v bun >/dev/null 2>&1; then
  bun remove -g @skylence-ai/skyline 2>/dev/null || true
fi

# Remove a stale skyline-owned dispatcher if package uninstall left it behind.
if [ -e "$HOME/.local/bin/sky" ] && strings "$HOME/.local/bin/sky" 2>/dev/null | grep -Eqi 'skyline|sky-hash|skylence'; then
  rm -f "$HOME/.local/bin/sky"
fi

# Remove Skyline-owned per-user state left by setup, daemon records, caches,
# snapshots, journals, and observability streams.
rm -rf \
  "${XDG_CONFIG_HOME:-$HOME/.config}/skyline" \
  "${XDG_CACHE_HOME:-$HOME/.cache}/skyline" \
  "$HOME/Library/Application Support/skyline" \
  "$HOME/Library/Caches/skyline"

# Verification output for the agent/user.
echo "skyline uninstall verification:"
printf 'skyline: '; command -v skyline || true
printf 'sky-hash: '; command -v sky-hash || true
printf 'sky: '; command -v sky || true
pgrep -af 'skyline|sky-hash' || true
test ! -e "$HOME/Library/Application Support/skyline" && echo "application support state absent" || echo "application support state still exists: $HOME/Library/Application Support/skyline"
if [ -f "$HOME/Library/LaunchAgents/ai.skylence.skyline.daemon.7333.plist" ]; then
  echo "launchd plist still exists: $HOME/Library/LaunchAgents/ai.skylence.skyline.daemon.7333.plist"
else
  echo "launchd plist absent"
fi
