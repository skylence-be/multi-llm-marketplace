#!/bin/bash
# judge-hook.sh — PreToolUse judge (dual Claude Code + Grok compatible).
#
# Reads the host's stdin JSON, evaluates ~/.claude or ~/.grok/judge-rules.json,
# decides allow/deny/escalate.
#
# Auto-detects Grok (toolName/hookEventName/sessionId + toolInput) vs Claude
# (tool_name/tool_input). 
#
# For Grok: outputs {"decision":"allow"} / {"decision":"deny","reason":"..."} + exit 0
# For Claude: exit 0 (allow) or exit 2 (deny); escalate uses transcript context.
#
# Skyline normalization + rule cache + mem pressure + user-intent transcript for
# escalate preserved for Claude path. Grok path gets equivalent basic matching.
#
# Fails open. Rules file chosen preferring explicit, then grok if context, else claude.

set -uo pipefail

LLM_TIMEOUT_SECONDS="${JUDGE_LLM_TIMEOUT:-10}"
LLM_MODEL="${JUDGE_LLM_MODEL:-claude-haiku-4-5-20251001}"
CACHE_FILE="${TMPDIR:-/tmp}/judge-rules-cache-$(id -u)"

b64d() { printf '%s' "$1" | base64 -d 2>/dev/null || printf '%s' "$1" | base64 -D 2>/dev/null; }

INPUT=$(cat 2>/dev/null || true)

# Detect host from input or env (after reading INPUT)
IS_GROK=false
if printf '%s' "$INPUT" | grep -qE '"toolName"|"hookEventName"|"sessionId"' || [ -n "${GROK_SESSION_ID:-}" ] || [ -n "${GROK_PLUGIN_ROOT:-}" ]; then
  IS_GROK=true
fi

# Choose rules location (user can override with JUDGE_RULES_FILE)
if [ -n "${JUDGE_RULES_FILE:-}" ]; then
  RULES_FILE="$JUDGE_RULES_FILE"
elif $IS_GROK || [ -f "$HOME/.grok/judge-rules.json" ]; then
  RULES_FILE="$HOME/.grok/judge-rules.json"
else
  RULES_FILE="$HOME/.claude/judge-rules.json"
fi

[ -f "$RULES_FILE" ] || { $IS_GROK && printf '{"decision":"allow"}\n' || true; exit 0; }
command -v jq >/dev/null 2>&1 || { $IS_GROK && printf '{"decision":"allow"}\n' || true; exit 0; }

# Host-specific parse of (raw_tool, tool_input_json_str, transcript_or_empty)
if $IS_GROK; then
  # Grok: toolName, toolInput; no reliable transcript in base payload for escalate
  RAW_TOOL=$(printf '%s' "$INPUT" | jq -r '.toolName // .tool_name // ""' 2>/dev/null || true)
  TOOL_INPUT_JSON=$(printf '%s' "$INPUT" | jq -c '.toolInput // .tool_input // {}' 2>/dev/null || echo '{}')
  TRANSCRIPT=""
else
  PARSED=$(printf '%s' "$INPUT" | jq -r \
    '[(.tool_name // ""), ((.tool_input // {}) | tojson | @base64), (.transcript_path // "")] | @tsv' 2>/dev/null) || exit 0
  RAW_TOOL=$(printf '%s' "$PARSED" | cut -f1)
  TOOL_INPUT_JSON=$(b64d "$(printf '%s' "$PARSED" | cut -f2)")
  TRANSCRIPT=$(printf '%s' "$PARSED" | cut -f3)
fi
[ -n "$RAW_TOOL" ] || { $IS_GROK && printf '{"decision":"allow"}\n' || true; exit 0; }

# Tool class + match text (skyline aware)
CLASS_TOOL="$RAW_TOOL"
MATCH_TEXT="$TOOL_INPUT_JSON"
case "$RAW_TOOL" in
  *skyline_run)
    CLASS_TOOL="Bash"
    CMDS=$(printf '%s' "$TOOL_INPUT_JSON" | jq -r \
      '((.argv // []) | join(" ")), ((.argv_list // [])[] | join(" "))' 2>/dev/null) || CMDS=""
    [ -n "$CMDS" ] && MATCH_TEXT="$TOOL_INPUT_JSON
