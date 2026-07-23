#!/bin/sh
# PreToolUse hook on the shell-class tools: the PLANNER is a MACHINE-WIDE
# SINGLETON (at most one across every Herdr session on the box), but field
# orchestrators kept spawning local planners "under their own wing" while a
# planner idled next door (Solo field evidence 2026-07-10). Denies any
# planner-named agent start unless a FRESH gate flag (<30 min) proves the deny
# already fired and the sweep ran; the deny text IS the sweep order. Inert for
# every non-planner command.
#
# Herdr's sweep is wider than Solo's: `herdr agent list` is scoped to the
# current session, so a real sweep walks `herdr session list` too.
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '[(.tool_input? // {}) | .. | strings] | join(" ")' 2>/dev/null || true)
case "$cmd" in
  *dispatch-worker*|*"agent start"*) ;;
  *) exit 0 ;;
esac
case "$cmd" in
  *[Pp][Ll][Aa][Nn][Nn][Ee][Rr]*) ;;
  *) exit 0 ;;
esac

sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
flag="/tmp/claude-herdr-planner-gate-${sid:-nosid}"
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

reason="PLANNER SINGLETON GATE: at most ONE planner exists across ALL Herdr sessions on this box, and a planner living in ANOTHER session is YOUR planner. This deny is the sweep order, not an error. NOW: (1) herdr agent list for this session, then herdr session list and one HERDR_SESSION=<name> herdr agent list per other session; (2) a live agent named planner ANYWHERE means do NOT respawn. Write the planning-request todo on YOUR board and point that planner at it (herdr agent prompt <planner> with your board root plus the todo slug; if it is busy, arm a herdr agent wait --until idle and send on settle); (3) only when the sweep proves no planner lives anywhere may you retry this spawn, and the retry passes this gate. Report the sweep result on the requesting todo either way."
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
