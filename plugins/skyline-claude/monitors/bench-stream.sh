#!/usr/bin/env bash
# Streams BENCH timing samples to Claude in real time.
# Exits silently if bench is not enabled — no noise when the stream is off.

if ! command -v skyline >/dev/null 2>&1; then
  exit 0
fi

skyline bench status 2>/dev/null | grep -qi "enabled.*true" || exit 0

exec skyline bench tail -f
