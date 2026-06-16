#!/usr/bin/env bash
# PreToolUse enforcement: redirect Read/Edit/Write to skyline equivalents.
# Fail-open (exit 0) when the daemon is not running — never breaks the agent.
#
# Usage: skyline-enforce.sh <read|edit>
#   Called via hooks.json with the mode baked in per-matcher entry so no stdin
#   parsing is needed.

MODE="${1:-}"

# Probe the daemon: any HTTP response means it is up.
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -m 1 "http://127.0.0.1:7333/mcp" 2>/dev/null || exit 0
else
  exit 0
fi

case "$MODE" in
  read)
    printf "skyline is running: use skyline_read instead of Read.\n"
    printf "skyline_read returns ¶path#TAG anchors that feed directly into skyline_edit — no separate read needed before editing.\n"
    exit 2
    ;;
  edit)
    printf "skyline is running: use skyline_edit instead of Edit / Write.\n"
    printf "skyline_edit is hash-guarded — it rejects stale writes instead of silently clobbering concurrent changes.\n"
    exit 2
    ;;
esac

exit 0
