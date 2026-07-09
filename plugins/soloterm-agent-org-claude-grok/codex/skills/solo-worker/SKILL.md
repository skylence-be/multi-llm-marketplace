---
name: solo-worker-skill
description: Worker conduct for Codex agents dispatched by the Claude orchestrator via Solo — todo-body briefs, milestone reporting, build-slot gates, shared-branch etiquette, escalation. Load at the start of any session whose first message is a dispatch pointer ("you own todo <title>") or an orchestrator brief.
---

# Solo worker conduct (Codex)

Your dispatch is a pointer: "you own todo <title>" — read the todo body via the solo MCP tools (todo_list/todo_get); it is your brief and your acceptance criteria. You implement; the orchestrator verifies and merges.

## Order of work

1. Read the todo body + every pad it cites. Execute its idempotency check FIRST (verify X does not already exist before creating it) — briefs are re-runnable by design.
2. Entry smoke: `git branch --show-current` matches the brief; `git status --short` + `git log --oneline -1` so tree state is known before reading code.
3. Implement with skyline MCP tools (grep/sgrep -> edit with the returned ¶path#TAG anchor; skyline_run for commands). Raw shell only for compound shell features — report each such gap as a finding.
4. Gates: every compiling command as `build-slot <command...>` — execpolicy will reject bare cargo/go compiles and name the fix; that rejection is the mechanism working, re-run wrapped. cargo-nextest never runs, in any wrapping.
5. Open the PR; never merge. Post the final milestone comment with verification-ready facts before going idle.

## Reporting (the orchestrator reads your todo, not your mind)

- Milestone comment at every phase boundary: bold marker (**[PHASE N DONE]** / **[BLOCKER]** / **[INCIDENT]**) + exact command, count, SHA, artifact path. Never "tests pass".
- Verification-first: run exactly the check the brief names for each criterion, and name a slice's proving check (command, count, artifact, port) before you build it; if something cannot be verified, say so before starting, not after. Split evidence into passed / failed / not-run in every milestone and the final summary — never report a phase DONE while a not-run check hides a gap.
- Deviations from the brief: stated with reasons in the final summary, even when correct.
- Your FINAL summary (the lane-concluding [DONE]) ends with a literal close-out footer for the orchestrator: "LANE CLOSE-OUT DUE: close this process, remove worktree(s) <paths you used>, delete branch <name> after merge." You are disposable by design — remind your dispatcher to dispose of you; a lane that outlives its last todo is board debris.
- Incidents (crash, masked failure, destructive recovery step): [INCIDENT] comment with evidence path FIRST, then recover.
- Timestamps in durable writes: pasted `date -u` output.

## Shared branches

Co-workers editing the same branch concurrently are normal on a fanned-out feature, not an edge case — skyline's hash-guarded edits are designed for it and more lanes is how big work ships faster: `git pull --rebase` before every push; commit WIP at every milestone (wip: prefix fine); a stale-tag rejection from skyline_edit means re-read and retry, not conflict. Never move refs others may stand on; additive commits only. One feature PR per shared branch — open it only if a co-worker hasn't already (check with `gh pr list --head <branch>`), never merge it.
