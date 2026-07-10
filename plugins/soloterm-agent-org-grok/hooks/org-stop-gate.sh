#!/bin/sh
# Stop hook: anti-idle gate for Grok. A session that spawned Solo workers may not
# end its turn without confirming follow-up state. Blocks the FIRST stop only
# (by emitting a deny reason; subsequent stops pass if stop_hook_active or the
# file is cleaned).
# Grok Stop is passive but the reason is shown; the checklist forces the extra turn.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // .stopHookActive // false' 2>/dev/null || echo false)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then SID="${GROK_SESSION_ID:-}"; fi

[ "$ACTIVE" = "true" ] && exit 0
{ [ -n "$SID" ] && [ -f "/tmp/grok-org-lanes-$SID" ]; } || exit 0

# Emit a deny-style payload; even if passive the UI will surface the reason as the gate message.
printf '%s' '{"decision":"deny","reason":"ANTI-IDLE FINGERPRINT SWEEP (this session dispatched Solo workers; post-compaction: re-read your role skill first): (1) idle or finished worker without a verdict? read output, verdict NOW; (2) live proc whose lane todo is verified/complete, review pending or not? close it NOW (L4; warm planner exempt: operator-owned) and settle worktree/branch per merge state (L5), verifying deletions; (3) running worker without an armed wake? arm one, cancel superseded gens (L6); (4) blocking operator question unposted? QUESTIONS pad + one notification. None of these and no live workers: rm /tmp/grok-org-lanes-'"$SID"', then stop again."}'
exit 0
