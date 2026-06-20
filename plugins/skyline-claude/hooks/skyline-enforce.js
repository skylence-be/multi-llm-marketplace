// PreToolUse enforcement: redirect native tools to skyline equivalents.
// Cross-platform (Windows/macOS/Linux) port of skyline-enforce.sh — invoked as
// `node skyline-enforce.js <mode>` so it needs no shell and no bash on PATH.
// Fail-open (exit 0) when the daemon is not running — never breaks the agent.

const http = require("http");

const MODE = process.argv[2] || "";

const CORE =
  "select:mcp__plugin_skyline-claude_skyline__skyline_read," +
  "mcp__plugin_skyline-claude_skyline__skyline_edit," +
  "mcp__plugin_skyline-claude_skyline__skyline_create," +
  "mcp__plugin_skyline-claude_skyline__skyline_grep," +
  "mcp__plugin_skyline-claude_skyline__skyline_tree," +
  "mcp__plugin_skyline-claude_skyline__skyline_find," +
  "mcp__plugin_skyline-claude_skyline__skyline_git," +
  "mcp__plugin_skyline-claude_skyline__skyline_run";

const SWITCH_ORIENT = `Skyline is active. Switch to skyline tools for this session: run ToolSearch("${CORE}") then retry.`;
const SWITCH_EDIT = `Skyline is active. Switch to skyline tools for this session: run ToolSearch("${CORE}") then skyline_guide, then retry.`;

const MESSAGES = {
  read: `skyline_read replaces Read. ${SWITCH_ORIENT}`,
  edit: `skyline_edit/skyline_create replace Edit/Write. ${SWITCH_EDIT}`,
  grep: `skyline_grep/skyline_sgrep replace Grep. ${SWITCH_ORIENT}`,
  glob: `skyline_find/skyline_tree replace Glob. ${SWITCH_ORIENT}`,
  bash: `skyline_grep/skyline_find/skyline_git/skyline_run/skyline_test replace Bash. ${SWITCH_EDIT}`,
};

// Fail open unless we positively reach the daemon AND have a message for the mode.
function enforce() {
  const msg = MESSAGES[MODE];
  if (!msg) process.exit(0);
  process.stderr.write(msg + "\n");
  process.exit(2);
}

const req = http.get(
  { host: "127.0.0.1", port: 7333, path: "/mcp", timeout: 1000 },
  (res) => {
    res.resume(); // drain and discard; any response means the daemon is up
    enforce();
  }
);
req.on("timeout", () => req.destroy());
req.on("error", () => process.exit(0)); // daemon down / unreachable -> fail open
