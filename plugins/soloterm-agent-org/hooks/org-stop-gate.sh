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
printf '%s' '{"decision":"block","reason":"ANTI-IDLE GATE (this session has dispatched Solo workers): before idling, (1) list_processes — any idle or finished worker gets its output read and a verdict/answer NOW; (1b) LANE CLOSE-OUT: any RUNNING lane whose todos are all completed/merged is DEBRIS — close_process + git worktree remove + delete its merged branch NOW, and VERIFY each deletion (gh --delete-branch fails silently; re-list branches). Lane reuse does not defer this: on the LAST todo, the close-out happens here; (2) every still-running worker has an armed wake (timer_list; arm timer_fire_when_idle_any if missing — Solo timers are one-shot); (3) blocking operator questions are on the QUESTIONS pad with one notification fired; (4) if no workers remain live, rm /tmp/claude-org-lanes-<your session_id> so this gate disarms. Then stop again."}'
exit 0
