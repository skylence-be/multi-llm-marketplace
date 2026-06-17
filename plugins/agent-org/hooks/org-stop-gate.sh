#!/bin/sh
# Stop hook: anti-idle gate. A session that spawned Solo workers may not end
# its turn without confirming follow-up state. Blocks the FIRST stop only
# (stop_hook_active passes the second), so it costs one extra turn, not a loop.
input=$(cat)
active=$(printf '%s' "$input" | /usr/bin/jq -r '.stop_hook_active // false')
sid=$(printf '%s' "$input" | /usr/bin/jq -r '.session_id // empty')
[ "$active" = "true" ] && exit 0
{ [ -n "$sid" ] && [ -f "/tmp/claude-org-lanes-$sid" ]; } || exit 0
printf '%s' '{"decision":"block","reason":"ANTI-IDLE GATE (this session has dispatched Solo workers): before idling, (1) list_processes — any idle or finished worker gets its output read and a verdict/answer NOW; (2) every still-running worker has an armed wake (timer_list; arm timer_fire_when_idle_any if missing — Solo timers are one-shot); (3) blocking operator questions are on the QUESTIONS pad with one notification fired; (4) if no workers remain live, rm /tmp/claude-org-lanes-<your session_id> and stop normally."}'
exit 0
