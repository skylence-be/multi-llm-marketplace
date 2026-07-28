#!/bin/sh
# SessionStart(startup|resume) hook for Grok: prime the role-skill contract
# before the first beat (soloterm #38, backported). A dispatch pointer is
# prose a model can read past, and a role that never invoked its skill is not
# running under it. Inert outside org sessions. Some Grok versions drop
# SessionStart stdout; AGENTS.md carries the same Binding line as fallback.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .session_id // empty' 2>/dev/null || true)
[ -z "$SID" ] && SID="${GROK_SESSION_ID:-}"

MARKED=0
[ -n "$SID" ] && [ -f "/tmp/grok-herdr-org-lanes-$SID" ] && MARKED=1
[ -f "/tmp/grok-herdr-org-lanes-herdr-env" ] && MARKED=1
[ "${HERDR_ENV:-}" = "1" ] && MARKED=1

[ "$MARKED" -eq 1 ] || exit 0

cat <<'EOF'
ORG CONDUCT PRIME (Herdr-managed session): if your first message is a dispatch
brief or pointer, invoke the role skill it names (herdr-worker; replacer;
orchestrator if you are the conductor) BEFORE your first org action. A pointer
is prose a model can read past, and a role that never invoked its skill is not
running under it. That skill is a CONTRACT, not a menu (L0): it binds in full,
every clause, until this session ends, and the clauses that read like overhead
are the ones other roles are counting on. Skipping, deferring, or substituting
a step is a deviation, declared where the org can see it ([LAW-FRICTION] as
the orchestrator, [CONDUCT] as a worker), never dropped silently. Holding no
org role in this session? Ignore this.
EOF
exit 0
