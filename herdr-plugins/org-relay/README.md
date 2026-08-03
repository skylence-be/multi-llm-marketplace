# org-relay — durable MCP message bus for the herdr agent-org

Operator ruling 2026-08-03: the composer-paste channel (doorbell + waker ring)
is retired as the org's message path. It typed into a human input box and
inherited every renderer race; nine compensating mechanisms later it still
parked three times in one day. Org communication moves to MCP.

**Design (settled):** data plane = SQLite queue (`$HERDR_ORG_ROOT/relay.db`),
messages `{sender, to, lane, kind, body}`, explicit consume. Wake plane =
blocking `relay_await(agent, timeout_s)` — a session waits for events INSIDE
a turn; no idle composer, no ring. Tools: `relay_send / relay_inbox /
relay_consume / relay_await / relay_status`.

**Transport (operator-directed):** rmcp 3.0 streamable-HTTP, the same stack
binary-skyline already ships — see
`sky-binaries/binary-skyline/Cargo.toml:34` (`rmcp = "3.0"`, features
`server`, `transport-streamable-http-server`) and its `src/mcp_server.rs`
for the serve pattern. The current `src/main.rs` here carries the queue
logic and tool contracts on a hand-rolled transport as WIP; the transport
layer is to be swapped for rmcp 3.0 per that reference. Wire agents with
`claude mcp add --transport http relay http://127.0.0.1:7431/mcp`.

Status: scaffold + queue + tool schemas committed, NOT yet compiled; see the
board handover on `dag-research-cycle-01` for the remaining steps.
