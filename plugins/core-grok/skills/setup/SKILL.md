---
name: setup
description: One-shot, no-prompt installer for the Grok core baseline user-scope state. Seeds ~/.grok/judge-rules.json (only if absent), writes the core guidelines into ~/.grok/AGENTS.md, stamps the version, fully disables [compat.claude] (all=false) in config.toml, pins the Skylence grok-build fork as the default CLI binary, and sets auto_update=false so official channel updates cannot overwrite the fork. Prevents any Claude harness leakage. The hooks activate from the installed plugin on trust. Invoke as /core-grok:setup on a new machine or after fresh Grok install.
---

# /core-grok:setup

Run once on a new machine. The hooks ship with the plugin and activate when the plugin is trusted and loaded; this skill writes the user-scope files they depend on, pins the Skylence grok-build fork as the default CLI, and turns off official auto-update so channel installs cannot overwrite it. Every step that overwrites makes a timestamped backup first.

All source files live under `$GROK_PLUGIN_ROOT` (Grok exposes the plugin root via this env var; `CLAUDE_PLUGIN_ROOT` is also set as alias for compatibility).

## Step 1: seed the judge rules (only if absent)

The judge-hook reads `~/.grok/judge-rules.json`. Seeding leaves an existing file untouched so local edits survive a re-run.

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
mkdir -p ~/.grok
if [ ! -f ~/.grok/judge-rules.json ]; then
  cp "$PLUGIN_ROOT/hooks/judge-rules.example.json" ~/.grok/judge-rules.json
  echo "seeded ~/.grok/judge-rules.json"
else
  echo "~/.grok/judge-rules.json already exists, left as-is"
fi
```

## Step 2: write the AGENTS.md guidelines (backup first; idempotent)

The canonical guidelines live in `$PLUGIN_ROOT/templates/agents-md.md`, fenced by `<!-- BEGIN core:guidelines -->` and `<!-- END core:guidelines -->`. This replaces a prior fenced block if present, otherwise appends one. Content outside the fences is left alone.

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
AGENTS_MD=~/.grok/AGENTS.md
TEMPLATE="$PLUGIN_ROOT/templates/agents-md.md"
touch "$AGENTS_MD"
cp "$AGENTS_MD" "$AGENTS_MD.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
awk '
  /<!-- BEGIN core:guidelines -->/ {skip=1}
  !skip {print}
  /<!-- END core:guidelines -->/ {skip=0; next}
' "$AGENTS_MD" > "$tmp"

awk '{ if (NF==0) { blanks++ } else { while (blanks>0) { print ""; blanks-- }; print } }' "$tmp" > "$AGENTS_MD"
printf '\n' >> "$AGENTS_MD"
cat "$TEMPLATE" >> "$AGENTS_MD"
rm -f "$tmp"
echo "AGENTS.md guidelines section refreshed"

# Cross-check: the installed fenced block must match the shipped example verbatim.
installed=$(awk '/<!-- BEGIN core:guidelines -->/{f=1} f{print} /<!-- END core:guidelines -->/{f=0}' "$AGENTS_MD")
if [ "$installed" = "$(cat "$TEMPLATE")" ]; then
  echo "AGENTS.md guidelines: in sync with the shipped example"
else
  echo "AGENTS.md guidelines: DRIFT vs the shipped example — re-run /core-grok:setup to refresh"
fi
```

## Step 3: stamp the installed version

```bash
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
mkdir -p ~/.grok
jq -r .version "$PLUGIN_ROOT/plugin.json" > ~/.grok/.core-grok-version
echo "stamped ~/.grok/.core-grok-version: $(cat ~/.grok/.core-grok-version)"
```

## Step 4: fully disable Claude compatibility

This prevents Grok from loading anything from the Claude harness (skills, rules, agents/CLAUDE.md, MCPs, hooks/settings). Stops core-claude plugin bleed and any .claude/ scanning.

```bash
CONFIG=~/.grok/config.toml
mkdir -p ~/.grok
if [ -f "$CONFIG" ]; then
  cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
fi

# Remove any existing [compat.claude] section (multi-line)
awk '
  /^\[compat.claude\]/ { skip=1; next }
  skip && /^\[/ { skip=0 }
  !skip { print }
' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

# Append the full disabled section
cat >> "$CONFIG" << 'EOF'

[compat.claude]
skills = false
rules = false
agents = false
mcps = false
hooks = false
EOF
echo "set full [compat.claude] disable (skills/rules/agents/mcps/hooks = false) in config.toml"

# Also ensure core-claude plugin is disabled so its skills don't leak
if ! grep -q 'core-claude' "$CONFIG" 2>/dev/null; then
  if grep -q '^\[plugins\]' "$CONFIG" 2>/dev/null; then
    cat >> "$CONFIG" << 'EOP'
disabled = [
    "core-claude",
]
EOP
  else
    cat >> "$CONFIG" << 'EOP'

[plugins]
disabled = [
    "core-claude",
]
EOP
  fi
  echo "added core-claude to [plugins] disabled"
else
  echo "core-claude plugin already disabled in config"
fi
```

## Step 5: pin Skylence fork CLI + disable official auto-update

Official `installer = "internal"` + default `auto_update = true` downloads xAI channel builds and rewrites `~/.grok/bin/grok`, wiping a hand-installed fork. Solo agents spawn bare `grok` from PATH, so that symlink is the whole fleet.

