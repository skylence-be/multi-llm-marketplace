#!/bin/sh
# Stop hook: anti-idle gate. A session that spawned Solo workers may not end
# its turn without confirming follow-up state. Blocks the FIRST stop only
# (stop_hook_active passes the second), so it costs one extra turn, not a loop.
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ "$active" = "true" ] && exit 0
{ [ -n "$sid" ] && [ -f "/tmp/claude-org-lanes-$sid" ]; } || exit 0
printf '%s' '{"decision":"block","reason":"ANTI-IDLE FINGERPRINT SWEEP (this session dispatched Solo workers; post-compaction: re-read your role skill first): (1) idle or finished worker without a verdict? read output, verdict NOW; (2) live proc whose lane todo is verified/complete, review pending or not? close it NOW (L4; warm planner exempt: operator-owned) and settle worktree/branch per merge state (L5), verifying deletions; (3) running worker without an armed wake? arm one, cancel superseded gens (L6); (4) blocking operator question unposted? QUESTIONS pad + one notification. None of these and no live workers: rm /tmp/claude-org-lanes-<your session_id>, then stop again."}'
exit 0
