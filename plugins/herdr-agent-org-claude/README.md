# herdr-agent-org-claude

Claude Code port of the Skylence agent-org, running on **[Herdr](https://herdr.dev)** instead of Solo.

Herdr is the agent multiplexer: real terminal panes, semantic agent state (`working` / `blocked` / `done` / `idle`), and CLI plus socket control so agents can orchestrate each other. This plugin maps the Skylence conductor-and-workers doctrine onto those primitives plus a **filesystem board**, so no Solo MCP server is involved.

## Prerequisites

1. **Herdr** installed and running (`brew install herdr`, or `curl -fsSL https://herdr.dev/install.sh | sh`). Target **>= 0.7** for `agent start` / `wait` / `prompt`.
2. Orchestrator and workers must run **inside Herdr panes** (`HERDR_ENV=1`).
3. `jq` on PATH (the hooks and `dispatch-worker` parse Herdr's JSON).
4. Optional: `herdr integration install claude`. See the caveat below before assuming it does more than it does.
5. Recommended: the **org-waker** herdr plugin (`herdr plugin install skylence-be/multi-llm-marketplace/herdr-plugins/org-waker`). It is the event-driven wake mechanism L6 builds on; without it the org runs on fallback waits alone.

## What it provides

- **Skills** (roles):
  - `orchestrator` conducts: dispatches via Herdr panes plus the board, verifies, merges, owns the single gate build
  - `herdr-worker` is worker conduct for dispatched agents
  - `replacer` is successor pickup after a stall, kill, or compaction
  - `org-audit` is an on-demand cold review, never scheduled
  - `herdr` is the low-level control surface (pane, agent, workspace CLI)
- **Scripts**:
  - `board` is the filesystem board (todos, comments, pads, blockers); `set-status` best-effort publishes the lane's status into the herdr sidebar pane (`pane report-metadata`), `ready` lists unblocked pending todos, `create --tags`/`list --tags` tag and filter todos, `query <text>` case-insensitively searches todo files, `list`/`ready`/`get` support `--json`, and every mutating command snapshots a best-effort silent git commit when git is available
  - `dispatch-worker` splits a pane, starts a named agent, sends the pointer prompt, and reports the post-send state
  - `build-slot` is the machine-wide compile serializer
  - `ghost-probe.sh` is the no-fusion input-line classifier
  - `waker-ctl` is the org-side client of the org-waker herdr plugin (register, unregister, list, drain, doctor)
- **Hooks** (`hooks/hooks.json`, wired on install):
  - `org-lane-mark.sh` (PreToolUse on Bash and skyline_run) records one line per org event, `dispatch` or `wait`
  - `org-stop-gate.sh` (Stop) blocks a marked session's FIRST stop with the anti-idle sweep
  - `org-conduct-refresh.sh` (SessionStart, matchers `startup|resume|compact`) primes the role-skill contract in fresh sessions and re-injects the re-read order after compaction
- **templates/claude-md.md**: worker guidance to paste into `~/.claude/CLAUDE.md` on a machine that runs lane workers.

## Install

```
/plugin marketplace add skylence-be/multi-llm-marketplace
/plugin install herdr-agent-org-claude@multi-llm-marketplace
```

Then bootstrap IN THE PANE SHELL, BEFORE starting claude. Exports made inside a Claude session do not persist across its shell calls; the claude process inherits the pane shell's env and `dispatch-worker` forwards it to workers via `--env`:

```bash
# inside Herdr, in a pane:
export HERDR_ORG_ROOT="$HOME/.herdr-org/my-feature"
export PATH="<plugin-root>/scripts:$PATH"   # board, dispatch-worker, waker-ctl
board init my-feature
claude
```

(Print the two export lines once from any session with the plugin: `printf 'export HERDR_ORG_ROOT="%s"\nexport PATH="%s/scripts:$PATH"\n' "$HOME/.herdr-org/my-feature" "$CLAUDE_PLUGIN_ROOT"`.)

Split panes do NOT inherit the requester's environment: they get the herdr server's env (measured on herdr 0.7.5, 2026-07-28). `dispatch-worker` therefore passes `--env HERDR_ORG_ROOT=...` and `--env PATH=...` on the split itself; a hand-rolled `pane split` must do the same or the worker resolves neither the board nor the org scripts.

## Two Claude-specific facts that shape the doctrine

**Pane reads are frames; the board is what survives.** `--source visible` (or `--source detection`) shows the current frame. `recent` and `recent-unwrapped` reach back through the pane's host scrollback, and on the Claude Code build measured here that scrollback does carry committed transcript, so a bigger `--lines` really does recover past turns. Two limits still bind: a worker mid-turn has scrolled nothing yet, so `recent` equals `visible` until it commits output; and scrollback dies with the pane, so reaping an agent (L4) takes its history with it. Hence the board comment trail is the record, and every brief orders milestone comments at phase boundaries rather than one summary at the end. Note that Herdr's docs state alternate-screen rows never enter host scrollback and count Claude Code as a full-screen agent. That is not what this build did (measured 2026-07-23 on herdr 0.7.5, two independent panes), so re-check with `herdr pane read <pane> --source recent --lines 300` before trusting either statement.

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
| Idle wake | `timer_fire_when_idle` | org-waker ring (event-driven prompt); fallback `herdr agent wait` |
| Agent state | Process status | Herdr semantic states plus sidebar |
| MCP required | Solo stdio MCP | None, CLI only |
| Run location | Any terminal Solo manages | **Must** be `HERDR_ENV=1` |
| Peer discovery | `list_projects` | `herdr session list` plus per-session agent list |

Doctrine (LAWS, compile monopoly, no-fusion, verify-before-accept, MCP-first lane trees) is shared with the Solo siblings; only the control plane changes.

## Typical flow

1. Operator: "you're the conductor", which invokes the `orchestrator` skill.
2. Orchestrator initializes or reads the board and plans the program itself (L3: no planner agent exists in this org).
3. Dispatch: `dispatch-worker --name <lane> --kind claude --todo <slug> --cwd <lane-tree> -- --permission-mode bypassPermissions`.
4. The worker invokes `herdr-worker` and reports milestones via `board comment`.
5. The orchestrator arms `herdr agent wait`, verifies claims by re-running them, gates the build once, and merges. Workers never compile.

## Notes

- Hook markers live at `/tmp/claude-herdr-org-lanes-<session_id>`, so they do not collide with the Solo sibling's `/tmp/claude-org-lanes-<session_id>`.
- The stop gate carries both fixes the Solo sibling landed 2026-07-21: the premise follows recorded evidence (a session that only armed waits is not told it dispatched workers), and an answered sweep settles until org state actually moves.
- `ghost-probe.sh` on a pure Herdr box: use `live` then `probe`. `zero-touch` needs a source that strips a suggestion ghost's styling to an empty prompt line, which Solo provided and Herdr does not.
- Prefer `${HERDR_BIN_PATH:-herdr}`; Herdr injects that variable inside managed panes.
- Pair with `core-claude` for the baseline guidelines and judge-hook, and with `skyline-claude` for hash-guarded edits.
