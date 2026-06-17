#!/usr/bin/env sh
# writing-guard.sh — AI-tells guard for Google Antigravity, run as a PreToolUse
# hook on the write/replace tools. Antigravity's write payload carries the
# content in toolCall.args, so we inspect it BEFORE the write and deny (with a
# corrective reason) when AI writing tells are present — the agent then rewrites.
#
# Contract: tool-call JSON on STDIN (camelCase); print {"decision":"allow"} or
# {"decision":"deny","reason":"..."} on STDOUT, exit 0. Fails OPEN. Uses printf
# (never echo) so backslashes in content survive intact under POSIX sh.
#
# ⚠️ UNVERIFIED: the exact args field names for write_to_file /
# replace_file_content are not documented. We try several and fall back to allow.

allow() { printf '{"decision":"allow"}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || allow
INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || allow

FILE_PATH=$(printf '%s\n' "$INPUT" | jq -r '
  (.toolCall.args.TargetFile // .toolCall.args.target_file // .toolCall.args.path
   // .toolCall.args.file_path // .toolCall.args.filePath
   // .args.path // .args.file_path // empty)' 2>/dev/null || true)

CONTENT=$(printf '%s\n' "$INPUT" | jq -r '
  (.toolCall.args.content // .toolCall.args.CodeContent // .toolCall.args.code_content
   // .toolCall.args.ReplacementContent // .toolCall.args.new_string // .toolCall.args.text
   // .args.content // .args.new_string // empty)' 2>/dev/null || true)

[ -n "$CONTENT" ] || allow
[ -n "$FILE_PATH" ] || FILE_PATH="(written file)"

case "$FILE_PATH" in
  *.json|*.jsonc|*.yaml|*.yml|*.toml|*.xml|*.csv|*.tsv|*.lock|*.lockb|*.lockfile|*.sum|*.mod|*.svg|*.map|*.min.js|*.min.css) allow ;;
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.zip|*.gz|*.tar|*.docx|*.xlsx|*.pptx|*.doc|*.xls|*.ppt|*.key|*.numbers|*.pages) allow ;;
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
EM_COUNT=$(printf '%s\n' "$STRIPPED" | grep -o '—' | wc -l | tr -d ' ')
if [ "$EM_COUNT" -gt 0 ]; then
  VIOLATIONS="${VIOLATIONS}- Em dashes: ${EM_COUNT} found (zero allowed)\n"
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

REASON=$(printf "Write to %s blocked: content violates the Writing Guidelines (~/.gemini/AGENTS.md):\n\n%b\nRewrite to remove these tells, then write again. Do not acknowledge or apologize." "$FILE_PATH" "$VIOLATIONS")
jq -n --arg r "$REASON" '{decision:"deny",reason:$r}'
