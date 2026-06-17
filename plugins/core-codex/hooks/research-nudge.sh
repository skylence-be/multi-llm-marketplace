#!/bin/bash
# research-nudge.sh — Stop hook for Codex. Codex port of the core Claude hook:
# when the agent's final turn hedges a FACTUAL claim ("might", "may",
# "probably", "I think") without verifying it, nudge it to confirm with a web
# search before concluding.
#
# ADAPTATION vs the Claude variant: reads the last assistant text from the
# Codex transcript/rollout (several likely field names tried) and escalates the
# "is this a hedged factual claim" judgment to `codex exec`. Gated by a cheap
# hedge grep first, then the LLM judge; the stop_hook_active-style flag caps it
# at one nudge. Fails *open* on anything unexpected.
#
# ⚠️ UNVERIFIED: Codex's Stop payload field for the transcript path is not
# confirmed. If it can't be read, the hook no-ops.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

# Second pass guard (avoid loops): honor a Claude-style or Codex-style flag.
ACTIVE=$(echo "$INPUT" | jq -r '(.stop_hook_active // .stopHookActive // false)' 2>/dev/null || echo false)
[ "$ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '
  (.transcript_path // .rollout_path // .session.rollout_path
   // .session_path // .transcriptPath // empty)' 2>/dev/null || true)
{ [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; } || exit 0

# Last assistant text from the JSONL transcript (best-effort across shapes).
LAST=$(tail -n 400 "$TRANSCRIPT" | jq -rs '
  [ .[] | select((.type // .role) == "assistant" or (.role // "") == "assistant") ] | last
  | ( (.message.content // .content // []) )
  | (if type == "string" then . else (map(select((.type // "text") == "text") | (.text // .content // ""))| join("\n")) end)
' 2>/dev/null || true)
[ -n "$LAST" ] || exit 0

HEDGE="might|may( |,|\.|\$)|probably|possibly|i think|i believe|i'm not sure|not entirely sure|as far as i know|if i recall|presumably|i assume|i guess|afaik|likely"
echo "$LAST" | grep -qiE "$HEDGE" || exit 0

command -v codex >/dev/null 2>&1 || exit 0
TIMEOUT="${NUDGE_LLM_TIMEOUT:-20}"

PROMPT=$(printf 'An assistant just ended its turn with the text below. Does it assert a FACTUAL, externally checkable claim (API/flag behavior, version number, library capability, default value, historical fact) while hedging it ("might", "may", "probably", "I think")? Subjective opinions, design suggestions ("you may want to"), and plans are NOT verifiable claims. First line: NUDGE if there is a hedged factual claim worth web-verifying, else OK. Second line: name the claim.\n\n---\n%s' "$LAST")

DECISION=$(perl -e '
  $SIG{ALRM} = sub { die "timeout\n" };
  alarm $ARGV[0];
  open(my $fh, "-|", "codex", "exec", "--sandbox", "read-only", $ARGV[1]) or die "spawn: $!";
  local $/; my $out = <$fh>; close($fh);
  print $out;
' "$TIMEOUT" "$PROMPT" 2>/dev/null) || exit 0

VERDICT=$(echo "$DECISION" | grep -oiE '\b(NUDGE|OK)\b' | tail -1 | tr '[:lower:]' '[:upper:]')
[ "$VERDICT" = "NUDGE" ] || exit 0

REASON="You hedged a factual claim instead of verifying it. Before concluding, confirm it with a web search and state the confirmed fact with its source — or say plainly that you could not verify it. If the statement is genuinely subjective or you already verified it, you may stop again."
jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
