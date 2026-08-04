//! Data plane: the SQLite queue, observability streams, awaiter registry,
//! and the tool operations themselves. Ported intact from the 0.5.x
//! hand-rolled server; the transport moved to rmcp (server.rs) but every
//! queue semantic here is unchanged: explicit consume, second-precision ISO
//! stamps, WAL, one box-wide db resolved by `db_path()`.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rusqlite::Connection;
use serde_json::{json, Value};

pub const AWAIT_MAX_S: u64 = 3600;
/// Long by default: the await is armed as the LAST call of a turn. A client
/// with the tasks extension gets a task handle back immediately; a client
/// without it holds the call open (Claude Code >= 2.1.212 auto-backgrounds
/// the held call at ~2 minutes into a native background task, freeing the
/// turn — the result then arrives as a task notification). The old 50s
/// default existed only for the hand-rolled transport whose silent holds the
/// 2026-08-03 client aborted at ~60s; that ceiling is retired with it.
pub const AWAIT_DEFAULT_S: u64 = 1800;

// ── Nudge watchdog constants (semantics unchanged from 0.5.0) ───────────────
pub const NUDGE_POLL_S: u64 = 20;
pub const NUDGE_GRACE_S: i64 = 90;
pub const NUDGE_COOLDOWN_S: u64 = 300;
pub const NUDGE_NOAGENT_COOLDOWN_S: u64 = 1200;

// ── Observability ───────────────────────────────────────────────────────────
pub const AUDIT_DEFAULT_ON: bool = true;
pub const ACCESS_DEFAULT_ON: bool = false;
pub const MAX_LOG_BYTES: u64 = 10_000_000;
pub const MAX_BACKUPS: u32 = 1;

// ── Awaiter registry ────────────────────────────────────────────────────────
// Recipients with a live await in this process — in-call holds AND task-backed
// holds both register (the guard lives inside the spawned task future). The
// nudge watchdog reads it; relay_status exposes it. Non-empty queues with an
// empty awaiting list is the deaf-org shape the watchdog exists for.
fn awaiters() -> &'static Mutex<HashMap<String, u32>> {
    static A: OnceLock<Mutex<HashMap<String, u32>>> = OnceLock::new();
    A.get_or_init(|| Mutex::new(HashMap::new()))
}

/// RAII guard so an await that returns, times out, errors, is cancelled, or
/// panics always deregisters; a leaked entry would silently disable the nudge
/// for that name.
pub struct AwaitGuard(String);
impl AwaitGuard {
    pub fn new(agent: &str) -> Self {
        *awaiters().lock().unwrap().entry(agent.to_string()).or_insert(0) += 1;
        AwaitGuard(agent.to_string())
    }
}
impl Drop for AwaitGuard {
    fn drop(&mut self) {
        let mut m = awaiters().lock().unwrap();
        if let Some(n) = m.get_mut(&self.0) {
            *n = n.saturating_sub(1);
            if *n == 0 {
                m.remove(&self.0);
            }
        }
    }
}

pub fn awaiter_active(agent: &str) -> bool {
    awaiters().lock().unwrap().contains_key(agent)
}

pub fn awaiting_names() -> Vec<String> {
    let mut v: Vec<String> = awaiters().lock().unwrap().keys().cloned().collect();
    v.sort();
    v
}

// ── In-process send notification ────────────────────────────────────────────
// relay_send pings the recipient's Notify so a live awaiter wakes in
// microseconds instead of on its next poll. The 2s poll fallback still covers
// writers that bypass this daemon (sqlite3 CLI, tests).
fn notifiers() -> &'static Mutex<HashMap<String, Arc<tokio::sync::Notify>>> {
    static N: OnceLock<Mutex<HashMap<String, Arc<tokio::sync::Notify>>>> = OnceLock::new();
    N.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn notifier_for(agent: &str) -> Arc<tokio::sync::Notify> {
    notifiers()
        .lock()
        .unwrap()
        .entry(agent.to_string())
        .or_insert_with(|| Arc::new(tokio::sync::Notify::new()))
        .clone()
}

pub fn notify_recipient(agent: &str) {
    if let Some(n) = notifiers().lock().unwrap().get(agent) {
        n.notify_waiters();
    }
}

