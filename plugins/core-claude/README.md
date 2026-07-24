# core

An opinionated baseline for Claude Code. `/core-claude:setup` installs the
whole baseline in a single no-prompt run; `/core-claude:doctor` audits the
install read-only (file drift, settings wiring, rules coverage, version).

## What `/core-claude:setup` installs

| Component | Where | What it does |
|-----------|-------|--------------|
| `judge-hook.sh` | plugin `hooks/`, `PreToolUse` | Rules engine over tool inputs: `deny` (block), `allow` (allowlist), `escalate` (LLM judge via Haiku, fed the last few user messages from the transcript so intent-referencing prompts are decidable). Registered by the plugin's own `hooks.json`, so it updates with the plugin. |
| `writing-guard.sh` | plugin `hooks/`, `PostToolUse` (Write\|Edit + skyline_create/edit) | Flags AI writing tells in the NEW content only (Write/create: full content; Edit: new_string; skyline_edit: patch `+` lines): em dashes above 1-per-500-words in prose (0 in code) and the banned-word list. |
| `research-nudge.sh` | plugin `hooks/`, `Stop` | Nudges on hedged factual claims; skipped in org sessions and under memory pressure. |
| `judge-rules.json` | plugin `hooks/` | The COMPLETE ruleset, plugin-owned: destructive fs/git/db/cloud guards plus dependency version-pin escalations. Every rule carries a stable `id`. New rules and schema changes arrive on plugin update, with nothing to re-seed. |
| `~/.claude/judge-rules.json` | your machine, optional | Overlay, empty by default. `rules` adds (evaluated first, so a local allow can sit above a shipped deny), `disable` drops shipped rules by `id` or `_category`, `only` narrows to a subset. Absent, empty, or malformed leaves the shipped ruleset fully active. |
| `core-hud.sh` | `~/.claude/`, `statusLine` | Four-line HUD: model (family-colored) + effort chip + project ⎇ branch +/- stats; 24-cell gradient context bar with 1/8-cell resolution + handoff banner; 5h/7d quota lines with a live BURN-RATE engine. The one file still copied, because `statusLine` takes a plain command path. |
| Guidelines | `~/.claude/CLAUDE.md` | Advisor, Decisive Thinking, Coding, Review Mindset, and Writing Guidelines, written between managed markers. |
| `/core-claude:doctor` | skill | Read-only install audit. Proves the gate by RUNNING it, flags legacy copy-based wiring that double-fires, reports the overlay (including shipped-rule copies that silently pin old versions), statusline drift, guidelines sync, version stamp. |

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

Re-running `/core-claude:setup` strips any legacy copy-based hook entries from
`settings.json` (the plugin registers those three hooks itself now), leaves an
existing overlay alone unless it carries copies of shipped rules, and replaces
only the fenced guidelines block in `CLAUDE.md`.

## Migrating from a pre-0.9 install

Before 0.9 the three hooks were COPIED into `~/.claude/` and wired there by
absolute path, and the full ruleset was seeded to `~/.claude/judge-rules.json`
once. Neither ever updated again: an install could run a current plugin against
a hook and a ruleset from months earlier, and keep the exact behaviour an
update had fixed. `/core-claude:setup` migrates both. It retires the copied
scripts to `*.retired.*`, strips their `settings.json` entries so nothing
double-fires, and rewrites a full-copy rules file into an overlay (backed up to
`*.fullcopy.bak.*`) keeping only rules that are genuinely yours.
