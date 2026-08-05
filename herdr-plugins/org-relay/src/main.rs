//! org-relay 1.0: durable MCP message bus for the herdr agent-org.
//!
//! Data plane: SQLite queue (WAL), explicit consume (queue.rs). Wake plane:
//! TASK-BACKED `relay_await` — a tasks-capable client (SEP-2663,
//! io.modelcontextprotocol/tasks) gets a task handle immediately; any other
//! client holds the call in-turn, and Claude Code >= 2.1.212 auto-backgrounds
//! that hold at ~2 minutes into a native background task whose settlement
//! starts the recipient's next turn. Either way ONE long await covers a whole
//! idle period; the 0.5.x 50-second re-arm loop is retired with the
//! hand-rolled transport that required it.
//!
//! Transport: rmcp streamable HTTP behind axum (the binary-skyline stack),
//! serving POST/GET/DELETE /mcp plus a bare GET /health. Wire an agent with:
//! `claude mcp add --transport http relay http://127.0.0.1:7431/mcp`
//!
//! Guide gate: messaging tools refuse until the session reads relay://guide
//! (or calls relay_guide); strictly per-session and in-memory — every
//! session reads the short contract once (guide.rs, server.rs). Nudge
//! watchdog: the NET for recipients with backlog and no live await coverage,
//! where task-backed coverage requires tasks/get poll liveness (nudge.rs,
//! queue.rs).
//! recipients with backlog and no live await coverage (nudge.rs).

mod guide;
mod nudge;
mod queue;
mod server;

use rmcp::transport::streamable_http_server::{
    session::local::LocalSessionManager, StreamableHttpServerConfig, StreamableHttpService,
};
use std::sync::Arc;

fn build_router() -> axum::Router {
    use axum::routing::get;

    async fn health() -> &'static str {
        "ok"
    }

    // Plain-HTTP mirror of the relay_status tool for CLI and hook consumers
    // (relay-ctl status, org-stop-gate): no MCP handshake, no session, no
    // guide gate — the same never-gated diagnostics the tool exposes.
    async fn status() -> impl axum::response::IntoResponse {
        let body = tokio::task::spawn_blocking(|| {
            queue::op_sync("relay_status", &serde_json::json!({}))
                .unwrap_or_else(|e| serde_json::json!({"error": e}))
                .to_string()
        })
        .await
        .unwrap_or_else(|e| format!("{{\"error\":\"{e}\"}}"));
        ([(axum::http::header::CONTENT_TYPE, "application/json")], body)
    }
    let session_manager = Arc::new(LocalSessionManager::default());
    let service: StreamableHttpService<server::RelayServer, LocalSessionManager> =
        StreamableHttpService::new(
            || Ok(server::RelayServer::new()),
            session_manager,
            StreamableHttpServerConfig::default(),
        );

    axum::Router::new()
        .nest_service("/mcp", service)
        .route("/health", get(health))
        .route("/status", get(status))
        .layer(tower_http::limit::RequestBodyLimitLayer::new(1024 * 1024))
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    #[cfg(unix)]
    let terminate = async {
        if let Ok(mut s) = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            s.recv().await;
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();
    tokio::select! {
        _ = ctrl_c => {}
        _ = terminate => {}
    }
}

#[tokio::main]
async fn main() {
    let port = std::env::var("ORG_RELAY_PORT").ok().and_then(|p| p.parse::<u16>().ok()).unwrap_or(7431);
    if let Err(e) = queue::open_db() {
        eprintln!("org-relay: cannot open {}: {e}", queue::db_path());
        std::process::exit(1);
    }
    let addr = format!("127.0.0.1:{port}");
    let listener = match tokio::net::TcpListener::bind(&addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("org-relay: bind {addr} failed (already running?): {e}");
            std::process::exit(1);
        }
    };
    eprintln!("org-relay: serving MCP on http://{addr}/mcp  (db: {})", queue::db_path());
    if !nudge::nudge_enabled() {
        eprintln!("org-relay: nudge watchdog OFF (ORG_RELAY_NUDGE)");
    } else if let Some(h) = nudge::nudge_helper() {
        eprintln!(
            "org-relay: nudge watchdog on (poll {}s, grace {}s, cooldown {}s, helper {})",
            queue::NUDGE_POLL_S,
            queue::NUDGE_GRACE_S,
            queue::NUDGE_COOLDOWN_S,
            h.display()
        );
        nudge::spawn_nudge_watchdog(h);
    } else {
        eprintln!("org-relay: nudge watchdog OFF — helper nudge-deliver not found beside the crate (set ORG_RELAY_NUDGE_HELPER)");
    }

    // Retention: consumed rows are history the audit stream already carries.
    // Daily prune, ORG_RELAY_RETAIN_DAYS (default 7, 0 disables).
    let retain_days = std::env::var("ORG_RELAY_RETAIN_DAYS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(7);
    if retain_days > 0 {
        std::thread::spawn(move || loop {
            match queue::prune_consumed(retain_days) {
                Ok(n) if n > 0 => queue::log_event(
                    "audit",
                    serde_json::json!({"event":"prune","deleted":n,"retain_days":retain_days}),
                ),
                Ok(_) => {}
                Err(e) => queue::log_event(
                    "audit",
                    serde_json::json!({"event":"prune-error","error":e}),
                ),
            }
            std::thread::sleep(std::time::Duration::from_secs(86_400));
        });
    }

    if let Err(e) = axum::serve(listener, build_router())
        .with_graceful_shutdown(shutdown_signal())
        .await
    {
        eprintln!("org-relay: server error: {e}");
        std::process::exit(1);
    }
}
