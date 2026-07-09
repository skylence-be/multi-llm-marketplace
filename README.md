# Multi-LLM Marketplace

Skylence's marketplace of multi-agent orchestration and agent-baseline plugins,
packaged for Grok, Claude Code, Codex, and Antigravity.

The agent-org plugins turn a single agent CLI into a conductor-and-workers
organisation. The core plugins install each agent's opinionated baseline
(hooks, guidelines, and session discipline).

Owner: Skylence (github.com/skylence-be).

## What's in here

The agent-org plugins bundle the **Solo MCP server** (board / PTY / timer
substrate) that the orchestration roles depend on. An orchestrator dispatches;
planner, solo-worker, replacer, and org-audit fill the roles. capacity-check
and build-slot provide machine-level guardrails.

The core plugins install each agent's baseline: judge-hook (rules engine),
writing-guard, research-nudge, and the shared guidelines.

Everything is self-contained — the Solo MCP server ships with the plugin. No
separate daemon is required.

## Plugins

Each plugin ships in a per-agent variant. Current versions live in each
plugin's manifest, not in this README.

**Grok** (`.grok-plugin/marketplace.json`):

- `core-claude-grok`: Unified baseline for Claude Code + Grok. `/core-claude-grok:setup`
  seeds rules/guidelines (AGENTS.md on Grok), stamps version, sets compat flag on Grok.
  Includes dual judge-hook, writing-guard, research-nudge + core-hud.
  `/core-claude-grok:doctor` audits.
- `soloterm-agent-org-claude-grok`: Unified agent-org stack for Claude + Grok.
  Skills + Solo MCP + dual discipline hooks.

**Claude Code** (`.claude-plugin/marketplace.json`):

- `core-claude-grok`: unified baseline (Claude + Grok). `/core-claude-grok:setup`
  installs the judge-hook, writing-guard, core-hud statusline, and guidelines.
- `soloterm-agent-org-claude-grok`: the agent-org stack. Orchestrator, planner,
  solo-worker, replacer, org-audit, capacity-check + Solo MCP, build-slot,
  capacity-probe, and session-discipline hooks.

**Codex and Antigravity** (`.agents/plugins/marketplace.json`):

- `core-codex`, `core-antigravity`: the core baseline for each CLI.
- `soloterm-agent-org-codex`, `soloterm-agent-org-antigravity`: the agent-org
  stack for each CLI, kept in doctrinal sync with the other variants.

## Install

**Grok:**

```
grok plugin marketplace add skylence-be/multi-llm-marketplace
grok plugin marketplace update multi-llm-marketplace
grok plugin install soloterm-agent-org-claude-grok@skylence-be/multi-llm-marketplace --trust
grok plugin install core-claude-grok@skylence-be/multi-llm-marketplace --trust
```

Then run `/core-claude-grok:setup` and use the org roles.

**Note:** After adding, run `grok plugin marketplace update multi-llm-marketplace`.
For install commands, use the full qualifier: `...@skylence-be/multi-llm-marketplace` (the short name may not resolve for installs).

**Claude Code:**

```
/plugin marketplace add skylence-be/multi-llm-marketplace
/plugin install soloterm-agent-org-claude-grok@multi-llm-marketplace
/plugin install core-claude-grok@multi-llm-marketplace
```

**Codex / Antigravity:** add this repo as a plugin source for the agent, then
install the matching `-codex` or `-antigravity` variant. The offerings for those
CLIs are declared in `.agents/plugins/marketplace.json`.

## Keeping variants in sync

All agent-org variants (grok, claude, codex, antigravity) share one body of doctrine
in the skills/. A change to conduct or the shared playbooks lands across the
trees on the next release of each variant.

## Verification

**Grok:**

```bash
grok plugin list
grok plugin details core-claude-grok
grok plugin details soloterm-agent-org-claude-grok
grok inspect | grep -E '(core-claude-grok|soloterm-agent-org-claude-grok|solo)'
/core-claude-grok:setup
/core-claude-grok:doctor
```

**Local dev (any agent):**

```bash
grok plugin marketplace add /path/to/this/repo
```

The marketplace will be usable via the GitHub shorthand (`skylence-be/multi-llm-marketplace`) once published.

See the individual `plugins/*/README.md` files for plugin-specific details.
