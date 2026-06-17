---
name: solo-setup-skill
description: One-shot, no-prompt add-on for machines running SoloTerm. Installs the notify.sh hook and wires the six lifecycle notification hooks (PreCompact, PostCompact, Stop, StopFailure, TeammateIdle, Notification[idle_prompt]) into settings.json, and writes the core:solo guidance block (Solo MCP coordination: handoffs, scratchpads, todos, locks, cross-project transfer) into the user-scope CLAUDE.md. Additive only: it never touches the core:guidelines block or the hooks that core:setup installs. Invoke as /core:solo-setup.
disable-model-invocation: true
---

# /core:solo-setup

Run once on a SoloTerm machine, after `/core:setup`. Adds Solo-specific extras with no prompts. Every step that overwrites makes a timestamped backup first. Execute the steps in order, then report the Step 4 checklist.

All source files live under `$CLAUDE_PLUGIN_ROOT` (the root of this plugin). Run each block exactly as written.

> This skill is purely additive. It only installs `notify.sh` + its hook wiring and the `core:solo` CLAUDE.md block. It does NOT write the `core:guidelines` block, install judge/writing/research hooks, or change the permission posture — that is `/core:setup`'s job. Run `/core:setup` first.

## Step 1: install the notification hook script

```bash
mkdir -p ~/.claude
cp "$CLAUDE_PLUGIN_ROOT/hooks/notify.sh" ~/.claude/
chmod +x ~/.claude/notify.sh
```

## Step 2: wire the notification hooks into settings.json (backup first; idempotent)

Wires `notify.sh` into six lifecycle events. Native desktop notifications on macOS (osascript), Windows (PowerShell NotifyIcon), and Linux (notify-send); requires `jq`. Re-running strips the prior notify.sh entries from each event array before re-adding, so it never stacks duplicates. Existing unrelated hooks are preserved. If `Stop` is too noisy, delete the `.hooks.Stop` entry afterward.

```bash
SETTINGS=~/.claude/settings.json
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
jq '
  .hooks = (.hooks // {})
  | .hooks.PreCompact = (
      ((.hooks.PreCompact // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("notify.sh") | not)))
      + [{hooks: [{type: "command", command: "bash ~/.claude/notify.sh"}]}]
    )
  | .hooks.PostCompact = (
      ((.hooks.PostCompact // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("notify.sh") | not)))
      + [{hooks: [{type: "command", command: "bash ~/.claude/notify.sh"}]}]
    )
  | .hooks.Stop = (
      ((.hooks.Stop // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("notify.sh") | not)))
      + [{hooks: [{type: "command", command: "bash ~/.claude/notify.sh"}]}]
    )
  | .hooks.StopFailure = (
      ((.hooks.StopFailure // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("notify.sh") | not)))
      + [{hooks: [{type: "command", command: "bash ~/.claude/notify.sh"}]}]
    )
  | .hooks.TeammateIdle = (
      ((.hooks.TeammateIdle // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("notify.sh") | not)))
      + [{hooks: [{type: "command", command: "bash ~/.claude/notify.sh"}]}]
    )
  | .hooks.Notification = (
      ((.hooks.Notification // []) | map(select(((.hooks // []) | map(.command) | join(" ")) | test("notify.sh") | not)))
      + [{matcher: "idle_prompt", hooks: [{type: "command", command: "bash ~/.claude/notify.sh"}]}]
    )
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "settings.json wired: notify.sh on PreCompact, PostCompact, Stop, StopFailure, TeammateIdle, Notification(idle_prompt)"
```

## Step 3: write the CLAUDE.md core:solo block (backup first; idempotent; cross-checked)

The Solo coordination guidance lives in `$CLAUDE_PLUGIN_ROOT/templates/solo-md.md`, fenced by `<!-- BEGIN core:solo -->` and `<!-- END core:solo -->`. This replaces a prior `core:solo` block if present, otherwise appends one. The `core:guidelines` block and all other content are left alone.

```bash
CLAUDE_MD=~/.claude/CLAUDE.md
TEMPLATE="$CLAUDE_PLUGIN_ROOT/templates/solo-md.md"
touch "$CLAUDE_MD"
cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
awk '
  /<!-- BEGIN core:solo -->/ {skip=1}
  !skip {print}
  /<!-- END core:solo -->/ {skip=0; next}
' "$CLAUDE_MD" > "$tmp"

# Collapse trailing blank lines to exactly one separator, then append the template.
awk '{ if (NF==0) { blanks++ } else { while (blanks>0) { print ""; blanks-- }; print } }' "$tmp" > "$CLAUDE_MD"
printf '\n' >> "$CLAUDE_MD"
cat "$TEMPLATE" >> "$CLAUDE_MD"
rm -f "$tmp"
echo "CLAUDE.md core:solo block refreshed"

# Cross-check: the installed fenced block must match the shipped template verbatim.
installed=$(awk '/<!-- BEGIN core:solo -->/{f=1} f{print} /<!-- END core:solo -->/{f=0}' "$CLAUDE_MD")
if [ "$installed" = "$(cat "$TEMPLATE")" ]; then
  echo "CLAUDE.md core:solo: in sync with the shipped template"
else
  echo "CLAUDE.md core:solo: DRIFT vs the shipped template — re-run /core:solo-setup to refresh"
fi
```

## Step 4: summary

Print this checklist:

```
core:solo-setup
---------------
~/.claude/notify.sh            installed
~/.claude/settings.json        wired (notify.sh on PreCompact, PostCompact, Stop, StopFailure, TeammateIdle, Notification[idle_prompt])
~/.claude/CLAUDE.md            core:solo block written + cross-checked against the shipped template
```

Then tell the user: restart Claude Code for the notification hooks to take effect. If `Stop` notifications are too noisy, delete the `.hooks.Stop` notify.sh entry from `~/.claude/settings.json`.
