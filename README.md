# Multi-LLM Marketplace

Skylence's marketplace of multi-agent orchestration and agent-baseline plugins,
packaged for Grok, Claude Code, Codex, and Antigravity.

The agent-org plugins turn a single agent CLI into a conductor-and-workers
organisation. The core plugins install each agent's opinionated baseline
(hooks, guidelines, and session discipline).

Owner: Skylence (github.com/skylence-be).

## What's in here

Two agent-org substrates ship here:

- **Solo** (`soloterm-agent-org-*`): board / PTY / timer via Solo MCP. An
  orchestrator dispatches; planner, solo-worker, replacer, and org-audit fill
  the roles. build-slot provides the machine-wide compile gate.
- **Herdr** (`herdr-agent-org-*`): same doctrine on the
  [Herdr](https://herdr.dev) agent multiplexer, meaning real panes, semantic
  agent state, and CLI control. Filesystem board instead of Solo todos; no Solo
  MCP required. Requires agents to run with `HERDR_ENV=1`.

The core plugins install each agent's baseline: judge-hook (rules engine),
writing-guard, research-nudge, and the shared guidelines.

## Plugins

Each plugin ships in a per-agent variant. Current versions live in each
plugin's manifest, not in this README.

**Grok** (`.grok-plugin/marketplace.json`):

- `core-grok`: Grok baseline. `/core-grok:setup` seeds `~/.grok/judge-rules.json`,
  writes the guidelines into `~/.grok/AGENTS.md`, and stamps the version.
  Includes native PreToolUse judge-hook, writing-guard, research-nudge.
  `/core-grok:doctor` audits the install (rules, guidelines, version, hooks).
  Uses Grok hook contract + `grok -p` escalation.
- `soloterm-agent-org-grok`: Full agent-org stack on Solo. Orchestrator, planner,
  solo-worker, replacer, org-audit. Bundles Solo MCP, build-slot, ghost-probe,
  and Grok-adapted discipline hooks.
- `herdr-agent-org-grok`: Full agent-org stack on Herdr. Orchestrator, planner,
  herdr-worker, replacer, org-audit + herdr skill; filesystem board CLI;
  dispatch-worker; build-slot; ghost-probe; Grok discipline hooks.

**Claude Code** (`.claude-plugin/marketplace.json`):

- `core-claude`: opinionated Claude Code baseline. `/core-claude:setup` installs
  the judge-hook rules engine, the writing-guard, the core-hud statusline, and
  the CLAUDE.md guidelines.
- `soloterm-agent-org`: the agent-org stack. Orchestrator, planner, solo-worker,
  replacer, and org-audit skills, plus the Solo MCP server, the build-slot
  compile serializer, the ghost-probe no-fusion classifier, and the four
  session-discipline hooks.
- `herdr-agent-org-claude`: the same agent-org stack on the Herdr multiplexer.
  Orchestrator, planner, herdr-worker, replacer, org-audit, and a herdr control
  skill, plus the filesystem board CLI, dispatch-worker, build-slot,
  ghost-probe, and four session-discipline hooks. No Solo MCP; requires
  `HERDR_ENV=1`.

**Codex and Antigravity** (`.agents/plugins/marketplace.json`):

- `core-codex`, `core-antigravity`: the core baseline for each CLI.
- `soloterm-agent-org-codex`, `soloterm-agent-org-antigravity`: the agent-org
  stack for each CLI, kept in doctrinal sync with the other variants.

## Install

**Grok:**

```
grok plugin marketplace add skylence-be/multi-llm-marketplace
grok plugin marketplace update multi-llm-marketplace
grok plugin install core-grok@skylence-be/multi-llm-marketplace --trust
# Solo substrate (board/PTY via Solo MCP):
grok plugin install soloterm-agent-org-grok@skylence-be/multi-llm-marketplace --trust
# OR Herdr substrate (real panes; requires herdr + HERDR_ENV=1):
grok plugin install herdr-agent-org-grok@skylence-be/multi-llm-marketplace --trust
```

Then run `/core-grok:setup` and use the org roles (orchestrator, planner, etc.).
For Herdr: install Herdr (`brew install herdr` or https://herdr.dev), run agents inside `herdr` panes, and `board init <feature>` once.

For full skyline MCP tools (skyline_read, skyline_edit with ¶path#TAG hash guards, skyline_grep, skyline_run, etc.) and the PreToolUse enforce hook that redirects native tools to skyline equivalents when the daemon is running:

```
grok plugin marketplace add skylence-be/skylence-plugins
grok plugin marketplace update skylence-plugins
grok plugin install skyline-grok@skylence-be/skylence-plugins --trust
```

The enforce hook (in skyline-grok) will be active for Grok sessions as long as the skyline daemon is up (fails open otherwise). See the skyline-grok README for details.

**Note:** After adding, run `grok plugin marketplace update multi-llm-marketplace`.
For install commands, use the full qualifier: `...@skylence-be/multi-llm-marketplace` (the short name may not resolve for installs).

**Claude Code:**

```
/plugin marketplace add skylence-be/multi-llm-marketplace
/plugin install core-claude@multi-llm-marketplace
# Solo substrate (board/PTY via Solo MCP):
/plugin install soloterm-agent-org@multi-llm-marketplace
# OR Herdr substrate (real panes; requires herdr + HERDR_ENV=1):
/plugin install herdr-agent-org-claude@multi-llm-marketplace
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
grok plugin details herdr-agent-org-grok
grok inspect | grep -E '(core-grok|soloterm-agent-org-grok|herdr-agent-org-grok|solo|herdr)'
/core-grok:setup
/core-grok:doctor
```

**Local dev (any agent):**

```bash
grok plugin marketplace add /path/to/this/repo
```

The marketplace will be usable via the GitHub shorthand (`skylence-be/multi-llm-marketplace`) once published.

See the individual `plugins/*/README.md` files for plugin-specific details.
