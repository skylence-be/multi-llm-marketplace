#!/bin/bash
# research-nudge.sh — Stop hook. Dual-compatible for Claude + Grok.
# When the assistant's final turn hedges a FACTUAL claim without verification,
# output a nudge reason (block/deny) so the agent verifies before idling.
#
# - Robust session id + org-lane check (both prefixes)
# - Transcript for Claude; payload content fallback for Grok
# - Uses claude -p or grok -p (prefers the one present; grok path uses restricted tools)
# - Outputs appropriate decision JSON; fails open.
#
# Skipped in SOLO org sessions and under critical mem pressure.

set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"decision":"allow"}\n'; exit 0; }
INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

IS_GROK=false
if printf '%s' "$INPUT" | grep -qE '"hookEventName"|"toolName"|"sessionId"'; then
  IS_GROK=true
fi

# Second pass gate
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // .stopHookActive // false' 2>/dev/null || echo false)
[ "$ACTIVE" = "true" ] && exit 0

# Org sessions: skip (dual lane check)
[ -n "${SOLO_PROCESS_ID:-}" ] && exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)
if [ -z "$SID" ]; then SID="${GROK_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"; fi
LANED=false
for p in claude grok; do
  if [ -n "$SID" ] && [ -f "/tmp/${p}-org-lanes-$SID" ]; then LANED=true; break; fi
done
[ "$LANED" = true ] && exit 0

# Mem pressure (macOS)
PRESSURE=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)
[ "$PRESSURE" = "4" ] && exit 0

# Extract last assistant text.
LAST=""
if ! $IS_GROK; then
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    LAST=$(tail -n 400 "$TRANSCRIPT" | jq -rs '
      [ .[] | select(.type == "assistant") ] | last
      | (.message.content // [])
      | map(select(.type == "text") | .text) | join("\n")
    ' 2>/dev/null || true)
  fi
fi
if [ -z "$LAST" ]; then
  # Grok payload or fallback
  LAST=$(printf '%s' "$INPUT" | jq -r '
    (.content // .lastAssistantMessage // .message.content // .text // "")
    | (if type == "string" then . else (if type == "array" then (map(.text // .content // "") | join("\n")) else (. // "") end) end)
  ' 2>/dev/null | tail -c 8000 || true)
fi
[ -n "$LAST" ] || exit 0

# Stage 1: cheap hedge
HEDGE="might|may( |,|\.|\$)|probably|possibly|i think|i believe|i'm not sure|not entirely sure|not totally sure|as far as i know|if i recall|presumably|i assume|i guess|afaik|i'd guess|likely"
printf '%s\n' "$LAST" | grep -qiE "$HEDGE" || exit 0

# Stage 2: LLM judge. Pick claude or grok binary.
LLM_BIN=""
if command -v claude >/dev/null 2>&1; then LLM_BIN=claude; LLM_MODEL="${NUDGE_LLM_MODEL:-claude-haiku-4-5-20251001}"; fi
if [ -z "$LLM_BIN" ] && command -v grok >/dev/null 2>&1; then LLM_BIN=grok; fi
[ -n "$LLM_BIN" ] || exit 0

TIMEOUT="${NUDGE_LLM_TIMEOUT:-10}"

if [ "$LLM_BIN" = "grok" ]; then
  PROMPT=$(printf 'The assistant response below ends a turn. Does it make a FACTUAL externally-checkable claim while hedging with words like "might", "may", "probably", "I think", "likely"? Opinions and suggestions do NOT count. Reply with exactly one word: NUDGE or OK.\n\n---\n%s' "$LAST")
  OUT=$(perl -e '
    $SIG{ALRM} = sub { die "timeout\n" };
    alarm $ARGV[0];
    open(my $f, "-|", "grok", "-p", $ARGV[1], "--output-format", "json", "--always-approve", "--max-turns", "1", "--disallowed-tools", "run_terminal_command,search_replace,web_search,web_fetch,task,todo_write,Agent,read_file,grep,list_dir") or die "spawn: $!";
    local $/; my $o = <$f>; close($f); print $o;
  ' "$TIMEOUT" "$PROMPT" 2>/dev/null) || exit 0
  VERDICT=$(printf '%s\n' "$OUT" | grep -oiE 'NUDGE|OK' | tail -1 | tr '[:lower:]' '[:upper:]')
  [ "$VERDICT" = "NUDGE" ] || exit 0
  REASON="You hedged a factual claim. Verify with web_search (or web_fetch) and state the confirmed fact + source before concluding the turn. Or state plainly that the claim could not be verified right now."
  if $IS_GROK; then
    jq -n --arg r "$REASON" '{decision:"deny",reason:$r}'
  else
    jq -n --arg r "$REASON" '{decision:"block",reason:$r}'
  fi
  exit 0
else
  # claude path (richer prompt)
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
  if $IS_GROK; then
    jq -n --arg r "$REASON" '{decision:"deny",reason:$r}'
  else
    jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
  fi
fi
