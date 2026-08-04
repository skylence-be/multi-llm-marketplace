#!/bin/sh
# Stop hook: anti-idle gate for Grok Herdr org. A session that dispatched Herdr
# workers may not end its turn without confirming follow-up state. Blocks the
# FIRST stop only (deny reason); subsequent stops pass if stop_hook_active.
# 2026-08-04: relay-backlog aware — unconsumed relay messages for this pane's
# agent get named first in the deny reason (paddle-GDPR stall: messages rotted
# 3h23m behind a turn that ended onto a quiet queue).
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // .stopHookActive // false' 2>/dev/null || echo false)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then SID="${GROK_SESSION_ID:-}"; fi

[ "$ACTIVE" = "true" ] && exit 0

MARKED=0
[ -n "$SID" ] && [ -f "/tmp/grok-herdr-org-lanes-$SID" ] && MARKED=1
[ -f "/tmp/grok-herdr-org-lanes-herdr-env" ] && MARKED=1
[ "$MARKED" -eq 1 ] || exit 0

relay_line=""
relay_db="$HOME/.config/herdr/org-relay/relay.db"
if [ -n "${HERDR_PANE_ID:-}" ] && [ -f "$relay_db" ] && command -v sqlite3 >/dev/null 2>&1; then
  ME=$("${HERDR_BIN_PATH:-herdr}" agent list 2>/dev/null | jq -r --arg p "$HERDR_PANE_ID" '.result.agents[]? | select(.pane_id==$p) | .name // empty' 2>/dev/null | head -1)
  if [ -n "$ME" ]; then
    ME_SQL=$(printf '%s' "$ME" | sed "s/'/''/g")
    N=$(sqlite3 -readonly "$relay_db" "SELECT COUNT(*) FROM messages WHERE recipient='$ME_SQL' AND consumed_at IS NULL;" 2>/dev/null)
    if [ -n "$N" ] && [ "$N" -gt 0 ] 2>/dev/null; then
      relay_line="RELAY BACKLOG: $N unconsumed relay message(s) queued for $ME — relay_inbox(agent: $ME), act, consume, re-arm coverage BEFORE idling. "
    fi
  fi
fi

jq -n --arg r "${relay_line}ANTI-IDLE FINGERPRINT SWEEP (this session dispatched Herdr workers; post-compaction: re-read your role skill first): (1) idle/done/blocked worker without a verdict? agent read + board comment verdict NOW; (2) ANY live agent (working/idle/blocked/done) whose lane todo is verified/complete? unregister (waker-ctl unregister --lane) then REAP pane NOW same beat as accept: idle named grok is still L4 FP (marketplace#32); L5 is tree/branch only after merge; (3) in-flight lanes with no relay coverage? relay_inbox(agent: <you>) for backlog, then re-arm relay_await or document (L6); (4) unblocked pending todos with free capacity? dispatch; (5) board list + herdr agent list re-read: board is truth; (6) never operator status that says lane done while that agent still lists. Then stop." '{decision:"deny", reason:$r}'
exit 0
