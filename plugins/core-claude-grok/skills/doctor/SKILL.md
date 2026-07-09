---
name: doctor-skill
description: Read-only health check of the core install (Claude or Grok). Checks hook files, wiring (settings or compat flag), guidelines sync (CLAUDE.md/AGENTS.md), judge-rules, version stamp. Run /core-claude-grok:doctor after updates or if hooks seem inert.
---

# /core-claude-grok:doctor

One read-only pass; report the output verbatim and make NO writes. The single most important line is the judge-hook wiring check: with `bypassPermissions` on and the judge unwired, nothing gates tool calls.

```bash
P="$CLAUDE_PLUGIN_ROOT"
S=~/.claude/settings.json
echo '== files (plugin vs installed) =='
for pair in "hooks/judge-hook.sh judge-hook.sh" "hooks/writing-guard.sh writing-guard.sh" "hooks/research-nudge.sh research-nudge.sh" "statusline/core-hud.sh core-hud.sh"; do
  set -- $pair
  if [ ! -f ~/.claude/"$2" ]; then echo "$2: MISSING — run /core-claude-grok:setup"
  elif diff -q "$P/$1" ~/.claude/"$2" >/dev/null 2>&1; then echo "$2: in sync"
  else echo "$2: DRIFT — local differs from the plugin copy; diff them before re-running setup (setup backs up first, but decide which side wins)"
  fi
done

echo '== settings wiring =='
if [ ! -f "$S" ]; then echo 'settings.json: MISSING'; else
  jq -e '.permissions.defaultMode == "bypassPermissions"' "$S" >/dev/null 2>&1 \
    && echo 'bypassPermissions: on' || echo 'bypassPermissions: off (posture not applied — judge wiring below matters less)'
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("judge-hook"))' "$S" >/dev/null 2>&1 \
    && echo 'judge-hook (PreToolUse): wired' \
    || echo 'judge-hook (PreToolUse): NOT WIRED — if bypassPermissions is on, NOTHING gates tool calls; re-run /core-claude-grok:setup now'
  jq -e '[.hooks.PostToolUse[]?.hooks[]?.command] | any(test("writing-guard"))' "$S" >/dev/null 2>&1 \
    && echo 'writing-guard (PostToolUse): wired' || echo 'writing-guard (PostToolUse): NOT WIRED'
  jq -e '[.hooks.PostToolUse[]? | select((.hooks | map(.command) | join(" ")) | test("writing-guard")) | .matcher // ""] | any(test("skyline"))' "$S" >/dev/null 2>&1 \
    && echo 'writing-guard matcher: covers skyline_create/skyline_edit' \
    || echo 'writing-guard matcher: Write|Edit only — DEAD on skyline-mandated machines; re-run /core-claude-grok:setup'
  jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("research-nudge"))' "$S" >/dev/null 2>&1 \
    && echo 'research-nudge (Stop): wired' || echo 'research-nudge (Stop): NOT WIRED'
  jq -e '.statusLine.command // "" | test("core-hud")' "$S" >/dev/null 2>&1 \
    && echo 'core-hud (statusLine): wired' || echo 'core-hud (statusLine): NOT WIRED'
fi

echo '== CLAUDE.md guidelines =='
awk '/<!-- BEGIN core:guidelines -->/{f=1} f{print} /<!-- END core:guidelines -->/{f=0}' ~/.claude/CLAUDE.md 2>/dev/null \
  | diff -q - "$P/templates/claude-md.md" >/dev/null 2>&1 \
  && echo 'fenced block: in sync with the plugin template' \
  || echo 'fenced block: DRIFT or missing — re-run /core-claude-grok:setup Step 4 to refresh (content outside the fences is preserved)'

echo '== judge rules =='
if [ -f ~/.claude/judge-rules.json ]; then
  echo "active rules: $(jq '.rules | length' ~/.claude/judge-rules.json 2>/dev/null || echo 'UNPARSEABLE — judge is effectively a no-op')"
  MISSING=$(jq -r --slurpfile ex "$P/hooks/judge-rules.example.json" '
    [.rules[].pattern] as $mine
    | [$ex[0].rules[] | select(.pattern as $p | ($mine | index($p)) | not)
       | "  " + (._category // "?") + ": " + (.reason // .pattern)] | .[]' ~/.claude/judge-rules.json 2>/dev/null)
  if [ -n "$MISSING" ]; then
    echo 'shipped example rules NOT in your local set (your file is never auto-edited; merge by hand if wanted):'
    echo "$MISSING"
  else
    echo 'local set covers every shipped example rule'
  fi
else
  echo 'judge-rules.json: MISSING — the judge is a NO-OP; seed it via /core-claude-grok:setup Step 2'
fi

echo '== version =='
inst=$(cat ~/.claude/.core-claude-grok-version 2>/dev/null || echo none)
plug=$(jq -r .version "$P/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)
echo "installed: $inst | plugin: $plug"
[ "$inst" = "$plug" ] || echo 'install is stale relative to the plugin — re-run /core-claude-grok:setup'
```

Interpretation guide for the report you give the user:

- The FILES section names which side moved; do not overwrite DRIFT blindly — the local copy may carry deliberate customization (statuslines often do).
- NOT WIRED on judge-hook while bypassPermissions is on is the one red-alert combination; recommend re-running setup in the same breath.
- The judge-rules section lists example rules missing locally so upgrades are visible; the local file is user-owned and never auto-merged.
