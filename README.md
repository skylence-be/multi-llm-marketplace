# Multi-LLM Marketplace

Skylence's marketplace of multi-agent orchestration and agent-baseline plugins,
packaged for Claude Code, Codex, and Antigravity. The agent-org plugins turn a
single agent CLI into a conductor-and-workers organisation; the core plugins
install each agent's opinionated baseline (hooks, statusline, guidelines).

Owner: Skylence (github.com/skylence-be).

## What's in here

The agent-org plugins bundle the **Solo MCP server**, the board / PTY / timer
substrate the orchestration skills run on. An orchestrator conducts; planner,
solo-worker, replacer, and org-audit skills fill the roles; a capacity-check
gate rations spawns and the build-slot serializer keeps one compile at a time on
a shared machine. The core plugins install the per-agent baseline: a judge-hook
rules engine, a writing-guard, a statusline, and CLAUDE.md guidelines.

The agent-org plugins are self-contained. The Solo MCP server is bundled and
wired by the plugin, so no separate daemon install is required.

## Plugins

Each plugin ships in a per-agent variant. Current versions live in each plugin's
manifest, not in this README.

**Claude Code** (`.claude-plugin/marketplace.json`):

- `core-claude` : opinionated Claude Code baseline. `/core-claude:setup` installs
  the judge-hook rules engine, the writing-guard, the core-hud statusline, and
  the CLAUDE.md guidelines.
- `soloterm-agent-org` : the agent-org stack. Orchestrator, planner, solo-worker,
  replacer, org-audit, and capacity-check skills, plus the Solo MCP server,
  the build-slot compile serializer, the capacity-probe RAM gate, and the
  session-discipline hooks.

**Codex and Antigravity** (`.agents/plugins/marketplace.json`):

- `core-codex`, `core-antigravity` : the core baseline for each CLI.
- `soloterm-agent-org-codex`, `soloterm-agent-org-antigravity` : the agent-org
  stack for each CLI, kept in doctrinal sync with the Claude variant.

## Install

**Claude Code:**

```
/plugin marketplace add skylence-be/multi-llm-marketplace
/plugin install soloterm-agent-org@multi-llm-marketplace
/plugin install core-claude@multi-llm-marketplace
```

**Codex / Antigravity:** add this repo as a plugin source for the agent, then
install the matching `-codex` or `-antigravity` variant. The offerings for those
CLIs are declared in `.agents/plugins/marketplace.json`.

## Keeping variants in sync

The three agent-org variants share one body of doctrine. A change to the shared
conduct lands in all three skill trees together, each with its own version bump.
