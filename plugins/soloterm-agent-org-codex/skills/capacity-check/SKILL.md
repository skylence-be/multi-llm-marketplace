---
name: capacity-check-skill
description: Device-capacity gate for Solo agent spawning (macOS-only probe for now) — run scripts/capacity-probe.sh before every spawn_agent/spawn_process; the GREEN/YELLOW/RED verdict decides spawn now, free-then-spawn, or defer with a one-shot wake. Invoke before spawning Solo agents or when the machine feels slow.
---

# Capacity check (spawn gate)

Solo agents are RAM-expensive (a claude or codex session runs ~0.5-1 GB RSS, more once it works), and an OOM freeze on this 8GB-class hardware kills EVERY lane at once, far more expensive than deferring one spawn. Spawning therefore gates on MEASURED capacity: never on optimism, and never on anxiety either; on GREEN, wide fan-out stays the default, and this gate bounds it by measurement, not fear.

## The probe

Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/capacity-probe.sh"` via skyline_run (or `~/.local/bin/capacity-probe` if installed). macOS-only for now; other platforms return YELLOW/exit 3 (assume constrained). First line is the verdict, and the EXIT CODE is the verdict too, not an error: 0 GREEN, 1 YELLOW, 2 RED, 3 unsupported.

- `VERDICT=GREEN|YELLOW|RED <reason>` — byte math (reclaimable = free+inactive+purgeable+speculative pages) sets the tier; the kernel's own pressure level (1 normal / 2 warn / 4 critical) can only WORSEN it.
- Facts line: `total_gb= reclaimable_gb= pressure_level= swap_used= agent_procs= agent_rss_gb=`, where the last two are the live claude/codex worker process count and their combined RSS, i.e. what the org itself is burning.
- Tunables: `SOLO_CAP_GREEN_GB` (default 2.0), `SOLO_CAP_RED_GB` (default 1.0).

## Decision rules (for the roles that spawn: orchestrator, and the operator)

- Probe BEFORE EVERY spawn (worker, planner, reviewer) and BETWEEN spawns when fanning out a batch: each spawn changes the answer, so never probe once for N spawns.
- GREEN → spawn.
- YELLOW → free capacity FIRST: pay any close-out debt NOW (finished lane still open, idle process, orphan **skyrift** workspace via `skyrift list`/`doctor` on registered sources, orphan git worktree if any fallback trees remain), then re-probe. Nothing freeable → DEFER: arm ONE one-shot wake (10-20 min) whose body names the deferred dispatch, note the deferral on the lane todo, and go do non-spawn work (reviews, board sweep, doc lanes you already own).
- A close-out debt is payable ONLY through the PRE-CLOSE GUARD (orchestrator skill, Standing laws): before closing anything, read its tail; unsubmitted text or input you did not send yourself means an operator may be in that PTY, and that is NOT debt. Skip that close, route it to the operator, and defer the spawn instead. Never buy RAM with someone's live session (field incident 2026-07-06: a planner was closed mid-operator-use to free capacity).
- The WARM PLANNER is never capacity debt (operator order 2026-07-06): idling between requests is its job. On RED, the question ("shut the planner down?") goes to the operator via the QUESTIONS pad; nothing closes it autonomously.
- RED → NO spawns of any kind. Sweep aggressively (close idle lanes, close_process zombies you own), tell PEER orchestrators via their inbox pads so they sweep too (capacity is machine-wide — your lanes share RAM with every other org), re-probe after. RED persisting while dispatchable work queues → escalate to the operator with the probe output pasted.
- A deferral is an EVENT, not a cadence: one wake per deferred dispatch, re-probe when it fires. Never loop-poll capacity.
- On YELLOW/RED, count the whole machine before adding to it: peer orgs' live lanes (list_processes with project_id) are the same RAM pool.

## What this does NOT change

build-slot still owns compile serialization — the capacity gate is about PROCESS count, not builds. Fan-out doctrine stands: build-serialization is not lane-serialization, and imagined machine limits still never justify serial dispatch; the MEASURED verdict is the one machine limit that binds.
