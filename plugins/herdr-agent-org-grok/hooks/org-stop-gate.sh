#!/bin/sh
# Stop hook: anti-idle gate for Grok Herdr org. A session that dispatched Herdr
# workers may not end its turn without confirming follow-up state. Blocks the
# FIRST stop only (deny reason); subsequent stops pass if stop_hook_active.
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

printf '%s' '{"decision":"deny","reason":"ANTI-IDLE FINGERPRINT SWEEP (this session dispatched Herdr workers; post-compaction: re-read your role skill first): (1) idle/done/blocked worker without a verdict? agent read + board comment verdict NOW; (2) live agent whose lane todo is verified/complete? reap/close follow-up NOW (L4; warm planner exempt) and settle worktree/branch per merge state (L5); (3) working agent without an armed agent-wait or re-check plan? arm wait or document plan (L6); (4) unblocked pending todos with free capacity? dispatch; (5) board list + herdr agent list re-read — board is truth. Then stop."}'
exit 0
