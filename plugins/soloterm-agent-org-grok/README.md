# soloterm-agent-org-grok

Grok port of the Skylence soloterm-agent-org (agent orchestration substrate).

## What it provides

- Solo MCP server registration (`solo` via `/Applications/Solo.app/Contents/MacOS/mcp`) — the board, PTY, timers, process management that powers every role.
- Skills (all five roles + helpers):
  - `orchestrator`
  - `planner`
  - `solo-worker`
  - `replacer`
  - `org-audit`
  - `capacity-check`
- Scripts: `build-slot`, `capacity-probe.sh`, `ghost-probe.sh`
- Session discipline hooks (adapted for Grok hook JSON + env):
  - org-lane-mark (PreToolUse on spawn/timer MCP tools)
  - org-conduct-refresh (SessionStart compact)
  - org-stop-gate (Stop)
- AGENTS.md worker guidance.
- `plugin.json` + `mcp_config.json`

## Install

```bash
grok plugin marketplace add skylence-be/multi-llm-marketplace
grok plugin install soloterm-agent-org-grok@multi-llm-marketplace --trust
```

After install, the `solo` MCP tools become available and the skills are listed (use `/skills` or invoke as slash commands).

## Usage in org mode

Typical flow:
- Orchestrator dispatches via Solo MCP `spawn_*` + `todo_write`.
- Workers run with the solo-worker skill.
- Capacity check gates heavy spawns on macOS.
- Post-compaction the conduct refresh fires automatically in marked sessions.
- Stop gate forces lane hygiene before idle.

See the skills for detailed playbooks. The conduct is the same as the Claude/Codex siblings.

## Notes

- The Solo binary path is the one used by the rest of the Skylence multi-LLM stack. If you use a different packaging, edit `mcp_config.json`.
- Hook markers use `/tmp/grok-org-lanes-<sessionId>` (falls back to claude names for mixed environments).
- Skills are host-agnostic; only spawn flags and a few env references are host specific in comments.

This plugin + core-grok together give you the full "super" Grok baseline + org.
