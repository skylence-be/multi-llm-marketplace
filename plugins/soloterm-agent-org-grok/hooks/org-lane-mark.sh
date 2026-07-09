#!/bin/sh
# PreToolUse hook: mark this Grok session as having dispatched Solo workers/timers.
# Read by org-stop-gate. Uses GROK_SESSION_ID (with fallback).
set -e
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // .GROK_SESSION_ID // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then
  SID="${GROK_SESSION_ID:-}"
fi
[ -n "$SID" ] && touch "/tmp/grok-org-lanes-$SID"
exit 0
