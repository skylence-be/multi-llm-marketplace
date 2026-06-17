---
name: org-audit-skill
description: On-demand cold review of the running agent org — board health, lane liveness, verification discipline, token burn. Invoke manually when the operator asks for an outside look; nothing schedules this, ever.
---

# Org audit (on demand, never on a cadence)

One read-only pass; the deliverable is a chat report to the operator.

1. BOARD: todo_list — every in_progress todo has a live owner process (list_processes) and a recent milestone comment; finished work was completed promptly; blockers encode the real gate graph; bodies referencing dead IDs are flagged.
2. LIVENESS: any worker idle with no orchestrator verdict? Any running worker without an armed wake (timer_list)? Both are findings — name the lane and how long it sat.
3. VERIFICATION: sample 2-3 recent merges/completions — was the claim re-run? Does the PR tip actually contain the fix commit? Acceptance that was lint-green but never executed is a finding.
4. BURN: count live processes vs live lanes — any standing process without a current purpose is debris; flag for closure. Any cadence timer existing anywhere is a finding by itself (this org is event-driven by design).
5. REPORT: verdict (healthy / drifting / stalled), findings with full ids and evidence, at most 3 recommended corrections. No board writes; you are eyes, not hands.
