#!/usr/bin/env sh
# research-nudge.sh — Stop hook for Google Antigravity. Antigravity port of the
# core Claude hook: when the final turn hedges a FACTUAL claim, nudge a
# web-search verification before concluding.
#
# Contract: print a JSON object on STDOUT. We emit {"decision":"deny","reason":...}
# to push one more turn, or {"decision":"allow"} to let the stop through. Uses
# printf (never echo) for backslash safety under POSIX sh.
#
# ⚠️ HEAVILY UNVERIFIED: Antigravity's Stop event, its payload (transcript path,
# any stop-loop guard flag), and whether a Stop hook can request another turn are
# all undocumented. Best-effort and fails OPEN — if the contract differs,
# Antigravity ignores the output and the session stops normally.

allow() { printf '{"decision":"allow"}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || allow
INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || allow

ACTIVE=$(printf '%s\n' "$INPUT" | jq -r '(.stop_hook_active // .stopHookActive // false)' 2>/dev/null || echo false)
[ "$ACTIVE" = "true" ] && allow

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '
  (.transcriptPath // .transcript_path // .session.transcriptPath // empty)' 2>/dev/null || true)
{ [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; } || allow

LAST=$(tail -n 400 "$TRANSCRIPT" | jq -rs '
  [ .[] | select((.type // .role) == "assistant" or (.role // "") == "assistant") ] | last
  | ((.message.content // .content // []))
  | (if type == "string" then . else (map(select((.type // "text") == "text") | (.text // "")) | join("\n")) end)
' 2>/dev/null || true)
[ -n "$LAST" ] || allow

HEDGE="might|may( |,|\.|\$)|probably|possibly|i think|i believe|i'm not sure|as far as i know|presumably|i assume|likely"
printf '%s\n' "$LAST" | grep -qiE "$HEDGE" || allow

command -v gemini >/dev/null 2>&1 || allow
TIMEOUT="${NUDGE_LLM_TIMEOUT:-20}"
PROMPT=$(printf 'An assistant just ended its turn with the text below. Does it assert a FACTUAL, externally checkable claim while hedging it ("might", "may", "probably", "I think")? Subjective opinions and suggestions ("you may want to") are NOT verifiable claims. First line: NUDGE or OK.\n\n---\n%s' "$LAST")
OUT=$(perl -e '
  $SIG{ALRM} = sub { die "timeout\n" };
  alarm $ARGV[0];
  open(my $f, "-|", "gemini", "-p", $ARGV[1]) or die "spawn: $!";
  local $/; my $o = <$f>; close($f); print $o;
' "$TIMEOUT" "$PROMPT" 2>/dev/null) || allow

V=$(printf '%s\n' "$OUT" | grep -oiE 'NUDGE|OK' | tail -1 | tr '[:lower:]' '[:upper:]')
[ "$V" = "NUDGE" ] || allow

REASON="You hedged a factual claim instead of verifying it. Confirm it with a web search and state the confirmed fact with its source before concluding, or say plainly that you could not verify it."
jq -n --arg r "$REASON" '{decision:"deny",reason:$r}'
