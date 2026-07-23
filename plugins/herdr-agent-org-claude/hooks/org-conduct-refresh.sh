#!/bin/sh
# SessionStart(compact) hook: post-compaction conduct refresh. Compaction keeps
# facts and drops conduct. The role skill's text is among the first things the
# summary evicts, and decay from there is self-invisible to the degraded agent.
#
# Herdr has no per-worker env marker the way Solo has SOLO_PROCESS_ID: every
# pane carries HERDR_ENV=1, orchestrator and worker alike, so this arms for any
# Herdr-managed Claude session (or any session that dispatched). Under-arming
# would cost a worker its conduct right after compaction, which is the exact
# failure the hook exists to prevent; over-arming costs one paragraph, and the
# text below no-ops itself in a session that holds no org role.
command -v jq >/dev/null 2>&1 || exit 0
sid=$(cat | jq -r '.session_id // empty')
if [ "${HERDR_ENV:-}" != "1" ] && { [ -z "$sid" ] || [ ! -f "/tmp/claude-herdr-org-lanes-$sid" ]; }; then
  exit 0
fi
cat <<'EOF'
ORG CONDUCT REFRESH (compaction just ran; Herdr substrate). If you hold no
agent-org role in this session, ignore this. Otherwise: the summary you now run
on keeps facts, not conduct. Your role skill's text is gone and decay from here
is self-invisible. Before the next org action: (1) re-invoke your role skill
(orchestrator; herdr-worker or replacer if you were dispatched; planner if you
are the singleton; the herdr skill for the control surface); (2) re-ANCHOR from
durable state, meaning board list + herdr agent list + herdr pane list. The
board is truth and the summary is hearsay, so re-verify any claim it carries
before acting on it; (3) re-arm a one-shot `herdr agent wait` for every
still-working worker you own, because a missed re-arm right after compaction is
the signature of conduct that did not survive; (4) confirm HERDR_ENV=1 still
holds.
EOF
exit 0
