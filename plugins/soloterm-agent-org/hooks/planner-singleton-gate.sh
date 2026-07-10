#!/bin/sh
# PreToolUse hook on mcp__solo__spawn_agent|spawn_process: the PLANNER is a
# MACHINE-WIDE SINGLETON (at most one across ALL Solo projects), but field
# orchestrators kept spawning project-local planners "under their own wing"
# while a planner idled in a peer project (2026-07-10). Denies any
# planner-named spawn unless a FRESH gate flag (<30 min) proves the deny
# already fired and the sweep ran; the deny text IS the sweep order. Inert
# for every non-planner spawn.
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
name=$(printf '%s' "$input" | jq -r '.tool_input.name // empty')
case "$name" in
  *[Pp][Ll][Aa][Nn][Nn][Ee][Rr]*) ;;
  *) exit 0 ;;
esac
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
flag="/tmp/claude-planner-gate-${sid:-nosid}"
if [ -f "$flag" ]; then
  mtime=$(stat -f %m "$flag" 2>/dev/null || stat -c %Y "$flag" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - mtime ))
  if [ "$age" -le 1800 ]; then
    # Consume the flag: a later planner spawn in this session re-gates.
    rm -f "$flag"
    exit 0
  fi
fi
touch "$flag"
printf '%s' '{"decision":"block","reason":"PLANNER SINGLETON GATE: at most ONE planner exists across ALL Solo projects, and a planner living in ANOTHER project is YOUR planner (every solo tool takes a project_id override). This deny is the sweep order, not an error. NOW: (1) list_projects, then list_processes for EVERY project; (2) a live process named planner ANYWHERE means do NOT respawn: write the planning-request todo on YOUR board and send the pointer (your project id + todo id) to THAT planner (idle: send now; busy: arm timer_fire_when_idle_any and send when it frees); (3) ONLY if the sweep proves no planner lives anywhere: capacity-gate (scripts/capacity-probe.sh), then retry this exact spawn; the post-sweep retry passes this gate for 30 minutes."}'
exit 0
