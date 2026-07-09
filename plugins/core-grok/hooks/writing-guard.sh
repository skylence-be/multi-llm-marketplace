#!/usr/bin/env sh
# writing-guard.sh — AI-tells guard for Grok, run as PreToolUse on edit/write tools.
# Inspects content BEFORE write and denies with corrective reason when tells present.
# Fails open. Uses printf never echo.
#
# Matches Grok tool names (search_replace) and common aliases.
# Extracts from toolInput (Grok) or legacy shapes.

allow() { printf '{"decision":"allow"}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || allow
INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || allow

# Extract file path and content from Grok's toolInput or fallback shapes
FILE_PATH=$(printf '%s\n' "$INPUT" | jq -r '
  (.toolInput.file_path // .toolInput.path // .toolInput.filePath // .toolInput.TargetFile
   // .toolInput.target_file // .args.file_path // .toolCall.args.file_path // empty)' 2>/dev/null || true)

CONTENT=$(printf '%s\n' "$INPUT" | jq -r '
  (.toolInput.new_string // .toolInput.content // .toolInput.CodeContent
   // .toolInput.replacement // .toolInput.ReplacementContent
   // .toolInput.text // .args.new_string // .args.content // empty)' 2>/dev/null || true)

[ -n "$CONTENT" ] || allow
[ -n "$FILE_PATH" ] || FILE_PATH="(written file)"

# Skip binary/config formats
case "$FILE_PATH" in
  *.json|*.jsonc|*.yaml|*.yml|*.toml|*.xml|*.csv|*.tsv|*.lock|*.lockb|*.lockfile|*.sum|*.mod|*.svg|*.map|*.min.js|*.min.css) allow ;;
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.zip|*.gz|*.tar|*.docx|*.xlsx|*.pptx|*.doc|*.xls|*.ppt|*.key|*.numbers|*.pages) allow ;;
esac

case "$FILE_PATH" in
  *.md|*.mdx|*.markdown|*.html|*.htm|*.txt|*.rst|*.adoc|*.tex|*.rtf) IS_PROSE=1 ;;
  *) IS_PROSE=0 ;;
esac

# Strip code fences and inline code for tell detection
STRIPPED=$(printf '%s\n' "$CONTENT" | awk '
  /^```/ { in_code = !in_code; next }
  !in_code { print }
' | sed 's/`[^`]*`//g')

VIOLATIONS=""
EM_COUNT=$(printf '%s\n' "$STRIPPED" | grep -o '—' | wc -l | tr -d ' ')
if [ "$EM_COUNT" -gt 0 ]; then
  VIOLATIONS="${VIOLATIONS}- Em dashes: ${EM_COUNT} found (zero allowed per guidelines)\n"
fi

if [ "$IS_PROSE" -eq 1 ]; then
  WORD_COUNT=$(printf '%s\n' "$STRIPPED" | wc -w | tr -d ' ')
  if [ "$WORD_COUNT" -ge 150 ]; then
    BANNED='delve|tapestry|pivotal|testament|meticulous|nuanced|multifaceted|embark|spearhead|bolster|garner|interplay|nestled|bustling|vibrant|comprehensive|invaluable|reimagine|empower|groundbreaking|transformative|paramount|myriad|cornerstone|catalyst|seamless|seamlessly'
    FOUND=$(printf '%s\n' "$STRIPPED" | grep -oiE "\b(${BANNED})\b" 2>/dev/null | sort -fu | tr '\n' ',' | sed 's/,$//' || true)
    [ -n "$FOUND" ] && VIOLATIONS="${VIOLATIONS}- Banned AI vocabulary: ${FOUND}\n"

    PHRASES='great question!|certainly!|absolutely!|i hope this helps|let'\''s dive in|without further ado|it'\''s worth noting that|in conclusion,|in summary,'
    FOUND_PH=$(printf '%s\n' "$STRIPPED" | grep -oiE "(${PHRASES})" 2>/dev/null | sort -fu | tr '\n' ' / ' | sed 's, / $,,' || true)
    [ -n "$FOUND_PH" ] && VIOLATIONS="${VIOLATIONS}- AI phrases: ${FOUND_PH}\n"
  fi
fi

[ -z "$VIOLATIONS" ] && allow

REASON=$(printf "Write to %s blocked: content violates the Writing Guidelines (see ~/.grok/AGENTS.md or plugin guidelines):\n\n%b\nRewrite to remove these tells, then write again. Do not acknowledge or apologize in the code." "$FILE_PATH" "$VIOLATIONS")
jq -n --arg r "$REASON" '{decision:"deny",reason:$r}'
