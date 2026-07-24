---
name: replacer-skill
description: Successor pickup — inherit a predecessor worker's lane from durable state (todo trail, committed WIP) after context exhaustion, a kill, or a stall. Invoke when a dispatch brief names you as REPLACER.
---

# Replacer (successor pickup)

Your context is fresh; the predecessor's knowledge survives only in artifacts. Trust artifacts, never prose.

## This skill is a contract, not a menu

All seven steps below run, in order, before you continue the lane. You are here precisely because a predecessor's state stopped being legible; a step you skip recreates that hole for your own successor, and you will not be the one paying for it. The breach arrives as a reasonable local story ("the handover comment reads complete, the git baseline is a formality"), never as a decision to disobey. Trust artifacts, never prose, and that includes the prose you tell yourself.

1. CONTRACT: read the lane todo body + referenced issues — that is your acceptance criteria.
2. HANDOVER: read the todo comments newest-first; the last [HANDOVER]/checkpoint comment is your starting state, earlier milestones are the history.
3. TREE: verify it yourself — `git status` + `git log --oneline -5` + `git diff --stat` in the inherited **lane tree** (absolute path from brief/todo; usually a skyrift workspace under `<repo>-workspaces/`). If skyrift: confirm `.skyrift-workspace` is present and still untracked. Uncommitted changes described in prose but absent on disk are LOST — say so in your pickup comment instead of guessing.
4. BASELINE: do NOT run cargo/build-slot — replacers never compile either (you would poll-loop on the single slot). Baseline the inherited state from git (`git status` + `git log --oneline -5` + `git diff --stat`) + the todo trail; whether it compiles is the orchestrator's gate build, not yours.
5. EXTERNAL TARGETS in inherited next-steps (push remote, PR repo, deploy path, port) are PROPOSED until a one-command proof verifies them (git ls-remote / gh repo view / port probe) — nonexistent remotes have been inherited unverified across two generations.
6. PICKUP comment: verified SHA, baseline counts, anything lost vs the handover, continuation plan — confirm the predecessor's plan or revise it WITH the stated reason. Deviating from the inherited plan needs a [DESIGN REVISION] comment BEFORE implementing.
7. Continue under worker rules for whichever runtime you were spawned as (/solo-worker for a Claude worker, ~/.codex/AGENTS.md for a Codex worker). The predecessor's reported failures bind you, do not re-try them without saying why.

Note: skyline_run's UNCHANGED dedup is daemon-global — your verification re-runs may return "unchanged since last call" because the PREDECESSOR ran the identical command; the raw tee path in that message is fresh, read it.
- Same closure sequence applies to you: verification, supervisor retrospective (mention you were a replacer — handover quality is retro material), dispositions, then close.
- After any compaction in YOUR session: re-invoke this skill and re-read the todo trail before continuing. You inherited this lane because a predecessor's state stopped being legible; a compacted replacer running on a summary is that same failure starting over, and your pickup comment is now part of the trail your own successor will trust.

## Skylore

On pickup: one `skyline_lore_recall` with the lane keywords + `repo=` (and unscoped if the failure mode smelled machine-wide). Prefer the todo trail for contract; use lore only so you do not re-burn a gotcha the predecessor or a peer already paid for. Mark only if you discover a new durable fact the next successor needs.
