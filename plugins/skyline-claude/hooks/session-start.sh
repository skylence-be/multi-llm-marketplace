#!/usr/bin/env bash
# session-start.sh — injects a steer to prefer skyline MCP tools over the
# built-in file tools whenever the skyline server is connected. When the
# local skyline HTTP daemon is NOT running, additionally instructs the model
# to offer the user a one-time daemon setup (with the benefits spelled out).
# A decline is recorded in ~/.claude/skyline-daemon-offer-declined and the
# offer is never injected again until that file is removed.

STEER="## skyline tool preference\n\nWhen skyline MCP tools (mcp__skyline__* or mcp__skyline-http__*) are connected, ALWAYS prefer them over the built-in file tools:\n\n- skyline_read instead of Read\n- skyline_edit instead of Edit / Write (hash-guarded patches; copy the ¶path#TAG header from skyline_read or skyline_grep output verbatim)\n- skyline_grep instead of Grep (returns ¶path#TAG anchors that feed straight into skyline_edit — no separate read needed)\n- skyline_sgrep / skyline_srewrite for structural (AST) search and multi-file rewrites\n- skyline_definition / skyline_references / skyline_rename / skyline_symbols when symbol identity matters\n\nIf the local HTTP server is connected (skyline-http-mcp, http://127.0.0.1:7333/mcp), prefer it — it is the locally installed daemon: faster startup, shared state across sessions, no per-session process spawn.\n\nWhy: skyline edits are content-hash guarded, so they reject stale writes instead of silently clobbering concurrent changes, and its grep anchors eliminate read-before-edit round-trips.\n\nUse the built-in tools only when actually needed: skyline is not connected, reading images / PDFs / Jupyter notebooks (built-in Read), editing notebooks (NotebookEdit), or a capability skyline lacks. Brief any delegated subagent with this same rule — it will not infer it."

OFFER="\n\n## skyline daemon offer\n\nThe local skyline HTTP daemon is NOT running on 127.0.0.1:7333. At the first natural opportunity (not mid-task), offer the user to install and set it up — once per session, and drop it if declined. Benefits to state:\n\n- Always-warm shared daemon: tool calls answer in 10-40 ms instead of paying ~1 s of npx startup per session\n- One process shared by every session and client, with state (snapshots, stale-edit recovery) shared across them\n- Hash-guarded edits stay ~60 tokens regardless of file size — vs read-then-edit flows that grow with the file (~83k tokens on a 10,000-line file)\n- Structural search/rewrite and symbol tools (rename, references) on top of plain grep\n\nIf they accept, run:\n\n1. npm install -g @skylence-ai/skyline\n2. skyline daemon start --port 7333\n3. claude mcp add --scope user --transport http skyline http://127.0.0.1:7333/mcp\n4. Verify: skyline daemon status (port should read running), then restart the session or /reload-plugins\n\nIf port 7333 is taken, pick a free port and use it in steps 2-3.\n\nIf they DECLINE, record it so they are never asked again in any future session — run: touch ~/.claude/skyline-daemon-offer-declined — then drop the subject for good. If they say not now / maybe later, do NOT create the file; just drop it for this session."


# Probe the daemon: any HTTP response on /mcp means it is up (connection
# refused / timeout means it is not). Skip the offer if curl is unavailable,
# or if the user previously declined (marker file).
DECLINED_MARKER="$HOME/.claude/skyline-daemon-offer-declined"
DAEMON_UP=0
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -m 1 "http://127.0.0.1:7333/mcp" 2>/dev/null && DAEMON_UP=1
else
  DAEMON_UP=1
fi

CONTEXT="$STEER"
if [ "$DAEMON_UP" = "0" ] && [ ! -f "$DECLINED_MARKER" ]; then
  CONTEXT="$STEER$OFFER"
fi

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$CONTEXT"

exit 0