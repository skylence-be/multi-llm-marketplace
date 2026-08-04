//! org-relay: durable MCP message bus for the herdr agent-org.
//!
//! Replaces the composer-paste channel (doorbell + waker ring) whose bus was a
//! human text-input box. Data plane: SQLite queue (WAL). Wake plane: a blocking
//! `relay_await` tool call, so the receiving session waits for events INSIDE a
//! turn instead of idling behind a composer that parks.
//!
//! Transport: MCP over HTTP, minimal hand-rolled profile that tolerates both
//! the classic initialize handshake and 2026-07-28 stateless clients (we hold
//! no session state at all, so a call sequence in any order works). Single
//! endpoint POST /mcp, one JSON-RPC message per POST, JSON response.
//! GET /mcp answers 405 (no server stream; permitted). Wire an agent with:
//! `claude mcp add --transport http relay http://127.0.0.1:7431/mcp`

use std::io::Read;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rusqlite::Connection;
use serde_json::{json, Value};

const PROTOCOL_DEFAULT: &str = "2025-06-18";
const MAX_BODY: usize = 1_000_000;
const AWAIT_POLL_MS: u64 = 500;
const AWAIT_MAX_S: u64 = 3600;
const AWAIT_DEFAULT_S: u64 = 50; // under the ~60s MCP client per-call ceiling

// ── Observability ────────────────────────────────────────────────────────────
// Two JSONL streams, modelled on binary-skyline's observ.rs (AUDIT/ACCESS):
//   audit  = MESSAGE LIFECYCLE (send / await-start / wake / timeout / consume).
//            This is the org's own timeline and carries the two numbers nobody
//            could measure before: wake LATENCY (send -> delivery) and message
//            AGE at consume (how long a doorbell sat unhandled).
//   access = one record per MCP tool call (tool, duration_ms, status, bytes).
// Defaults follow skyline's rule and its stated reason: cheap bounded streams
// default ON, because a daemon that defaults to zero observability is how a
// regression stays invisible for hours; per-request-cost streams default OFF.
const AUDIT_DEFAULT_ON: bool = true;
const ACCESS_DEFAULT_ON: bool = false;
const MAX_LOG_BYTES: u64 = 10_000_000;
const MAX_BACKUPS: u32 = 1;

fn now_iso() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let days = secs / 86400;
    let (mut y, mut rem) = (1970i64, days as i64);
    loop {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
        let len = if leap { 366 } else { 365 };
        if rem < len {
            break;
        }
        rem -= len;
        y += 1;
    }
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let ml = [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut m = 0usize;
    while rem >= ml[m] {
        rem -= ml[m];
        m += 1;
    }
    let t = secs % 86400;
    format!(
        "{y:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        m + 1,
        rem + 1,
        t / 3600,
        (t % 3600) / 60,
        t % 60
    )
}

fn db_path() -> String {
    if let Ok(p) = std::env::var("ORG_RELAY_DB") {
        return p;
    }
    let root = std::env::var("HERDR_ORG_ROOT")
        .unwrap_or_else(|_| format!("{}/.herdr-org/default", std::env::var("HOME").unwrap_or_default()));
    format!("{root}/relay.db")
}

fn open_db() -> rusqlite::Result<Connection> {
    let conn = Connection::open(db_path())?;
    conn.busy_timeout(Duration::from_secs(5))?;
    // WAL: thread-per-request means concurrent readers during a writer.
    let _ = conn.pragma_update(None, "journal_mode", "WAL");
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts TEXT NOT NULL,
            sender TEXT NOT NULL,
            recipient TEXT NOT NULL,
            lane TEXT,
            kind TEXT NOT NULL,
            body TEXT NOT NULL,
            consumed_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_inbox ON messages(recipient, consumed_at);",
    )?;
    Ok(conn)
}

fn row_json(r: &rusqlite::Row) -> rusqlite::Result<Value> {
    Ok(json!({
        "id": r.get::<_, i64>(0)?,
        "ts": r.get::<_, String>(1)?,
        "sender": r.get::<_, String>(2)?,
        "recipient": r.get::<_, String>(3)?,
        "lane": r.get::<_, Option<String>>(4)?,
        "kind": r.get::<_, String>(5)?,
        "body": r.get::<_, String>(6)?,
        "consumed_at": r.get::<_, Option<String>>(7)?,
    }))
}

