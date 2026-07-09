# core-grok

Grok-native port of the Skylence core baseline.

Installs opinionated safety and quality guardrails that work with Grok's native hook and skill system.

## What it ships

- `hooks/hooks.json` + `hooks/judge-hook.sh` — PreToolUse rules engine. Denies or escalates dangerous operations using `~/.grok/judge-rules.json`. Escalate uses `grok -p` headless with tools restricted.
- `hooks/writing-guard.sh` — PreToolUse guard that blocks writes containing em-dashes, banned AI-tells vocabulary, and filler phrases in prose files (>150 words).
- `hooks/research-nudge.sh` — Stop hook that detects hedged factual claims in the last assistant turn and requests a verification step (best-effort; Grok Stop is passive).
- `hooks/judge-rules.example.json` — the shared Skylence safety ruleset.
- `skills/setup/` — `/core-grok:setup` seeds the rules file and writes the guidelines block.
- `templates/agents-md.md` — the canonical Advisor/Decisive/Coding/Review/Writing guidelines (compaction-surviving fenced block).
- `plugin.json` — Grok plugin manifest.

## Install (after adding the marketplace)

```bash
grok plugin marketplace add skylence-be/multi-llm-marketplace
grok plugin install core-grok@multi-llm-marketplace --trust
```

Then run the setup skill:

```
/core-grok:setup
```

Or from CLI: `grok -p "/core-grok:setup" --always-approve`

## Notes on compatibility

- Uses `GROK_PLUGIN_ROOT` with `CLAUDE_PLUGIN_ROOT` fallback so the same plugin files are robust.
- Writes user guidelines to `~/.grok/AGENTS.md` (Grok scans `~/.grok/` and project `AGENTS.md`).
- Hook contract matches Grok's documented stdin JSON (`toolName`/`toolInput`) + stdout decision JSON.
- The judge and nudge call back into `grok` headless for LLM verdicts; the inner call disables side-effect tools to reduce recursion risk.

## Verification

After setup:
- `ls ~/.grok/judge-rules.json ~/.grok/AGENTS.md`
- `grok plugin list` should show core-grok
- `grok inspect` should list the hooks under plugin: core-grok

Re-run `/core-grok:setup` safely — it only seeds when absent and replaces the fenced block.
