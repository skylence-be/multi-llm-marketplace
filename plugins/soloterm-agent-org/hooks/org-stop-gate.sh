#!/bin/sh
# Stop hook: anti-idle gate. A session that dispatched Solo workers may not end
# its turn without confirming follow-up state. Blocks the FIRST stop only
# (stop_hook_active passes the second), so it costs one extra turn, not a loop.
#
# Two defects fixed 2026-07-21 (L4 hook friction). Neither weakens the sweep:
#   1. FALSE PREMISE: the opening claim "this session dispatched Solo workers"
#      was unconditional, but org-lane-mark.sh also arms on timer_set and
#      timer_fire_when_idle_*. A session that only armed a timer, or whose
#      spawn failed (the mark is PreToolUse), was told it dispatched workers.
#      The premise now follows the recorded evidence.
#   2. REPETITION: an identical sweep re-fired on every stop attempt even when
#      the previous one ran clean and nothing moved. A sweep that was already
#      answered now settles until org state actually changes.
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ "$active" = "true" ] && exit 0
marker="/tmp/claude-org-lanes-$sid"
{ [ -n "$sid" ] && [ -f "$marker" ]; } || exit 0

# SETTLE: fingerprint the org state this sweep is about. org-lane-mark.sh
# appends a line per spawn/timer, so any new dispatch moves the fingerprint and
# re-arms the sweep; an unchanged fingerprint means the last sweep already
# covered this exact state and repeating it buys nothing.
fp=$(cksum < "$marker" | awk '{print $1 "-" $2}')
seen="/tmp/claude-org-sweep-$sid"
[ -f "$seen" ] && [ "$(cat "$seen" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$seen"

# PREMISE follows evidence: claim dispatched workers only when spawn_agent is
# on the record. Legacy empty markers (pre-2026-07-21) fall to the neutral case.
if grep -q 'spawn_agent' "$marker" 2>/dev/null; then
  premise="this session dispatched Solo workers"
else
  premise="this session armed Solo org state (timers or processes; no worker dispatch recorded)"
fi

reason="ANTI-IDLE FINGERPRINT SWEEP ($premise; post-compaction: re-read your role skill first): (1) idle or finished worker without a verdict? read output, verdict NOW; (2) live proc whose lane todo is verified/complete, review pending or not? close it NOW (L4; warm planner exempt: operator-owned) and settle worktree/branch per merge state (L5), verifying deletions; (3) running worker without an armed wake? arm one, cancel superseded gens (L6); (4) blocking operator question unposted? QUESTIONS pad + one notification. None of these and no live workers: rm /tmp/claude-org-lanes-<your session_id>, then stop again. This sweep will not repeat until org state changes."
# jq builds the payload so the reason is JSON-escaped rather than hand-quoted.
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
