# soloterm-agent-org-antigravity

The Google Antigravity (Gemini) sibling of the Skylence `soloterm-agent-org-claude-grok` plugin.

This is the Antigravity side of the Solo-orchestrated agent org. It bundles the
Solo MCP server so an Antigravity session can drive the same board / PTY /
timer substrate the Claude and Codex variants use, and it ships the same four
role playbooks plus the machine-law helper scripts.

## What it wires

- **mcp_config.json** — registers the `solo` MCP server (stdio,
  `/Applications/Solo.app/Contents/MacOS/mcp`). This is the dependency that
  makes every role skill runnable: orchestrator/worker/replacer/audit are all
  built on Solo's todo, process, and timer tools.
- **skills/** — the five host-neutral role playbooks (`orchestrator`,
  `planner`, `solo-worker`, `replacer`, `org-audit`) plus the
  `capacity-check` spawn gate, invocable as
  `soloterm-agent-org-antigravity:<skill>`.
- **scripts/build-slot** — machine-wide compile serializer (one build at a
  time; install to `~/.local/bin/`).
- **scripts/ghost-probe.sh** — the no-fusion law's input-line classifier for
  Solo PTYs.
- **scripts/capacity-probe.sh** — macOS RAM probe behind capacity-check:
  `VERDICT=GREEN|YELLOW|RED` spawn verdicts, exit code 0/1/2 (3 = non-macOS).
- **AGENTS.md** — portable worker guidance.

## Siblings

- `soloterm-agent-org-claude-grok` — Claude Code / Grok (auto-loads, ships the org-lane-mark +
  org-stop-gate session-discipline hooks).
- `soloterm-agent-org-codex` — Codex (`.codex-plugin/plugin.json` → `.mcp.json`, ships
  SessionStart steering + a PreToolUse build-slot guard).

Solo runs as the same stdio binary on every host; only the per-host wrapper
file differs (`.mcp.json` bare map for Claude, `{"mcpServers":{…}}` for Codex
and Antigravity).

## ⚠️ Still needs verification

1. **No enforcement / discipline hook yet.** The Claude variant's org-stop-gate
   is a `Stop` hook (with `stop_hook_active` + `session_id` JSON); Antigravity's
   documented hook surface is `PreToolUse` only, so the anti-idle gate does not
   port. A build-slot `PreToolUse` guard on `run_command` would need to parse
   Antigravity's `toolCall.args` payload, whose field shape is **not
   documented**. Until that is confirmed, build-slot is enforced by guidance
   (AGENTS.md) and the bundled script, not a hook. TODO: add the guard once the
   `run_command` payload shape is verified.
2. **`plugin.json` `mcpServers` pointer shape.** We keep
   `"mcpServers": "./mcp_config.json"`, matching `skyline-antigravity`; whether
   that exact field is required or `mcp_config.json` is auto-discovered at the
   plugin root is unconfirmed.
3. **Role-skill tool names.** The skills describe the Solo-based org model,
   which is host-neutral, but reference Claude/Codex spawn specifics in places.
   The Solo MCP tool names (todo_*, list_processes, timer_*, send_input) are the
   same across hosts; the agent-spawn flags differ. TODO: an Antigravity-native
   worker-spawn note once the org runs Gemini lane workers in anger.
