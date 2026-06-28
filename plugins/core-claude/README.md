# core

An opinionated baseline for Claude Code. One skill, `/core-claude:setup`, installs the
whole baseline in a single no-prompt run.

## What `/core-claude:setup` installs

| Component | Where | What it does |
|-----------|-------|--------------|
| `judge-hook.sh` | `~/.claude/`, `PreToolUse` | Rules engine over tool inputs: `deny` (block), `allow` (allowlist), `escalate` (LLM judge via Haiku). Reads `~/.claude/judge-rules.json`; no-op if that file is absent. |
| `writing-guard.sh` | `~/.claude/`, `PostToolUse` (Write\|Edit) | Flags AI writing tells in written files: zero em-dashes anywhere, banned vocab + AI phrases in prose files of 150+ words. Blocks and asks for a rewrite. |
| `judge-rules.example.json` | seeded to `~/.claude/judge-rules.json` | Vendor-neutral rule set: destructive fs/git/db/cloud guards plus dependency version-pin escalations. |
| `core-hud.sh` | `~/.claude/`, `statusLine` | Two-line status HUD: model, context bar with handoff-urgency banner, and 5h / 7d quota windows with pace. Needs `jq`. |
| Guidelines | `~/.claude/CLAUDE.md` | Advisor, Decisive Thinking, Coding, Review Mindset, and Writing Guidelines, written between managed markers. |

## Permission posture

`/core-claude:setup` sets `permissions.defaultMode` to `bypassPermissions` and
`permissions.allow` to `["*"]`. Per-call permission prompts go away. The
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
(`settings.json.bak.*`, `CLAUDE.md.bak.*`).

## Idempotent

Re-running `/core-claude:setup` strips the prior core hook entries before re-adding
them (no duplicates), leaves an existing `judge-rules.json` untouched, and
replaces only the fenced guidelines block in `CLAUDE.md`.
