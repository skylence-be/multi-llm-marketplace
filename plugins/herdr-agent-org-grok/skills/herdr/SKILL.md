---
name: herdr
description: "Control Herdr, a terminal multiplexer for coding agents. Use when HERDR_ENV=1 and you need to inspect or control panes, tabs, workspaces, commands, or another agent. Requires Herdr >= 0.7."
---

# Herdr

Herdr organizes terminals into workspaces, tabs, and panes, recognizes coding agents running inside panes, and exposes the session through the `herdr` CLI (and a JSON socket API).

## Guardrail

```bash
test "${HERDR_ENV:-}" = 1
```

If this fails, say you are not inside a Herdr-managed pane and stop. Prefer `${HERDR_BIN_PATH:-herdr}` for portability.

Do not run bare `herdr` for discovery (it attaches the TUI). Use `herdr --help` and group help (`herdr agent`, `herdr pane`, ...).

## Primitives

| Primitive | Responsibility |
| --- | --- |
| workspace / tab / pane topology | Create and organize terminal locations |
| pane | Raw terminal: run commands, send input, read/wait on output |
| agent | Recognized coding agent: prompt, wait on lifecycle, read |

A pane exists whether or not it contains an agent. `agent start` requires an **available shell pane** (interactive prompt, no foreground agent) and never creates layout — split first.

Agent states: `working`, `blocked`, `done` (idle + unseen), `idle` (seen), `unknown`.

## Discover

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

Public IDs: workspace `w1`, tab `w1:t1`, pane `w1:p1`. Parse IDs from JSON responses; never invent them from sidebar order.

## Start a sibling agent

```bash
# preserve focus + cwd
herdr pane split --current --direction right --cwd "$PWD" --no-focus
# read .result.pane.pane_id from JSON
herdr agent start reviewer --kind codex --pane <pane_id>
herdr agent prompt reviewer "Review the current diff." --wait --timeout 120000
herdr agent read reviewer --source recent-unwrapped --lines 120
```

Supported kinds include `claude`, `codex`, `grok`, `opencode`, `hermes`, `cursor`, and others — run `herdr agent` for the installed list. Args after `--` pass to the agent binary.

Names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents.

## Coordinate

```bash
herdr agent wait reviewer --until done --timeout 300000
herdr agent wait reviewer --until blocked --timeout 120000
herdr agent send-keys reviewer esc
herdr agent get reviewer
```

`agent prompt --wait` waits for settled `idle`/`done`/`blocked` by default. A prompt from a non-working state that never advances lifecycle returns `agent_prompt_stalled` within ~5s.

Ordinary commands (tests, servers):

```bash
herdr pane run <pane_id> "just test"
herdr pane wait-output <pane_id> --regex "passed|failed" --timeout 120000
herdr pane read <pane_id> --source recent-unwrapped --lines 120
```

Read sources: `visible`, `recent`, `recent-unwrapped` (prefer for logs), `detection`.

## Safety

- Use `--no-focus` for background work unless the user asked to switch context.
- Use `--current`, an explicit pane ID, or a unique agent name — never another client's focused pane.
- Do not close workspaces/tabs/panes you did not create unless asked.
- Never `herdr server stop` unless the operator explicitly intends to kill the session.
- Alternate-screen agents may not put history into host scrollback; if larger `--lines` yields nothing new, ask the agent to write a markdown file path as fallback.

## Org usage

In herdr-agent-org, the orchestrator prefers `scripts/dispatch-worker` for lane spawn and `scripts/board` for durable task state. This skill is the low-level control surface underneath those helpers.
