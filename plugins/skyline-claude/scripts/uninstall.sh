#!/usr/bin/env bash
set -e

# 1. Remove MCP wiring, hooks, and instructions from all agents.
skyline agent uninstall --target=all --yes

# 2. Stop the running daemon, then remove the autostart service.
skyline daemon stop --port 7333 2>/dev/null || true
skyline daemon uninstall --port 7333 2>/dev/null || true

echo ""
echo "skyline MCP wiring and daemon removed."
echo ""
echo "To complete removal, run:"
echo "  claude plugin uninstall skyline-claude"
echo "  codex plugin remove skyline-codex"
echo "  npm uninstall -g @skylence-ai/skyline"
