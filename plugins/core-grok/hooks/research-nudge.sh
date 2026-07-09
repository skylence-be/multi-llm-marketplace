#!/usr/bin/env sh
# research-nudge.sh — Stop hook for Grok. When assistant ends hedging a factual claim,
# suggest (or attempt to trigger) a verification step.
#
# Grok Stop hooks are passive (no blocking like PreToolUse). We still try to
# output a reason that may surface, and use an LLM call to decide NUDGE.
# Best effort, fails open. Uses printf.

allow() { printf '{"decision":"allow"}\n'; exit 0; }
nudge() { jq -n --arg r "$1" '{decision:"deny",reason:$r}'; exit 0; }

command -v jq >/dev/null 2>&1 || allow
INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || allow

# Try to pull last assistant content from the hook payload if present, else allow.
LAST=$(printf '%s\n' "$INPUT" | jq -r '
  (.content // .lastAssistantMessage // .message.content // .text // "")
  | (if type == "string" then . else (if type == "array" then (map(.text // .content // "") | join("\n")) else (. // "") end) end)
' 2>/dev/null | tail -c 8000 || true)

[ -n "$LAST" ] || allow

HEDGE="might|may( |,|\.|\$)|probably|possibly|i think|i believe|i'm not sure|as far as i know|presumably|i assume|likely|appears to|seems like"
printf '%s\n' "$LAST" | grep -qiE "$HEDGE" || allow

command -v grok >/dev/null 2>&1 || allow
TIMEOUT="${NUDGE_LLM_TIMEOUT:-20}"
PROMPT=$(printf 'The assistant response below ends a turn. Does it make a FACTUAL externally-checkable claim while hedging with words like "might", "may", "probably", "I think", "likely"? Opinions and suggestions do NOT count. Reply with exactly one word: NUDGE or OK.\n\n---\n%s' "$LAST")

OUT=$(perl -e '
  $SIG{ALRM} = sub { die "timeout\n" };
  alarm $ARGV[0];
  open(my $f, "-|", "grok", "-p", $ARGV[1], "--output-format", "json", "--always-approve", "--max-turns", "1", "--disallowed-tools", "run_terminal_command,search_replace,web_search,web_fetch,task,todo_write,Agent") or die "spawn: $!";
  local $/; my $o = <$f>; close($f); print $o;
' "$TIMEOUT" "$PROMPT" 2>/dev/null) || allow

V=$(printf '%s\n' "$OUT" | grep -oiE 'NUDGE|OK' | tail -1 | tr '[:lower:]' '[:upper:]')
if [ -z "$V" ]; then
  V=$(printf '%s\n' "$OUT" | jq -r '.text // ""' 2>/dev/null | grep -oiE 'NUDGE|OK' | tail -1 | tr '[:lower:]' '[:upper:]')
fi
[ "$V" = "NUDGE" ] || allow

REASON="You hedged a factual claim. Verify with web_search (or web_fetch) and state the confirmed fact + source before concluding the turn. Or state plainly that the claim could not be verified right now."
nudge "$REASON"
