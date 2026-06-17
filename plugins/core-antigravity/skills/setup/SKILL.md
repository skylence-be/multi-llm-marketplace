---
name: setup-skill
description: One-shot, no-prompt installer for the Antigravity core baseline user-scope state. Seeds ~/.gemini/judge-rules.json (only if absent) and writes the core guidelines (Advisor, Decisive Thinking, Coding, Review Mindset, Writing) into ~/.gemini/AGENTS.md inside a fenced block. The hooks (judge-hook, writing-guard, research-nudge) activate from the installed plugin itself. Invoke as /core-antigravity:setup on a new machine.
---

# /core-antigravity:setup

Run once on a new machine. The hooks ship with the plugin and activate on install; this skill writes the two user-scope files they depend on. Every step that overwrites makes a timestamped backup first.

All source files live under `$CLAUDE_PLUGIN_ROOT` (Antigravity exposes the plugin root via this env var, with `ANTIGRAVITY_PLUGIN_ROOT` / `GEMINI_PLUGIN_ROOT` as fallbacks).

## Step 1: seed the judge rules (only if absent)

The judge-hook reads `~/.gemini/judge-rules.json`. Seeding leaves an existing file untouched so local edits survive a re-run.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${ANTIGRAVITY_PLUGIN_ROOT:-${GEMINI_PLUGIN_ROOT:-}}}"
mkdir -p ~/.gemini
if [ ! -f ~/.gemini/judge-rules.json ]; then
  cp "$PLUGIN_ROOT/hooks/judge-rules.example.json" ~/.gemini/judge-rules.json
  echo "seeded ~/.gemini/judge-rules.json"
else
  echo "~/.gemini/judge-rules.json already exists, left as-is"
fi
```

## Step 2: write the AGENTS.md guidelines (backup first; idempotent)

The canonical guidelines live in `$PLUGIN_ROOT/templates/agents-md.md`, fenced by `<!-- BEGIN core:guidelines -->` and `<!-- END core:guidelines -->`. This replaces a prior fenced block if present, otherwise appends one. Content outside the fences is left alone.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${ANTIGRAVITY_PLUGIN_ROOT:-${GEMINI_PLUGIN_ROOT:-}}}"
AGENTS_MD=~/.gemini/AGENTS.md
TEMPLATE="$PLUGIN_ROOT/templates/agents-md.md"
touch "$AGENTS_MD"
cp "$AGENTS_MD" "$AGENTS_MD.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
awk '
  /<!-- BEGIN core:guidelines -->/ {skip=1}
  !skip {print}
  /<!-- END core:guidelines -->/ {skip=0; next}
' "$AGENTS_MD" > "$tmp"

awk '{ if (NF==0) { blanks++ } else { while (blanks>0) { print ""; blanks-- }; print } }' "$tmp" > "$AGENTS_MD"
printf '\n' >> "$AGENTS_MD"
cat "$TEMPLATE" >> "$AGENTS_MD"
rm -f "$tmp"
echo "AGENTS.md guidelines section refreshed"

# Cross-check: the installed fenced block must match the shipped example verbatim.
installed=$(awk '/<!-- BEGIN core:guidelines -->/{f=1} f{print} /<!-- END core:guidelines -->/{f=0}' "$AGENTS_MD")
if [ "$installed" = "$(cat "$TEMPLATE")" ]; then
  echo "AGENTS.md guidelines: in sync with the shipped example"
else
  echo "AGENTS.md guidelines: DRIFT vs the shipped example — re-run /core-antigravity:setup to refresh"
fi
```

## Step 3: summary

```
core-antigravity:setup
----------------------
~/.gemini/judge-rules.json    seeded | existing
~/.gemini/AGENTS.md           guidelines section written
hooks (judge/writing/research) active from the installed plugin
```

Then tell the user: restart the Antigravity session for the plugin hooks to take effect. The judge-hook and research-nudge escalate via `gemini`, so a working `gemini` CLI on PATH is required for the escalate rules and the doubt nudge (both fail open without it).
