# soloterm-agent-org-codex

Codex-native companion to the Claude Code `soloterm-agent-org` plugin.

This package is the Codex side of the Solo-orchestrated agent org and includes every shared `agent-org` skill from the Claude package, plus the Codex worker variant:

- `skills/orchestrator/` — shared Claude `agent-org` orchestrator skill, copied into the Codex package for install compatibility.
- `skills/planner/` — shared Claude `agent-org` planner skill (strongest-model max-effort program planning), copied into the Codex package for install compatibility.
- `skills/capacity-check/` — shared spawn-gate skill (capacity-probe RAM verdicts), copied into the Codex package for install compatibility.
- `skills/replacer/` — shared Claude `agent-org` replacer skill, copied into the Codex package for install compatibility.
- `skills/org-audit/` — shared Claude `agent-org` org-audit skill, copied into the Codex package for install compatibility.
- `skills/solo-worker/` — Codex worker conduct skill for todo-body briefs, milestone reporting, the no-compile law (the orchestrator owns the gate build), shared branches, and incident handling.
- `AGENTS.md` — portable global Codex agent guidance.
- `rules/org.rules` — execpolicy snippets for the nextest ban and build-slot law.
- `scripts/build-slot` — machine-wide compile serializer.
- `scripts/ghost-probe.sh` — helper for distinguishing rendered Claude suggestion ghosts from real operator typing in Solo PTYs.
- `scripts/capacity-probe.sh` — macOS RAM probe: `VERDICT=GREEN|YELLOW|RED` spawn verdicts, exit code 0/1/2 (3 = non-macOS).
- `hooks/hooks.json` — Codex lifecycle hooks: `SessionStart` agent-org steering and `PreToolUse` Bash checks for nextest/build-slot violations.

The source skills live in `plugins/soloterm-agent-org/`; these files are copied into the Codex package because Codex's GitHub plugin installer does not currently preserve symlinked skill directories into the installed plugin cache. Hook behavior is implemented against Codex lifecycle events and goes through Codex hook trust review.

Install from the repo-local Codex marketplace:

```sh
codex plugin marketplace add /Users/jv/Code/skylence/marketplaces/multi-llm-marketplace/.agents/plugins
codex plugin add soloterm-agent-org-codex@multi-llm-marketplace
```
