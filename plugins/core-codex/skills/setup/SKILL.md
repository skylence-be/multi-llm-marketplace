---
name: setup
description: One-shot, no-prompt installer for the Codex core baseline user-scope state. Seeds ~/.codex/judge-rules.json (only if absent) and writes the core guidelines (Advisor, Decisive Thinking, Coding, Review Mindset, Writing) into ~/.codex/AGENTS.md inside a fenced block. The hooks (judge-hook, writing-guard, research-nudge) activate from the installed plugin itself — this skill only writes the user-scope files those hooks and the agent read. Invoke as /core-codex:setup on a new machine.
---

# /core-codex:setup

Run once on a new machine. The hooks ship with the plugin and activate on install; this skill writes the two user-scope files they depend on: the judge rules and the AGENTS.md guidelines. Every step that overwrites makes a timestamped backup first.

All source files live under `$CODEX_PLUGIN_ROOT` (the root of this plugin).

## Step 1: seed the judge rules (only if absent)

The judge-hook reads `~/.codex/judge-rules.json`. Seeding leaves an existing file untouched so local edits survive a re-run.

```bash
mkdir -p ~/.codex
if [ ! -f ~/.codex/judge-rules.json ]; then
  cp "$CODEX_PLUGIN_ROOT/hooks/judge-rules.example.json" ~/.codex/judge-rules.json
  echo "seeded ~/.codex/judge-rules.json"
else
  echo "~/.codex/judge-rules.json already exists, left as-is"
fi
```

## Step 2: write the AGENTS.md guidelines (backup first; idempotent)

The canonical guidelines live in `$CODEX_PLUGIN_ROOT/templates/agents-md.md`, fenced by `<!-- BEGIN core:guidelines -->` and `<!-- END core:guidelines -->`. This replaces a prior fenced block if present, otherwise appends one. Content outside the fences is left alone.

```bash
AGENTS_MD=~/.codex/AGENTS.md
TEMPLATE="$CODEX_PLUGIN_ROOT/templates/agents-md.md"
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
```

## Step 3: summary

Print this checklist, substituting the seeded/existing state for judge-rules:

```
core-codex:setup
----------------
~/.codex/judge-rules.json     seeded | existing
~/.codex/AGENTS.md            guidelines section written
hooks (judge/writing/research) active from the installed plugin
```

Then tell the user: restart Codex for the plugin hooks to take effect, and note that the judge-hook and research-nudge escalate via `codex exec`, so a working `codex` CLI on PATH is required for the escalate rules and the doubt nudge (both fail open without it).
