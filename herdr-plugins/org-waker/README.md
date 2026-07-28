# org-waker (herdr plugin)

Event-driven wake-up for the [herdr](https://herdr.dev) agent-org plugins in this repo. It closes the gap issue #37 recorded: Solo's `timer_fire_when_idle_*` had no Herdr equivalent, so a lane that settled after the orchestrator's turn ended changed board state nobody was watching. This plugin subscribes to Herdr's pane events and turns a registered lane's settle, block, or death into ONE `herdr agent prompt` at the registered orchestrator agent. A prompt STARTS an orchestrator turn, which is the thing an armed `herdr agent wait` structurally cannot do after your turn has ended (see `#36`'s "what this does not fix").

Not a Claude Code plugin: this is a **herdr** plugin, installed with herdr's own plugin manager. It is runtime-agnostic; the claude and grok org plugins both drive it through the same files.

## Install

```bash
herdr plugin install skylence-be/multi-llm-marketplace/herdr-plugins/org-waker
# or, for local development against this checkout:
herdr plugin link /abs/path/to/multi-llm-marketplace/herdr-plugins/org-waker
```

Requires herdr >= 0.7.4 and `jq` on PATH. Verify with:

```bash
herdr plugin action invoke doctor --plugin skylence.org-waker
```

## How it works

- The manifest subscribes `pane.agent_status_changed`, `pane.exited`, and `pane.closed` (dot-form in the manifest; the JSON payload uses underscore-form event names and flat `.data.pane_id` / `.data.agent_status` fields).
- An event for a pane that is not in the registry exits with **zero herdr calls**, so the operator's unrelated panes never cost anything.
- Ring predicate: `blocked` rings on a blocked-edge; `idle`/`done` ring only on a working→terminal edge. Repeated re-emissions stay silent, so there is no stale-fire class for the orchestrator to dismiss (the Solo defect issue #20 records).
- Death coverage: `pane.exited`/`pane.closed` on a *registered* lane ring as crash-class, and so does a status event whose `agent` label went empty while registered (the agent process died before settling). Unregister a lane BEFORE reaping it at close-out and the expected death stays silent; a still-registered death is by definition a crash.
- Send safety (org law L11): before any prompt, two visible-frame tails of the target are compared ghost-probe-style. A changing or non-empty input line HOLDS the wake as a pending file and raises a toast instead of stomping operator text. On pure Herdr a suggestion ghost is indistinguishable from typed text, so a ghost false-positives into a hold; the drain path recovers it.
- Delivery: target `working` → plain `agent prompt` (Claude Code queues a mid-turn prompt cleanly; `--wait` would misread the still-running turn as failure). Target `idle`/`done` → `agent prompt --wait --timeout 8000` as verify-after-send. Target `blocked`/`unknown` → hold.
- Held wakes drain through a claim-by-rename queue (stale claims sweep back after 300s; delivery stops at the first failure so nothing lands out of order). Drain runs as a manifest action, opportunistically after handled events (2s debounce marker), and a `[[startup]]` sweep toasts if held wakes survived a restart.

## Wake line format

```
[WAKE g<gen>] lane <lane> -> <status>. board get <todo>
[WAKE g<gen>] lane <lane> PANE exited (exit 1) while registered. Crash-class: board get <todo>, consider a replacer.
[WAKE g<gen>] lane <lane>: agent process GONE (last status working). Crash-class: board get <todo>, consider a replacer.
```

The payload is a pointer, not content: the board comment trail remains the contract; the ring only makes it timely. `g<gen>` is the registration generation; a re-dispatched lane bumps it, and pending wakes from an older generation are dropped at drain instead of costing a turn.

## The registry contract

Everything lives under the plugin config dir, the one root both the handler environment (`HERDR_PLUGIN_CONFIG_DIR`) and a plain shell (`herdr plugin config-dir skylence.org-waker`) resolve identically:

```
registry.tsv          pane_id  lane  todo  target  gen  org_root  registered_at
state/                per-pane last status, dead markers, drain debounce
pending/              held wake lines, <epoch-ms>-<lane>-g<gen>.msg
spool/<lane>.jsonl    append-only event records (orchestrator catch-up surface)
log/rings.jsonl       delivery audit
```

`registry.tsv` is the interface: the org plugins' `dispatch-worker`/`waker-ctl` write rows through the same upsert semantics as `waker register` (re-registering a lane bumps `gen` and clears its per-pane state). Registration and steering:

```bash
waker register --pane <pane_id> --lane <name> --target <orchestrator-agent> [--todo <slug>] [--org-root <path>]
waker unregister --lane <name>     # BEFORE reaping the agent at close-out
waker list
waker drain                        # also exposed as the drain action
```

## Prior art

Built on patterns from [joelhooks/herdr-pings](https://github.com/joelhooks/herdr-pings) (MIT: the spool contract, the agent-label early-crash watchdog, pane-death lifecycle bridging) and [caioniehues/herdmates](https://github.com/caioniehues/herdmates) (MIT: the edge-filter ring predicate, unknown-pane silence, claim-by-rename delivery with stale-claim sweep, marker-file debounce). What neither ships, and this plugin adds, is a subscriber that rings an **agent** instead of a human.

## Limitations

- A held wake needs a later event, the startup sweep, or a manual drain to retry; an org with zero further events keeps it parked (the toast tells the operator). The orchestrator doctrine keeps a fallback `herdr agent wait` for exactly this window.
- The orchestrator must still exist and be reachable as an agent; a dead orchestrator needs the operator (same boundary as #36's doorbell).
- One herdr session: events reach the server that owns the pane, and the registry does not model peer sessions.