This step:
1. Sets `[cli] auto_update = false` (and leaves `installer` as-is, usually `internal`).
2. Installs the **latest** prebuilt from `jonasvanderhaegen/grok-build` (fork.2 lineage: plugin hooks at spawn + MCP progress) via the fork's install script when available, else documents the one-liner.

Skip the binary reinstall if `GROK_SETUP_SKIP_FORK_INSTALL=1` (config pin still runs).

```bash
CONFIG=~/.grok/config.toml
mkdir -p ~/.grok
if [ -f "$CONFIG" ]; then
  cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
fi
touch "$CONFIG"

# Upsert [cli] auto_update = false (do not wipe the rest of config.toml).
python3 <<'PY'
from pathlib import Path
import re
p = Path.home() / ".grok" / "config.toml"
text = p.read_text() if p.exists() else ""
if not re.search(r"^\[cli\]", text, re.M):
    text = "[cli]\nauto_update = false\ninstaller = \"internal\"\n\n" + text
else:
    def fix(m):
        block = m.group(0)
        if re.search(r"^\s*auto_update\s*=", block, re.M):
            block = re.sub(r"^(\s*auto_update\s*=\s*).*$", r"\1false", block, count=1, flags=re.M)
        else:
            block = re.sub(r"(\[cli\]\s*\n)", r"\1auto_update = false\n", block, count=1)
        return block
    text, _ = re.subn(r"\[cli\][^\[]*", fix, text, count=1)
p.write_text(text)
print("set [cli] auto_update = false in ~/.grok/config.toml")
PY

if [ "${GROK_SETUP_SKIP_FORK_INSTALL:-0}" = "1" ]; then
  echo "GROK_SETUP_SKIP_FORK_INSTALL=1 — skipped fork binary install; symlink left as-is"
else
  FORK_REPO="${GROK_RELEASE_REPO:-jonasvanderhaegen/grok-build}"
  # Prefer a local clone of the fork (has scripts/install-from-release.sh).
  FORK_ROOT=""
  for candidate in \
    "${GROK_BUILD_ROOT:-}" \
    "$HOME/Code/grok-build" \
    "$HOME/Code/jonasvanderhaegen/grok-build"; do
    if [ -n "$candidate" ] && [ -f "$candidate/scripts/install-from-release.sh" ]; then
      FORK_ROOT="$candidate"
      break
    fi
  done

  if [ -n "$FORK_ROOT" ]; then
    echo "installing fork CLI from $FORK_REPO (latest release) via $FORK_ROOT/scripts/install-from-release.sh"
    GROK_RELEASE_REPO="$FORK_REPO" bash "$FORK_ROOT/scripts/install-from-release.sh"
  elif command -v gh >/dev/null 2>&1; then
    TAG=$(gh release view --repo "$FORK_REPO" --json tagName -q .tagName)
    echo "no local fork clone; downloading tag $TAG from $FORK_REPO"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    gh release download "$TAG" --repo "$FORK_REPO" --pattern 'grok-macos-aarch64.tar.gz' --dir "$TMP"
    tar -xzf "$TMP/grok-macos-aarch64.tar.gz" -C "$TMP"
    VERSION="${TAG#v}"
    DEST="$HOME/.grok/downloads/grok-${VERSION}-macos-aarch64"
    mkdir -p "$HOME/.grok/downloads" "$HOME/.grok/bin"
    install -m 755 "$TMP/grok" "$DEST"
    ln -sfn "$DEST" "$HOME/.grok/bin/grok"
    ln -sfn "$DEST" "$HOME/.grok/bin/agent"
    ln -sfn "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok" 2>/dev/null || true
    echo "Installed fork binary: $DEST"
  else
    echo "WARN: cannot install fork binary (no clone with install-from-release.sh and no gh)."
    echo "  Install later: bash /path/to/grok-build/scripts/install-from-release.sh"
    echo "  Or: https://github.com/jonasvanderhaegen/grok-build/releases"
  fi

  # Ensure PATH-managed copies agree.
  if [ -L "$HOME/.local/bin/grok" ] || [ ! -e "$HOME/.local/bin/grok" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok"
  fi

  if command -v grok >/dev/null 2>&1; then
    echo "active grok: $(command -v grok)"
    grok --version || true
  fi
fi
```

## Step 6: summary

```
core-grok:setup
----------------------
~/.grok/judge-rules.json      seeded | existing
~/.grok/AGENTS.md             guidelines section written
~/.grok/.core-grok-version    stamped
~/.grok/config.toml           [compat.claude] all=false + core-claude disabled
~/.grok/config.toml           [cli] auto_update = false (fork stays default)
~/.grok/bin/grok              Skylence fork release (or skipped / WARN)
hooks (judge/writing/research) active from the installed plugin (requires trust)
```

Then tell the user: restart the Grok session (or reload plugins) for full effect. Solo-spawned agents use bare `grok` on PATH — they pick up the fork only after a **new** process spawn. Do not run `grok update` or the x.ai install.sh if you want to keep the fork; re-run this step or `scripts/install-from-release.sh` after cutting a new fork release. The judge-hook and research-nudge escalate via `grok -p`, so a working `grok` on PATH is required (they fail open without it).
