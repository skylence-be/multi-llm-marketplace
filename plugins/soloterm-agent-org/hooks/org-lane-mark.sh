#!/bin/sh
# PreToolUse hook on the Solo spawn/timer tools: records WHAT this Claude
# session actually did, so org-stop-gate.sh can state a premise it can prove.
# Read by org-stop-gate.sh.
#
# Before 2026-07-21 this wrote an empty marker file. The matcher also covers
# timer_set / timer_fire_when_idle_*, so a session that merely armed a timer
# was indistinguishable from one that dispatched workers, and the stop gate
# told it "this session dispatched Solo workers". One line per event fixes
# that without changing when the gate arms.
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
tool=${tool##*__}
[ -n "$tool" ] || tool=unknown
printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tool" >> "/tmp/claude-org-lanes-$sid"
exit 0
