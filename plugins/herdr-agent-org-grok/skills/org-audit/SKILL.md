---
name: org-audit
description: On-demand cold review of the running Herdr agent org — board health, lane liveness, verification discipline, token burn. Invoke manually when the operator asks for an outside look; nothing schedules this, ever.
---

# Org audit (on demand, never on a cadence)

One read-only pass; the deliverable is a chat report to the operator.

1. BOARD: `board list` + sample `board get` — every in_progress todo has a live owner agent (`herdr agent list`) and a recent milestone comment; finished work was completed promptly; blockers encode the real gate graph; bodies referencing dead IDs are flagged. Pads: superseded/concluded pads still unarchived are flagged. GitHub: done-but-open issues/epics.
2. LIVENESS: any worker agent `idle`/`done`/`blocked` with no orchestrator verdict? Any `working` agent without a pending wait or orchestrator plan to re-check? Name the lane and how long it sat (`herdr agent get <name>`).
3. VERIFICATION: sample 2–3 recent merges/completions — was the claim re-run? Does the PR tip actually contain the fix commit? Acceptance that was lint-green but never executed is a finding.
4. BURN: count live Herdr agents vs live board lanes; any standing agent without a current purpose is debris (EXCEPTION: warm planner singleton is operator-owned; idling between requests is its job). Cadence polling loops are a finding — this org is event-driven (`agent wait`, not sleep loops).
5. HERDR HEALTH: is the auditor/orchestrator inside `HERDR_ENV=1`? Are panes orphaned (no agent, no useful shell)? Flag stray workspaces from abandoned experiments.
6. REPORT: verdict (healthy / drifting / stalled), findings with full ids and evidence, at most 3 recommended corrections. No board writes; you are eyes, not hands.
