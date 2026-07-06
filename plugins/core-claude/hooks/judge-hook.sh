#!/bin/bash
# judge-hook.sh — PreToolUse judge for Claude Code.
#
# Reads stdin JSON ({tool_name, tool_input, transcript_path}), evaluates rules,
# and decides allow / deny / escalate-to-LLM.
#
# Rules file: ~/.claude/judge-rules.json (override with $JUDGE_RULES_FILE).
# Missing or empty file → silent no-op (opt-in by file presence).
#
# Per-rule behavior:
#   class=deny     → exit 2 with reason on stdout (Claude Code blocks the call)
#   class=allow    → exit 0 (allowlist patterns that override later rules)
#   class=escalate → spawn `claude -p` with judge_prompt; LLM returns ALLOW/BLOCK
#
# SKYLINE-AWARE TOOL NORMALIZATION: rules keyed on the classic tool names also
# bind their skyline MCP equivalents, so routing through skyline cannot bypass
# a rule:
#   Bash  ⇐ *skyline_run    (match text gains one "cmd: <argv joined>" line
#                            per argv/argv_list entry)
#   Write ⇐ *skyline_create (match text gains "file_path":"<path>")
#   Edit  ⇐ *skyline_edit   (match text gains one "file_path":"<p>" per ¶ header)
# A rule may still name an MCP tool exactly; exact tool match is checked first.
#
# ESCALATE rules receive the last few user messages from the transcript, so
# judge prompts that reference operator intent ("block unless the user asked")
# are actually decidable. Under kernel memory pressure CRITICAL (macOS level 4)
# escalate fails open instead of spawning another LLM on a starving machine.
#
# FAIL-OPEN CONTRACT: only an explicit rule verdict exits 2. Infrastructure
# errors (missing jq/claude, malformed rules, bad regex, LLM timeout) allow the
# call. Deliberately NO `set -e`: grep exits 2 on a bad pattern, and under -e
# that would propagate as a spurious deny-everything.
#
# Perf: rules compile once (one jq pass) into a per-user cache keyed on the
# rules file mtime; the hot path is one jq + one grep per candidate rule.

set -uo pipefail

RULES_FILE="${JUDGE_RULES_FILE:-$HOME/.claude/judge-rules.json}"
LLM_TIMEOUT_SECONDS="${JUDGE_LLM_TIMEOUT:-10}"
LLM_MODEL="${JUDGE_LLM_MODEL:-claude-haiku-4-5-20251001}"
CACHE_FILE="${TMPDIR:-/tmp}/judge-rules-cache-$(id -u)"

[ -f "$RULES_FILE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

b64d() { printf '%s' "$1" | base64 -d 2>/dev/null || printf '%s' "$1" | base64 -D 2>/dev/null; }

INPUT=$(cat)
PARSED=$(printf '%s' "$INPUT" | jq -r \
  '[(.tool_name // ""), ((.tool_input // {}) | tojson | @base64), (.transcript_path // "")] | @tsv' 2>/dev/null) || exit 0
RAW_TOOL=$(printf '%s' "$PARSED" | cut -f1)
TOOL_INPUT_JSON=$(b64d "$(printf '%s' "$PARSED" | cut -f2)")
TRANSCRIPT=$(printf '%s' "$PARSED" | cut -f3)
[ -n "$RAW_TOOL" ] || exit 0

# Tool class + match text (see SKYLINE-AWARE TOOL NORMALIZATION above).
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
      echo "judge-hook: blocked: $R_REASON" >&2
      exit 2
      ;;
    allow)
      exit 0
      ;;
    escalate)
      R_PROMPT=$(b64d "$R_PROMPT_B64")
      if [ -z "$R_PROMPT" ]; then
        echo "judge-hook: escalate rule missing judge_prompt; allowing" >&2
        exit 0
      fi
      command -v claude >/dev/null 2>&1 || {
        echo "judge-hook: claude CLI not found; escalate rule fails open" >&2
        exit 0
      }
      # A machine at kernel pressure CRITICAL doesn't get an extra LLM process.
      PRESSURE=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)
      if [ "$PRESSURE" = "4" ]; then
        echo "judge-hook: memory pressure critical; escalate fails open" >&2
        exit 0
      fi

      # Recent user intent from the transcript — judge prompts reference it.
      USER_CTX=""
      if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
        USER_CTX=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -rs '
          [ .[] | select(.type == "user") | .message.content
            | if type == "string" then .
              else ((map(select(.type == "text") | .text) // []) | join("\n")) end
            | select(length > 0) ] | .[-3:] | join("\n---\n")' 2>/dev/null | tail -c 1500) || USER_CTX=""
      fi

      FULL_PROMPT=$(printf '%s\n\nRecent user messages (most recent last; may be empty):\n%s\n\nTool: %s\nInput: %s\n\nRespond with exactly one word: ALLOW or BLOCK. Then on a new line, a one-sentence reason.' \
        "$R_PROMPT" "${USER_CTX:-<none available>}" "$RAW_TOOL" "$TOOL_INPUT_JSON")

      # Hard timeout; macOS lacks GNU timeout, so perl alarms.
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
      ;;
  esac
done <<EOF
$RULES_TSV
EOF

exit 0