fn inbox(conn: &Connection, agent: &str, include_consumed: bool) -> rusqlite::Result<Vec<Value>> {
    let sql = if include_consumed {
        "SELECT id, ts, sender, recipient, lane, kind, body, consumed_at FROM messages
         WHERE recipient = ?1 ORDER BY id"
    } else {
        "SELECT id, ts, sender, recipient, lane, kind, body, consumed_at FROM messages
         WHERE recipient = ?1 AND consumed_at IS NULL ORDER BY id"
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map([agent], |r| row_json(r))?;
    rows.collect()
}

fn req_str(args: &Value, key: &str) -> Result<String, String> {
    args.get(key)
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("missing required string argument: {key}"))
}

/// Execute one tool. Ok(payload) or Err(message) -> isError content.
fn obs_dir() -> std::path::PathBuf {
    std::path::Path::new(&db_path())
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| std::path::PathBuf::from("."))
}

fn cfg_path() -> std::path::PathBuf {
    obs_dir().join("relay-observability.json")
}

/// Effective on/off for a stream. Precedence: env override, then the config
/// file a runtime toggle writes, then the compiled default. Env wins so a
/// launchd plist or a one-off run can force a stream without touching state.
fn stream_enabled(stream: &str) -> bool {
    let env_key = format!("ORG_RELAY_{}", stream.to_uppercase());
    if let Ok(v) = std::env::var(&env_key) {
        let v = v.trim().to_ascii_lowercase();
        return matches!(v.as_str(), "1" | "on" | "true" | "yes");
    }
    if let Ok(txt) = std::fs::read_to_string(cfg_path()) {
        if let Ok(cfg) = serde_json::from_str::<Value>(&txt) {
            if let Some(b) = cfg.get(stream).and_then(|v| v.as_bool()) {
                return b;
            }
        }
    }
    match stream {
        "audit" => AUDIT_DEFAULT_ON,
        "access" => ACCESS_DEFAULT_ON,
        _ => false,
    }
}

fn set_stream(stream: &str, enabled: bool) -> Result<(), String> {
    let p = cfg_path();
    let mut cfg: Value = std::fs::read_to_string(&p)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| json!({}));
    cfg[stream] = json!(enabled);
    if let Some(d) = p.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    std::fs::write(&p, cfg.to_string()).map_err(|e| e.to_string())
}

/// Append one JSONL record, rotating at MAX_LOG_BYTES. Never fails a tool call:
/// observability that can break the bus is worse than no observability.
fn log_event(stream: &str, mut ev: Value) {
    if !stream_enabled(stream) {
        return;
    }
    let path = obs_dir().join(format!("{stream}.jsonl"));
    if let Ok(md) = std::fs::metadata(&path) {
        if md.len() >= MAX_LOG_BYTES {
            for i in (1..=MAX_BACKUPS).rev() {
                let _ = std::fs::rename(
                    obs_dir().join(format!("{stream}.jsonl.{i}")),
                    obs_dir().join(format!("{stream}.jsonl.{}", i + 1)),
                );
            }
            let _ = std::fs::rename(&path, obs_dir().join(format!("{stream}.jsonl.1")));
        }
    }
    if let Some(o) = ev.as_object_mut() {
        o.insert("ts".into(), json!(now_iso()));
    }
    if let Some(d) = path.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(f, "{ev}");
    }
}

fn tail_stream(stream: &str, limit: usize) -> Vec<Value> {
    let path = obs_dir().join(format!("{stream}.jsonl"));
    let txt = std::fs::read_to_string(path).unwrap_or_default();
    let lines: Vec<&str> = txt.lines().filter(|l| !l.trim().is_empty()).collect();
    lines
        .iter()
        .rev()
        .take(limit)
        .rev()
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .collect()
}

