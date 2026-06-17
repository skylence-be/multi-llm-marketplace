#!/bin/bash
# writing-guard.sh — PostToolUse AI-tells guard for Codex. Codex port of the
# core Claude hook: flags AI writing tells (em dashes, banned vocab, canned
# phrases) in prose the agent writes to disk.
#
# ADAPTATION vs the Claude variant: Codex's PostToolUse payload shape for a
# file write is not documented as {tool_input.content}, so this tries several
# likely field paths for the written path and content and falls back to the
# whole payload. On a block it emits {decision:"block", reason:...} on stdout,
# the Codex hook convention. Fails *open* on anything unexpected.
#
# ⚠️ UNVERIFIED: the exact PostToolUse payload field names for Codex file
# writes are not confirmed. If the extraction misses, the hook simply no-ops.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '
  (.tool_input.file_path // .tool_input.path
   // .arguments.file_path // .arguments.path
   // .input.file_path // .input.path
   // .toolInput.file_path // .toolInput.path // empty)' 2>/dev/null || true)

CONTENT=$(echo "$INPUT" | jq -r '
  (.tool_input.content // .tool_input.new_string // .tool_input.text
   // .arguments.content // .arguments.new_string // .arguments.text
   // .input.content // .input.new_string
   // .toolInput.content // .toolInput.new_string // empty)' 2>/dev/null || true)

# No structured content found → nothing reliable to scan.
[ -n "$CONTENT" ] || exit 0
[ -n "$FILE_PATH" ] || FILE_PATH="(written file)"

# Skip data, config, lock, and binary files where these checks are pure noise.
case "$FILE_PATH" in
  *.json|*.jsonc|*.yaml|*.yml|*.toml|*.xml|*.csv|*.tsv|*.lock|*.lockb|*.lockfile|*.sum|*.mod|*.svg|*.map|*.min.js|*.min.css) exit 0 ;;
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.zip|*.gz|*.tar|*.docx|*.xlsx|*.pptx|*.doc|*.xls|*.ppt|*.key|*.numbers|*.pages) exit 0 ;;
esac

case "$FILE_PATH" in
  *.md|*.mdx|*.markdown|*.html|*.htm|*.txt|*.rst|*.adoc|*.tex|*.rtf) IS_PROSE=1 ;;
  *) IS_PROSE=0 ;;
esac

STRIPPED=$(echo "$CONTENT" | awk '
  /^```/ { in_code = !in_code; next }
  !in_code { print }
' | sed 's/`[^`]*`//g')

VIOLATIONS=""

EM_COUNT=$(echo "$STRIPPED" | grep -o '—' | wc -l | tr -d ' ')
if [ "$EM_COUNT" -gt 0 ]; then
  VIOLATIONS="${VIOLATIONS}- Em dashes: ${EM_COUNT} found (zero allowed)\n"
fi

if [ "$IS_PROSE" -eq 1 ]; then
  WORD_COUNT=$(echo "$STRIPPED" | wc -w | tr -d ' ')
  if [ "$WORD_COUNT" -ge 150 ]; then
    BANNED='delve|tapestry|pivotal|testament|meticulous|nuanced|multifaceted|embark|spearhead|bolster|garner|interplay|nestled|bustling|vibrant|comprehensive|invaluable|reimagine|empower|groundbreaking|transformative|paramount|myriad|cornerstone|catalyst|seamless|seamlessly'
    FOUND=$(echo "$STRIPPED" | grep -oiE "\b(${BANNED})\b" 2>/dev/null | sort -fu | tr '\n' ',' | sed 's/,$//' || true)
    [ -n "$FOUND" ] && VIOLATIONS="${VIOLATIONS}- Banned AI vocabulary: ${FOUND}\n"

    PHRASES='great question!|certainly!|absolutely!|i hope this helps|let'\''s dive in|without further ado|it'\''s worth noting that|in conclusion,|in summary,'
    FOUND_PH=$(echo "$STRIPPED" | grep -oiE "(${PHRASES})" 2>/dev/null | sort -fu | tr '\n' ' / ' | sed 's, / $,,' || true)
    [ -n "$FOUND_PH" ] && VIOLATIONS="${VIOLATIONS}- AI phrases: ${FOUND_PH}\n"
  fi
fi

[ -z "$VIOLATIONS" ] && exit 0

REASON=$(printf "Wrote to %s but content violates the Writing Guidelines (~/.codex/AGENTS.md):\n\n%b\nEdit the file to remove these tells. Do not acknowledge or apologize, just produce a corrected version." "$FILE_PATH" "$VIOLATIONS")

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
