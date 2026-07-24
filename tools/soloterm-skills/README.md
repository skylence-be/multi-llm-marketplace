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

## Enforcement

`--check` is wired in two places so it does not depend on anyone remembering:

- **`.githooks/pre-commit`**: fast checks only (drift, plus shell and JSON
  syntax on staged files). Install once per clone:
  `git config core.hooksPath .githooks`. Bypass deliberately with
  `git commit --no-verify`. `.git/hooks` is not version controlled, which is
  why the hook lives in a tracked directory and is wired through
  `core.hooksPath`.
- **`.github/workflows/checks.yml`**: the same drift check plus a
  regenerate-and-`git diff --exit-code` idempotency proof, and the judge-hook
  suite on macOS.

The suite runs on macOS on purpose: it is only ever verified on the platform it
ships to, and it leans on BSD/GNU fallbacks (`stat -f` vs `-c`, `base64 -D` vs
`-d`) that have never been exercised on Linux. A green ubuntu run would be
testing a configuration nobody uses.
