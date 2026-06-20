// friction-nudge.js — debounced friction reporter (tracks skylence-be/skyline#6).
// Cross-platform (Windows/macOS/Linux) port of friction-nudge.sh — invoked as
// `node friction-nudge.js` so it needs no shell and no bash on PATH.
//
// After the agent stops calling skyline tools for IDLE seconds (it has "stopped
// typing"), if new friction has been recorded since the last nudge, emit ONE
// line asking the agent to file it. Fires once per friction cluster, never
// mid-flow, never per event. Each stdout line is delivered to the agent as a
// notification by the monitor harness (same channel as daemon-watchdog.js).
//
// INERT BY DESIGN when the observability streams are off (the default): if the
// log files do not exist it simply never fires. Power it on with
//   skyline observability set --devlog on --audit on
// Tune the debounce window with SKYLINE_FRICTION_IDLE_SECS; point at a
// non-default data dir with SKYLINE_DATA_DIR.

const fs = require("fs");
const os = require("os");
const path = require("path");

// Resolve skyline's cache dir per-OS (a wrong guess just stays inert, since the
// monitor never fires when the log files are absent).
function defaultDataDir() {
  const home = os.homedir();
  if (process.platform === "darwin") {
    return path.join(home, "Library", "Caches", "skyline");
  }
  if (process.platform === "win32") {
    return path.join(process.env.LOCALAPPDATA || path.join(home, "AppData", "Local"), "skyline");
  }
  return path.join(process.env.XDG_CACHE_HOME || path.join(home, ".cache"), "skyline");
}

const DATA = process.env.SKYLINE_DATA_DIR || defaultDataDir();
const AUDIT = path.join(DATA, "logs", "audit.jsonl");
const DEVLOG = path.join(DATA, "logs", "devlog.jsonl");
const IDLE = parseInt(process.env.SKYLINE_FRICTION_IDLE_SECS || "45", 10) || 45;
const STATE = path.join(os.tmpdir(), "skyline-friction-nudge.state");

const FRICTION_RE = /"level":"(warn|error)"|guide-gate|stale[- ]?tag|reject|fallback/i;

function readLines(file) {
  try {
    return fs.readFileSync(file, "utf8").split("\n");
  } catch {
    return [];
  }
}

// Count of friction-flavored devlog records across the live log and its backup.
function frictionCount() {
  let n = 0;
  for (const line of [...readLines(DEVLOG), ...readLines(DEVLOG + ".1")]) {
    if (FRICTION_RE.test(line)) n++;
  }
  return n;
}

// Most recent activity timestamp across both streams (epoch seconds), or null.
function lastTs() {
  let max = null;
  const text = (safeRead(AUDIT) + "\n" + safeRead(DEVLOG));
  const re = /"ts":(\d+)/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const v = parseInt(m[1], 10);
    if (max === null || v > max) max = v;
  }
  return max;
}

function safeRead(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}

function readState() {
  const v = parseInt(safeRead(STATE).trim(), 10);
  return Number.isInteger(v) ? v : 0;
}

function tick() {
  if (!fs.existsSync(AUDIT) && !fs.existsSync(DEVLOG)) return;

  const lt = lastTs();
  if (lt === null) return;
  const now = Math.floor(Date.now() / 1000);
  // Still active (the agent is "typing") — wait for the idle window to pass.
  if (now - lt < IDLE) return;

  const fc = frictionCount();
  const prev = readState();

  if (fc > prev) {
    const fresh = fc - prev;
    process.stdout.write(
      `${fresh} new skyline friction event(s) recorded since the last check (devlog warnings/errors: stale-tag rejections, guide-gate blocks, shell fallbacks). If any is a real defect, file it with skyline_report_issue after searching open AND closed issues; comment new evidence on a match instead of opening a duplicate.\n`
    );
    try { fs.writeFileSync(STATE, String(fc)); } catch {}
  } else if (fc < prev) {
    // Log rotated or cleared; resync the baseline downward without nudging.
    try { fs.writeFileSync(STATE, String(fc)); } catch {}
  }
}

setInterval(tick, 15000);
