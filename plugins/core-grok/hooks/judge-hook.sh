#!/usr/bin/env sh
# judge-hook.sh — PreToolUse judge for Grok. Grok-native port of the core baseline.
#
# Contract: Grok sends JSON on STDIN with hookEventName, toolName, toolInput.
# Prints {"decision":"allow"} or {"decision":"deny","reason":"..."} on STDOUT and exits 0.
# Fails open to allow on any problem.
#
# Rules: ~/.grok/judge-rules.json (override JUDGE_RULES_FILE).
# Patterns are matched against the full raw JSON payload (schema tolerant).
# Escalate rules call `grok -p` (headless, always-approve, tools limited to avoid recursion)
# and look for ALLOW or BLOCK in response.
#
# Uses printf, never echo.

RULES_FILE="${JUDGE_RULES_FILE:-$HOME/.grok/judge-rules.json}"
LLM_TIMEOUT_SECONDS="${JUDGE_LLM_TIMEOUT:-25}"

allow() { printf '{"decision":"allow"}\n'; exit 0; }
deny()  { jq -n --arg r "$1" '{decision:"deny",reason:$r}'; exit 0; }

command -v jq >/dev/null 2>&1 || { printf '{"decision":"allow"}\n'; exit 0; }
[ -f "$RULES_FILE" ] || allow

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || allow

COUNT=$(jq '.rules | length' "$RULES_FILE" 2>/dev/null || echo 0)
[ "$COUNT" = "0" ] && allow

i=0
while [ "$i" -lt "$COUNT" ]; do
  RULE=$(jq ".rules[$i]" "$RULES_FILE")
  PAT=$(printf '%s\n' "$RULE" | jq -r '.pattern // ""')
  CLASS=$(printf '%s\n' "$RULE" | jq -r '.class // "allow"')
  REASON=$(printf '%s\n' "$RULE" | jq -r '.reason // ""')
  i=$((i + 1))

  [ -n "$PAT" ] || continue
  printf '%s\n' "$INPUT" | grep -qE "$PAT" || continue

  case "$CLASS" in
    deny) deny "judge-hook: ${REASON:-blocked}" ;;
    allow) allow ;;
    escalate)
      JP=$(printf '%s\n' "$RULE" | jq -r '.judge_prompt // ""')
      [ -n "$JP" ] || allow
      command -v grok >/dev/null 2>&1 || allow
      PROMPT=$(printf '%s\n\nProposed tool call (raw JSON payload):\n%s\n\nRespond with exactly one word on the first line: ALLOW or BLOCK. No other text.' "$JP" "$INPUT")
      # Use headless, force no tools that could recurse or side-effect, short max turns.
      OUT=$(perl -e '
        $SIG{ALRM} = sub { die "timeout\n" };
        alarm $ARGV[0];
        open(my $f, "-|", "grok", "-p", $ARGV[1], "--effort", "medium", "--output-format", "json", "--always-approve", "--max-turns", "1", "--disallowed-tools", "run_terminal_command,search_replace,web_search,web_fetch,task,todo_write,Agent,read_file,grep,list_dir") or die "spawn: $!";
        local $/; my $o = <$f>; close($f); print $o;
      ' "$LLM_TIMEOUT_SECONDS" "$PROMPT" 2>/dev/null) || allow
      # Extract from JSON text field or plain
      V=$(printf '%s\n' "$OUT" | grep -oiE 'ALLOW|BLOCK' | tail -1 | tr '[:lower:]' '[:upper:]')
      if [ -z "$V" ]; then
        # fallback parse json .text
        V=$(printf '%s\n' "$OUT" | jq -r '.text // ""' 2>/dev/null | grep -oiE 'ALLOW|BLOCK' | tail -1 | tr '[:lower:]' '[:upper:]')
      fi
      [ "$V" = "BLOCK" ] && deny "judge-hook: ${REASON:-blocked by LLM judge}"
      allow ;;
  esac
done
allow
