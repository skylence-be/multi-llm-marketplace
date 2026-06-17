#!/usr/bin/env sh
# judge-hook.sh — PreToolUse judge for Google Antigravity. Antigravity port of
# the core Claude hook.
#
# Contract (differs from Claude/Codex): a tool-call JSON object arrives on STDIN
# (camelCase: toolCall.name, toolCall.args). This script PRINTS a JSON object on
# STDOUT — {"decision":"allow"} or {"decision":"deny","reason":"..."} — and
# exits 0. Antigravity has no exit-2 block convention.
#
# Rules: ~/.gemini/judge-rules.json (override $JUDGE_RULES_FILE). escalate rules
# call `gemini` for an ALLOW/BLOCK verdict. ADAPTATION: rule patterns match
# against the whole STDIN payload (schema-agnostic); the per-rule `tool` field is
# advisory. Fails OPEN (prints allow) on any uncertainty.
#
# NOTE: uses printf, never echo — under POSIX sh, echo mangles the backslashes
# in the rule regexes (\s, \b) and corrupts the JSON before jq parses it.

RULES_FILE="${JUDGE_RULES_FILE:-$HOME/.gemini/judge-rules.json}"
LLM_TIMEOUT_SECONDS="${JUDGE_LLM_TIMEOUT:-20}"

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
      command -v gemini >/dev/null 2>&1 || allow
      PROMPT=$(printf '%s\n\nProposed tool call (raw payload):\n%s\n\nAnswer with exactly one word: ALLOW or BLOCK.' "$JP" "$INPUT")
      OUT=$(perl -e '
        $SIG{ALRM} = sub { die "timeout\n" };
        alarm $ARGV[0];
        open(my $f, "-|", "gemini", "-p", $ARGV[1]) or die "spawn: $!";
        local $/; my $o = <$f>; close($f); print $o;
      ' "$LLM_TIMEOUT_SECONDS" "$PROMPT" 2>/dev/null) || allow
      V=$(printf '%s\n' "$OUT" | grep -oiE 'ALLOW|BLOCK' | tail -1 | tr '[:lower:]' '[:upper:]')
      [ "$V" = "BLOCK" ] && deny "judge-hook: ${REASON:-blocked by LLM judge}"
      allow ;;
  esac
done
allow
