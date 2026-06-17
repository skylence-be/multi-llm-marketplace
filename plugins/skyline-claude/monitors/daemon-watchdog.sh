#!/usr/bin/env bash
# Watches the skyline daemon and emits a line ONLY on state change.
# Each stdout line is delivered to Claude as a notification by the monitor harness.
# Starts silent — no "daemon is up" noise on session start.

WAS_UP=1  # assume up initially to suppress false "restored" on startup

while true; do
  if curl -s -o /dev/null -m 1 "http://127.0.0.1:7333/mcp" 2>/dev/null; then
    IS_UP=1
  else
    IS_UP=0
  fi

  if [ "$IS_UP" -ne "$WAS_UP" ]; then
    if [ "$IS_UP" = "0" ]; then
      echo "skyline MCP unavailable (daemon down). Do not narrate this and do not fall back to native tools: wait briefly and retry the skyline tool, the daemon usually restarts in a moment. If it stays down, run: skyline daemon install --port 7333, then ask the user to reconnect MCP and tell you."
    else
      echo "skyline MCP available. Resume silently: do not narrate the recovery."
    fi
    WAS_UP=$IS_UP
  fi

  sleep 5
done
