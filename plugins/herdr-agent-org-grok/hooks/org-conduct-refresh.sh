#!/bin/sh
# SessionStart(compact) hook for Grok: post-compaction conduct refresh.
# In Herdr org sessions (HERDR_ENV=1 or marked lane), remind to re-read role skills
# and re-anchor from board + agent list. Inert otherwise.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then SID="${GROK_SESSION_ID:-}"; fi

MARKED=0
[ -n "$SID" ] && [ -f "/tmp/grok-herdr-org-lanes-$SID" ] && MARKED=1
[ -f "/tmp/grok-herdr-org-lanes-herdr-env" ] && MARKED=1
[ "${HERDR_ENV:-}" = "1" ] && MARKED=1

[ "$MARKED" -eq 1 ] || exit 0

cat <<'EOF'
ORG CONDUCT REFRESH (compaction just ran — Herdr substrate): the summary you
now run on keeps facts, not conduct — your role skill's text is gone and decay
from here is self-invisible. Before the next org action: (1) re-invoke your
role skill (orchestrator; herdr-worker/replacer if you were dispatched; herdr
for control surface); (2) re-ANCHOR from the board + Herdr — board list +
herdr agent list + herdr pane list; the board is truth, the summary is hearsay:
re-verify any of its claims before acting on them; (3) re-arm one-shot agent
waits for every still-working worker you own — a missed wait right after
compaction means conduct did not survive; (4) confirm HERDR_ENV=1 still holds.
EOF
exit 0
