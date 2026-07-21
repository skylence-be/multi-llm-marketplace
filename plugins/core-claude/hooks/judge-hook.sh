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

# ARGV PROJECTION (false-positive fix, 2026-07-21).
# A regex over the raw tool_input cannot tell an argument from a program. It
# blocked `grep -n "...poweroff..." judge-rules.json` as a "system power
# command" and a `sudo` string inside a JSON test fixture as "sudo invocation";
# neither could execute anything. So for Bash-class calls, tokenize the command
# the way a shell would and project ONLY the program actually invoked, one
# `argv0: <basename>` line per pipeline stage. A rule opts in with
# "match": "argv0" and is then grepped against this projection ALONE, never
# the raw JSON, so command text such as `echo 'argv0: sudo'` cannot spoof it.
# Wrappers (env, nice, xargs, ...) are transparent; sudo/doas are emitted AND
# stepped past, so `env sudo reboot` yields both `sudo` and `reboot`; `sh -c`
# payloads are rescanned. Heredoc bodies are dropped: they are data, not
# commands. Anything perl cannot parse yields no line, which fails open in
# keeping with the FAIL-OPEN CONTRACT above.
ARGV_TEXT=""
if [ "$CLASS_TOOL" = "Bash" ] && command -v perl >/dev/null 2>&1; then
  read -r -d '' ARGV_SCAN_PL <<'PERL_EOF'
my $WRAP  = qr/^(env|command|builtin|exec|nice|ionice|nohup|setsid|time|stdbuf|xargs)$/;
my $PRIV  = qr/^(sudo|doas|pkexec|run0)$/;
my $SHELL = qr/^(sh|bash|zsh|dash|ksh|fish)$/;
# sudo flags that consume the next word; without this, `sudo -u root sh` would
# read `root` as the escalated program.
my $PRIV_VALUE_FLAG = qr/^-[ugpCThDrt]$/;
my %seen;

sub emit { my ($n) = @_; return if $seen{$n}++; print "argv0: $n\n"; }

# Drop heredoc bodies: `cat <<EOF ... sudo rm ... EOF` names no command.
# `<<<` is a herestring with no body, so it must not trigger the skip.
sub strip_heredocs {
  my @lines = split /\n/, $_[0], -1;
  my @out;
  for (my $i = 0; $i <= $#lines; $i++) {
    push @out, $lines[$i];
    next unless $lines[$i] =~ /(?<!<)<<-?\s*(?:'([^']+)'|"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))(?!<)/;
    my $d = defined $1 ? $1 : defined $2 ? $2 : $3;
    $i++;
    $i++ while $i <= $#lines && $lines[$i] !~ /^\s*\Q$d\E\s*$/;
  }
  return join "\n", @out;
}

# Split into pipeline stages and tokens in one pass, honouring quotes so that
# separators inside a quoted argument stay part of that argument.
sub lex {
  my ($s) = @_;
  my (@stages, @cur, $tok, $has);
  ($tok, $has) = ('', 0);
  my ($i, $n) = (0, length $s);
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '\\' && $i + 1 < $n) { $tok .= substr($s, $i + 1, 1); $has = 1; $i += 2; next; }
    if ($c eq "'") {
      my $j = index($s, "'", $i + 1);
      $j = $n if $j < 0;
      $tok .= substr($s, $i + 1, $j - $i - 1); $has = 1; $i = $j + 1; next;
    }
    if ($c eq '"') {
      $i++;
      while ($i < $n) {
        my $d = substr($s, $i, 1);
        last if $d eq '"';
        if ($d eq '\\' && $i + 1 < $n) { $tok .= substr($s, $i + 1, 1); $i += 2; next; }
        $tok .= $d; $i++;
      }
      $has = 1; $i++; next;
    }
    if ($c =~ /\s/) { push @cur, $tok if $has; ($tok, $has) = ('', 0); $i++; next; }
    # Stage break. `(`/`)`/`{`/`}` cover subshells and `$(...)` substitution,
    # whose body is itself a command and must be scanned as one.
    if ($c =~ /[|;&\n()\{\}]/) {
      push @cur, $tok if $has; ($tok, $has) = ('', 0);
      push @stages, [@cur] if @cur; @cur = ();
      $i++;
      next;
    }
    $tok .= $c; $has = 1; $i++;
  }
  push @cur, $tok if $has;
  push @stages, [@cur] if @cur;
  return @stages;
}

