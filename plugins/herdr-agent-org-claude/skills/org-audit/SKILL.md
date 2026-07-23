---
name: herdr-org-audit
description: On-demand cold review of the running Herdr agent org. Board health, lane liveness, verification discipline, token burn. Invoke manually when the operator asks for an outside look; nothing schedules this, ever.
---

# Org audit (on demand, never on a cadence)

One read-only pass; the deliverable is a chat report to the operator. No board writes: you are eyes, not hands.

1. BOARD: `board list` plus a sample of `board get`. Every `in_progress` todo should have a live owner in `herdr agent list` and a recent milestone comment; finished work should have been completed promptly; blockers should encode the real gate graph; bodies referencing dead pane or agent IDs are flagged. Pads: superseded or concluded pads still unarchived are flagged. GitHub: issues and epics that are done but still open.
2. LIVENESS: any worker `idle`, `done`, or `blocked` with no orchestrator verdict? Any `working` agent with neither a pending wait nor a written re-check plan? Name the lane and how long it sat (`herdr agent get <name>`).
3. VERIFICATION: sample 2 or 3 recent merges or completions. Was the claim re-run rather than inherited (L9)? Does the PR tip actually contain the fix commit? An acceptance that was lint-green but never executed is a finding.
4. BURN: count live Herdr agents against live board lanes. Any standing agent without a current purpose is debris, with one exception: the warm planner singleton is operator-owned, and idling between requests is its job. Cadence polling loops are a finding by themselves, since this org is event-driven (`agent wait`, not `sleep` loops).
5. HERDR HEALTH: is the orchestrator inside `HERDR_ENV=1`? Are there orphaned panes (no agent, no useful shell)? Flag stray workspaces from abandoned experiments. Check `herdr session list` for org state stranded in a session nobody is watching. IDENTITY (L18): any org agent still showing a bare runtime name (`claude`, `grok`) or carrying a name from a lane that already closed is a finding, because the sidebar is the operator's only view.
6. CLAUDE-SPECIFIC: a pane's scrollback dies with the pane, and a verified lane's agent is reaped (L4), so a lane whose evidence exists only in pane output has no evidence. Sample one accepted lane and check the claim is on the board, not just in someone's memory of a tail.
7. REPORT: verdict (healthy / drifting / stalled), findings with full IDs and evidence, and at most 3 recommended corrections.
