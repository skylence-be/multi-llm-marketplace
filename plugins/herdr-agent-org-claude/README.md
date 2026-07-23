# herdr-agent-org-claude

Claude Code port of the Skylence agent-org, running on **[Herdr](https://herdr.dev)** instead of Solo.

Herdr is the agent multiplexer: real terminal panes, semantic agent state (`working` / `blocked` / `done` / `idle`), and CLI plus socket control so agents can orchestrate each other. This plugin maps the Skylence conductor-and-workers doctrine onto those primitives plus a **filesystem board**, so no Solo MCP server is involved.

## Prerequisites

1. **Herdr** installed and running (`brew install herdr`, or `curl -fsSL https://herdr.dev/install.sh | sh`). Target **>= 0.7** for `agent start` / `wait` / `prompt`.
2. Orchestrator and workers must run **inside Herdr panes** (`HERDR_ENV=1`).
3. `jq` on PATH (the hooks and `dispatch-worker` parse Herdr's JSON).
4. Optional: `herdr integration install claude`. See the caveat below before assuming it does more than it does.

## What it provides

- **Skills** (roles):
  - `orchestrator` conducts: dispatches via Herdr panes plus the board, verifies, merges, owns the single gate build
  - `planner` is the machine-wide program planner singleton
  - `herdr-worker` is worker conduct for dispatched agents
  - `replacer` is successor pickup after a stall, kill, or compaction
  - `org-audit` is an on-demand cold review, never scheduled
  - `herdr` is the low-level control surface (pane, agent, workspace CLI)
- **Scripts**:
  - `board` is the filesystem board (todos, comments, pads, blockers)
  - `dispatch-worker` splits a pane, starts a named agent, sends the pointer prompt, and reports the post-send state
  - `build-slot` is the machine-wide compile serializer
  - `ghost-probe.sh` is the no-fusion input-line classifier
- **Hooks** (`hooks/hooks.json`, wired on install):
  - `org-lane-mark.sh` (PreToolUse on Bash and skyline_run) records one line per org event, `dispatch` or `wait`
  - `org-stop-gate.sh` (Stop) blocks a marked session's FIRST stop with the anti-idle sweep
  - `org-conduct-refresh.sh` (SessionStart, matcher `compact`) re-injects the re-read-your-role-skill order
  - `planner-singleton-gate.sh` (PreToolUse) denies a planner-named `agent start` until the machine-wide sweep has run
- **templates/claude-md.md**: worker guidance to paste into `~/.claude/CLAUDE.md` on a machine that runs lane workers.

## Install

```
/plugin marketplace add skylence-be/multi-llm-marketplace
/plugin install herdr-agent-org-claude@multi-llm-marketplace
```

Then, inside Herdr:

```bash
herdr
# in a pane:
claude
```

Initialize a board once per org:

```bash
export HERDR_ORG_ROOT="$HOME/.herdr-org/my-feature"
"${CLAUDE_PLUGIN_ROOT}/scripts/board" init my-feature
export PATH="${CLAUDE_PLUGIN_ROOT}/scripts:$PATH"
```

Worker panes inherit `HERDR_ORG_ROOT` and `PATH` from the split, so a lane dispatched with `dispatch-worker` resolves the same board.

## Two Claude-specific facts that shape the doctrine

**Pane reads are snapshots, not transcripts.** Claude Code renders its TUI in the terminal's alternate screen, and alternate-screen rows never enter Herdr's host scrollback. `herdr agent read --source visible` (or `--source detection`) shows the current frame; `recent` and `recent-unwrapped` are thin or empty, and a larger `--lines` cannot recover history that was never in scrollback. Every role in this plugin therefore treats the board comment trail as the record and orders milestone comments at phase boundaries rather than one summary at the end.

**Claude Code is not authoritative for its own state.** `herdr integration install claude` installs a session-identity hook so Herdr can restore the pane after a server restart. It does not install lifecycle hooks, so state still comes from Herdr's screen-manifest detection, and `blocked` is reported only when a known approval or permission UI is on screen. `herdr agent wait` is a good-enough settle signal, not a contract; `herdr agent explain <target>` diagnoses a state that looks wrong.

A third practical point: a Claude worker started with no arguments stops at its first permission prompt and parks in `blocked`. Dispatch full-auto lane workers explicitly.

```bash
dispatch-worker --name impl-a --todo impl-a --cwd /abs/lane-tree \
  -- --permission-mode bypassPermissions
```

`dispatch-worker` fills in the doctrinal default itself (`--model sonnet` for a Claude worker, `--effort medium` for a grok one) when you pass none, so silence at dispatch cannot resolve to whatever the box is installed at. Going above that default requires `--upgrade-reason "<why>"`, which the script refuses to skip and files on the lane todo as `[MODEL: ...]` or `[EFFORT: ...]`. A bare `herdr agent start` has no such protection, so pass the setting yourself there. Both rules come from [issue #32](https://github.com/skylence-be/multi-llm-marketplace/issues/32).

## Solo vs Herdr substrate

| Concern | soloterm-agent-org | herdr-agent-org-claude |
| --- | --- | --- |
| Board and todos | Solo MCP todos and pads | Filesystem board (`scripts/board`) |
| Worker PTYs | `spawn_agent` | `herdr pane split` plus `agent start` |
| Read and steer | `get_process_output` / `send_input` | `herdr agent read` / `agent prompt` |
| Idle wake | `timer_fire_when_idle` | `herdr agent wait --until idle|done|blocked` |
| Agent state | Process status | Herdr semantic states plus sidebar |
| MCP required | Solo stdio MCP | None, CLI only |
| Run location | Any terminal Solo manages | **Must** be `HERDR_ENV=1` |
| Peer discovery | `list_projects` | `herdr session list` plus per-session agent list |

Doctrine (LAWS, compile monopoly, no-fusion, verify-before-accept, MCP-first lane trees) is shared with the Solo siblings; only the control plane changes.

## Typical flow

1. Operator: "you're the conductor", which invokes the `orchestrator` skill.
2. Orchestrator initializes or reads the board, and routes planning to the `planner` singleton unless it is running on a model that self-plans.
3. Dispatch: `dispatch-worker --name <lane> --kind claude --todo <slug> --cwd <lane-tree> -- --permission-mode bypassPermissions`.
4. The worker invokes `herdr-worker` and reports milestones via `board comment`.
5. The orchestrator arms `herdr agent wait`, verifies claims by re-running them, gates the build once, and merges. Workers never compile.

## Notes

- Hook markers live at `/tmp/claude-herdr-org-lanes-<session_id>`, so they do not collide with the Solo sibling's `/tmp/claude-org-lanes-<session_id>`.
- The stop gate carries both fixes the Solo sibling landed 2026-07-21: the premise follows recorded evidence (a session that only armed waits is not told it dispatched workers), and an answered sweep settles until org state actually moves.
- `ghost-probe.sh` on a pure Herdr box: use `live` then `probe`. `zero-touch` needs a source that strips a suggestion ghost's styling to an empty prompt line, which Solo provided and Herdr does not.
- Prefer `${HERDR_BIN_PATH:-herdr}`; Herdr injects that variable inside managed panes.
- Pair with `core-claude` for the baseline guidelines and judge-hook, and with `skyline-claude` for hash-guarded edits.
