#!/usr/bin/env bash
# PreToolUse enforcement: redirect native tools to skyline equivalents.
# Fail-open (exit 0) when the daemon is not running — never breaks the agent.

MODE="${1:-}"

if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -m 1 "http://127.0.0.1:7333/mcp" 2>/dev/null || exit 0
else
  exit 0
fi

CORE="select:mcp__plugin_skyline-claude_skyline__skyline_read,mcp__plugin_skyline-claude_skyline__skyline_edit,mcp__plugin_skyline-claude_skyline__skyline_create,mcp__plugin_skyline-claude_skyline__skyline_grep,mcp__plugin_skyline-claude_skyline__skyline_tree,mcp__plugin_skyline-claude_skyline__skyline_find,mcp__plugin_skyline-claude_skyline__skyline_git,mcp__plugin_skyline-claude_skyline__skyline_run"
SWITCH_ORIENT="Skyline is active. Switch to skyline tools for this session: run ToolSearch(\"$CORE\") then retry."
SWITCH_EDIT="Skyline is active. Switch to skyline tools for this session: run ToolSearch(\"$CORE\") then skyline_guide, then retry."
case "$MODE" in
  read) printf "skyline_read replaces Read. %s\n" "$SWITCH_ORIENT" >&2; exit 2 ;;
  edit) printf "skyline_edit/skyline_create replace Edit/Write. %s\n" "$SWITCH_EDIT" >&2; exit 2 ;;
  grep) printf "skyline_grep/skyline_sgrep replace Grep. %s\n" "$SWITCH_ORIENT" >&2; exit 2 ;;
  glob) printf "skyline_find/skyline_tree replace Glob. %s\n" "$SWITCH_ORIENT" >&2; exit 2 ;;
  bash) printf "skyline_grep/skyline_find/skyline_git/skyline_run/skyline_test replace Bash. %s\n" "$SWITCH_EDIT" >&2; exit 2 ;;
esac

exit 0