pub fn now_iso() -> String {
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

pub fn db_path() -> String {
    if let Ok(p) = std::env::var("ORG_RELAY_DB") {
        return p;
    }
    let root = std::env::var("HERDR_ORG_ROOT")
        .unwrap_or_else(|_| format!("{}/.herdr-org/default", std::env::var("HOME").unwrap_or_default()));
    format!("{root}/relay.db")
}

pub fn open_db() -> rusqlite::Result<Connection> {
    let conn = Connection::open(db_path())?;
    conn.busy_timeout(Duration::from_secs(5))?;
    // WAL: concurrent readers during a writer (async handlers + watchdog).
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
        CREATE INDEX IF NOT EXISTS idx_inbox ON messages(recipient, consumed_at);
        CREATE TABLE IF NOT EXISTS guide_acks (
            token TEXT NOT NULL,
            guide_hash TEXT NOT NULL,
            acked_at INTEGER NOT NULL,
            PRIMARY KEY (token, guide_hash)
        );",
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

pub fn inbox(conn: &Connection, agent: &str, include_consumed: bool) -> rusqlite::Result<Vec<Value>> {
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

pub fn req_str(args: &Value, key: &str) -> Result<String, String> {
    args.get(key)
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("missing required string argument: {key}"))
}

// ── Guide-ack ledger (guide gate persistence) ───────────────────────────────
// Keyed by client token (clientInfo name/version) + guide content hash, TTL
// 24h: bounce-day relief, not a standing exemption. Any guide change re-arms
// the gate for everyone; a fresh day re-reads. Lives in the relay db so it
// survives daemon restarts with zero extra files.
pub const ACK_TTL_SECS: u64 = 86_400;

pub fn now_secs() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// TTL check against an explicit clock (testable core; clock skew backwards
/// never invalidates).
pub fn ack_valid(acked_at: u64, now: u64) -> bool {
    now.saturating_sub(acked_at) <= ACK_TTL_SECS
}

pub fn record_ack(token: &str, guide_hash: &str) {
    if let Ok(conn) = open_db() {
        let _ = conn.execute(
            "INSERT INTO guide_acks (token, guide_hash, acked_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(token, guide_hash) DO UPDATE SET acked_at = excluded.acked_at",
            rusqlite::params![token, guide_hash, now_secs() as i64],
        );
    }
}

pub fn has_ack(token: &str, guide_hash: &str) -> bool {
    let Ok(conn) = open_db() else { return false };
    conn.query_row(
        "SELECT acked_at FROM guide_acks WHERE token = ?1 AND guide_hash = ?2",
        rusqlite::params![token, guide_hash],
        |r| r.get::<_, i64>(0),
    )
    .ok()
    .is_some_and(|at| ack_valid(at as u64, now_secs()))
}

// ── Observability streams ───────────────────────────────────────────────────

pub fn obs_dir() -> std::path::PathBuf {
    std::path::Path::new(&db_path())
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| std::path::PathBuf::from("."))
}

fn cfg_path() -> std::path::PathBuf {
    obs_dir().join("relay-observability.json")
}

pub fn cfg_path_string() -> String {
    cfg_path().to_string_lossy().into_owned()
}

/// Effective on/off for a stream. Precedence: env override, then the config
/// file a runtime toggle writes, then the compiled default.
pub fn stream_enabled(stream: &str) -> bool {
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
        // Cheap, bounded, and the only record of turn-starter activity: ON.
        "nudge" => true,
        _ => false,
    }
}

