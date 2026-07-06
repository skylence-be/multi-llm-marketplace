#!/bin/sh
# SessionStart(compact) hook: post-compaction conduct refresh. Compaction keeps
# facts and drops conduct — the role skill's text is the first thing the
# summary evicts, and decay from there is self-invisible to the degraded agent.
# In org sessions (Solo-managed process, or a session that dispatched Solo
# workers), re-inject the order to re-read the role skill before the next org
# beat. Inert everywhere else.
command -v jq >/dev/null 2>&1 || exit 0
sid=$(cat | jq -r '.session_id // empty')
if [ -z "$SOLO_PROCESS_ID" ] && { [ -z "$sid" ] || [ ! -f "/tmp/claude-org-lanes-$sid" ]; }; then
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
