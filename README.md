# Multi-LLM Skyline Marketplace

Marketplace repo for Skyline agent plugins. It exposes the same Skyline MCP
daemon to Claude Code and Codex, with agent-side hooks that steer native file
work toward Skyline's hash-guarded tools.

## Prerequisite

Install and bootstrap Skyline first:

```bash
npm install -g @skylence-ai/skyline
skyline setup
```

`skyline setup` installs the shared HTTP daemon on port 7333 and installs the
optional marketplace plugins when supported agent CLIs are available. The Claude
and Codex plugins in this repo carry their own MCP configuration; global MCP
wiring is only needed when explicitly requested with `skyline agent install`.

## Included plugins

- `core-claude`: Opinionated Claude Code baseline: `/core-claude:setup` installs the
  judge-hook rules engine, the writing-guard, the core-hud statusline, and
  CLAUDE.md guidelines.
- `soloterm-agent-org`: Skylence agent-org v2 in a box — orchestrator, solo-worker,
  replacer, and org-audit skills, with Solo MCP server substrate, build-slot
  compile serializer, and the Codex-side conduct pack.

## Verify

```bash
skyline daemon status
```

The port 7333 row should show `running`. In a fresh agent session, the Skyline
MCP tools should include `skyline_read`, `skyline_grep`, `skyline_edit`,
`skyline_git`, and `skyline_run`.

## Upgrade and removal

Manual removal commands are printed by the uninstall flow. Package removal uses
the package manager you installed with, for example
`npm uninstall -g @skylence-ai/skyline`.
