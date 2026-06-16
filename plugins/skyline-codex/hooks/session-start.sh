#!/bin/sh
# Codex SessionStart hook for the skylence-codex plugin.
# Keep this advisory and fail-open: it should steer the session when Codex
# consumes hook stdout, but never block startup if the hook contract changes.
cat <<'EOF'
## Skylence Codex plugin

Prefer skyline MCP tools for code work when available: skyline_tree, skyline_read,
skyline_grep, skyline_edit, skyline_git, and skyline_run. Use the bundled
Skylence MCP servers only when their local endpoints or binaries are reachable.
EOF
exit 0
