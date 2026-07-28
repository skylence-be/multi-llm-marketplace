---
name: herdr-setup
description: One-shot playbook to bootstrap a fresh macOS box from "herdr installed" to "org-ready": preflight, org-waker wiring, board bootstrap, ecosystem plugin picks, and an end-to-end verification checklist. Invoke when the operator says "set up herdr for the org".
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
`jq` parses every Herdr JSON response: `board`, `dispatch-worker`, and `waker-ctl` all shell out to it, and silently break without it. `gh` opens and inspects PRs (workers open, never merge; L14). Either missing: install it (`brew install jq gh` on macOS) before continuing; nothing downstream degrades gracefully without them.

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
`waker-ctl present` exits 0 with no output when the plugin's config dir resolves, exit 1 with a stderr message when it does not. The `doctor` action runs async: it returns a `log_id` immediately with `status: running`. Read the completed result with:
```bash
herdr plugin log list --plugin skylence.org-waker
```
and find that `log_id`'s entry; its `stdout` reports herdr/jq versions, registered lanes, pending wakes, and the last few `rings.jsonl` lines.

Then the correctness gate, both suites, from the repo root:
```bash
sh herdr-plugins/org-waker/test/classify_composer.sh
sh herdr-plugins/org-waker/test/parked_retry.sh
```
Each prints its own `OK` line (`classify_composer.sh: OK`, `parked_retry.sh: OK`) at the end when every case passes. Anything else means stop before dispatching: the wake mechanism's classification or retry logic is broken, and lanes will hang silently instead of ringing the orchestrator.

## S3 Board bootstrap

Exports made INSIDE a Claude session die with that shell call: each tool call starts a fresh shell from the profile. `HERDR_ORG_ROOT` and the scripts `PATH` must therefore live in the **pane shell**, exported BEFORE `claude` starts, so the claude process inherits them and forwards them to workers itself:

```bash
# inside Herdr, in the pane shell, BEFORE starting claude:
export HERDR_ORG_ROOT="$HOME/.herdr-org/<org-name>"
export PATH="<plugin-root>/scripts:$PATH"   # board, dispatch-worker, waker-ctl
board init <org-name>
claude
```

**ABSOLUTE-PATH GOTCHA:** `board init <name>` with a bare name ALWAYS resolves to `~/.herdr-org/<name>`. It ignores `HERDR_ORG_ROOT` entirely, even when the export above already ran. Only an absolute or `./`/`../`-relative argument to `board init` itself honors a non-default location:
```bash
board init /abs/path/to/org   # only this form can put the org somewhere else
```
Every OTHER board subcommand (`get`, `list`, `comment`, `set-status`, ...) reads `HERDR_ORG_ROOT` correctly; only `init`'s own root resolution is special.

**ORIENT guard**, the first thing any orchestrator or worker session should check:
```bash
test -n "$HERDR_ORG_ROOT"
```
Unset means stop and redo the export block above; never improvise with ad-hoc exports inside the Claude session, since they die with the current shell call. Left unset, the board CLI silently falls back to `~/.herdr-org/default`, quietly sending this org's milestones to the wrong board. Also remember a split worker pane does NOT inherit the requesting pane's environment (measured herdr 0.7.5, 2026-07-28): `dispatch-worker` forwards `HERDR_ORG_ROOT` and `PATH` via `--env` from your own process env, which is exactly why both must be exported before `claude` starts.

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

Prove the wake path actually works before calling the box org-ready. Dispatch a throwaway probe with `--wake-target`:
```bash
dispatch-worker --name probe --todo <throwaway-slug> --wake-target orchestrator \
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
