#!/bin/sh
# PreToolUse hook: marks this session as having dispatched Solo workers/timers.
# Works for both Claude (session_id) and Grok (sessionId / GROK_SESSION_ID).
# Touches both legacy prefixes so either stop/refresh check sees the marker.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // .sessionId // .GROK_SESSION_ID // .CLAUDE_SESSION_ID // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then
  SID="${GROK_SESSION_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}"
fi
if [ -n "$SID" ]; then
  touch "/tmp/claude-org-lanes-$SID"
  touch "/tmp/grok-org-lanes-$SID"
fi
exit 0