$(printf '%s\n' "$CMDS" | sed 's/^/cmd: /')"
    ;;
  *skyline_create)
    CLASS_TOOL="Write"
    FP=$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '.path // empty' 2>/dev/null) || FP=""
    [ -n "$FP" ] && MATCH_TEXT="$TOOL_INPUT_JSON
\"file_path\":\"$FP\""
    ;;
  *skyline_edit)
    CLASS_TOOL="Edit"
    FPS=$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '.patch // empty' 2>/dev/null \
      | sed -n 's/^¶\([^#]*\)#.*/\1/p') || FPS=""
    [ -n "$FPS" ] && MATCH_TEXT="$TOOL_INPUT_JSON
$(printf '%s\n' "$FPS" | sed 's/^/"file_path":"/; s/$/"/')"
    ;;
esac

# Compile rules to a TSV cache: tool, class, pattern/reason/judge_prompt (b64).
RULES_MTIME=$(stat -f %m "$RULES_FILE" 2>/dev/null || stat -c %Y "$RULES_FILE" 2>/dev/null || echo 0)
HDR="$RULES_MTIME	$RULES_FILE"
RULES_TSV=""
if [ -f "$CACHE_FILE" ] && [ "$(head -n 1 "$CACHE_FILE" 2>/dev/null)" = "$HDR" ]; then
  RULES_TSV=$(tail -n +2 "$CACHE_FILE" 2>/dev/null)
