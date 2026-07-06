#!/bin/sh
# Codex SessionStart hook for the soloterm-agent-org-codex plugin.
cat <<'EOF'
## agent-org Codex

This plugin exposes orchestrator, replacer, org-audit, and solo-worker skills.
If this session is the conductor, invoke orchestrator and operate from Solo
todos/processes/timers. If this session is a dispatched worker, invoke
solo-worker and read the todo body before implementing. Workers NEVER compile
(no cargo/go build/test/clippy, no build-slot) — the orchestrator runs the
single gate build at feature-end via build-slot; cargo nextest stays banned.
Milestone reports need exact commands, counts, SHAs, and artifact paths.
If this block arrived after a COMPACTION: re-invoke your role skill and
re-anchor from the board before the next action — summaries keep facts, not
conduct.
EOF
exit 0
