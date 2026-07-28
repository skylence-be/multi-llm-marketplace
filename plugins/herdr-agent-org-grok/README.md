# herdr-agent-org-grok

Grok port of Skylence agent-org, running on **[Herdr](https://herdr.dev)** instead of Solo.

Herdr is the agent multiplexer: real terminal panes, semantic agent state
(`working` / `blocked` / `done` / `idle`), CLI + socket control so agents can
orchestrate each other. This plugin maps the Skylence conductor/worker doctrine
onto those primitives and a **filesystem board** (no Solo MCP).

## Prerequisites

1. **Herdr** installed and running (`curl -fsSL https://herdr.dev/install.sh | sh`
   or `brew install herdr`). Target **>= 0.7** for agent start/wait/prompt.
2. Orchestrator and workers must run **inside Herdr panes** (`HERDR_ENV=1`).
3. Optional integrations for richer state: `herdr integration install claude`
   (and codex/opencode/etc. as needed). Grok is a supported `agent start --kind`.
4. Recommended: the **org-waker** herdr plugin (`herdr plugin install skylence-be/multi-llm-marketplace/herdr-plugins/org-waker`): the event-driven wake mechanism L6 builds on; without it the org runs on fallback waits alone.

## What it provides

- **Skills** (roles):
  - `orchestrator` — conductor; dispatches via Herdr panes + board
  - `herdr-worker` — worker conduct for dispatched agents
  - `replacer` — successor pickup after stall/compaction kill
  - `org-audit` — on-demand cold review (never on a cadence)
  - `herdr` — control surface skill (pane/agent/workspace CLI)
- **Scripts**:
  - `board` — filesystem board (todos, comments, pads, blockers); `set-status` best-effort publishes lane status into the herdr sidebar pane (`pane report-metadata`), `ready` lists unblocked pending todos, `create --tags`/`list --tags` tag and filter todos, `query <text>` case-insensitively searches todo files, `list`/`ready`/`get` support `--json`, and every mutating command snapshots a best-effort silent git commit when git is available
  - `dispatch-worker` — split pane + `agent start` + pointer prompt (auto layout: below the orchestrator, then rightward, rows of at most 3; explicit `--direction` overrides)
  - `build-slot` — machine-wide compile serializer
  - `ghost-probe.sh` — no-fusion input-line classifier (same recipe as Solo variant)
  - `waker-ctl` — org-side client of the org-waker herdr plugin (register/unregister/list/drain/doctor)
- **Hooks** (Grok lifecycle):
  - org-lane-mark (PreToolUse when shell runs `herdr agent start` / `dispatch-worker`)
  - org-conduct-prime / org-conduct-refresh (SessionStart `startup|resume` primes the role-skill contract; `compact` re-injects it)
  - org-stop-gate (Stop anti-idle for marked sessions)
- **AGENTS.md** worker guidance for sessions under this org

## Install

```bash
grok plugin marketplace add skylence-be/multi-llm-marketplace
grok plugin marketplace update multi-llm-marketplace
grok plugin install herdr-agent-org-grok@skylence-be/multi-llm-marketplace --trust
```

Then bootstrap IN THE PANE SHELL, BEFORE starting the agent (exports made inside a session do not persist across its shell calls; the agent process inherits the pane shell's env and `dispatch-worker` forwards it via `--env`):

```bash
# inside Herdr, in a pane:
export HERDR_ORG_ROOT="$HOME/.herdr-org/my-feature"
export PATH="<plugin-root>/scripts:$PATH"   # board, dispatch-worker, waker-ctl
board init my-feature
grok   # or your preferred agent CLI as orchestrator
```

## Solo vs Herdr substrate

| Concern | soloterm-agent-org-grok | herdr-agent-org-grok |
| --- | --- | --- |
| Board / todos | Solo MCP todos/pads | Filesystem board (`scripts/board`) |
| Worker PTYs | Solo spawn_process | `herdr pane split` + `agent start` |
| Read / steer | get_process_output / send_input | `herdr agent read` / `agent prompt` |
| Idle wake | Solo timer_fire_when_idle | org-waker ring (event-driven prompt); fallback `herdr agent wait` |
| Agent state | Process status | Herdr semantic states + sidebar |
| MCP required | Solo stdio MCP | None (CLI only) |
| Run location | Any terminal Solo manages | **Must** be `HERDR_ENV=1` |

Doctrine (LAWS, compile monopoly, no-fusion, verify-before-accept, MCP-first
lane trees) is shared with the Solo siblings; only the control plane changes.

## Typical flow

1. Operator: "you're the conductor" → invoke `orchestrator` skill.
2. Orchestrator inits/reads board and plans the program itself (L3: no planner agent exists in this org).
3. Dispatch: `dispatch-worker` (or manual split + `agent start --kind grok\|claude\|codex`) with a pointer to a board todo.
4. Worker runs `herdr-worker` skill; reports milestones via `board comment`.
5. The org-waker rings the orchestrator on lane settle/block/death (fallback `agent wait`); it verifies claims, merges; workers never compile.

See each skill for playbooks.

## Notes

- Hook commands use exact `${GROK_PLUGIN_ROOT}/hooks/...` load-time substitution
  (nested `${VAR:-default}` expands empty and leaves hooks inert — same Grok gotcha as core-grok).
- Hook markers: `/tmp/grok-herdr-org-lanes-<sessionId>`.
- Prefer `HERDR_BIN_PATH` when set (Herdr injects it inside managed panes).
- Pair with `core-grok` for baseline guidelines/judge-hook, and `skyline-grok`
  for hash-guarded edits.

## Research snapshot (Herdr, 2026)

Herdr ([ogulcancelik/herdr](https://github.com/ogulcancelik/herdr), ~19k★, Apache-2.0)
is a Rust terminal multiplexer purpose-built for coding agents: real PTYs, detach/reattach
(including over SSH and phone), agent-aware sidebar, CLI/socket API, and a plugin system
(`herdr-plugin.toml`). Supported agent kinds include `claude`, `codex`, `grok`, `opencode`,
`hermes`, and more. Official docs: [herdr.dev/docs](https://herdr.dev/docs/).
