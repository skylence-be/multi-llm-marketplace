---
name: setup
description: One-shot, no-prompt installer for the Grok core baseline user-scope state. Seeds ~/.grok/judge-rules.json (only if absent), writes the core guidelines into ~/.grok/AGENTS.md, stamps the version, and sets [compat.claude] hooks = false in config.toml. The hooks (judge-hook, writing-guard, research-nudge) activate from the installed plugin itself on trust. Invoke as /core-grok:setup on a new machine or after fresh Grok install.
---

# /core-grok:setup

Run once on a new machine. The hooks ship with the plugin and activate when the plugin is trusted and loaded; this skill writes the two user-scope files they depend on. Every step that overwrites makes a timestamped backup first.

All source files live under `$GROK_PLUGIN_ROOT` (Grok exposes the plugin root via this env var; `CLAUDE_PLUGIN_ROOT` is also set as alias for compatibility).

## Step 1: seed the judge rules (only if absent)

The judge-hook reads `~/.grok/judge-rules.json`. Seeding leaves an existing file untouched so local edits survive a re-run.

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
mkdir -p ~/.grok
if [ ! -f ~/.grok/judge-rules.json ]; then
  cp "$PLUGIN_ROOT/hooks/judge-rules.example.json" ~/.grok/judge-rules.json
  echo "seeded ~/.grok/judge-rules.json"
else
  echo "~/.grok/judge-rules.json already exists, left as-is"
fi
```

## Step 2: write the AGENTS.md guidelines (backup first; idempotent)

The canonical guidelines live in `$PLUGIN_ROOT/templates/agents-md.md`, fenced by `<!-- BEGIN core:guidelines -->` and `<!-- END core:guidelines -->`. This replaces a prior fenced block if present, otherwise appends one. Content outside the fences is left alone.

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
AGENTS_MD=~/.grok/AGENTS.md
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
  echo "AGENTS.md guidelines: DRIFT vs the shipped example — re-run /core-grok:setup to refresh"
fi
```

## Step 3: stamp the installed version

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
mkdir -p ~/.grok
jq -r .version "$PLUGIN_ROOT/plugin.json" > ~/.grok/.core-grok-version
echo "stamped ~/.grok/.core-grok-version: $(cat ~/.grok/.core-grok-version)"
```

## Step 4: disable Claude hooks compatibility

This prevents Grok from loading Claude's hooks (which can conflict with the Grok-native ones from this plugin).

```bash
CONFIG=~/.grok/config.toml
mkdir -p ~/.grok
if [ -f "$CONFIG" ]; then
  cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
fi

# Check if section exists
if grep -q '^\[compat.claude\]' "$CONFIG" 2>/dev/null; then
  # Update hooks = false inside the section
  awk '
    /^\[compat.claude\]/ { print; in_sec=1; next }
    in_sec && /^hooks[[:space:]]*=/ { print "hooks = false"; in_sec=0; next }
    in_sec && /^\[/ { in_sec=0; print; next }
    { print }
  ' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  echo "updated [compat.claude] hooks = false in config.toml"
else
  # Append the section
  cat >> "$CONFIG" << 'EOF'

[compat.claude]
hooks = false
EOF
  echo "added [compat.claude] hooks = false to config.toml"
fi
```

## Step 5: summary

```
core-grok:setup
----------------------
~/.grok/judge-rules.json      seeded | existing
~/.grok/AGENTS.md             guidelines section written
~/.grok/.core-grok-version    stamped
~/.grok/config.toml           [compat.claude] hooks = false set
hooks (judge/writing/research) active from the installed plugin (requires trust)
```

Then tell the user: restart the Grok session (or reload plugins with `grok plugin reload` or the UI) for full effect. The judge-hook and research-nudge escalate via `grok -p`, so a working `grok` on PATH is required (the escalate and nudge fail open without it).
