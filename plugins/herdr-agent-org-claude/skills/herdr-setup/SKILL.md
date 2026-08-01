---
name: herdr-setup
description: 'One-shot playbook to bootstrap a fresh macOS box from "herdr installed" to "org-ready": preflight, org-waker wiring, optional ActivityWatch context (aw-context install + category sync), board bootstrap, ecosystem plugin picks, and an end-to-end verification checklist. Invoke when the operator says "set up herdr for the org".'
---

# Herdr org bootstrap (one-shot)

Run S1 through S5 in order, once per box. It takes a machine from "herdr is installed" to "an orchestrator can dispatch workers and get woken on their settle." Every command below is copy-paste-exact.

## S1 Preflight

```bash
herdr --version
```
This skill was authored and measured against **0.7.5**. Anything older is unverified for the `agent start` / `wait` / `prompt` semantics the org depends on; treat a lower version as a stop-and-upgrade, not a "probably fine."

```bash
herdr agent start --help
```
Read the `--kind` possible-values list. It must include both `claude` and `grok`, the two runtimes this org dispatches (`herdr-agent-org-claude` / `herdr-agent-org-grok`). Missing either means that plugin variant has nothing to start against on this box; reinstall or upgrade herdr.

```bash
command -v jq && jq --version
command -v gh && gh --version
```
`jq` is required by `dispatch-worker` (parses Herdr JSON for pane splits, agent status, and the summary payload) and by the org-waker plugin script itself (`herdr-plugins/org-waker/waker`, plus its test suites). `board` and `waker-ctl` do not call jq. `gh` opens and inspects PRs (workers open, never merge; L14). Either missing: install it (`brew install jq gh` on macOS) before continuing; nothing downstream degrades gracefully without them.

## S2 Org-waker wiring

Pick ONE, matching the box:

**Dev box** (this repo is checked out locally and you want plugin fixes to ship without reinstalling):
```bash
herdr plugin link <abs-path-to-repo>/herdr-plugins/org-waker
```
LINKED means the plugin runs the WORKING TREE, not a frozen snapshot. Keep that checkout on `main` and current. A stale link quietly serves stale waker behavior with no error.

**Consumer box** (no local checkout, just want the wake mechanism installed):
```bash
herdr plugin install skylence-be/multi-llm-marketplace/herdr-plugins/org-waker
```

Verify either path landed:
```bash
waker-ctl present
herdr plugin action invoke doctor --plugin skylence.org-waker
```
`waker-ctl present` exits 0 with no output when the plugin's config dir resolves, and exit 1 with no output when it does not (verified 2026-07-29: `HERDR_BIN_PATH` pointed at a failing stub). Other `waker-ctl` subcommands print a stderr message when the plugin is missing; `present` is silent by design. The `doctor` action runs async: it returns a `log_id` immediately with `status: running`. Read the completed result with:
```bash
herdr plugin log list --plugin skylence.org-waker
```
and find that `log_id`'s entry; its `stdout` reports herdr/jq versions, registered lanes, pending wakes, and the last few `rings.jsonl` lines.

Then the correctness gate, ALL suites, from the repo root (dev box with a checkout):
```bash
for t in herdr-plugins/org-waker/test/*.sh; do sh "$t"; done
```
Each suite prints its own `<name>.sh: OK` line at the end when every case passes (six suites as of waker 0.3.0: classify_composer, parked_retry, sent_no_resend, coalesce_hold, drain_sent_preserve, pasted_placeholder). Anything else means stop before dispatching: the wake mechanism's classification, dedup, or retry logic is broken, and lanes will hang silently or ring stale bursts instead of waking the orchestrator cleanly.

**Consumer box (no repo checkout):** you cannot run those suites from a path that does not exist. Either clone `skylence-be/multi-llm-marketplace` long enough to run them from its root, or treat the doctor action above plus the S5 live probe as your gate. Do not invent a substitute shell check.

## S2.5 ActivityWatch context (aw-context) — optional

Gives every agent on the box read access to the operator's real desktop
activity (current window, presence, afk-filtered per-app time) plus
category-tree/settings management, via the `skylence.aw-context` herdr plugin.
Skip cleanly when ActivityWatch is not part of this box's workflow; nothing
later depends on it.

Preflight — an aw-server must already answer or everything below is a no-op:
```bash
curl -sf --max-time 3 http://127.0.0.1:5600/api/0/info
```
No answer: install and start ActivityWatch (aw-server + aw-watcher-window +
aw-watcher-afk) first, or skip this section.

Same dev/consumer split as S2, same stale-link warning for the dev form:
```bash
herdr plugin link <abs-path-to-repo>/herdr-plugins/aw-context                    # dev box
herdr plugin install skylence-be/multi-llm-marketplace/herdr-plugins/aw-context  # consumer box
```

