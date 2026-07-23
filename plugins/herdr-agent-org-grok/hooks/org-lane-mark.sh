#!/bin/sh
# PreToolUse hook: mark this Grok session as having dispatched Herdr workers.
# Read by org-stop-gate. Marks only when the tool input looks like a dispatch.
set -e
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // .GROK_SESSION_ID // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then
  SID="${GROK_SESSION_ID:-}"
fi

# Heuristic: command string mentions herdr agent start or dispatch-worker
HIT=$(printf '%s' "$INPUT" | jq -r '
  [
    .tool_input.command // empty,
    (.tool_input.argv // []) | join(" "),
    (.tool_input.argv_list // [] | map(join(" ")) | join(" ")),
    .tool_name // empty
  ] | join(" ")
' 2>/dev/null || true)

case "$HIT" in
  *"agent start"*|*dispatch-worker*|*dispatch_worker*)
    [ -n "$SID" ] && touch "/tmp/grok-herdr-org-lanes-$SID"
    if [ -z "$SID" ] && [ "${HERDR_ENV:-}" = "1" ]; then
      touch "/tmp/grok-herdr-org-lanes-herdr-env"
    fi
    ;;
esac
exit 0
