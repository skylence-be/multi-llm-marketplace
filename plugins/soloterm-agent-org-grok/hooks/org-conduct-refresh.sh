#!/bin/sh
# SessionStart hook for Grok, two events, one contract.
#
# startup/resume: a Solo-managed process IS an org lane, and nothing else in a
# fresh session reliably says so. The dispatch pointer names the role skill,
# but a pointer is prose a model can read past, and a role that never invoked
# its skill is not running under it. Prime the contract before the first beat.
#
# compact: compaction keeps facts and drops conduct. The role skill's text is
# the first thing a summary evicts, the decay is self-invisible to the degraded
# agent, and a half-remembered skill is exactly where clauses go optional.
#
# Inert outside org sessions (no SOLO_PROCESS_ID and no marked lane).
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then SID="${GROK_SESSION_ID:-}"; fi
SRC=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)

if [ -z "$SOLO_PROCESS_ID" ] && { [ -z "$SID" ] || [ ! -f "/tmp/grok-org-lanes-$SID" ]; }; then
  exit 0
fi

if [ "$SRC" = "compact" ]; then
  cat <<'EOF'
ORG CONDUCT REFRESH (compaction just ran): the summary you now run on keeps
facts, not conduct. Your role skill's text is gone, decay from here is
self-invisible, and the skill did not become advisory because you compacted:
it is still the contract you are under, in full (L0). Before the next org
action: (1) re-invoke your role skill (orchestrator; solo-worker/replacer if
you were dispatched); (2) re-ANCHOR from the board, todo_list +
list_processes + timer_list + scratchpad_list; the board is truth and the
summary is hearsay, so re-verify any of its claims before acting on them;
(3) run the skill's wake-close retrospective on your next beat: a missed
re-arm or close-out right after compaction means conduct did not survive.
EOF
else
  cat <<'EOF'
ORG CONDUCT PRIME (this session runs as a Solo-managed org process): before
your first org action, invoke the role skill your dispatch names (orchestrator,
solo-worker, planner, replacer). If none is named, read your todo body and ask
rather than improvise. That skill is a CONTRACT, not a menu: it binds in full,
every clause, until this session ends, and the clauses that read like overhead
are the ones other roles are counting on. Skipping, deferring, or substituting
a step is a deviation, and a deviation is declared where the org can see it
(a todo comment, [LAW-FRICTION] as the orchestrator, [CONDUCT] as a worker),
never dropped silently. The org moves at the speed of its least compliant role.
EOF
fi
exit 0
