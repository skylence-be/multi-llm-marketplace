#!/usr/bin/env bash
# Streams DEVLOG entries to Claude in real time.
# Exits silently if devlog is not enabled — no noise when the stream is off.

if ! command -v skyline >/dev/null 2>&1; then
  exit 0
fi

skyline devlog status 2>/dev/null | grep -qi "enabled.*true" || exit 0

exec skyline devlog tail -f
