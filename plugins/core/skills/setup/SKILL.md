---
name: setup
description: One-shot, no-prompt installer for the core Claude Code baseline. Copies the judge-hook and writing-guard hooks plus the core-hud statusline into ~/.claude, seeds judge-rules.json, wires settings.json to a full-bypass permission posture gated by the judge-hook, and writes the core guidelines (Advisor, Decisive Thinking, Coding, Review Mindset, Writing) into the user-scope CLAUDE.md. Invoke as /core:setup on a new machine.
---

# /core:setup

Run once on a new machine. Installs the core baseline with no prompts. Every step that overwrites makes a timestamped backup first. Execute the steps in order, then report the Step 5 checklist.

All source files live under `$CLAUDE_PLUGIN_ROOT` (the root of this plugin). Run each block exactly as written.

> Posture note: this skill sets `permissions.defaultMode` to `bypassPermissions` and `permissions.allow` to `["*"]`. Per-call permission prompts go away; the judge-hook (PreToolUse) plus its rules become the safety gate. PreToolUse hooks still run under bypass mode, so the gate stays live.

## Step 1: install the hook and statusline scripts

```bash
mkdir -p ~/.claude
cp "$CLAUDE_PLUGIN_ROOT/hooks/judge-hook.sh" \
   "$CLAUDE_PLUGIN_ROOT/hooks/writing-guard.sh" \
   "$CLAUDE_PLUGIN_ROOT/statusline/core-hud.sh" ~/.claude/
chmod +x ~/.claude/judge-hook.sh ~/.claude/writing-guard.sh ~/.claude/core-hud.sh
```

## Step 2: seed the judge rules (only if absent)

Leaves an existing rules file untouched so local edits survive a re-run.

```bash
if [ ! -f ~/.claude/judge-rules.json ]; then
  cp "$CLAUDE_PLUGIN_ROOT/hooks/judge-rules.example.json" ~/.claude/judge-rules.json
  echo "seeded ~/.claude/judge-rules.json"
else
  echo "~/.claude/judge-rules.json already exists, left as-is"
fi
```

## Step 3: wire settings.json (backup first; idempotent)

Adds the two hooks, the statusline, and the full-bypass posture. Re-running strips the prior core hook entries before re-adding, so it never stacks duplicates. Existing unrelated hooks and the deny list are preserved.

```bash
SETTINGS=~/.claude/settings.json
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
jq '
  .statusLine = {type: "command", command: "bash ~/.claude/core-hud.sh"}
  | .permissions = (.permissions // {})
  | .permissions.defaultMode = "bypassPermissions"
  | .permissions.allow = ["*"]
  | .hooks = (.hooks // {})
  | .hooks.PreToolUse = (
      ((.hooks.PreToolUse // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("judge-hook.sh") | not)))
      + [{hooks: [{type: "command", command: "bash ~/.claude/judge-hook.sh", statusMessage: "judge-hook"}]}]
    )
  | .hooks.PostToolUse = (
      ((.hooks.PostToolUse // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("writing-guard.sh") | not)))
      + [{matcher: "Write|Edit", hooks: [{type: "command", command: "bash ~/.claude/writing-guard.sh", statusMessage: "writing-guard"}]}]
    )
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "settings.json wired: judge-hook, writing-guard, core-hud, bypassPermissions, allow [*]"
```

## Step 4: write the CLAUDE.md guidelines (backup first; idempotent)

The canonical guidelines (Advisor, Decisive Thinking, Coding, Review Mindset, Writing) live in `$CLAUDE_PLUGIN_ROOT/templates/claude-md.md`, fenced by `<!-- BEGIN core:guidelines -->` and `<!-- END core:guidelines -->`. This replaces a prior fenced block if present, otherwise appends one. Content outside the fences is left alone.

```bash
CLAUDE_MD=~/.claude/CLAUDE.md
TEMPLATE="$CLAUDE_PLUGIN_ROOT/templates/claude-md.md"
touch "$CLAUDE_MD"
cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
awk '
  /<!-- BEGIN core:guidelines -->/ {skip=1}
  !skip {print}
  /<!-- END core:guidelines -->/ {skip=0; next}
' "$CLAUDE_MD" > "$tmp"

# Collapse trailing blank lines to exactly one separator, then append the template.
awk '{ if (NF==0) { blanks++ } else { while (blanks>0) { print ""; blanks-- }; print } }' "$tmp" > "$CLAUDE_MD"
printf '\n' >> "$CLAUDE_MD"
cat "$TEMPLATE" >> "$CLAUDE_MD"
rm -f "$tmp"
echo "CLAUDE.md guidelines section refreshed"
```

## Step 5: summary

Print this checklist, substituting the seeded/existing state for judge-rules:

```
core:setup
----------
~/.claude/judge-hook.sh        installed
~/.claude/writing-guard.sh     installed
~/.claude/core-hud.sh          installed (statusline)
~/.claude/judge-rules.json     seeded | existing
~/.claude/settings.json        wired (bypassPermissions, allow [*])
~/.claude/CLAUDE.md            guidelines section written
```

Then tell the user: restart Claude Code for the hooks and statusline to take effect.
