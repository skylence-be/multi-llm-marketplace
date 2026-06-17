#!/bin/sh
# Codex SessionStart hook for the agent-org-codex plugin.
cat <<'EOF'
## agent-org Codex

This plugin exposes orchestrator, replacer, org-audit, and solo-worker skills.
If this session is the conductor, invoke orchestrator and operate from Solo
todos/processes/timers. If this session is a dispatched worker, invoke
solo-worker and read the todo body before implementing. Compiling commands must
go through build-slot, cargo nextest stays banned, and milestone reports need
exact commands, counts, SHAs, and artifact paths.
EOF
exit 0
