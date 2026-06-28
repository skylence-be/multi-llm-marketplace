#!/bin/bash
# research-nudge.sh — Stop hook. When the assistant's final turn hedges a
# FACTUAL claim ("might", "may", "probably", "I think", ...) without having
# verified it, nudge it to confirm the claim with a web search before concluding.
#
# Mechanism note: PreToolUse judge hooks only see tool calls, not the assistant's
# prose — and hedged claims live in the chat text. So this runs on the Stop event
# and reads the last assistant turn from the transcript.
#
# Two-stage gate keeps it quiet: (1) a cheap grep for hedge markers — most turns
# exit here; (2) only then a short LLM judge that distinguishes a hedged FACTUAL
# claim ("the flag may be --foo") from a benign hedge ("you may want to..."). The
# stop_hook_active flag caps it at one nudge per turn, never a loop. Fails *open*
# on any infrastructure error (missing jq/claude, timeout, unreadable transcript).

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

# Second pass through the gate (we already nudged once) → let the stop through.
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
{ [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; } || exit 0

# Last assistant turn's text from the JSONL transcript.
LAST=$(tail -n 400 "$TRANSCRIPT" | jq -rs '
  [ .[] | select(.type == "assistant") ] | last
  | (.message.content // [])
  | map(select(.type == "text") | .text) | join("\n")
' 2>/dev/null || true)
[ -n "$LAST" ] || exit 0

# Stage 1 — cheap hedge gate. Most turns stop here.
HEDGE="might|may( |,|\.|\$)|probably|possibly|i think|i believe|i'm not sure|not entirely sure|not totally sure|as far as i know|if i recall|presumably|i assume|i guess|afaik|i'd guess|likely"
echo "$LAST" | grep -qiE "$HEDGE" || exit 0

# Stage 2 — LLM judge. Only fires when a hedge marker was present.
command -v claude >/dev/null 2>&1 || exit 0
LLM_MODEL="${NUDGE_LLM_MODEL:-claude-haiku-4-5-20251001}"
TIMEOUT="${NUDGE_LLM_TIMEOUT:-10}"

PROMPT=$(printf 'An assistant just ended its turn with the text below. Does it assert a FACTUAL, externally checkable claim (API/flag behavior, version number, library capability, default value, historical fact, who-did-what) while hedging it ("might", "may", "probably", "I think", "should be")? Subjective opinions, design suggestions ("you may want to"), plans, and hedges about the user'\''s own intent are NOT verifiable factual claims. Respond with exactly one word on the first line: NUDGE if there is a hedged factual claim worth web-verifying, otherwise OK. On a second line, name the specific claim in a few words.\n\n---\n%s' "$LAST")

DECISION=$(perl -e '
  $SIG{ALRM} = sub { die "timeout\n" };
  alarm $ARGV[0];
  open(my $fh, "-|", "claude", "-p", "--model", $ARGV[1], $ARGV[2]) or die "spawn: $!";
  local $/; my $out = <$fh>; close($fh);
  print $out;
' "$TIMEOUT" "$LLM_MODEL" "$PROMPT" 2>/dev/null) || exit 0

VERDICT=$(echo "$DECISION" | head -1 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
CLAIM=$(echo "$DECISION" | sed -n '2p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[ "$VERDICT" = "NUDGE" ] || exit 0

REASON=$(printf 'You hedged a factual claim (%s) instead of verifying it. Before concluding, confirm it with a web search (WebSearch / WebFetch) and state the confirmed fact with its source — or say plainly that you could not verify it. If the statement is genuinely subjective, or you already verified it this session, you may stop again.' "${CLAIM:-see your last message}")
jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
