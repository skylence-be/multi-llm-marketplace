---
name: org-audit-skill
description: On-demand cold review of the running agent org — board health, lane liveness, verification discipline, token burn. Invoke manually when the operator asks for an outside look; nothing schedules this, ever.
---

# Org audit (on demand, never on a cadence)

One read-only pass; the deliverable is a chat report to the operator.

## This skill is a contract, not a menu

Every pass below runs, every time, including the ones you expect back clean: an audit that skips a check reports health it never measured, and a clean verdict is exactly what the org will act on.

1. BOARD: todo_list, where every in_progress todo has a live owner process (list_processes) and a recent milestone comment; finished work was completed promptly; blockers encode the real gate graph; bodies referencing dead IDs are flagged. scratchpad_list, where superseded/concluded pads still unarchived (stale handoffs, shipped-issue research, done gate pads) are flagged. GitHub: done-but-open issues/epics (PR merged or all children closed) and any completed-todo / dead-in_progress board clutter are flagged as bloat. BRANCHES: any local or remote branch whose PR has merged or was closed yet still lingers undeleted is flagged (a squash-merge hides this from git ancestry, so judge by PR state, not `git branch --merged`); a branch with an open PR or unpushed unique commits is NOT debris.
2. LIVENESS: any worker idle with no orchestrator verdict? Any running worker without an armed wake (timer_list)? Both are findings — name the lane and how long it sat.
3. VERIFICATION: sample 2-3 recent merges/completions — was the claim re-run? Does the PR tip actually contain the fix commit? Acceptance that was lint-green but never executed is a finding.
4. BURN: count live processes vs live lanes; any standing process without a current purpose is debris; flag for closure (EXCEPTION: the warm planner singleton is operator-ratified 2026-07-06; idling between requests is its job, not debris). Any cadence timer existing anywhere is a finding by itself (this org is event-driven by design).
5. CONTRACT: this org's characteristic failure is discipline steps going optional under forward-motion bias (marketplace#32: three skill breaches in one session, not one of them a missing capability), so audit for it directly. Look for a lane dispatched with no role skill named in the pointer; a worker todo carrying one closing summary and no milestone comments; a finished lane whose PTY is still alive; a lane tree created by a route the brief template ranks below one that was available, with no reason on the board; a dispatch left on install defaults with no [EFFORT]/[MODEL] filing; any deviation with no [LAW-FRICTION] or [CONDUCT] filing behind it. Name the role and the exact clause it dropped; "looks sloppy" is not a finding.
6. REPORT: verdict (healthy / drifting / stalled), findings with full ids and evidence, at most 3 recommended corrections. No board writes; you are eyes, not hands.