/// Milliseconds since an ISO-8601 second-precision stamp this server wrote.
fn age_ms_since(ts: &str) -> Option<i64> {
    let p: Vec<&str> = ts.trim_end_matches('Z').split(['-', 'T', ':']).collect();
    if p.len() < 6 {
        return None;
    }
    let n = |i: usize| p[i].parse::<i64>().ok();
    let (y, mo, d, h, mi, s) = (n(0)?, n(1)?, n(2)?, n(3)?, n(4)?, n(5)?);
    // days-from-civil (Howard Hinnant's algorithm), valid for any Gregorian date.
    let yy = if mo <= 2 { y - 1 } else { y };
    let era = if yy >= 0 { yy } else { yy - 399 } / 400;
    let yoe = yy - era * 400;
    let mp = (mo + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    let then = days * 86400 + h * 3600 + mi * 60 + s;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs() as i64;
    Some((now - then) * 1000)
}

/// ACCESS stream wrapper: one record per tool call. Off by default (per-request
/// cost); the audit stream carries the org-meaningful events either way.
fn call_tool(name: &str, args: &Value) -> Result<Value, String> {
    let t0 = Instant::now();
    let out = call_tool_inner(name, args);
    if stream_enabled("access") {
        let (status, err_kind, bytes) = match &out {
            Ok(v) => ("ok", Value::Null, v.to_string().len()),
            Err(e) => ("error", json!(e.split(':').next().unwrap_or("error")), 0),
        };
        log_event("access", json!({"tool": name, "status": status, "error_kind": err_kind,
            "duration_ms": t0.elapsed().as_millis() as u64, "result_bytes": bytes,
            "agent": args.get("agent").or_else(|| args.get("sender")).cloned()}));
    }
    out
}

fn call_tool_inner(name: &str, args: &Value) -> Result<Value, String> {
    let conn = open_db().map_err(|e| format!("db open failed: {e}"))?;
    match name {
        "relay_send" => {
            let sender = req_str(args, "sender")?;
            let to = req_str(args, "to")?;
            let kind = req_str(args, "kind")?;
            let body = req_str(args, "body")?;
            let lane = args.get("lane").and_then(|v| v.as_str()).map(str::to_string);
            conn.execute(
                "INSERT INTO messages (ts, sender, recipient, lane, kind, body) VALUES (?1,?2,?3,?4,?5,?6)",
                rusqlite::params![now_iso(), sender, to, lane, kind, body],
            )
            .map_err(|e| e.to_string())?;
            let id = conn.last_insert_rowid();
            log_event("audit", json!({"event":"send","id":id,"sender":sender,"recipient":to,
                "lane":lane,"kind":kind,"body_bytes":body.len()}));
            Ok(json!({"id": id, "queued_for": to}))
        }
        "relay_inbox" => {
            let agent = req_str(args, "agent")?;
            let all = args.get("include_consumed").and_then(|v| v.as_bool()).unwrap_or(false);
            let msgs = inbox(&conn, &agent, all).map_err(|e| e.to_string())?;
            Ok(json!({"agent": agent, "count": msgs.len(), "messages": msgs}))
        }
        "relay_consume" => {
            let agent = req_str(args, "agent")?;
            let ids: Vec<i64> = args
                .get("ids")
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|v| v.as_i64()).collect())
                .unwrap_or_default();
            if ids.is_empty() {
                return Err("ids must be a non-empty array of message ids".into());
            }
            let mut n = 0usize;
            for id in &ids {
                n += conn
                    .execute(
                        "UPDATE messages SET consumed_at = ?1 WHERE id = ?2 AND recipient = ?3 AND consumed_at IS NULL",
                        rusqlite::params![now_iso(), id, agent],
                    )
                    .map_err(|e| e.to_string())?;
            }
            log_event("audit", json!({"event":"consume","agent":agent,"ids":ids,
                "consumed":n,"requested":ids.len()}));
            Ok(json!({"consumed": n, "of": ids.len()}))
        }
        "relay_await" => {
            let agent = req_str(args, "agent")?;
            // Default sits UNDER the typical MCP client per-tool-call ceiling
            // (~60s in Claude Code). The server honors any timeout_s exactly
            // (verified: asked 90, held 90), but a client that gives up first
            // turns a clean {timed_out:true} into a tool ERROR the caller has
            // to handle. Returning cleanly under the cap and re-arming is the
            // supported long-wait pattern. Measured 2026-08-03: an
            // orchestrator asking 600 got client timeouts at ~70s, seven
            // times, and had to hand-roll the re-arm loop.
            let timeout_s = args
                .get("timeout_s")
                .and_then(|v| v.as_u64())
                .unwrap_or(AWAIT_DEFAULT_S)
                .clamp(1, AWAIT_MAX_S);
            drop(conn); // fresh connection per poll; never hold one across the wait
            log_event("audit", json!({"event":"await_start","agent":agent,"timeout_s":timeout_s}));
            let started = Instant::now();
            let deadline = started + Duration::from_secs(timeout_s);
            loop {
                let c = open_db().map_err(|e| format!("db open failed: {e}"))?;
                let msgs = inbox(&c, &agent, false).map_err(|e| e.to_string())?;
                if !msgs.is_empty() {
                    // Wake LATENCY: how long this agent blocked, and how old the
                    // oldest delivered message was. The pair nobody could measure
                    // while the bus was a composer.
                    let oldest_age = msgs.first()
                        .and_then(|m| m.get("ts")).and_then(|v| v.as_str())
                        .and_then(age_ms_since);
                    log_event("audit", json!({"event":"await_wake","agent":agent,
                        "waited_ms":started.elapsed().as_millis() as u64,
                        "count":msgs.len(),
                        "ids": msgs.iter().filter_map(|m| m.get("id").cloned()).collect::<Vec<_>>(),
                        "oldest_msg_age_ms": oldest_age}));
                    return Ok(json!({
                        "agent": agent, "count": msgs.len(), "messages": msgs,
                        "note": "messages are NOT auto-consumed; act, then relay_consume the ids"
                    }));
                }
                if Instant::now() >= deadline {
                    log_event("audit", json!({"event":"await_timeout","agent":agent,
                        "waited_ms":started.elapsed().as_millis() as u64,"timeout_s":timeout_s}));
                    return Ok(json!({"agent": agent, "count": 0, "messages": [],
                        "timed_out": true, "retry": true,
                        "note": "no messages within timeout_s; call relay_await again to keep waiting (re-arming is the supported long-wait pattern)"}));
                }
                std::thread::sleep(Duration::from_millis(AWAIT_POLL_MS));
            }
        }
        "relay_status" => {
            let mut stmt = conn
                .prepare(
                    "SELECT recipient, COUNT(*) FROM messages WHERE consumed_at IS NULL GROUP BY recipient",
                )
                .map_err(|e| e.to_string())?;
            let rows: Vec<Value> = stmt
                .query_map([], |r| {
                    Ok(json!({"recipient": r.get::<_, String>(0)?, "unconsumed": r.get::<_, i64>(1)?}))
                })
                .map_err(|e| e.to_string())?
                .filter_map(Result::ok)
                .collect();
            Ok(json!({"db": db_path(), "queues": rows}))
        }
        "relay_audit_tail" => {
            let stream = args.get("stream").and_then(|v| v.as_str()).unwrap_or("audit").to_string();
            if stream != "audit" && stream != "access" {
                return Err("stream must be \"audit\" or \"access\"".into());
            }
            let limit = args.get("limit").and_then(|v| v.as_u64()).unwrap_or(50).clamp(1, 1000) as usize;
            let ev = tail_stream(&stream, limit);
            Ok(json!({"stream": stream, "enabled": stream_enabled(&stream),
                      "count": ev.len(), "events": ev}))
        }
        "relay_observability_set" => {
            let stream = req_str(args, "stream")?;
            if stream != "audit" && stream != "access" {
                return Err("stream must be \"audit\" or \"access\"".into());
            }
            let enabled = args.get("enabled").and_then(|v| v.as_bool())
                .ok_or("enabled must be a boolean")?;
            set_stream(&stream, enabled)?;
            Ok(json!({"stream": stream, "enabled": stream_enabled(&stream),
                      "config": cfg_path().to_string_lossy(),
                      "note": "an ORG_RELAY_<STREAM> env var, if set, overrides this file"}))
        }
        "relay_observability_status" => {
            let f = |s: &str| json!({"enabled": stream_enabled(s),
                "path": obs_dir().join(format!("{s}.jsonl")).to_string_lossy(),
                "bytes": std::fs::metadata(obs_dir().join(format!("{s}.jsonl"))).map(|m| m.len()).unwrap_or(0)});
            Ok(json!({"audit": f("audit"), "access": f("access"),
                      "config": cfg_path().to_string_lossy(),
                      "max_log_bytes": MAX_LOG_BYTES, "max_backups": MAX_BACKUPS}))
        }
        other => Err(format!("unknown tool: {other}")),
    }
}

