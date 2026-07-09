#!/bin/sh
# SessionStart(compact) hook for Grok: post-compaction conduct refresh.
# In org sessions (SOLO_PROCESS_ID or marked lane), remind to re-read role skills
# and re-anchor from board. Inert otherwise.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then SID="${GROK_SESSION_ID:-}"; fi

if [ -z "$SOLO_PROCESS_ID" ] && { [ -z "$SID" ] || [ ! -f "/tmp/grok-org-lanes-$SID" ]; }; then
  exit 0
fi

cat <<'EOF'
ORG CONDUCT REFRESH (compaction just ran): the summary you now run on keeps
facts, not conduct — your role skill's text is gone and decay from here is
self-invisible. Before the next org action: (1) re-invoke your role skill
(orchestrator; solo-worker/replacer if you were dispatched); (2) re-ANCHOR from
the board — todo_list + list_processes + timer_list + scratchpad_list; the
board is truth, the summary is hearsay: re-verify any of its claims before
acting on them; (3) run the skill's wake-close retrospective on your next beat
— a missed re-arm or close-out right after compaction means conduct did not
survive.
EOF
exit 0