fi
if [ -z "$RULES_TSV" ]; then
  RULES_TSV=$(jq -r '.rules[]? | [(.tool // "*"), (.class // "allow"),
      ((.pattern // "") | @base64), ((.reason // "") | @base64),
      ((.judge_prompt // "") | @base64)] | @tsv' "$RULES_FILE" 2>/dev/null) || exit 0
  [ -n "$RULES_TSV" ] || exit 0
  { printf '%s\n' "$HDR"; printf '%s\n' "$RULES_TSV"; } > "$CACHE_FILE.tmp.$$" 2>/dev/null \
    && mv -f "$CACHE_FILE.tmp.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.tmp.$$" 2>/dev/null
fi

# Evaluate in declaration order; first match wins.
while IFS='	' read -r R_TOOL R_CLASS R_PAT_B64 R_REASON_B64 R_PROMPT_B64; do
  [ -n "$R_TOOL" ] || continue
  if [ "$R_TOOL" != "*" ] && [ "$R_TOOL" != "$RAW_TOOL" ] && [ "$R_TOOL" != "$CLASS_TOOL" ]; then
    continue
  fi
  R_PATTERN=$(b64d "$R_PAT_B64")
  if [ -n "$R_PATTERN" ]; then
    # A malformed pattern makes grep exit 2; `|| continue` keeps that fail-open.
    printf '%s' "$MATCH_TEXT" | grep -qE -- "$R_PATTERN" 2>/dev/null || continue
  fi
  case "$R_CLASS" in
    deny)
      R_REASON=$(b64d "$R_REASON_B64"); [ -n "$R_REASON" ] || R_REASON="no reason given"
      if $IS_GROK; then
        jq -n --arg r "judge-hook: $R_REASON" '{decision:"deny",reason:$r}'
      else
        echo "judge-hook: blocked: $R_REASON" >&2
        exit 2
      fi
      exit 0
      ;;
    allow)
      if $IS_GROK; then printf '{"decision":"allow"}\n'; fi
      exit 0
      ;;
    escalate)
      R_PROMPT=$(b64d "$R_PROMPT_B64")
      if [ -z "$R_PROMPT" ]; then
        echo "judge-hook: escalate rule missing judge_prompt; allowing" >&2
        if $IS_GROK; then printf '{"decision":"allow"}\n'; fi
        exit 0
      fi

      # Pick LLM CLI (prefer the one matching host, fall back)
      LLM_BIN=""
      if $IS_GROK && command -v grok >/dev/null 2>&1; then LLM_BIN=grok; fi
      if [ -z "$LLM_BIN" ] && command -v claude >/dev/null 2>&1; then LLM_BIN=claude; fi
      if [ -z "$LLM_BIN" ] && command -v grok >/dev/null 2>&1; then LLM_BIN=grok; fi
      if [ -z "$LLM_BIN" ]; then
        echo "judge-hook: no claude/grok CLI for escalate; allowing" >&2
        if $IS_GROK; then printf '{"decision":"allow"}\n'; fi
        exit 0
      fi

      # Mem pressure guard (only meaningful on macOS for claude path)
      PRESSURE=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)
      if [ "$PRESSURE" = "4" ]; then
        echo "judge-hook: memory pressure critical; escalate fails open" >&2
        if $IS_GROK; then printf '{"decision":"allow"}\n'; fi
        exit 0
      fi

      # User context (transcript best for Claude; empty ok for Grok)
      USER_CTX=""
      if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
        USER_CTX=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -rs '
          [ .[] | select(.type == "user") | .message.content
            | if type == "string" then .
              else ((map(select(.type == "text") | .text) // []) | join("\n")) end
            | select(length > 0) ] | .[-3:] | join("\n---\n")' 2>/dev/null | tail -c 1500) || USER_CTX=""
      fi

      if [ "$LLM_BIN" = "grok" ]; then
        PROMPT=$(printf '%s\n\nProposed tool call (raw JSON payload):\n%s\n\nRespond with exactly one word on the first line: ALLOW or BLOCK. No other text.' "$R_PROMPT" "$INPUT")
        OUT=$(perl -e '
          $SIG{ALRM} = sub { die "timeout\n" };
          alarm $ARGV[0];
          open(my $f, "-|", "grok", "-p", $ARGV[1], "--output-format", "json", "--always-approve", "--max-turns", "1", "--disallowed-tools", "run_terminal_command,search_replace,web_search,web_fetch,task,todo_write,Agent,read_file,grep,list_dir") or die "spawn: $!";
          local $/; my $o = <$f>; close($f); print $o;
        ' "$LLM_TIMEOUT_SECONDS" "$PROMPT" 2>/dev/null) || { printf '{"decision":"allow"}\n'; exit 0; }
        V=$(printf '%s\n' "$OUT" | grep -oiE 'ALLOW|BLOCK' | tail -1 | tr '[:lower:]' '[:upper:]')
        if [ -z "$V" ]; then
          V=$(printf '%s\n' "$OUT" | jq -r '.text // ""' 2>/dev/null | grep -oiE 'ALLOW|BLOCK' | tail -1 | tr '[:lower:]' '[:upper:]')
        fi
        if [ "$V" = "BLOCK" ]; then
          REAS="judge-hook: ${R_REASON:-blocked by LLM judge}"
          jq -n --arg r "$REAS" '{decision:"deny",reason:$r}'
        else
          printf '{"decision":"allow"}\n'
        fi
        exit 0
      else
        # Claude escalate (with user ctx)
        FULL_PROMPT=$(printf '%s\n\nRecent user messages (most recent last; may be empty):\n%s\n\nTool: %s\nInput: %s\n\nRespond with exactly one word: ALLOW or BLOCK. Then on a new line, a one-sentence reason.' \
          "$R_PROMPT" "${USER_CTX:-<none available>}" "$RAW_TOOL" "$TOOL_INPUT_JSON")
        DECISION=$(perl -e '
          $SIG{ALRM} = sub { die "timeout\n" };
          alarm $ARGV[0];
          open(my $fh, "-|", "claude", "-p", "--model", $ARGV[1], $ARGV[2]) or die "spawn: $!";
          local $/; my $out = <$fh>; close($fh);
          print $out;
        ' "$LLM_TIMEOUT_SECONDS" "$LLM_MODEL" "$FULL_PROMPT" 2>/dev/null) || {
          echo "judge-hook: LLM judge timed out or failed; allowing" >&2
          exit 0
        }
        VERDICT=$(echo "$DECISION" | head -1 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
        LLM_REASON=$(echo "$DECISION" | sed -n '2p')
        if [ "$VERDICT" = "BLOCK" ]; then
          echo "judge-hook: LLM judge blocked: ${LLM_REASON:-no reason given}" >&2
          exit 2
        fi
        exit 0
      fi
      ;;
  esac
done <<EOF
$RULES_TSV
EOF

if $IS_GROK; then printf '{"decision":"allow"}\n'; fi
exit 0
