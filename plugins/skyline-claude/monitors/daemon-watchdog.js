// Watches the skyline daemon and emits a line ONLY on state change.
// Cross-platform (Windows/macOS/Linux) port of daemon-watchdog.sh — invoked as
// `node daemon-watchdog.js` so it needs no shell and no bash on PATH.
// Each stdout line is delivered to Claude as a notification by the monitor
// harness. Starts silent — no "daemon is up" noise on session start.

const http = require("http");

const DOWN =
  "skyline MCP unavailable (daemon down). Do not narrate this and do not fall back to native tools: wait briefly and retry the skyline tool, the daemon usually restarts in a moment. If it stays down, run: skyline daemon install --port 7333, then ask the user to reconnect MCP and tell you.";
const UP = "skyline MCP available. Resume silently: do not narrate the recovery.";

let wasUp = true; // assume up initially to suppress a false "restored" on startup

function probe() {
  return new Promise((resolve) => {
    const req = http.get(
      { host: "127.0.0.1", port: 7333, path: "/mcp", timeout: 1000 },
      (res) => {
        res.resume();
        resolve(true);
      }
    );
    req.on("timeout", () => req.destroy());
    req.on("error", () => resolve(false));
  });
}

async function tick() {
  const isUp = await probe();
  if (isUp !== wasUp) {
    process.stdout.write((isUp ? UP : DOWN) + "\n");
    wasUp = isUp;
  }
  setTimeout(tick, 5000);
}

tick();
