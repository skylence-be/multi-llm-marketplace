---
name: solo-worker-skill
description: Worker conduct for agents dispatched by the orchestrator via Solo — todo-body briefs, milestone reporting, build-slot gates, shared-branch etiquette, escalation. Load at the start of any session whose first message is a dispatch pointer ("you own todo <title>") or an orchestrator brief.
---

# Solo worker conduct

Your dispatch is a pointer: "you own todo <title>" — read the todo body via the solo MCP tools (todo_list/todo_get); it is your brief and your acceptance criteria. You implement; the orchestrator verifies and merges.

## Order of work

1. Read the todo body + every pad it cites. Execute its idempotency check FIRST (verify X does not already exist before creating it) — briefs are re-runnable by design.
2. Entry smoke: `git branch --show-current` matches the brief; `git status --short` + `git log --oneline -1` so tree state is known before reading code.
3. Implement with skyline MCP tools (grep/sgrep -> edit with the returned ¶path#TAG anchor; skyline_run for commands). Native shell only for compound shell features — report each such gap as a finding.
4. Gates: every compiling command as `build-slot <command...>` — the machine runs one compile at a time. cargo-nextest never runs, in any wrapping.
5. Open the PR; never merge. Post the final milestone comment with verification-ready facts before going idle.

## Reporting (the orchestrator reads your todo, not your mind)

- Milestone comment at every phase boundary: bold marker (**[PHASE N DONE]** / **[BLOCKER]** / **[INCIDENT]**) + exact command, count, SHA, artifact path. Never "tests pass".
- Deviations from the brief: stated with reasons in the final summary, even when correct.
- Incidents (crash, masked failure, destructive recovery step): [INCIDENT] comment with evidence path FIRST, then recover.
- Timestamps in durable writes: pasted `date -u` output.

## Shared branches

Co-workers editing the same branch concurrently are normal on a fanned-out feature, not an edge case — skyline's hash-guarded edits are designed for it: `git pull --rebase` before every push; commit WIP at every milestone (wip: prefix fine); a stale-tag rejection means re-read and retry, not conflict. Additive commits only. One feature PR per shared branch — open it only if a co-worker hasn't already, never merge it.

## No-fusion

Before any send_input, read the target's tail; unsubmitted text on its input line → todo comment instead. If the text might be a suggestion placeholder (they render like typed text): a raw tail shows a ghost's prompt empty, or send one space (bytes [32]) — a ghost vanishes, real typing is retained — then backspace (bytes [127]) to restore. Probe once; changing text is live typing, never send. See scripts/ghost-probe.sh.
