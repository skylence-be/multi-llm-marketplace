# core-codex

Codex port of the `core` baseline. The Codex sibling of `core` (Claude Code).

Codex supports the same hook lifecycle Claude does — `PreToolUse`, `PostToolUse`,
and `Stop` are all real events — so this is a full port, not a guidance-only
subset. The three hooks ship with the plugin and activate on install; the
`/core-codex:setup` skill writes the two user-scope files they read.

## What it ships

- **hooks/judge-hook.sh** (`PreToolUse`) — the LLM-as-judge rules engine. Reads
  `~/.codex/judge-rules.json`; `deny` rules block with exit 2, `escalate` rules
  ask `codex exec` for an ALLOW/BLOCK verdict.
- **hooks/writing-guard.sh** (`PostToolUse`) — flags AI writing tells (em dashes,
  banned vocab, canned phrases) in prose written to disk.
- **hooks/research-nudge.sh** (`Stop`) — when the final turn hedges a factual
  claim, nudges a web-search verification before concluding. Two-stage gate
  (cheap hedge grep, then a `codex exec` judge) keeps it quiet.
- **hooks/judge-rules.example.json** — the same ruleset as the Claude `core`
  plugin; `/core-codex:setup` seeds it to `~/.codex/judge-rules.json`.
- **templates/agents-md.md** — the core guidelines (Advisor, Decisive Thinking,
  Coding, Review Mindset, Writing) for `~/.codex/AGENTS.md`.

## Adaptations from the Claude `core` plugin

- **Escalation CLI.** Claude's hooks call `claude -p`; these call `codex exec`
  (read-only sandbox, final message to stdout — confirmed against the Codex
  non-interactive docs).
- **Rules matching.** Codex's `PreToolUse` payload is not the Claude
  `{tool_name, tool_input}` schema, so each rule's `pattern` is matched against
  the whole payload JSON and the per-rule `tool` field is advisory. The patterns
  are command-content regexes (`rm -rf /`, `git push --force`, …) so they still
  match against the serialized payload.
- **No statusline.** Codex has no statusline surface, so `core-hud` is dropped.

## ⚠️ Still needs verification

1. **`PostToolUse` / `Stop` payload shapes.** `writing-guard` and
   `research-nudge` extract the written file content and the transcript path by
   trying several likely field names and fall back to a no-op when none match.
   The exact Codex field names are not documented; if they miss, the hook is
   dormant rather than wrong. TODO: confirm and pin the field paths.
2. **`codex exec` flags.** Escalation uses `codex exec --sandbox read-only
   "<prompt>"`. If a flag is rejected the escalate path fails open (allows).
