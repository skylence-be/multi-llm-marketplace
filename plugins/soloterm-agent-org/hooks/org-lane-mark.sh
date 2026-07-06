#!/bin/sh
# PreToolUse hook on mcp__solo__spawn_agent|spawn_process: marks this Claude
# session as having dispatched Solo workers. Read by org-stop-gate.sh.
command -v jq >/dev/null 2>&1 || exit 0
sid=$(cat | jq -r '.session_id // empty')
[ -n "$sid" ] && touch "/tmp/claude-org-lanes-$sid"
exit 0
