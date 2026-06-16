#!/usr/bin/env bash
# PreToolUse enforcement: redirect native tools to skyline equivalents.
# Fail-open (exit 0) when the daemon is not running — never breaks the agent.
#
# Usage: skyline-enforce.sh <mode>
#   Mode is baked into each hooks.json matcher entry — no stdin parsing needed.

MODE="${1:-}"

# Probe the daemon: any HTTP response means it is up.
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -m 1 "http://127.0.0.1:7333/mcp" 2>/dev/null || exit 0
else
  exit 0
fi

case "$MODE" in
  read)
    printf "skyline is running: use skyline_read instead of Read.\n"
    printf "Returns ¶path#TAG anchors that feed directly into skyline_edit — no round-trip read before editing.\n"
    exit 2
    ;;
  edit)
    printf "skyline is running: use skyline_edit instead of Edit/Write, or skyline_create for new files.\n"
    printf "skyline_edit is hash-guarded — rejects stale writes instead of silently clobbering concurrent changes.\n"
    exit 2
    ;;
  grep)
    printf "skyline is running: use skyline_grep instead of Grep.\n"
    printf "Returns ¶path#TAG anchors; supports ripgrep options, PCRE2, context lines, multiline, and byte offsets.\n"
    printf "Use skyline_sgrep for structural (AST) search with pattern metavariables.\n"
    exit 2
    ;;
  glob)
    printf "skyline is running: use skyline_find instead of Glob.\n"
    printf "Gitignore-aware, returns ¶path#TAG anchors, supports mtime sorting and timeout.\n"
    printf "Use skyline_tree for a token-lean directory shape overview.\n"
    exit 2
    ;;
  bash)
    printf "skyline is running: use the appropriate skyline tool instead of Bash:\n"
    printf "  skyline_grep / skyline_sgrep  — text and structural (AST) search\n"
    printf "  skyline_find / skyline_tree   — file discovery and directory listing\n"
    printf "  skyline_git                   — git operations (status, diff, log, commit, push, …)\n"
    printf "  skyline_run                   — command execution (audited, compressed output, batch/background)\n"
    printf "  skyline_test                  — test runner and linter (cargo, go, pytest, jest, …)\n"
    printf "  skyline_conflicts             — merge conflict inspection and resolution\n"
    exit 2
    ;;
esac

exit 0
