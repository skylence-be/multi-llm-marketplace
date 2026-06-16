#!/usr/bin/env bash
# PreToolUse enforcement: redirect native tools to skyline equivalents.
# Fail-open (exit 0) when the daemon is not running — never breaks the agent.

MODE="${1:-}"

if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -m 1 "http://127.0.0.1:7333/mcp" 2>/dev/null || exit 0
else
  exit 0
fi

case "$MODE" in
  read) printf "use skyline_read, not Read.\n"; exit 2 ;;
  edit) printf "use skyline_edit, not Edit/Write.\n"; exit 2 ;;
  grep) printf "use skyline_grep, not Grep.\n"; exit 2 ;;
  glob) printf "use skyline_find, not Glob.\n"; exit 2 ;;
  bash) printf "use skyline tools, not Bash.\n"; exit 2 ;;
esac

exit 0
