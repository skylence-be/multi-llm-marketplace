#!/usr/bin/env bash
set -e

# 1. Update the skyline binary itself to the latest GitHub release.
skyline update --yes

# 2. Restart the daemon so it runs the freshly installed binary.
skyline daemon restart --port 7333 2>/dev/null || skyline daemon install --port 7333

echo ""
echo "skyline binary updated and daemon restarted."
echo ""
echo "To pull the latest plugins, run:"
echo "  claude plugin marketplace update multi-llm-marketplace && claude plugin update skyline-claude"
echo "  codex plugin marketplace upgrade multi-llm-marketplace"
echo ""
echo "Restart your agent session to load the updated plugin."
