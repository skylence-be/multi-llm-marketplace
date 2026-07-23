#!/bin/sh
# Stop hook: anti-idle gate. A session that put Herdr org state in flight may
# not end its turn without confirming follow-up. Blocks the FIRST stop only
# (stop_hook_active passes the second), so it costs one extra turn, not a loop.
#
# Carries both fixes the Solo sibling landed 2026-07-21, which the Grok/Herdr
# port predates:
#   PREMISE FOLLOWS EVIDENCE. org-lane-mark.sh records dispatch and wait
#     separately, so a session that only armed a lifecycle wait is never told it
#     dispatched workers.
#   SETTLE. An answered sweep does not re-fire until org state actually moves.
#     The marker's fingerprint IS the state: any new dispatch or wait appends a
#     line, moves the fingerprint, and re-arms the sweep.
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ "$active" = "true" ] && exit 0
marker="/tmp/claude-herdr-org-lanes-$sid"
{ [ -n "$sid" ] && [ -f "$marker" ]; } || exit 0

fp=$(cksum < "$marker" | awk '{print $1 "-" $2}')
seen="/tmp/claude-herdr-org-sweep-$sid"
[ -f "$seen" ] && [ "$(cat "$seen" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$seen"

if grep -q ' dispatch$' "$marker" 2>/dev/null; then
  premise="this session dispatched Herdr workers"
else
  premise="this session armed Herdr org state (lifecycle waits; no worker dispatch recorded)"
fi

reason="ANTI-IDLE FINGERPRINT SWEEP ($premise; post-compaction: re-invoke your role skill FIRST). Run it against live reads, not memory, meaning board list + herdr agent list: (1) an idle/done/blocked worker with no verdict? read it (herdr agent read --source visible; Claude workers render in the alternate screen, so their board comments are the durable record) and post the verdict on its lane todo NOW; (2) a live agent whose lane todo is verified or complete? reap it NOW (L4; the warm planner is exempt, it is operator-owned) and settle lane tree + branch per merge state (L5); (3) a working agent with neither an armed herdr agent wait nor a written re-check plan? arm the wait or write the plan (L6); (4) a blocking operator question still unposted? inbox pad plus one line under Questions; (5) anything you are about to assert that a board list / herdr agent list read would contradict? correct it (L15). Then stop."
# jq builds the payload so the reason is JSON-escaped rather than hand-quoted.
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