Verify (doctor is async like org-waker's: the invoke returns a `log_id` with
`status: running`; read the completed stdout in the log list):
```bash
herdr plugin action invoke doctor --plugin skylence.aw-context
herdr plugin log list --plugin skylence.aw-context
```
doctor must report aw-server reachable and BOTH watcher buckets fresh. A
WARN/stale bucket line means the watchers are not actually reporting, and
every "current activity" answer agents get will be quietly stale — fix the
watchers before wiring agents to the data.

Category consistency, so per-app summaries mean the same thing on every box.
Idempotent: an in-sync tree prints `already in sync` and writes nothing, so
run it unconditionally on every setup pass. Any real write snapshots the
prior tree to the plugin config dir `backups/` first.
```bash
sh <plugin-path>/awctx category sync <plugin-path>/presets/agent-org.json
```
`<plugin-path>` is `<abs-path-to-repo>/herdr-plugins/aw-context` on a dev box;
on a consumer box it is the installed plugin root (the directory holding the
`manifest_path` shown by `herdr plugin list`).

Fresh device that should carry the FULL reference config (whole category tree
plus portable settings: startOfDay, startOfWeek, durationDefault, theme,
views), not just the agent categories layered on: apply the committed
baseline instead — also idempotent, also backed up before any real write:
```bash
sh <plugin-path>/awctx bootstrap apply <plugin-path>/presets/aw-baseline.json
```
The baseline is exported from the reference machine with
`awctx bootstrap export`; re-export and commit it whenever the desired
ActivityWatch config changes, and every other box picks it up on its next
setup pass.

Agent wiring, per the plugin README: put `awctx` on PATH once and add one
instruction line to agent briefs (agents then self-serve via
`awctx agent-help`, and check `awctx doctor` before trusting numbers):
```bash
ln -s <plugin-path>/awctx ~/.local/bin/awctx
```

## S3 Board bootstrap

Exports made INSIDE a Claude session die with that shell call: each tool call starts a fresh shell from the profile. `HERDR_ORG_ROOT` and the scripts `PATH` must therefore reach the **claude process** itself, set before it starts, so it forwards them to workers.

**Use `orgclaude`.** It does all of it and `exec`s claude:

```bash
# inside Herdr, in the pane shell:
orgclaude <org-name>                 # doctrinal launch built in: injects --model opusplan --advisor opus (explicit flags win; empty ORGCLAUDE_MODEL/ORGCLAUDE_ADVISOR suppresses)
orgclaude <org-name> --model sonnet  # further args pass through to claude and override the injected defaults
```

Install it once by putting the plugin's `scripts/` dir on `PATH` from your shell rc. Resolve it by newest mtime so a plugin version bump needs no edit:

```zsh
# >>> herdr-org >>>
typeset -a _horg=( "$HOME"/.claude/plugins/cache/*/herdr-agent-org-claude/*/scripts(N/om) )
(( ${#_horg} )) && path=( "${_horg[1]}" $path )
unset _horg
# <<< herdr-org <<<
```

That also puts `board`, `dispatch-worker`, `waker-ctl` and `build-slot` on `PATH` in the pane shell, so you can inspect a board without going through claude.

**Do NOT reimplement `orgclaude` as a shell function that warns on a missing board and starts claude anyway.** That was the original form and it cost ~25 minutes on 2026-07-30: the warning went to stderr microseconds before a full-screen TUI took the terminal, so the operator rarely saw it and the agent never did. From inside, the org simply had no board and every call fell back to `~/.herdr-org/default`. A typo'd org name was indistinguishable from a new one. Create the board or refuse to start; do not warn and continue.

The equivalent by hand:

```bash
export HERDR_ORG_ROOT="$HOME/.herdr-org/<org-name>"
export PATH="<plugin-root>/scripts:$PATH"   # board, dispatch-worker, waker-ctl
board init "$HERDR_ORG_ROOT"
claude
```

**ABSOLUTE-PATH GOTCHA:** `board init <name>` with a bare name ALWAYS resolves to `~/.herdr-org/<name>`. It ignores `HERDR_ORG_ROOT` entirely, even when the export above already ran. Only an absolute or `./`/`../`-relative argument to `board init` itself honors a non-default location:
```bash
board init /abs/path/to/org   # only this form can put the org somewhere else
```
Every OTHER board subcommand (`get`, `list`, `comment`, `set-status`, ...) reads `HERDR_ORG_ROOT` correctly; only `init`'s own root resolution is special. `orgclaude` passes the absolute path for exactly this reason.

**ORIENT guard**, the first thing any orchestrator or worker session should check:
```bash
test -n "$HERDR_ORG_ROOT"
```
Unset means stop and redo the bootstrap above; never improvise with ad-hoc exports inside the Claude session, since they die with the current shell call. Left unset, the board CLI silently falls back to `~/.herdr-org/default`, quietly sending this org's milestones to the wrong board.

