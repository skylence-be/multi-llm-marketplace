#!/bin/bash
# writing-guard.sh — Pre/PostToolUse guard that flags AI writing tells in NEWLY
# WRITTEN content (dual compatible for Claude Code + Grok).
#
# Content extraction supports Claude (tool_input) and Grok (toolInput / toolName).
# Decision: Claude "block" JSON (or exit), Grok "deny" JSON.
# Guidelines reference is generic; policy is the same.
#
# Em-dash policy: at most one per 500 words in prose (min 1); zero in code.
# Vocab/phrase scans on prose >=150 words. WRITING_GUARD_EXEMPT_RE to skip paths.
# Fails open.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"decision":"allow"}\n'; exit 0; }
INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

# Detect Grok vs Claude input shape
IS_GROK=false
if printf '%s' "$INPUT" | grep -qE '"toolName"|"hookEventName"|"sessionId"'; then
  IS_GROK=true
fi

# Parse file + new content. Grok uses toolInput.*, Claude tool_input.*
if $IS_GROK; then
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.toolInput.file_path // .toolInput.path // .toolInput.filePath // .toolInput.TargetFile // .toolInput.target_file // empty' 2>/dev/null || true)
  CONTENT=$(printf '%s' "$INPUT" | jq -r '.toolInput.new_string // .toolInput.content // .toolInput.CodeContent // .toolInput.replacement // .toolInput.ReplacementContent // .toolInput.text // empty' 2>/dev/null || true)
else
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
  CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || true)
fi

# skyline_edit support (Claude skyline or equivalent)
if [ -z "$CONTENT" ]; then
  PATCH=$(printf '%s' "$INPUT" | jq -r '.toolInput.patch // .tool_input.patch // empty' 2>/dev/null || true)
  if [ -n "$PATCH" ]; then
    [ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s\n' "$PATCH" | sed -n 's/^¶\([^#]*\)#.*/\1/p' | head -1)
    CONTENT=$(printf '%s\n' "$PATCH" | sed -n 's/^+//p')
  fi
fi

[ -z "$FILE_PATH" ] && exit 0
[ -z "$CONTENT" ] && exit 0

if [ -n "${WRITING_GUARD_EXEMPT_RE:-}" ]; then
  printf '%s' "$FILE_PATH" | grep -qE -- "$WRITING_GUARD_EXEMPT_RE" 2>/dev/null && exit 0
fi

# Skip data/config/lock/binary
case "$FILE_PATH" in
  *.json|*.jsonc|*.yaml|*.yml|*.toml|*.xml|*.csv|*.tsv|*.lock|*.lockb|*.lockfile|*.sum|*.mod|*.svg|*.map|*.min.js|*.min.css) exit 0 ;;
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.zip|*.gz|*.tar|*.docx|*.xlsx|*.pptx|*.doc|*.xls|*.ppt|*.key|*.numbers|*.pages) exit 0 ;;
esac

case "$FILE_PATH" in
  *.md|*.mdx|*.markdown|*.html|*.htm|*.txt|*.rst|*.adoc|*.tex|*.rtf) IS_PROSE=1 ;;
  *) IS_PROSE=0 ;;
esac

STRIPPED=$(printf '%s\n' "$CONTENT" | awk '
  /^```/ { in_code = !in_code; next }
  !in_code { print }
' | sed 's/`[^`]*`//g')

VIOLATIONS=""

WORD_COUNT=$(printf '%s\n' "$STRIPPED" | wc -w | tr -d ' ')
EM_COUNT=$(printf '%s\n' "$STRIPPED" | grep -o '—' | wc -l | tr -d ' ')
if [ "$IS_PROSE" -eq 1 ]; then
  EM_ALLOWED=$((WORD_COUNT / 500))
  [ "$EM_ALLOWED" -lt 1 ] && EM_ALLOWED=1
else
  EM_ALLOWED=0
fi
if [ "$EM_COUNT" -gt "$EM_ALLOWED" ]; then
  VIOLATIONS="${VIOLATIONS}- Em dashes: ${EM_COUNT} in ${WORD_COUNT} new words (allowed ${EM_ALLOWED}; policy: max 1 per 500 words in prose, 0 in code)\n"
fi

if [ "$IS_PROSE" -eq 1 ] && [ "$WORD_COUNT" -ge 150 ]; then
  BANNED='delve|tapestry|pivotal|testament|meticulous|nuanced|multifaceted|embark|spearhead|bolster|garner|interplay|nestled|bustling|vibrant|comprehensive|invaluable|reimagine|empower|groundbreaking|transformative|paramount|myriad|cornerstone|catalyst|seamless|seamlessly'
  FOUND=$(printf '%s\n' "$STRIPPED" | grep -oiE "\b(${BANNED})\b" 2>/dev/null | sort -fu | tr '\n' ',' | sed 's/,$//' || true)
  [ -n "$FOUND" ] && VIOLATIONS="${VIOLATIONS}- Banned AI vocabulary: ${FOUND}\n"

  PHRASES='great question!|certainly!|absolutely!|i hope this helps|let'\''s dive in|without further ado|it'\''s worth noting that|in conclusion,|in summary,'
  FOUND_PH=$(printf '%s\n' "$STRIPPED" | grep -oiE "(${PHRASES})" 2>/dev/null | sort -fu | tr '\n' ' / ' | sed 's, / $,,' || true)
  [ -n "$FOUND_PH" ] && VIOLATIONS="${VIOLATIONS}- AI phrases: ${FOUND_PH}\n"
fi

[ -z "$VIOLATIONS" ] && { $IS_GROK && printf '{"decision":"allow"}\n' || true; exit 0; }

GUIDE_REF="your guidelines (CLAUDE.md / AGENTS.md)"
REASON=$(printf "New content written to %s violates ## Writing Guidelines (%s):\n\n%b\nEdit the file to remove these tells from the text you just added. Do not acknowledge or apologize, just produce a corrected version." "$FILE_PATH" "$GUIDE_REF" "$VIOLATIONS")

if $IS_GROK; then
  # Grok PreToolUse expects decision deny on stdout, exit 0
  jq -n --arg r "$REASON" '{decision:"deny",reason:$r}'
else
  jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
fi
