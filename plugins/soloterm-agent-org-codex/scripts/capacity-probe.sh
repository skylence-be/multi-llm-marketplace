#!/bin/sh
# capacity-probe.sh — macOS device-capacity probe for Solo agent-org spawn
# decisions. Solo agents (claude/codex sessions) cost roughly 0.5-1 GB RSS
# each, and an OOM freeze kills EVERY lane at once, so spawning gates on
# MEASURED capacity, never on optimism.
#
# Output: first line `VERDICT=GREEN|YELLOW|RED <reason>`, then fact lines,
# then one guidance line. Exit code IS the verdict, not an error:
#   0 = GREEN  (spawn OK)
#   1 = YELLOW (free capacity first, or defer with a one-shot wake)
#   2 = RED    (no spawns; sweep; escalate if persistent)
#   3 = probe unsupported/failed (non-macOS) — treat as YELLOW
#
# Tunables (env):
#   SOLO_CAP_GREEN_GB  reclaimable-GB floor for GREEN (default 2.0)
#   SOLO_CAP_RED_GB    reclaimable-GB floor below which RED (default 1.0)
#
# "Reclaimable" = free + inactive + purgeable + speculative pages: what macOS
# can hand out without swapping. The kernel pressure level (1 normal, 2 warn,
# 4 critical) can only make the verdict WORSE, never better.

[ "$(uname -s)" = "Darwin" ] || { echo "VERDICT=YELLOW non-macOS: probe unsupported, assume constrained"; exit 3; }

GREEN_GB=${SOLO_CAP_GREEN_GB:-2.0}
RED_GB=${SOLO_CAP_RED_GB:-1.0}

total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
page=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
vmstat=$(vm_stat 2>/dev/null) || { echo "VERDICT=YELLOW vm_stat failed, assume constrained"; exit 3; }

pget() {
  printf '%s\n' "$vmstat" | awk -v k="$1" -F':' '
    $1 == k { gsub(/[. ]/, "", $2); print $2; found = 1 }
    END { if (!found) print 0 }'
}
free=$(pget "Pages free")
inactive=$(pget "Pages inactive")
purgeable=$(pget "Pages purgeable")
speculative=$(pget "Pages speculative")

avail_gb=$(awk -v p="$page" -v a="$free" -v b="$inactive" -v c="$purgeable" -v d="$speculative" \
  'BEGIN { printf "%.2f", (a + b + c + d) * p / 1073741824 }')
total_gb=$(awk -v t="$total_bytes" 'BEGIN { printf "%.1f", t / 1073741824 }')

pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)
swap_used=$(sysctl -n vm.swapusage 2>/dev/null | awk '{ print $6 }')
agents=$(ps -axo rss=,comm= | awk '
  $2 ~ /(^|\/)(claude|codex)$/ { n++; s += $1 }
  END { printf "%d %.2f", n + 0, s / 1048576 }')
agent_count=${agents% *}
agent_rss_gb=${agents#* }

verdict=GREEN
reason="reclaimable ${avail_gb}GB >= ${GREEN_GB}GB, kernel pressure normal"
if awk -v a="$avail_gb" -v r="$RED_GB" 'BEGIN { exit !(a < r) }'; then
  verdict=RED reason="reclaimable ${avail_gb}GB < ${RED_GB}GB floor"
elif awk -v a="$avail_gb" -v g="$GREEN_GB" 'BEGIN { exit !(a < g) }'; then
  verdict=YELLOW reason="reclaimable ${avail_gb}GB < ${GREEN_GB}GB comfort floor"
fi
case $pressure in
  4) verdict=RED reason="kernel memory pressure CRITICAL (level 4)" ;;
  2) [ "$verdict" = "GREEN" ] && verdict=YELLOW reason="kernel memory pressure WARN (level 2)" ;;
esac

echo "VERDICT=$verdict $reason"
echo "total_gb=$total_gb reclaimable_gb=$avail_gb pressure_level=$pressure swap_used=${swap_used:-n/a} agent_procs=$agent_count agent_rss_gb=$agent_rss_gb"
case $verdict in
  GREEN)  echo "guidance: spawn OK — re-probe BETWEEN spawns when fanning out a batch; each spawn changes the answer."; exit 0 ;;
  YELLOW) echo "guidance: free capacity FIRST (pay close-out debts: finished lanes, idle procs, orphan worktrees), re-probe; else DEFER with ONE one-shot wake naming the deferred dispatch."; exit 1 ;;
  RED)    echo "guidance: NO spawns. Sweep idle lanes now, tell peer orchestrators to sweep too, re-probe; if RED persists with work queued, escalate to the operator with this output."; exit 2 ;;
esac
