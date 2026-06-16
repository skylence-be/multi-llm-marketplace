#!/usr/bin/env sh
# PreToolUse enforcement for Google Antigravity.
# Contract: a JSON tool-call object arrives on STDIN; this script PRINTS a JSON
# object on STDOUT with a "decision" of "allow" / "deny" / "ask".
#
# Behaviour:
#   - FAIL OPEN: if the skyline daemon is unreachable, or curl is missing,
#     print {"decision":"allow"} and exit 0 so the native tool proceeds and the
#     agent is never blocked.
#   - If the daemon IS up, print {"decision":"deny","reason":"..."} steering the
#     agent to the skyline_* MCP tools instead of the native tool.
#
# POSIX sh. The first argument selects the redirect message (read/edit/grep/
# glob/bash); the STDIN payload is drained for contract compliance but the mode
# arg is what we key off.

MODE="${1:-}"

# Drain the tool-call JSON from STDIN (contract: STDIN carries the pending call).
# We do not currently parse it; the mode arg already tells us which tool fired.
STDIN_PAYLOAD="$(cat 2>/dev/null || true)"
: "${STDIN_PAYLOAD}"

allow() {
  printf '{"decision":"allow"}\n'
  exit 0
}

deny() {
  # $1 is a JSON-safe reason string (no embedded double quotes / backslashes).
  printf '{"decision":"deny","reason":"%s"}\n' "$1"
  exit 0
}

# Fail open when we cannot confirm the daemon is up.
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -m 1 "http://127.0.0.1:7333/mcp" 2>/dev/null || allow
else
  allow
fi

# Daemon is up: redirect to skyline tools. Tool names are the generic skyline_*
# names; the exact MCP namespace prefix Antigravity applies is unverified.
case "$MODE" in
  read) deny "skyline is active: use the skyline_read MCP tool instead of the native view_file tool." ;;
  edit) deny "skyline is active: use the skyline_edit / skyline_create MCP tools instead of the native write_to_file / replace_file_content / multi_replace_file_content tools." ;;
  grep) deny "skyline is active: use the skyline_grep / skyline_sgrep MCP tools instead of the native search tool." ;;
  glob) deny "skyline is active: use the skyline_find / skyline_tree MCP tools instead of the native glob tool." ;;
  bash) deny "skyline is active: use skyline_grep, skyline_find, skyline_tree, skyline_git, skyline_run, skyline_test instead of run_command for file/repo work." ;;
esac

# Unknown mode: do not block.
allow
