# soloterm-agent-org

The Skylence agent-org v2 doctrine, packaged as a distributable Claude Code
plugin. This is a **packaging, not a migration**: the live user-scope files on
the origin machine (`~/.claude/hooks`, `~/.claude/skills`, `~/.codex/*`,
`~/.local/bin/build-slot`) stay authoritative and untouched; this plugin is
the portable copy that serves the agent org anywhere.

**Design doc:** the org redesign gist (architecture, diagrams, ghost-probe
field validation, promote ritual, risks):
<https://gist.github.com/jonasvanderhaegen/4f6251458e529d290db93ee7afada592>

## What activates automatically (Claude Code side)

- **skills/** — the four role playbooks, invocable as
  `soloterm-agent-org:<skill>`:
  - `orchestrator` — event-driven conductor for Solo-based worker agents:
    dispatch via todo-body briefs, wake-on-idle follow-up, verification and
    merge discipline, board state.
  - `solo-worker` — worker conduct when dispatched by an orchestrator.
  - `replacer` — successor pickup of a predecessor's lane from durable state
    (todo trail, committed WIP) after context exhaustion, a kill, or a stall.
  - `org-audit` — on-demand cold review of the running org; operator-invoked
    only, never scheduled.
- **hooks/** (`hooks.json`):
  - `org-lane-mark.sh` — PreToolUse on
    `mcp__solo__spawn_agent|spawn_process|timer_set|timer_fire_when_idle_*`;
    marks the session (a `/tmp/claude-org-lanes-<session_id>` flag file) as
    having dispatched Solo workers.
  - `org-stop-gate.sh` — Stop hook; in marked sessions, blocks the FIRST stop
    with the anti-idle checklist (read idle/finished workers and give verdicts,
    arm one-shot wakes for still-running workers, put blocking questions on the
    QUESTIONS pad). `stop_hook_active` passes the second stop, so it costs one
    extra turn, never a loop. Inert in sessions that never spawn workers.
  - `org-conduct-refresh.sh` — SessionStart hook (matcher `compact`); in org
    sessions (Solo-managed process or a lane-marked session), re-injects the
    order to re-invoke the role skill and re-anchor from the board after every
    compaction. Summaries keep facts, not conduct — long-session decay is
    self-invisible, so the refresh is hook-driven, never self-assessed.

## Manual installs (documented, not auto-wired)

- **scripts/build-slot** — machine-wide compile serializer (one build at a
  time; mkdir-style lock at `/tmp/skylence-build.lock`, stale-PID takeover,
  hard nextest refusal). Install: `cp scripts/build-slot ~/.local/bin/ &&
  chmod +x ~/.local/bin/build-slot`. Law: exactly ONE lock layer per
  invocation — `build-slot <cmd>` OR a caller-held lock on the same path,
  never both (self-deadlock).
- **scripts/ghost-probe.sh** — the no-fusion law's input-line classifier.
  Before ANY `send_input` to a PTY, classify its input line; ghost suggestion
  text renders exactly like operator typing in a rendered tail. Run
  `ghost-probe.sh --help` for the three subcommands (`zero-touch` on
  rendered+raw tails, `probe` on before/after tails around a single probe
  space, `live` on two tails moments apart). Exit 0 = safe to send,
  1 = DO NOT SEND, 2 = ambiguous. Probe once, never in a loop; restore with
  backspace (bytes `[127]`) after every probe space.
- **codex/** — the Codex CLI side of the org:
  - `AGENTS.md` — worker conduct for Codex full-auto lane workers; install to
    `~/.codex/AGENTS.md`.
  - `rules/org.rules` — execpolicy entries for the nextest ban and the
    build-slot law; append to `~/.codex/rules/default.rules` (adjust the
    absolute cargo-bin paths for the target machine).
  - `skills/solo-worker/` — the Codex variant of the worker playbook; install
    to `~/.codex/skills/solo-worker/`.

## Origin

Standing oversight roles (supervisor, questioner, outside-auditor, observer,
reporter, builder, groundskeeper) were retired in the 2026-06-10 redesign;
nothing in this plugin runs on a cadence. Dispatch is event-driven, every
delegated worker is a Solo PTY process its dispatcher can read and steer, and
board trails (todo comments, pads with named readers) are the record.