fn tool_defs() -> Value {
    let s = |d: &str| json!({"type": "string", "description": d});
    // outputSchema (SEP-2106) mirrors what call_tool actually returns per
    // tool; results also arrive as structuredContent so consumers never
    // string-parse the text block.
    let msg_schema = json!({"type": "object", "properties": {
        "id": {"type": "integer"}, "ts": {"type": "string"},
        "sender": {"type": "string"}, "recipient": {"type": "string"},
        "lane": {"type": ["string", "null"]}, "kind": {"type": "string"},
        "body": {"type": "string"}, "consumed_at": {"type": ["string", "null"]}}});
    let inbox_out = json!({"type": "object", "properties": {
        "agent": {"type": "string"}, "count": {"type": "integer"},
        "messages": {"type": "array", "items": msg_schema},
        "timed_out": {"type": "boolean"}, "note": {"type": "string"}}});
    json!([
        {"name": "relay_send",
         "description": "Queue a durable message for another org agent (replaces doorbell/ring). Delivery = the recipient's next relay_await or relay_inbox; nothing is typed into anyone's composer.",
         "inputSchema": {"type": "object", "required": ["sender", "to", "kind", "body"], "properties": {
             "sender": s("your agent name"),
             "to": s("recipient agent name (e.g. orchestrator)"),
             "lane": s("optional lane/todo slug for context"),
             "kind": s("doorbell | ring | blocker | incident | peer | operator | other"),
             "body": s("the message; stored verbatim, no shell interpolation hazards")}},
         "outputSchema": {"type": "object", "properties": {
             "id": {"type": "integer"}, "queued_for": {"type": "string"}}}},
        {"name": "relay_inbox",
         "description": "List messages queued for an agent (unconsumed only unless include_consumed).",
         "inputSchema": {"type": "object", "required": ["agent"], "properties": {
             "agent": s("agent name"),
             "include_consumed": {"type": "boolean", "description": "default false"}}},
         "outputSchema": inbox_out},
        {"name": "relay_consume",
         "description": "Mark handled message ids consumed. Explicit on purpose: a crash between reading and acting loses nothing.",
         "inputSchema": {"type": "object", "required": ["agent", "ids"], "properties": {
             "agent": s("agent name"),
             "ids": {"type": "array", "items": {"type": "integer"}, "description": "message ids from inbox/await"}}},
         "outputSchema": {"type": "object", "properties": {
             "consumed": {"type": "integer"}, "of": {"type": "integer"}}}},
        {"name": "relay_await",
         "description": "Block until a message arrives for agent, then return the unconsumed inbox. Event-driven waiting INSIDE a turn: no idle session, no composer, no ring. timeout_s default 50, max 3600 — the server honors it exactly, but most MCP clients abort a single tool call around 60s, so values above that surface as a CLIENT timeout error instead of a clean result. For longer waits, re-arm: a timed-out reply carries retry:true and costs one tool call per ~50s.",
         "inputSchema": {"type": "object", "required": ["agent"], "properties": {
             "agent": s("agent name"),
             "timeout_s": {"type": "integer", "description": "1..3600, default 50; keep at or under ~55 unless the client is known to allow longer tool calls"}}},
         "outputSchema": inbox_out},
        {"name": "relay_audit_tail",
         "description": "Last N events from an observability stream. audit = message lifecycle (send / await_start / await_wake with waited_ms and oldest_msg_age_ms / await_timeout / consume) — the org's own timeline, including wake latency and how long a doorbell sat unhandled. access = one record per MCP tool call (tool, status, duration_ms, result_bytes).",
         "inputSchema": {"type": "object", "properties": {
             "stream": s("audit (default) | access"),
             "limit": {"type": "integer", "description": "1..1000, default 50"}}},
         "outputSchema": {"type": "object", "properties": {
             "stream": {"type": "string"}, "enabled": {"type": "boolean"},
             "count": {"type": "integer"}, "events": {"type": "array", "items": {"type": "object"}}}}},
        {"name": "relay_observability_set",
         "description": "Turn a stream on or off at runtime; persists to relay-observability.json next to the db. An ORG_RELAY_AUDIT / ORG_RELAY_ACCESS env var overrides the file. Defaults: audit ON (cheap, bounded), access OFF (per-request cost).",
         "inputSchema": {"type": "object", "required": ["stream", "enabled"], "properties": {
             "stream": s("audit | access"),
             "enabled": {"type": "boolean", "description": "true to record, false to stop"}}},
         "outputSchema": {"type": "object", "properties": {
             "stream": {"type": "string"}, "enabled": {"type": "boolean"}, "config": {"type": "string"}}}},
        {"name": "relay_observability_status",
         "description": "Per-stream enabled flag, log path, current size, plus rotation settings.",
         "inputSchema": {"type": "object", "properties": {}},
         "outputSchema": {"type": "object", "properties": {
             "audit": {"type": "object"}, "access": {"type": "object"},
             "max_log_bytes": {"type": "integer"}}}},
        {"name": "relay_status",
         "description": "Unconsumed message counts per recipient, plus the db path.",
         "inputSchema": {"type": "object", "properties": {}},
         "outputSchema": {"type": "object", "properties": {
             "db": {"type": "string"},
             "queues": {"type": "array", "items": {"type": "object", "properties": {
                 "recipient": {"type": "string"}, "unconsumed": {"type": "integer"}}}}}}}
    ])
}