**Read that guard with the harness Bash tool, not `skyline_run`.** `skyline_run` children inherit the skyline daemon's environment (a LaunchAgent, cwd `/`), where `HERDR_*` is stale or unset regardless of what your pane has — so a `skyline_run` read of `HERDR_ORG_ROOT` is not evidence about your own process. Measured 2026-07-30: it reported `HERDR_ORG_ROOT` unset and `HERDR_PANE_ID=w5:p1` while the real pane was `wG:p1` in a different workspace. Filesystem checks (`ls ~/.herdr-org/<org>`) are daemon-independent and settle it either way.

Also remember a split worker pane does NOT inherit the requesting pane's environment (measured herdr 0.7.5, 2026-07-28): `dispatch-worker` forwards `HERDR_ORG_ROOT` and `PATH` via `--env` from your own process env.

## S4 Recommended ecosystem plugins (surveyed 2026-07-28)

These are the OPERATOR's call: this skill instructs, it does not auto-install anything below.

**Starter set**, the four with the clearest day-one payoff:
- `dot/herdr-terminal-notifier`: macOS notifications on agent state changes, so a parked worker rings instantly instead of waiting for a sweep. `herdr plugin install dot/herdr-terminal-notifier`
- `persiyanov/herdr-reviewr`: review sidebar for the L10 flow, comment on a worker's diff and see the PR plus its checks in one pane. `herdr plugin install persiyanov/herdr-reviewr`
- `senna-lang/herdr-agent-usage`: per-agent context meters and rate limits in the sidebar; succession triggers read these. `herdr plugin install senna-lang/herdr-agent-usage`
- `ntindle/herdr-resurrect`: snapshot and restore workspaces plus agents after a server crash or reboot. `herdr plugin install ntindle/herdr-resurrect`

**Optional**, pick what the workflow needs, do not install all of them:
- ONE remote-operation pick, to answer prompts from a phone: `dcolinmorgan/herdr-remote`, `AltanS/collie`, or `alexei-led/ccgram`.
- Many-pane navigation: `thanhdat77/herdr-navigator` or `JanTvrdik/herdr-command-palette`.
- `smarzban/herdr-file-viewer`: read-only diff and markdown pane.
- `ogulcancelik/herdr-browser`: a Chromium pane for web lanes.
- `natori-hrj/herdr-lazy`: declarative plugin manager; adopt once several of the above have landed, not before.

Living index of the wider ecosystem: `yigitkonur/awesome-herdr`.

Install syntax for any of the above: `herdr plugin install <owner>/<repo>` (`--ref <tag>` pins a version, `-y` skips the confirmation prompt).

## S5 Verification checklist (end-to-end)

Prove the wake path actually works before calling the box org-ready. Dispatch a throwaway probe with `--wake-target` and an explicit `--prompt` (do not pass `--todo` for a nonexistent slug: the default pointer asks for `board get <slug>`, board side-effects fail, and the probe dead-ends):
```bash
dispatch-worker --name probe --wake-target orchestrator \
  --prompt $'Reply with the single word PROBE_OK, then idle. Do not edit files.' \
  --cwd /abs/scratch-tree -- --permission-mode bypassPermissions
```
1. Confirm the settle ring arrives WITHOUT an operator pressing Enter; the orchestrator pane should receive the wake prompt on its own.
2. Confirm the ring is logged with a truthful outcome:
   ```bash
   herdr plugin action invoke doctor --plugin skylence.org-waker
   herdr plugin log list --plugin skylence.org-waker   # find that log_id, read "last rings"
   ```
   The recorded outcome (`delivered`, `held:undelivered`, `drain-delivered`, ...) must match what was actually observed on screen.
3. Unregister and reap the probe:
   ```bash
   waker-ctl unregister --lane probe
   ```
   then close or reap the probe's pane and agent as usual.
4. If a pending wake existed for the probe at unregister time, expect a new `dropped:unregistered` line in `rings.jsonl`. Confirm it is there, not silently swallowed.

5. Conductor model probe (once per box, after S3): launch `orgclaude probe-org --model opusplan --advisor opus` in a scratch pane, have it enter plan mode, produce a two-line plan for a trivial task, and exit plan mode. Confirm three things: (a) it proceeds past plan exit WITHOUT a human approval — bypassPermissions un-enforces plan-mode blocks, but ExitPlanMode-unattended is undocumented, so if the pane parks `blocked` here the operator gates every planning beat and must decide whether that is acceptable; (b) the statusline shows Opus during the plan phase and Sonnet after exit; (c) any advisor consultation appears in the transcript (advisor-during-plan-mode is likewise undocumented). The docs are silent on (a) and (c); this probe is the box's answer. Then clean up: remove `~/.herdr-org/probe-org` and close the scratch pane.
