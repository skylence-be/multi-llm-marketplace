# soloterm-skills

One source of truth for the five agent-org role skills that ship in all four
`soloterm-agent-org*` plugins (marketplace#11).

```
src/<skill>/SKILL.md   the only hand-edited copy
sync-skills.py         materializes plugins/<variant>/skills/<skill>/SKILL.md
```

**Edit doctrine:**

```bash
$EDITOR tools/soloterm-skills/src/orchestrator/SKILL.md
python3 tools/soloterm-skills/sync-skills.py
git add tools/soloterm-skills plugins
```

**Verify (exits 1 on drift, with a diff):**

```bash
python3 tools/soloterm-skills/sync-skills.py --check
```

The generated copies are committed on purpose. Claude Code, Codex, Grok and
Antigravity all install a plugin directory as-is with no build step, so each
variant has to stay self-contained and installable on its own.

Never hand-edit `plugins/soloterm-agent-org*/skills/*/SKILL.md`: sync overwrites
it, and `--check` fails as soon as it differs. Variant-specific wording goes in
the `OVERLAYS` table at the top of `sync-skills.py`, not in a forked copy. The
script header documents both.
