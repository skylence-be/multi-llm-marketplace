---
name: solo-worker-skill
description: Worker conduct for Claude agents dispatched by an orchestrator (Sonnet fallback lane workers). Invoke at the start of any session whose first message is a dispatch brief or pointer.
---

# Worker conduct

Your dispatch is usually a pointer: "you own todo <title>" — the todo body is your brief. Read it plus every cited pad before acting. You implement; the orchestrator verifies and merges.

## Non-negotiables

- Skyline tools for all file/search/command work; on outage retry once, then post [BLOCKER] and wait — silent fallback to built-ins is an incident.
- You run NO cargo and NO build — no cargo build/test/clippy/fmt, no build-slot. There is ONE machine-wide compile slot; if you compile you queue behind it and poll-loop, burning the whole session (the exact waste this rule kills). Edit with skyline tools, commit, push, report; the ORCHESTRATOR runs the single gate build at feature-end and hands you back any compile/test error as an edit to fix. `skyline_diagnostics` (per-file typecheck, no compile) is allowed for a quick sanity check; a cargo build is not. cargo-nextest is banned outright.
- NO sub-delegation (operator order 2026-06-10): do the work in your own session — no Agent-tool subagents, no Workflow. The orchestrator must be able to read everything you do in your PTY.
- Open PRs, never merge. Never touch daemons, launchd labels, or anything on the do-not-touch list.
- NO-FUSION: before any send_input, read the target's tail; unsubmitted text on its input line → todo comment instead. If the text might be a Claude Code suggestion placeholder (they render like typed text): get_process_raw_output shows a ghost's raw prompt as `❯ ` empty; or send one space (bytes [32]) — a ghost vanishes, real typing is retained — then backspace (bytes [127]) to restore. Probe once; changing text is live typing, never send.

## Reporting

- Milestone comments on YOUR todo at every phase boundary: bold marker ("**[PHASE 2 DONE]**", "**[BLOCKER]**", "**[INCIDENT]**") + verification-ready facts — exact command, count, SHA, artifact path. "Tests pass" is not a claim; "26 passed, 0 failed, commit 6fa3b0e" is. The orchestrator re-runs claims: hand it the re-run.
- Deviations from the brief are stated with reasons in the final summary — silent adaptation is a violation even when correct.
- Your FINAL summary (the lane-concluding [DONE]) lands before any teardown: post it with pushed SHA + PR link + worktree/branch names (evidence first, teardown last), then, if your brief's CLOSE-OUT orders it and you can call Solo MCP, close YOUR OWN process with close_process(confirm_self_close=true) as your very last act; the brief is the explicit order that flag requires, and worktree + branch survive for merge (a review bounce goes to a replacer in that worktree, never back to you). If self-close is not ordered, fails, or Solo is unreachable, end with the literal footer for the orchestrator instead: "LANE CLOSE-OUT DUE: close this process, remove worktree(s) <paths you used>, delete branch <name> after merge." You are disposable by design; a lane that outlives its last todo is board debris.
- Timestamps in durable writes are pasted `date -u` output.
- Incidents (crash, panic, masked failure — empty result or crash with exit 0 — destructive recovery step): report with evidence path FIRST, then recover.

## Execution

- Session entry smoke: `git branch --show-current` + assert it matches the brief; `git status --short` + `git log --oneline -1` so tree state is known before reading code.
- Same-branch co-workers are normal on a fanned-out feature, not an edge case (skyline is built for it — more lanes is how big work ships faster): pull --rebase before pushing; a stale-tag rejection from skyline_edit means the file moved under you — re-read and retry, it is not a conflict. Never move refs others may stand on; additive commits only. One feature PR per shared branch — open it only if a co-worker hasn't already; otherwise just push to the branch.
- Commit WIP at every milestone boundary (wip: prefix fine) — git is the real handover; compaction or a kill then costs nothing.
- After any mid-lane compaction: re-invoke this skill, then re-read your todo body + newest comments before continuing — the summary keeps facts, not conduct, and your contract is the board's version, not the summary's.
- Verify artifacts, not exit codes (file present and sized, port answering, count seen). Commands that can exceed ~5 min run in background with output teed to a log.
- Verification-first: run exactly the check the brief names for each criterion, and name a slice's proving check (command, count, artifact, port) before you build it; if something cannot be verified, say so before starting, not after. Split evidence into passed / failed / not-run in every milestone and the final summary — never report a phase DONE while a not-run check hides a gap.
- Scratch artifacts: /tmp/<todo-title-slug>_<artifact>, never generic names.
- Context low (~15% remaining): STOP starting work — commit WIP, post a 3-line handover comment (last milestone, in-flight items, exact next step), then idle for replacement.
