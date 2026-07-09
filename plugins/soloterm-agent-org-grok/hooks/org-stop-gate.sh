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
printf '%s' '{"decision":"deny","reason":"ANTI-IDLE GATE (this session has dispatched Solo workers): before idling, (0) CONDUCT: if compaction has run since you last read your role skill, re-read it FIRST (summaries keep facts, not conduct); (1) list_processes: any idle or finished worker gets its output read and a verdict/answer NOW; (1b) LANE CLOSE-OUT: any RUNNING lane whose todos are all completed/merged is DEBRIS (EXCEPT the warm planner: operator-owned, never auto-closed). close_process (PRE-CLOSE GUARD first: read its tail; unsubmitted text or operator-typed input = do NOT close, ask instead) + git worktree remove + delete its merged branch NOW, and VERIFY each deletion (gh --delete-branch fails silently; re-list branches). Lane reuse does not defer this: on the LAST todo, the close-out happens here; (2) every still-running worker has an armed wake (timer_list; arm timer_fire_when_idle_any if missing; Solo timers are one-shot); (3) blocking operator questions are on the QUESTIONS pad with one notification fired; (4) if no workers remain live, rm /tmp/grok-org-lanes-'"$SID"' so this gate disarms. Then stop again."}'
exit 0
