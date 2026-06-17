---
name: replacer
description: Successor pickup — inherit a predecessor worker's lane from durable state (todo trail, committed WIP) after context exhaustion, a kill, or a stall. Invoke when a dispatch brief names you as REPLACER.
---

# Replacer (successor pickup)

Your context is fresh; the predecessor's knowledge survives only in artifacts. Trust artifacts, never prose.

1. CONTRACT: read the lane todo body + referenced issues — that is your acceptance criteria.
2. HANDOVER: read the todo comments newest-first; the last [HANDOVER]/checkpoint comment is your starting state, earlier milestones are the history.
3. TREE: verify it yourself — `git status` + `git log --oneline -5` + `git diff --stat` in the inherited worktree. Uncommitted changes described in prose but absent on disk are LOST — say so in your pickup comment instead of guessing.
4. BASELINE: run the relevant gate via build-slot on the inherited state BEFORE changing anything; record counts — know whether you inherited green or broken.
5. EXTERNAL TARGETS in inherited next-steps (push remote, PR repo, deploy path, port) are PROPOSED until a one-command proof verifies them (git ls-remote / gh repo view / port probe) — nonexistent remotes have been inherited unverified across two generations.
6. PICKUP comment: verified SHA, baseline counts, anything lost vs the handover, continuation plan — confirm the predecessor's plan or revise it WITH the stated reason. Deviating from the inherited plan needs a [DESIGN REVISION] comment BEFORE implementing.
7. Continue under worker rules (~/.codex/AGENTS.md for Codex; /solo-worker for Claude). The predecessor's reported failures bind you — do not re-try them without saying why.

Note: skyline_run's UNCHANGED dedup is daemon-global — your verification re-runs may return "unchanged since last call" because the PREDECESSOR ran the identical command; the raw tee path in that message is fresh, read it.
- Same closure sequence applies to you: verification, supervisor retrospective (mention you were a replacer — handover quality is retro material), dispositions, then close.