sub scan {
  my ($cmd, $depth) = @_;
  return if $depth > 3 || !defined $cmd;
  for my $st (lex(strip_heredocs($cmd))) {
    my @t = @$st;
    my $i = 0;
    $i++ while $i < @t && $t[$i] =~ /^[A-Za-z_][A-Za-z0-9_]*=/;
    while ($i < @t) {
      (my $p = $t[$i]) =~ s{.*/}{};
      if ($p =~ $WRAP) {
        $i++;
        $i++ while $i < @t && $t[$i] =~ /^-/;
        $i++ while $i < @t && $t[$i] =~ /^[A-Za-z_][A-Za-z0-9_]*=/;
        next;
      }
      if ($p =~ $PRIV) {
        emit($p);
        $i++;
        while ($i < @t && $t[$i] =~ /^-/) {
          my $f = $t[$i]; $i++;
          $i++ if $f =~ $PRIV_VALUE_FLAG && $i < @t;
        }
        $i++ while $i < @t && $t[$i] =~ /^[A-Za-z_][A-Za-z0-9_]*=/;
        next;
      }
      emit($p);
      if ($p =~ $SHELL) {
        for my $j ($i + 1 .. $#t) {
          next unless $t[$j] =~ /^-[a-zA-Z]*c$/ && $j < $#t;
          scan($t[$j + 1], $depth + 1);
          last;
        }
      }
      last;
    }
  }
}

# One base64 command per line: a command may contain newlines, quotes, or NULs,
# and base64 is the only separator none of them can forge.
use MIME::Base64 ();
while (my $line = <STDIN>) {
  chomp $line;
  next unless length $line;
  scan(MIME::Base64::decode_base64($line), 0);
}
PERL_EOF
  # @sh shell-quotes each argv element, so a pre-tokenized skyline_run call and
  # a raw Bash string go through one and the same tokenizer.
  ARGV_TEXT=$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '
    [ (.command? // empty),
      ((.argv? // []) | select(length > 0) | @sh),
      ((.argv_list? // [])[] | @sh) ]
    | .[] | tostring | @base64' 2>/dev/null \
    | perl -e "$ARGV_SCAN_PL" 2>/dev/null)
fi

# Compile rules to a cache: tool, class, pattern/reason/judge_prompt (b64),
# match scope. Fields are joined with "|", NOT a tab: a tab is IFS whitespace,
# so `read` folds runs of them together and a rule with an empty judge_prompt
# would shift every later column left by one. "|" cannot occur in base64, a
# class, or a match scope, and as non-whitespace IFS it preserves empty fields.
# The header carries a schema version so a cache written by an older hook is
# recompiled rather than read back a column short.
RULES_MTIME=$(stat -f %m "$RULES_FILE" 2>/dev/null || stat -c %Y "$RULES_FILE" 2>/dev/null || echo 0)
HDR="v2	$RULES_MTIME	$RULES_FILE"
RULES_TSV=""
if [ -f "$CACHE_FILE" ] && [ "$(head -n 1 "$CACHE_FILE" 2>/dev/null)" = "$HDR" ]; then
  RULES_TSV=$(tail -n +2 "$CACHE_FILE" 2>/dev/null)
fi
if [ -z "$RULES_TSV" ]; then
  RULES_TSV=$(jq -r '.rules[]? | [(.tool // "*"), (.class // "allow"),
      ((.pattern // "") | @base64), ((.reason // "") | @base64),
      ((.judge_prompt // "") | @base64), (.match // "raw")] | join("|")' "$RULES_FILE" 2>/dev/null) || exit 0
  [ -n "$RULES_TSV" ] || exit 0
  { printf '%s\n' "$HDR"; printf '%s\n' "$RULES_TSV"; } > "$CACHE_FILE.tmp.$$" 2>/dev/null \
    && mv -f "$CACHE_FILE.tmp.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.tmp.$$" 2>/dev/null
fi

# Evaluate in declaration order; first match wins.
while IFS='|' read -r R_TOOL R_CLASS R_PAT_B64 R_REASON_B64 R_PROMPT_B64 R_MATCH; do
  [ -n "$R_TOOL" ] || continue
  if [ "$R_TOOL" != "*" ] && [ "$R_TOOL" != "$RAW_TOOL" ] && [ "$R_TOOL" != "$CLASS_TOOL" ]; then
    continue
  fi
  # "argv0" rules see the invoked-program projection ONLY, so text that merely
  # names a command cannot match them. Any other value keeps raw-JSON matching.
  if [ "$R_MATCH" = "argv0" ]; then R_TEXT="$ARGV_TEXT"; else R_TEXT="$MATCH_TEXT"; fi
  R_PATTERN=$(b64d "$R_PAT_B64")
  if [ -n "$R_PATTERN" ]; then
    # A malformed pattern makes grep exit 2; `|| continue` keeps that fail-open.
    printf '%s' "$R_TEXT" | grep -qE -- "$R_PATTERN" 2>/dev/null || continue
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
