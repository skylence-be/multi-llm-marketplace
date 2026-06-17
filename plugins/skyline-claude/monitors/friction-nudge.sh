#!/usr/bin/env bash
# friction-nudge.sh — debounced friction reporter (tracks skylence-be/skyline#6).
#
# After the agent stops calling skyline tools for IDLE seconds (it has "stopped
# typing"), if new friction has been recorded since the last nudge, emit ONE
# line asking the agent to file it. Fires once per friction cluster, never
# mid-flow, never per event. Each stdout line is delivered to the agent as a
# notification by the monitor harness (same channel as daemon-watchdog.sh).
#
# Friction source (a proxy until skyline#6 lands a clean always-on friction
# feed): devlog warn/error records and common friction markers. Idle source:
# the max `ts` (epoch seconds) across the audit + devlog jsonl logs.
#
# INERT BY DESIGN when the observability streams are off (the default): if the
# log files do not exist it simply never fires. Power it on with
#   skyline observability set --devlog on --audit on
# (or the skyline_observability_set MCP tool). Tune the debounce window with
# SKYLINE_FRICTION_IDLE_SECS; point at a non-default data dir with
# SKYLINE_DATA_DIR.

set -u

DATA="${SKYLINE_DATA_DIR:-$HOME/Library/Caches/skyline}"
AUDIT="$DATA/logs/audit.jsonl"
DEVLOG="$DATA/logs/devlog.jsonl"
IDLE="${SKYLINE_FRICTION_IDLE_SECS:-45}"
STATE="${TMPDIR:-/tmp}/skyline-friction-nudge.state"

# Count of friction-flavored devlog records. -h suppresses filenames so the
# count is across the live log and its rotated backup.
friction_count() {
  grep -hiE '"level":"(warn|error)"|guide-gate|stale[- ]?tag|reject|fallback' \
    "$DEVLOG" "$DEVLOG.1" 2>/dev/null | wc -l | tr -d ' '
}

# Most recent activity timestamp across both streams (epoch seconds).
last_ts() {
  grep -hoE '"ts":[0-9]+' "$AUDIT" "$DEVLOG" 2>/dev/null \
    | grep -oE '[0-9]+' | sort -n | tail -1
}

while true; do
  sleep 15

  { [ -f "$AUDIT" ] || [ -f "$DEVLOG" ]; } || continue

  lt=$(last_ts)
  [ -n "$lt" ] || continue
  now=$(date +%s)
  # Still active (the agent is "typing") — wait for the idle window to pass.
  [ $((now - lt)) -ge "$IDLE" ] || continue

  fc=$(friction_count)
  prev=$(cat "$STATE" 2>/dev/null || echo 0)
  case "$prev" in '' | *[!0-9]*) prev=0 ;; esac

  if [ "$fc" -gt "$prev" ]; then
    new=$((fc - prev))
    echo "$new new skyline friction event(s) recorded since the last check (devlog warnings/errors: stale-tag rejections, guide-gate blocks, shell fallbacks). If any is a real defect, file it with skyline_report_issue after searching open AND closed issues; comment new evidence on a match instead of opening a duplicate."
    echo "$fc" > "$STATE"
  elif [ "$fc" -lt "$prev" ]; then
    # Log rotated or cleared; resync the baseline downward without nudging.
    echo "$fc" > "$STATE"
  fi
done
