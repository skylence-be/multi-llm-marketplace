---
name: setup-skill
description: One-shot, no-prompt installer for the unified core baseline (Claude Code + Grok). Detects host, seeds judge-rules (to ~/.claude or ~/.grok), writes guidelines (CLAUDE.md or AGENTS.md), wires posture for Claude, sets compat.claude hooks=false for Grok, stamps version. Hooks activate via plugin (Grok) or settings (Claude). Invoke as /core-claude-grok:setup.
---

# /core-claude-grok:setup

Run once on a new machine. Installs the core baseline with no prompts. Every step that overwrites makes a timestamped backup first. Execute the steps in order, then report the checklist.

All source files live under the plugin root (`$CLAUDE_PLUGIN_ROOT` or `$GROK_PLUGIN_ROOT`; aliases provided for cross-compat). The script below auto-detects the host.

> Posture note: this skill sets `permissions.defaultMode` to `bypassPermissions` on Claude. On Grok it sets `[compat.claude] hooks = false` so Grok-native plugin hooks take precedence. The judge-hook + rules are the safety gate.

## Host detection (run this first)

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -n "${GROK_SESSION_ID:-${GROK_PLUGIN_ROOT:-}}" ] || command -v grok >/dev/null 2>&1 && [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  HOST=grok
  CONFIG_DIR=~/.grok
  RULES_FILE=~/.grok/judge-rules.json
  GUIDELINES_FILE=~/.grok/AGENTS.md
  GUIDELINES_TEMPLATE="$PLUGIN_ROOT/templates/agents-md.md"
  VERSION_FILE=~/.grok/.core-claude-grok-version
  echo "Host: Grok (using $CONFIG_DIR)"
else
  HOST=claude
  CONFIG_DIR=~/.claude
  RULES_FILE=~/.claude/judge-rules.json
  GUIDELINES_FILE=~/.claude/CLAUDE.md
  GUIDELINES_TEMPLATE="$PLUGIN_ROOT/templates/claude-md.md"
  VERSION_FILE=~/.claude/.core-claude-grok-version
  echo "Host: Claude (using $CONFIG_DIR)"
fi
mkdir -p "$CONFIG_DIR"
```

## Step 1 (Claude): install hook/statusline scripts to ~/.claude (Grok uses plugin hooks/hooks.json)

```bash
if [ "$HOST" = claude ]; then
  mkdir -p ~/.claude
  ts=$(date +%Y%m%d%H%M%S)
  for f in judge-hook.sh writing-guard.sh research-nudge.sh core-hud.sh; do
    [ -f ~/.claude/$f ] && cp ~/.claude/$f ~/.claude/$f.bak.$ts
  done
  cp "$PLUGIN_ROOT/hooks/judge-hook.sh" \
     "$PLUGIN_ROOT/hooks/writing-guard.sh" \
     "$PLUGIN_ROOT/hooks/research-nudge.sh" \
     "$PLUGIN_ROOT/statusline/core-hud.sh" ~/.claude/
  chmod +x ~/.claude/judge-hook.sh ~/.claude/writing-guard.sh ~/.claude/research-nudge.sh ~/.claude/core-hud.sh
  echo "hook scripts + hud copied to ~/.claude"
else
  echo "Grok: hooks declared in plugin hooks/hooks.json (no copy needed)"
fi
```

## Step 2: seed the judge rules (only if absent)

Leaves an existing rules file untouched.

```bash
if [ ! -f "$RULES_FILE" ]; then
  cp "$PLUGIN_ROOT/hooks/judge-rules.example.json" "$RULES_FILE"
  echo "seeded $RULES_FILE"
else
  echo "$RULES_FILE already exists, left as-is"
fi
```

## Step 3 (continued): wire settings (Claude only) + compat flag (Grok)

```bash
if [ "$HOST" = claude ]; then
  SETTINGS=~/.claude/settings.json
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

  tmp=$(mktemp)
  jq '
    .statusLine = {type: "command", command: "bash ~/.claude/core-hud.sh"}
    | .disableWorkflows = true
    | .awaySummaryEnabled = false
    | .env = (.env // {})
    | .env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
    | .permissions = (.permissions // {})
    | .permissions.defaultMode = "bypassPermissions"
    | .hooks = (.hooks // {})
    | .hooks.PreToolUse = (
        ((.hooks.PreToolUse // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("judge-hook.sh") | not)))
        + [{hooks: [{type: "command", command: "bash ~/.claude/judge-hook.sh", statusMessage: "judge-hook"}]}]
      )
    | .hooks.PostToolUse = (
        ((.hooks.PostToolUse // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("writing-guard.sh") | not)))
        + [{matcher: "Write|Edit|mcp__.*skyline_(create|edit)", hooks: [{type: "command", command: "bash ~/.claude/writing-guard.sh", statusMessage: "writing-guard"}]}]
      )
    | .hooks.Stop = (
        ((.hooks.Stop // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("research-nudge.sh") | not)))
        + [{hooks: [{type: "command", command: "bash ~/.claude/research-nudge.sh", statusMessage: "research-nudge"}]}]
      )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  PROFILE="$HOME/.zshrc"
  case "${SHELL:-}" in *bash) PROFILE="$HOME/.bashrc" ;; esac
  touch "$PROFILE"
  cp "$PROFILE" "$PROFILE.bak.$(date +%Y%m%d%H%M%S)"
  ptmp=$(mktemp)
  awk '/# >>> core:env >>>/{s=1} !s{print} /# <<< core:env <<</{s=0; next}' "$PROFILE" > "$ptmp"
  { cat "$ptmp"; printf '\n# >>> core:env >>>\nexport CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1\n# <<< core:env <<<\n'; } > "$PROFILE"
  rm -f "$ptmp"
  echo "Claude: settings.json wired + profile pinned"
else
  # Grok: disable claude hook compat so our plugin hooks win
  CONFIG=~/.grok/config.toml
  mkdir -p ~/.grok
  if [ -f "$CONFIG" ]; then cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)"; fi
  if grep -q '^\[compat.claude\]' "$CONFIG" 2>/dev/null; then
    awk '
      /^\[compat.claude\]/ { print; in_sec=1; next }
      in_sec && /^hooks[[:space:]]*=/ { print "hooks = false"; in_sec=0; next }
      in_sec && /^\[/ { in_sec=0; print; next }
      { print }
    ' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
    echo "Grok: updated [compat.claude] hooks = false"
  else
    cat >> "$CONFIG" << 'EOT'

[compat.claude]
hooks = false
EOT
    echo "Grok: added [compat.claude] hooks = false"
  fi
fi
```

## Step 4: write the guidelines (CLAUDE.md or AGENTS.md; uses same content)

```bash
touch "$GUIDELINES_FILE"
cp "$GUIDELINES_FILE" "$GUIDELINES_FILE.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
awk '
  /<!-- BEGIN core:guidelines -->/ {skip=1}
  !skip {print}
  /<!-- END core:guidelines -->/ {skip=0; next}
' "$GUIDELINES_FILE" > "$tmp"

awk '{ if (NF==0) { blanks++ } else { while (blanks>0) { print ""; blanks-- }; print } }' "$tmp" > "$GUIDELINES_FILE"
printf '\n' >> "$GUIDELINES_FILE"
cat "$GUIDELINES_TEMPLATE" >> "$GUIDELINES_FILE"
rm -f "$tmp"
echo "guidelines section refreshed in $GUIDELINES_FILE"

installed=$(awk '/<!-- BEGIN core:guidelines -->/{f=1} f{print} /<!-- END core:guidelines -->/{f=0}' "$GUIDELINES_FILE")
if [ "$installed" = "$(cat "$GUIDELINES_TEMPLATE")" ]; then
  echo "guidelines: in sync"
else
  echo "guidelines: DRIFT — re-run setup"
fi
```

## Step 5: stamp the installed version

```bash
if [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
  jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json" > "$VERSION_FILE"
elif [ -f "$PLUGIN_ROOT/plugin.json" ]; then
  jq -r .version "$PLUGIN_ROOT/plugin.json" > "$VERSION_FILE"
else
  echo "unknown" > "$VERSION_FILE"
fi
echo "stamped $VERSION_FILE: $(cat "$VERSION_FILE")"
```

## Step 6: summary

Print the report from the commands above. Rough checklist (adapts to host):

```
core-claude-grok:setup
----------
judge rules          seeded | existing   ($RULES_FILE)
guidelines           written + verified  ($GUIDELINES_FILE)
version stamp        written
Grok:                [compat.claude] hooks = false (if applicable)
Claude:              hooks/statusline copied + settings wired + profile pinned + bypass
```

Restart/reload the session (or `grok plugin reload`) after setup. Run `/core-claude-grok:doctor` to audit. For Grok the hooks come from the installed plugin's `hooks/hooks.json` (requires --trust on install).
