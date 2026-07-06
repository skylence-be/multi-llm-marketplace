#!/bin/sh
# Codex SessionStart hook for the soloterm-agent-org-codex plugin.
cat <<'EOF'
## agent-org Codex

This plugin exposes orchestrator, planner, replacer, org-audit, and
solo-worker skills. If this session is the conductor, invoke orchestrator and
operate from Solo todos/processes/timers — program-sized work is planned by
the PLANNER (strongest model, max effort), the conductor only delegates it.
If this session is a dispatched worker, invoke
solo-worker and read the todo body before implementing. Workers NEVER compile
(no cargo/go build/test/clippy, no build-slot) — the orchestrator runs the
single gate build at feature-end via build-slot; cargo nextest stays banned.
Milestone reports need exact commands, counts, SHAs, and artifact paths.
Spawns gate on the capacity probe (capacity-check skill / capacity-probe.sh),
and the PLANNER is a machine-wide singleton — find the live one across all
projects before spawning another.
If this block arrived after a COMPACTION: re-invoke your role skill and
re-anchor from the board before the next action — summaries keep facts, not
conduct.
EOF
exit 0
