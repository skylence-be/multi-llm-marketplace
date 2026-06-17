#!/bin/bash
# judge-hook.sh — PreToolUse judge for Codex. Codex port of the core Claude hook.
#
# Reads the PreToolUse payload on stdin, evaluates rules from
# ~/.codex/judge-rules.json (override $JUDGE_RULES_FILE), and decides
# allow / deny / escalate-to-LLM:
#   class=deny     → exit 2 with reason on stderr (Codex blocks the call)
#   class=allow    → exit 0
#   class=escalate → `codex exec` judges ALLOW / BLOCK
#
# ADAPTATION vs the Claude variant: Codex's PreToolUse payload is not the
# {tool_name, tool_input} schema, so each rule's `pattern` is matched against
# the WHOLE payload JSON (schema-agnostic) and the per-rule `tool` field is
# advisory only. Escalation shells out to `codex exec` (read-only sandbox)
# instead of `claude -p`. Fails *open* on missing rules/jq/codex, timeout, or
# any parse failure — use class=deny rules for anything that must block
# deterministically.

set -euo pipefail

RULES_FILE="${JUDGE_RULES_FILE:-$HOME/.codex/judge-rules.json}"
LLM_TIMEOUT_SECONDS="${JUDGE_LLM_TIMEOUT:-20}"

[ -f "$RULES_FILE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

RULE_COUNT=$(jq '.rules | length' "$RULES_FILE" 2>/dev/null || echo 0)
[ "$RULE_COUNT" = "0" ] && exit 0

for i in $(seq 0 $((RULE_COUNT - 1))); do
  RULE=$(jq ".rules[$i]" "$RULES_FILE")
  R_PATTERN=$(echo "$RULE" | jq -r '.pattern // ""')
  R_CLASS=$(echo "$RULE" | jq -r '.class // "allow"')
  R_REASON=$(echo "$RULE" | jq -r '.reason // ""')

  [ -n "$R_PATTERN" ] || continue
  # Schema-agnostic: match the rule pattern against the full payload JSON.
  echo "$INPUT" | grep -qE "$R_PATTERN" || continue

  case "$R_CLASS" in
    deny)
      echo "judge-hook: blocked — ${R_REASON:-no reason given}" >&2
      exit 2
      ;;
    allow)
      exit 0
      ;;
    escalate)
      JUDGE_PROMPT=$(echo "$RULE" | jq -r '.judge_prompt // ""')
      [ -n "$JUDGE_PROMPT" ] || exit 0
      command -v codex >/dev/null 2>&1 || exit 0

      FULL_PROMPT=$(printf '%s\n\nProposed tool call (raw payload):\n%s\n\nAnswer with exactly one word on the first line: ALLOW or BLOCK. Then a one-sentence reason.' \
        "$JUDGE_PROMPT" "$INPUT")

      # codex exec: non-interactive single turn, read-only sandbox, final
      # message to stdout. macOS lacks GNU timeout; use perl's alarm.
      DECISION=$(perl -e '
        $SIG{ALRM} = sub { die "timeout\n" };
        alarm $ARGV[0];
        open(my $fh, "-|", "codex", "exec", "--sandbox", "read-only", $ARGV[1]) or die "spawn: $!";
        local $/; my $out = <$fh>; close($fh);
        print $out;
      ' "$LLM_TIMEOUT_SECONDS" "$FULL_PROMPT" 2>/dev/null) || exit 0

      # codex exec may print reasoning before the verdict; take the last ALLOW/BLOCK.
      VERDICT=$(echo "$DECISION" | grep -oiE '\b(ALLOW|BLOCK)\b' | tail -1 | tr '[:lower:]' '[:upper:]')
      if [ "$VERDICT" = "BLOCK" ]; then
        echo "judge-hook: LLM judge blocked — ${R_REASON:-no reason given}" >&2
        exit 2
      fi
      exit 0
      ;;
  esac
done

exit 0
