# skyline-antigravity

Wires the [skyline](https://github.com/skylence-be) MCP daemon into **Google
Antigravity**: one HTTP MCP server plus a `PreToolUse` enforcement hook that
steers sessions toward skyline-first tooling while the daemon is running.

This plugin is the Antigravity sibling of `skyline-claude` (Claude Code) and
`skyline-codex` (Codex). The manifest, MCP config, hooks, and skills have been
shaped to Antigravity's real plugin format (verified against live Antigravity
documentation).

## What it does

- Registers a single HTTP MCP server, `skyline`, pointing at the local skyline
  daemon (`http://127.0.0.1:7333/mcp`).
- Installs a `PreToolUse` enforcement hook. When the daemon is up, native
  shell/read/edit tool calls are **denied** with a message redirecting the
  agent to the corresponding `skyline_*` MCP tools. When the daemon is
  unreachable (or `curl` is missing) the hook **fails open** — it returns
  `{"decision":"allow"}` so the agent is never blocked.
- Ships `upgrade` and `uninstall` skills that drive the skyline binary/daemon
  lifecycle.

## The daemon dependency

This plugin does nothing useful on its own — it assumes the skyline daemon and
the global `@skylence-ai/skyline` npm package are installed.

- **Daemon endpoint:** `http://127.0.0.1:7333/mcp` (HTTP MCP). Port `7333` is
  fixed and shared with the Claude/Codex variants.
- **Lifecycle:** `skyline daemon install|restart|stop|uninstall --port 7333`.
- **Package:** `@skylence-ai/skyline`, installed globally (npm/pnpm/yarn/bun).
- **Update:** `skyline update --yes`.

These values are preserved **exactly** from the `skyline-claude` /
`skyline-codex` plugins.

## Install / config layout

Antigravity plugins load from a per-user or per-workspace plugin directory:

- **Global scope:** `~/.gemini/antigravity-cli/plugins/<name>/`.
- **Workspace scope:** `<project-root>/.agents/plugins/<name>/`.

The plugin marker (`plugin.json`), MCP config (`mcp_config.json`), and hooks
config (`hooks.json`) all live at the **plugin root**. Skills live in
`skills/<name>/SKILL.md`.

Install via the CLI or the IDE:

- **CLI:** `agy plugin install skyline-antigravity` (or
  `agy plugin import <source>`). Other verbs: `agy plugin uninstall <name>`,
  `agy plugin enable|disable|validate|list`. There is **no** `agy plugin
  upgrade` verb — reinstall to refresh.
- **IDE:** `/plugin install`.

## File tree

```
plugins/skyline-antigravity/
├── plugin.json              # plugin manifest / marker (mcpServers -> ./mcp_config.json)
├── mcp_config.json          # HTTP MCP server "skyline" -> 127.0.0.1:7333/mcp
├── hooks.json               # PreToolUse matchers -> hooks/skyline-enforce.sh
├── hooks/
│   └── skyline-enforce.sh   # daemon health check + allow/deny JSON on STDOUT
├── scripts/
│   └── uninstall.sh         # bundled full-uninstall flow
├── skills/
│   ├── upgrade/SKILL.md
│   └── uninstall/SKILL.md
└── README.md
```

## Hook contract (how this differs from Claude/Codex)

Claude and Codex enforcement hooks signal a block via **exit code 2 + stderr**.
Antigravity hooks instead receive the pending tool-call JSON on **STDIN**
(camelCase payload: `toolCall.name`, `toolCall.args`, `workspacePaths`,
`transcriptPath`) and must **print a JSON object on STDOUT** with a
`"decision"` field:

- `{"decision":"allow"}` — let the native tool run (used on fail-open and for
  unknown modes).
- `{"decision":"deny","reason":"..."}` — block and surface the reason. We use
  `deny` (not `ask`) to match the existing enforcement intent of the
  Claude/Codex variants: redirection should be automatic, not a prompt.

`hooks.json` lives at the plugin root and resolves the plugin directory via
`CLAUDE_PLUGIN_ROOT` (the env var Antigravity exposes to hook commands), with
`ANTIGRAVITY_PLUGIN_ROOT` / `GEMINI_PLUGIN_ROOT` as fallbacks. The matchers map
Antigravity's native tool names to enforce.sh modes:

- `run_command` → mode `bash`
- `view_file` → mode `read`
- `write_to_file|replace_file_content|multi_replace_file_content` → mode `edit`

`skyline-enforce.sh` is POSIX `sh`, executable, drains STDIN for contract
compliance, performs the same `curl -s -m 1 http://127.0.0.1:7333/mcp` health
check as the other variants, and fails open on any uncertainty.

## Confirmed against live Antigravity docs

The following were previously assumptions and are now confirmed:

- **Root-level layout.** `plugin.json`, `mcp_config.json`, and `hooks.json` all
  live at the plugin root. Skills in `skills/<name>/SKILL.md`. Plugins load from
  `~/.gemini/antigravity-cli/plugins/<name>/` or workspace `.agents/plugins/`.
- **Hook deny contract.** stdout `{"decision":"deny","reason":"..."}`; also
  `"allow"` / `"ask"`. The STDIN payload is camelCase (`toolCall.name`,
  `toolCall.args`, `workspacePaths`, `transcriptPath`).
- **Native tool names** for the matchers: shell = `run_command`; read =
  `view_file`; edit/write = `write_to_file`, `replace_file_content`,
  `multi_replace_file_content`.
- **Hook plugin-root env var:** `CLAUDE_PLUGIN_ROOT` (kept
  `ANTIGRAVITY_PLUGIN_ROOT` / `GEMINI_PLUGIN_ROOT` as fallbacks).
- **CLI:** the binary is `agy`; plugin verbs are
  `install | uninstall <name> | import <source> | enable | disable | validate |
  list`. There is **no** `upgrade` verb.

## ⚠️ Still needs verification

1. **Native tool names for search interception.** Antigravity's native
   grep/find/glob tool names are **not documented**, so search calls are **not
   intercepted** by this plugin. Only `run_command`, `view_file`, and the
   write/edit tools are matched. (The shell `run_command` hook still steers
   agents toward `skyline_grep` / `skyline_find` / `skyline_tree` for shell-
   driven search.) TODO: add search matchers once the names are documented.

2. **`plugin.json` `mcpServers` pointer shape.** We keep
   `"mcpServers": "./mcp_config.json"`, but whether that exact field/shape is
   the accepted form is unconfirmed — `mcp_config.json` may be auto-discovered
   at the plugin root regardless of the pointer. TODO: confirm.

3. **Marketplace / distribution wiring — RESOLVED.** Registered in the repo's
   `.agents/plugins/marketplace.json` (the Antigravity/Codex marketplace
   manifest) as a `local` source at `./plugins/skyline-antigravity`, alongside
   `skyline-codex`. The Claude-only `.claude-plugin/marketplace.json`
   intentionally still lists `skyline-claude` only.