pub fn set_stream(stream: &str, enabled: bool) -> Result<(), String> {
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

/// Append one JSONL record, rotating at MAX_LOG_BYTES. Never fails a tool
/// call: observability that can break the bus is worse than no observability.
pub fn log_event(stream: &str, mut ev: Value) {
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

pub fn tail_stream(stream: &str, limit: usize) -> Vec<Value> {
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
pub fn age_ms_since(ts: &str) -> Option<i64> {
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

// ── Synchronous tool operations (everything except the await) ───────────────
// Called from server.rs via spawn_blocking; Ok(payload) or Err(message).

pub fn op_sync(name: &str, args: &Value) -> Result<Value, String> {
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
            notify_recipient(&to);
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
            Ok(json!({"db": db_path(), "queues": rows, "awaiting": awaiting_names(),
                      "nudge": {"enabled": crate::nudge::nudge_enabled(),
                                "helper": crate::nudge::nudge_helper().map(|p| p.to_string_lossy().into_owned())}}))
        }
        "relay_audit_tail" => {
            let stream = args.get("stream").and_then(|v| v.as_str()).unwrap_or("audit").to_string();
            if stream != "audit" && stream != "access" && stream != "nudge" {
                return Err("stream must be \"audit\", \"access\", or \"nudge\"".into());
            }
            let limit = args.get("limit").and_then(|v| v.as_u64()).unwrap_or(50).clamp(1, 1000) as usize;
            let ev = tail_stream(&stream, limit);
            Ok(json!({"stream": stream, "enabled": stream_enabled(&stream),
                      "count": ev.len(), "events": ev}))
        }
        "relay_observability_set" => {
            let stream = req_str(args, "stream")?;
            if stream != "audit" && stream != "access" && stream != "nudge" {
                return Err("stream must be \"audit\", \"access\", or \"nudge\"".into());
            }
            let enabled = args.get("enabled").and_then(|v| v.as_bool())
                .ok_or("enabled must be a boolean")?;
            set_stream(&stream, enabled)?;
            Ok(json!({"stream": stream, "enabled": stream_enabled(&stream),
                      "config": cfg_path_string(),
                      "note": "an ORG_RELAY_<STREAM> env var, if set, overrides this file"}))
        }
        "relay_observability_status" => {
            let f = |s: &str| json!({"enabled": stream_enabled(s),
                "path": obs_dir().join(format!("{s}.jsonl")).to_string_lossy(),
                "bytes": std::fs::metadata(obs_dir().join(format!("{s}.jsonl"))).map(|m| m.len()).unwrap_or(0)});
            Ok(json!({"audit": f("audit"), "access": f("access"), "nudge": f("nudge"),
                      "config": cfg_path_string(),
                      "max_log_bytes": MAX_LOG_BYTES, "max_backups": MAX_BACKUPS}))
        }
        other => Err(format!("unknown tool: {other}")),
    }
}

/// The await: hold until a message lands for `agent`, a timeout passes, or the
/// caller goes away. Runs identically as an in-call hold (no tasks extension)
/// and as the future backing a task (tasks extension declared) — the
/// AwaitGuard registers the recipient as covered either way, which is what
/// suppresses the nudge watchdog.
pub async fn op_await(args: &Value) -> Result<Value, String> {
    let agent = req_str(args, "agent")?;
    let timeout_s = args
        .get("timeout_s")
        .and_then(|v| v.as_u64())
        .unwrap_or(AWAIT_DEFAULT_S)
        .clamp(1, AWAIT_MAX_S);
    let _guard = AwaitGuard::new(&agent);
    log_event("audit", json!({"event":"await_start","agent":agent,"timeout_s":timeout_s}));
    let notify = notifier_for(&agent);
    let started = Instant::now();
    let deadline = started + Duration::from_secs(timeout_s);
    loop {
        // Arm the listener BEFORE the poll so a send landing between the poll
        // and the select cannot be missed (notified() buffers one permit).
        let notified = notify.notified();
        let a = agent.clone();
        let msgs = tokio::task::spawn_blocking(move || -> Result<Vec<Value>, String> {
            let c = open_db().map_err(|e| format!("db open failed: {e}"))?;
            inbox(&c, &a, false).map_err(|e| e.to_string())
        })
        .await
        .map_err(|e| format!("await poll task failed: {e}"))??;
        if !msgs.is_empty() {
            // Wake LATENCY: how long this agent was covered, and how old the
            // oldest delivered message was.
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
        let now = Instant::now();
        if now >= deadline {
            log_event("audit", json!({"event":"await_timeout","agent":agent,
                "waited_ms":started.elapsed().as_millis() as u64,"timeout_s":timeout_s}));
            return Ok(json!({"agent": agent, "count": 0, "messages": [],
                "timed_out": true, "retry": true,
                "note": "no messages within timeout_s; re-arm one long relay_await as the last call of this turn"}));
        }
        let poll_in = std::cmp::min(deadline - now, Duration::from_secs(2));
        tokio::select! {
            _ = notified => {}
            _ = tokio::time::sleep(poll_in) => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn await_guard_registers_and_clears() {
        assert!(!awaiter_active("guard-test"));
        {
            let _g = AwaitGuard::new("guard-test");
            assert!(awaiter_active("guard-test"));
            {
                let _h = AwaitGuard::new("guard-test");
            }
            assert!(awaiter_active("guard-test"));
        }
        assert!(!awaiter_active("guard-test"));
    }

    #[test]
    fn ack_ttl_boundaries() {
        assert!(ack_valid(100, 100), "same instant valid");
        assert!(ack_valid(100, 100 + ACK_TTL_SECS), "exact TTL edge valid");
        assert!(!ack_valid(100, 101 + ACK_TTL_SECS), "past TTL invalid — fresh day re-reads");
        assert!(ack_valid(200, 100), "clock skew backwards never invalidates");
    }
}