fn server_info() -> Value {
    json!({"name": "org-relay", "version": env!("CARGO_PKG_VERSION")})
}

/// Wrap a result body per 2026-07-28: required resultType plus serverInfo in
/// _meta. Harmless extras for classic-handshake clients.
fn rpc_result(id: &Value, mut result: Value) -> Value {
    if let Some(obj) = result.as_object_mut() {
        obj.entry("resultType").or_insert(json!("complete"));
        obj.entry("_meta")
            .or_insert(json!({"io.modelcontextprotocol/serverInfo": server_info()}));
    }
    json!({"jsonrpc": "2.0", "id": id, "result": result})
}

fn rpc_error(id: &Value, code: i64, msg: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": msg}})
}

/// Handle one JSON-RPC message; None for notifications (no response body).
fn handle_rpc(msg: &Value) -> Option<Value> {
    let method = msg.get("method").and_then(|m| m.as_str()).unwrap_or("");
    if msg.get("id").is_none() {
        return None; // notification (e.g. notifications/initialized): accept silently
    }
    let id = msg.get("id").cloned().unwrap_or(Value::Null);
    let params = msg.get("params").cloned().unwrap_or_else(|| json!({}));
    Some(match method {
        "initialize" => {
            let requested = params
                .get("protocolVersion")
                .and_then(|v| v.as_str())
                .unwrap_or(PROTOCOL_DEFAULT);
            rpc_result(&id, json!({
                "protocolVersion": requested,
                "capabilities": {"tools": {}},
                "serverInfo": server_info()
            }))
        }
        // 2026-07-28: servers MUST implement server/discover (stateless
        // version selection / capability probe; SEP-2575).
        "server/discover" => rpc_result(&id, json!({
            "protocolVersions": ["2026-07-28", "2025-06-18", "2025-03-26"],
            "capabilities": {"tools": {}},
            "serverInfo": server_info()
        })),
        // Kept for pre-2026 clients; removed from the new core but harmless.
        "ping" => rpc_result(&id, json!({})),
        // CacheableResult (SEP-2549): the tool set is static for a server
        // build, so advertise a long freshness hint; private — this is a
        // loopback bus, shared caches have no business with it. Order is
        // deterministic (a literal array) per the prompt-cache guidance.
        "tools/list" => rpc_result(&id, json!({
            "tools": tool_defs(),
            "ttlMs": 3_600_000,
            "cacheScope": "private"
        })),
        "tools/call" => {
            let name = params.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let args = params.get("arguments").cloned().unwrap_or_else(|| json!({}));
            match call_tool(name, &args) {
                // structuredContent (SEP-2106): the JSON payload itself, so
                // agent consumers stop string-parsing the text block. Text
                // stays for clients that only render content.
                Ok(v) => rpc_result(&id, json!({
                    "content": [{"type": "text", "text": v.to_string()}],
                    "structuredContent": v,
                    "isError": false
                })),
                Err(e) => rpc_result(&id, json!({
                    "content": [{"type": "text", "text": e}],
                    "isError": true
                })),
            }
        }
        _ => rpc_error(&id, -32601, &format!("method not found: {method}")),
    })
}

