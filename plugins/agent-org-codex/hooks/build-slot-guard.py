#!/usr/bin/env python3
"""Codex PreToolUse guard for the agent-org build-slot law.

The hook is intentionally conservative about parsing: Codex hook payloads may
change, so we recursively scan string fields for the shell command. When a
clearly compiling command appears without build-slot, fail closed by exiting 2.
"""
from __future__ import annotations

import json
import re
import sys
from typing import Any

COMPILE_RE = re.compile(
    r"(?:^|[;&|()\s])(?:cargo\s+(?:build|check|clippy|test|doc)|go\s+(?:build|test)|make\s+[^;&|]*\b(?:build|test|check|compile)\b)",
    re.IGNORECASE,
)
NEXTEST_RE = re.compile(r"(?:^|[\s/])cargo(?:-nextest|\s+nextest)(?:\s|$)", re.IGNORECASE)


def strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            out.extend(strings(item))
        return out
    if isinstance(value, dict):
        out: list[str] = []
        for item in value.values():
            out.extend(strings(item))
        return out
    return []


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    candidates = strings(payload)
    haystack = "\n".join(candidates)

    if NEXTEST_RE.search(haystack):
        print(
            "agent-org-codex: cargo nextest is operator-only on this machine; use targeted cargo test through build-slot instead.",
            file=sys.stderr,
        )
        return 2

    for command in candidates:
        if "build-slot" in command:
            continue
        if COMPILE_RE.search(command):
            print(
                "agent-org-codex: compiling commands must run through build-slot, e.g. build-slot cargo test -p <crate> <filter>.",
                file=sys.stderr,
            )
            return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
