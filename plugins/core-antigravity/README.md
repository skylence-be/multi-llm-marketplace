# core-antigravity

Google Antigravity (Gemini) port of the `core-claude` baseline.

Antigravity's hook contract differs from Claude/Codex: a hook receives the
tool-call JSON on STDIN (camelCase `toolCall.name` / `toolCall.args`) and prints
a `{"decision":"allow"|"deny","reason":...}` object on STDOUT — there is no
exit-2 block. All three hooks here follow that contract and fail open.

## What it ships

- **hooks/judge-hook.sh** (`PreToolUse` on `run_command`) — the LLM-as-judge
  rules engine. Reads `~/.gemini/judge-rules.json`; `deny` rules return a deny
  decision, `escalate` rules ask `gemini` for an ALLOW/BLOCK verdict.
- **hooks/writing-guard.sh** (`PreToolUse` on the write tools) — Antigravity's
  write payload carries the content, so AI writing tells are caught *before* the
  write and the call is denied with a corrective reason (the agent rewrites).
  This is cleaner than the Claude/Codex PostToolUse approach.
- **hooks/research-nudge.sh** (`Stop`) — nudges web-search verification of a
  hedged factual claim. Escalates via `gemini`.
- **hooks/judge-rules.example.json** — the same ruleset as the Claude `core-claude`
  plugin; `/core-antigravity:setup` seeds it to `~/.gemini/judge-rules.json`.
- **templates/agents-md.md** — the core guidelines for `~/.gemini/AGENTS.md`.

## Adaptations from the Claude `core-claude` plugin

- **Decision contract.** `{"decision":...}` JSON on STDOUT, not exit 2.
- **Escalation CLI.** `gemini -p "<prompt>"` instead of `claude -p`.
- **writing-guard is pre-write.** Run at `PreToolUse` on the write tools (the
  content is in the payload) rather than `PostToolUse`.
- **No statusline.** Dropped (no Antigravity surface).

## ⚠️ Still needs verification

1. **Escalation CLI.** `gemini -p` is assumed for the Gemini CLI; if absent or
   the flag differs, the escalate path and the nudge fail open (allow).
2. **Write-payload field names.** `writing-guard` tries several `toolCall.args`
   field names for the target path and content and falls back to allow if none
   match. Not documented; confirm and pin.
3. **`Stop` event.** Whether Antigravity fires a `Stop` hook, its payload, and
   whether a Stop hook may request another turn are all undocumented. The
   research-nudge is best-effort and dormant if the event never fires.
4. **`AGENTS.md` vs `GEMINI.md`.** The guidelines target `~/.gemini/AGENTS.md`;
   if Antigravity reads `GEMINI.md` instead, adjust the setup skill.
