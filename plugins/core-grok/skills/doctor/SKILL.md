---
name: doctor
description: Read-only health check of the core-grok install — judge-rules.json vs plugin example, ~/.grok/AGENTS.md guidelines sync, version stamp, and notes on plugin-provided hooks. Run /core-grok:doctor when hooks look inert, after a plugin update, or on a machine you don't trust. Writes nothing.
---

# /core-grok:doctor

One read-only pass; report the output verbatim and make NO writes.

All source files live under `$GROK_PLUGIN_ROOT` (Grok exposes the plugin root via this env var; `CLAUDE_PLUGIN_ROOT` is also set as alias for compatibility).

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"

echo '== files (plugin vs user scope) =='
if [ ! -f ~/.grok/judge-rules.json ]; then
  echo "judge-rules.json: MISSING — run /core-grok:setup"
elif diff -q "$PLUGIN_ROOT/hooks/judge-rules.example.json" ~/.grok/judge-rules.json >/dev/null 2>&1; then
  echo "judge-rules.json: in sync with plugin example"
else
  echo "judge-rules.json: DRIFT or customized — local differs from the plugin copy (this is normal if you edited rules by hand)"
fi

echo ''
echo '== AGENTS.md guidelines =='
if [ -f ~/.grok/AGENTS.md ]; then
  installed=$(awk '/<!-- BEGIN core:guidelines -->/{f=1} f{print} /<!-- END core:guidelines -->/{f=0}' ~/.grok/AGENTS.md)
  template=$(cat "$PLUGIN_ROOT/templates/agents-md.md")
  if [ "$installed" = "$template" ]; then
    echo "fenced block: in sync with the plugin template"
  else
    echo "fenced block: DRIFT or missing — re-run /core-grok:setup to refresh (content outside the fences is preserved)"
  fi
else
  echo "~/.grok/AGENTS.md: MISSING — run /core-grok:setup"
fi

echo ''
echo '== version stamp =='
if [ -f ~/.grok/.core-grok-version ]; then
  inst=$(cat ~/.grok/.core-grok-version)
  plug=$(jq -r .version "$PLUGIN_ROOT/plugin.json" 2>/dev/null || echo unknown)
  echo "installed: $inst | plugin: $plug"
  [ "$inst" = "$plug" ] || echo 'install is stale relative to the plugin — re-run /core-grok:setup'
else
  echo "~/.grok/.core-grok-version: MISSING — re-run /core-grok:setup"
fi

echo ''
echo '== hooks note (Grok specific) =='
echo "Hooks (judge-hook, writing-guard, research-nudge) are declared in the plugin's hooks/hooks.json."
echo "They are loaded automatically when the core-grok plugin is trusted and active in the session."
echo "There is no manual copy into ~/.grok/hooks/ (unlike some Claude setups)."
echo "To force reload: open /plugins and press 'r', or run 'grok plugin reload'."
echo ""
echo '== compat check =='
if grep -q '^\[compat.claude\]' ~/.grok/config.toml 2>/dev/null && grep -q 'hooks = false' ~/.grok/config.toml; then
  echo "[compat.claude] hooks = false : set (good, prevents loading Claude hooks)"
else
  echo "[compat.claude] hooks = false : missing — re-run /core-grok:setup"
fi

echo ''
echo '== plugin root =='
echo "PLUGIN_ROOT: $PLUGIN_ROOT"
if [ -f "$PLUGIN_ROOT/hooks/hooks.json" ]; then
  echo "plugin hooks/hooks.json present"
else
  echo "WARNING: plugin hooks/hooks.json missing"
fi
```

Interpretation guide for the report:

- The most important thing for safety is that judge-rules are seeded when using the baseline.
- DRIFT on the guidelines block means re-run setup to get the latest conduct rules.
- Version mismatch means the installed plugin is older than what setup last ran.
- Hooks are plugin-managed; reload the plugin if they don't seem active.
