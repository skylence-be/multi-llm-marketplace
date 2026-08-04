# org-relay — durable MCP message bus for the herdr agent-org

Operator ruling 2026-08-03: the composer-paste channel (doorbell + waker ring)
is retired as the org's message path. It typed into a human input box and
inherited every renderer race; nine compensating mechanisms later it still
parked three times in one day. Org communication moves to MCP.

**Design (settled):** data plane = SQLite queue — ONE box-wide db for every
org (`~/.config/herdr/org-relay/relay.db`, set as ORG_RELAY_DB by the launchd
plist; the `$HERDR_ORG_ROOT/relay.db` fallback only applies to ad-hoc runs
without that env), messages `{sender, to, lane, kind, body}`, explicit
consume. Wake plane = blocking `relay_await(agent, timeout_s)` — a session
waits for events INSIDE a turn; no idle composer, no ring. Tools:
`relay_send / relay_inbox / relay_consume / relay_await / relay_status`, plus
`relay_audit_tail / relay_observability_set / relay_observability_status`
over the audit / access / nudge JSONL streams (0.4.0).

**Nudge watchdog (0.5.0, field-driven 2026-08-04):** an awaiter exists only
inside a live turn, and turns end — an operator Esc, a natural answer-end, a
crash — taking the armed await with them. Measured: a paddle-GDPR
orchestrator ended a turn with no await armed, two operator interrupts killed
its recovery turns, and 5 [DONE]/[BLOCKER] messages sat unconsumed for 3h23m
while every lane idled "waiting for the durable queue". Durable ENQUEUE is
not delivery to a mind. The daemon now polls its own queue (~20s): a
recipient with unconsumed messages older than ~90s, no blocked relay_await
(in-process awaiter registry), and no consume inside the grace window gets a
short, content-free composer ring via `nudge-deliver` (composer-guarded
classify / verify / empty-submit recover — a deliberately simplified cut of
org-waker's pipeline, safe here because a nudge is idempotent and
content-free). Per-recipient cooldown ~5 min (~20 min once a recipient has no
live herdr agent). Outcomes land on the `nudge` stream; `relay_status`
reports `awaiting` plus nudge state — non-empty `queues` with an empty
`awaiting` list is the deaf-org shape the watchdog exists for. Env:
`ORG_RELAY_NUDGE=0` disables; `ORG_RELAY_NUDGE_HELPER` overrides the helper
path; `relay-ctl install-daemon` bakes PATH and HERDR_BIN_PATH into the plist
(launchd's default PATH cannot find herdr).

**Transport (operator-directed):** rmcp 3.0 streamable-HTTP, the same stack
binary-skyline already ships — see
`sky-binaries/binary-skyline/Cargo.toml:34` (`rmcp = "3.0"`, features
`server`, `transport-streamable-http-server`) and its `src/mcp_server.rs`
for the serve pattern. The current `src/main.rs` here carries the queue
logic and tool contracts on a hand-rolled transport; the transport layer is
still to be swapped for rmcp 3.0 per that reference. Wire agents with
`claude mcp add --transport http relay http://127.0.0.1:7431/mcp`.

Status: queue + tools + observability (0.4.0) + nudge watchdog (0.5.0),
compiled and tested (`cargo test`, `sh test/nudge_deliver_classify.sh`).
Deploy: `cargo build --release`, then re-run `sh relay-ctl install-daemon`
after 0.5.0 so the plist gains PATH / HERDR_BIN_PATH.