fn main() {
    let port = std::env::var("ORG_RELAY_PORT").ok().and_then(|p| p.parse::<u16>().ok()).unwrap_or(7431);
    if let Err(e) = open_db() {
        eprintln!("org-relay: cannot open {}: {e}", db_path());
        std::process::exit(1);
    }
    let addr = format!("127.0.0.1:{port}");
    let server = match tiny_http::Server::http(&addr) {
        Ok(s) => Arc::new(s),
        Err(e) => {
            eprintln!("org-relay: bind {addr} failed (already running?): {e}");
            std::process::exit(1);
        }
    };
    eprintln!("org-relay: serving MCP on http://{addr}/mcp  (db: {})", db_path());

    loop {
        let request = match server.recv() {
            Ok(r) => r,
            Err(_) => continue,
        };
        // Thread per request: relay_await blocks for up to an hour and must
        // not stall other callers.
        std::thread::spawn(move || {
            let url = request.url().to_string();
            let method = request.method().to_string();
            let respond = |req: tiny_http::Request, code: u16, body: String, ct: &str| {
                let header = tiny_http::Header::from_bytes(&b"Content-Type"[..], ct.as_bytes()).unwrap();
                let _ = req.respond(tiny_http::Response::from_string(body).with_status_code(code).with_header(header));
            };
            if url != "/mcp" && url != "/mcp/" {
                if url == "/health" {
                    return respond(request, 200, "ok".into(), "text/plain");
                }
                return respond(request, 404, "not found".into(), "text/plain");
            }
            match method.as_str() {
                "POST" => {
                    // SEP-2243 routing header, captured before the body read
                    // consumes the request.
                    let hdr_method: Option<String> = request
                        .headers()
                        .iter()
                        .find(|h| h.field.equiv("Mcp-Method"))
                        .map(|h| h.value.as_str().to_string());
                    let mut body = String::new();
                    let mut req = request;
                    {
                        let reader = req.as_reader();
                        if reader.take(MAX_BODY as u64).read_to_string(&mut body).is_err() {
                            return respond(req, 400, "unreadable body".into(), "text/plain");
                        }
                    }
                    let parsed: Value = match serde_json::from_str(&body) {
                        Ok(v) => v,
                        Err(e) => {
                            let out = rpc_error(&Value::Null, -32700, &format!("parse error: {e}"));
                            return respond(req, 200, out.to_string(), "application/json");
                        }
                    };
                    // When the routing header is present it must agree with
                    // the body; -32020 = HeaderMismatchError (2026-07-28).
                    if let Some(hm) = hdr_method.as_deref() {
                        let bm = parsed.get("method").and_then(|m| m.as_str()).unwrap_or("");
                        if !hm.is_empty() && !bm.is_empty() && hm != bm {
                            let id = parsed.get("id").cloned().unwrap_or(Value::Null);
                            let out = rpc_error(&id, -32020, &format!("Mcp-Method header {hm:?} does not match body method {bm:?}"));
                            return respond(req, 200, out.to_string(), "application/json");
                        }
                    }
                    match handle_rpc(&parsed) {
                        Some(out) => respond(req, 200, out.to_string(), "application/json"),
                        None => respond(req, 202, String::new(), "application/json"),
                    }
                }
                "GET" => respond(request, 405, "SSE stream not offered; POST JSON-RPC".into(), "text/plain"),
                "DELETE" => respond(request, 200, String::new(), "text/plain"),
                _ => respond(request, 405, "method not allowed".into(), "text/plain"),
            }
        });
    }
}
