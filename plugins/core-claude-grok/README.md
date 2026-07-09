# core-claude-grok

An opinionated unified baseline for Claude Code + Grok.
`/core-claude-grok:setup` installs the whole baseline in a single no-prompt run
(auto-detects host); `/core-claude-grok:doctor` audits the install read-only.

## What `/core-claude-grok:setup` installs

| Component | Where | What it does |
|-----------|-------|--------------|
| `judge-hook.sh` | `~/.claude/`, `PreToolUse` | Rules engine over tool inputs: `deny` (block), `allow` (allowlist), `escalate` (LLM judge via Haiku, fed the last few user messages from the transcript so intent-referencing prompts are decidable). Rules on `Bash`/`Write`/`Edit` also bind the skyline equivalents (`skyline_run`/`skyline_create`/`skyline_edit`) via match-text normalization, so skyline routing cannot bypass a rule. Rules compile to an mtime-keyed cache; no-op if `~/.claude/judge-rules.json` is absent; escalations fail open under kernel memory pressure CRITICAL. |
| `writing-guard.sh` | `~/.claude/`, `PostToolUse` (Write\|Edit + skyline_create/edit) | Flags AI writing tells in the NEW content only (Write/create: full content; Edit: new_string; skyline_edit: patch `+` lines): em dashes above 1-per-500-words in prose (0 in code), banned vocab + AI phrases in prose of 150+ new words. Blocks and asks for a rewrite. `WRITING_GUARD_EXEMPT_RE` skips matching paths. |
| `judge-rules.example.json` | seeded to `~/.claude/judge-rules.json` | Vendor-neutral rule set: destructive fs/git/db/cloud guards plus dependency version-pin escalations. |
| `core-hud.sh` | `~/.claude/`, `statusLine` | Four-line HUD: model (family-colored) + effort chip + project ⎇ branch +/- stats; 24-cell gradient context bar with 1/8-cell resolution + handoff banner; 5h/7d quota lines with a live BURN-RATE engine — %/h over the last ~10 min from a sampled history, an 8-bucket sparkline, and a red `⚠ limit ~HH:MM before reset` projection when the current pace hits 100% before the window resets. Needs `jq`. |
| Guidelines | `~/.claude/CLAUDE.md` | Advisor, Decisive Thinking, Coding, Review Mindset, and Writing Guidelines, written between managed markers. |
| `/core-claude-grok:doctor` | skill | Read-only install audit... |

## Permission posture

`/core-claude-grok:setup` sets `permissions.defaultMode` to `bypassPermissions` on Claude hosts.

## Install

```
/plugin install core-claude-grok@multi-llm-marketplace
/core-claude-grok:setup
```

Restart after. Files are backed up before overwrite.

## Idempotent

Re-runs are safe (no duplicate hooks, existing rules untouched, only replaces the managed guidelines block).
