---
name: org-audit
description: On-demand cold review of the running Herdr agent org — board health, lane liveness, verification discipline, token burn. Invoke manually when the operator asks for an outside look; nothing schedules this, ever.
---

# Org audit (on demand, never on a cadence)

One read-only pass; the deliverable is a chat report to the operator.

## This skill is a contract, not a menu

Every pass below runs, every time, including the ones you expect back clean: an audit that skips a check reports health it never measured, and a clean verdict is exactly what the org will act on.

1. BOARD: `board list` + sample `board get` — every in_progress todo has a live owner agent (`herdr agent list`) and a recent milestone comment; finished work was completed promptly; blockers encode the real gate graph; bodies referencing dead IDs are flagged. Pads: superseded/concluded pads still unarchived are flagged. GitHub: done-but-open issues/epics.
2. LIVENESS: any worker agent `idle`/`done`/`blocked` with no orchestrator verdict? Any `working` agent with neither a waker registration (`waker-ctl list`) nor an armed wait nor a written re-check plan (L6)? Name the lane and how long it sat (`herdr agent get <name>`).
3. VERIFICATION: sample 2–3 recent merges/completions — was the claim re-run? Does the PR tip actually contain the fix commit? Acceptance that was lint-green but never executed is a finding.
4. BURN: count live Herdr agents vs live board lanes; any standing agent without a current purpose is debris. Cadence polling loops are a finding: this org is event-driven (waker rings and one-shot `agent wait`, not sleep loops).
5. WAKER: cross-check `waker-ctl list` against `herdr agent list`: a registered lane whose agent/pane is gone is a missed unregister or a lost event; a reaped lane still registered is an L6 finding. Held pending wakes older than ~15 min with no drain, or stuck `.claim` files, mean rings are parking. `herdr plugin list` must show org-waker enabled, else every working lane needs a fallback wait armed.
6. CONTRACT: this org's characteristic failure is discipline steps going optional under forward-motion bias (marketplace#32: three skill breaches in one session, none a missing capability), so audit for it directly: a lane dispatched with no role skill named in the pointer; a worker todo with one closing summary and no milestones; a finished lane whose agent is still live; a reaped lane still in `waker-ctl list`; a lane tree via a lower-ranked route with no reason on the board; a dispatch above doctrine defaults with no [EFFORT]/[MODEL] filing; any deviation with no [LAW-FRICTION]/[CONDUCT] filing. Name the role and the exact clause dropped; "looks sloppy" is not a finding.
7. HERDR HEALTH: is the auditor/orchestrator inside `HERDR_ENV=1`? Are panes orphaned (no agent, no useful shell)? Flag stray workspaces from abandoned experiments.
8. REPORT: verdict (healthy / drifting / stalled), findings with full ids and evidence, at most 3 recommended corrections. No board writes; you are eyes, not hands.
