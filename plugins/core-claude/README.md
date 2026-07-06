# core

An opinionated baseline for Claude Code. `/core-claude:setup` installs the
whole baseline in a single no-prompt run; `/core-claude:doctor` audits the
install read-only (file drift, settings wiring, rules coverage, version).

## What `/core-claude:setup` installs

| Component | Where | What it does |
|-----------|-------|--------------|
| `judge-hook.sh` | `~/.claude/`, `PreToolUse` | Rules engine over tool inputs: `deny` (block), `allow` (allowlist), `escalate` (LLM judge via Haiku, fed the last few user messages from the transcript so intent-referencing prompts are decidable). Rules on `Bash`/`Write`/`Edit` also bind the skyline equivalents (`skyline_run`/`skyline_create`/`skyline_edit`) via match-text normalization, so skyline routing cannot bypass a rule. Rules compile to an mtime-keyed cache; no-op if `~/.claude/judge-rules.json` is absent; escalations fail open under kernel memory pressure CRITICAL. |
| `writing-guard.sh` | `~/.claude/`, `PostToolUse` (Write\|Edit + skyline_create/edit) | Flags AI writing tells in the NEW content only (Write/create: full content; Edit: new_string; skyline_edit: patch `+` lines): em dashes above 1-per-500-words in prose (0 in code), banned vocab + AI phrases in prose of 150+ new words. Blocks and asks for a rewrite. `WRITING_GUARD_EXEMPT_RE` skips matching paths. |
| `judge-rules.example.json` | seeded to `~/.claude/judge-rules.json` | Vendor-neutral rule set: destructive fs/git/db/cloud guards plus dependency version-pin escalations. |
| `core-hud.sh` | `~/.claude/`, `statusLine` | Four-line status HUD: model line, context bar with handoff-urgency banner, and 5h / 7d quota lines with pace. Needs `jq`. |
| Guidelines | `~/.claude/CLAUDE.md` | Advisor, Decisive Thinking, Coding, Review Mindset, and Writing Guidelines, written between managed markers. |
| `/core-claude:doctor` | skill | Read-only install audit: per-file drift vs the plugin, settings wiring (flags the judge-unwired-under-bypass red alert), guidelines sync, judge-rules coverage vs the shipped example, version stamp. |

## Permission posture

`/core-claude:setup` sets `permissions.defaultMode` to `bypassPermissions`.
Per-call permission prompts go away. The
judge-hook plus its rules become the safety gate. PreToolUse hooks still run
under bypass mode, so the gate stays live. If you do not want that posture,
edit `~/.claude/settings.json` after setup, or skip the plugin.

## Install

```
/plugin install core-claude@multi-llm-marketplace
/core-claude:setup
```

Restart Claude Code afterward so the hooks and statusline take effect. Every
file `/core-claude:setup` overwrites is backed up with a timestamp first
(`settings.json.bak.*`, `CLAUDE.md.bak.*`, and per-script `*.bak.*` copies).

## Idempotent

Re-running `/core-claude:setup` strips the prior core hook entries before re-adding
them (no duplicates), leaves an existing `judge-rules.json` untouched, and
replaces only the fenced guidelines block in `CLAUDE.md`.
