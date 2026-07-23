# core-grok

Grok-native port of the Skylence core baseline.

Installs opinionated safety and quality guardrails that work with Grok's native hook and skill system.

## What it ships

- `hooks/hooks.json` + `hooks/judge-hook.sh` — PreToolUse rules engine. Denies or escalates dangerous operations using `~/.grok/judge-rules.json`. Escalate uses `grok -p` headless with tools restricted.
- `hooks/writing-guard.sh` — PreToolUse guard that blocks writes containing em-dashes, banned AI-tells vocabulary, and filler phrases in prose files (>150 words).
- `hooks/research-nudge.sh` — Stop hook that detects hedged factual claims in the last assistant turn and requests a verification step (best-effort; Grok Stop is passive).
- `hooks/judge-rules.example.json` — the shared Skylence safety ruleset.
- `skills/setup/` — `/core-grok:setup` seeds the rules file, writes the guidelines block, and stamps the version.
- `skills/doctor/` — `/core-grok:doctor` performs a read-only audit of judge-rules, AGENTS.md, version stamp, and hook notes.
- `templates/agents-md.md` — the canonical Advisor/Decisive/Coding/Review/Writing guidelines (compaction-surviving fenced block), including Grok worker/subagent effort: default medium, high only when complexity warrants it.
- `plugin.json` — Grok plugin manifest.

## Install (after adding the marketplace)

```bash
grok plugin marketplace add skylence-be/multi-llm-marketplace
grok plugin marketplace update multi-llm-marketplace
grok plugin install core-grok@skylence-be/multi-llm-marketplace --trust
```

Then run the setup skill:

```
/core-grok:setup
```

Or from CLI: `grok -p "/core-grok:setup" --always-approve`

## Notes on compatibility

- Hook commands must use exact `${GROK_PLUGIN_ROOT}/hooks/...` (load-time substitution). Nested forms like `${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}` expand empty against process env and leave hooks fail-open — do not reintroduce them.
- Judge also matches `skyline_run` so shell still goes through the rules engine when skyline-grok redirects bash.
- Writes user guidelines to `~/.grok/AGENTS.md` (Grok scans `~/.grok/` and project `AGENTS.md`).
- Hook contract matches Grok's documented stdin JSON (`toolName`/`toolInput`) + stdout decision JSON.
- The judge and nudge call back into `grok` headless for LLM verdicts at `--effort medium`; the inner call disables side-effect tools to reduce recursion risk.
- Guidelines tell agents to spawn Grok workers/subagents at medium effort by default (high only on judged complexity) — same policy as soloterm-agent-org.

## Verification

After setup:
- `ls ~/.grok/judge-rules.json ~/.grok/AGENTS.md ~/.grok/.core-grok-version`
- `grok plugin list` should show core-grok
- `grok inspect` should list skills/hooks from the plugin
- Run `/core-grok:doctor` for a full read-only audit (judge-rules, guidelines, version, hook notes)

Re-run `/core-grok:setup` safely — it only seeds when absent and replaces the fenced block.

Run `/core-grok:doctor` any time you want to audit the install (especially after updates or if hooks seem inactive).
