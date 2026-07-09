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

- `core-grok`: Grok baseline. `/core-grok:setup` seeds `~/.grok/judge-rules.json`,
  writes the guidelines into `~/.grok/AGENTS.md`, and stamps the version.
  Includes native PreToolUse judge-hook, writing-guard, research-nudge.
  `/core-grok:doctor` audits the install (rules, guidelines, version, hooks).
  Uses Grok hook contract + `grok -p` escalation.
- `soloterm-agent-org-grok`: Full agent-org stack. Orchestrator, planner,
  solo-worker, replacer, org-audit + capacity-check. Bundles Solo MCP,
  build-slot, ghost-probe, and Grok-adapted discipline hooks.

**Claude Code** (`.claude-plugin/marketplace.json`):

- `core-claude`: opinionated Claude Code baseline. `/core-claude:setup` installs
  the judge-hook rules engine, the writing-guard, the core-hud statusline, and
  the CLAUDE.md guidelines.
- `soloterm-agent-org`: the agent-org stack. Orchestrator, planner, solo-worker,
  replacer, org-audit, and capacity-check skills, plus the Solo MCP server,
  the build-slot compile serializer, the capacity-probe RAM gate, and the
  session-discipline hooks.

**Codex and Antigravity** (`.agents/plugins/marketplace.json`):

- `core-codex`, `core-antigravity`: the core baseline for each CLI.
- `soloterm-agent-org-codex`, `soloterm-agent-org-antigravity`: the agent-org
  stack for each CLI, kept in doctrinal sync with the other variants.

## Install

**Grok:**

```
grok plugin marketplace add skylence-be/multi-llm-marketplace
grok plugin marketplace update multi-llm-marketplace
grok plugin install soloterm-agent-org-grok@skylence-be/multi-llm-marketplace --trust
grok plugin install core-grok@skylence-be/multi-llm-marketplace --trust
```

Then run `/core-grok:setup` and use the org roles (orchestrator, planner, etc.).

**Note:** After adding, run `grok plugin marketplace update multi-llm-marketplace`.
For install commands, use the full qualifier: `...@skylence-be/multi-llm-marketplace` (the short name may not resolve for installs).

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

All agent-org variants (grok, claude, codex, antigravity) share one body of doctrine
in the skills/. A change to conduct or the shared playbooks lands across the
trees on the next release of each variant.

## Verification

**Grok:**

```bash
grok plugin list
grok plugin details core-grok
grok plugin details soloterm-agent-org-grok
grok inspect | grep -E '(core-grok|soloterm-agent-org-grok|solo)'
/core-grok:setup
/core-grok:doctor
```

**Local dev (any agent):**

```bash
grok plugin marketplace add /path/to/this/repo
```

The marketplace will be usable via the GitHub shorthand (`skylence-be/multi-llm-marketplace`) once published.

See the individual `plugins/*/README.md` files for plugin-specific details.
