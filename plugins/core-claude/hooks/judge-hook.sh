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

# ARGV PROJECTION (false-positive fix, 2026-07-21; fail-closed, 2026-07-21).
# A regex over the raw tool_input cannot tell an argument from a program. It
# blocked `grep -n "...poweroff..." judge-rules.json` as a "system power
# command" and a `sudo` string inside a JSON test fixture as "sudo invocation";
# neither could execute anything. So for Bash-class calls, tokenize the command
# the way a shell would and project ONLY the program actually invoked, one
# `argv0: <basename>` line per pipeline stage. A rule opts in with
# "match": "argv0" and is then grepped against this projection ALONE, never
# the raw JSON, so command text such as `echo 'argv0: sudo'` cannot spoof it.
# Wrappers (env, nice, timeout, xargs, ...) are transparent; their flag VALUES
# are consumed so `env -u FOO sudo` still yields `sudo`. sudo/doas are emitted
# AND stepped past; `sh -c`, `eval`, and backtick bodies are rescanned. Heredoc
# bodies are dropped: they are data, not commands.
#
# FAIL-CLOSED for argv0 rules: when the tokenizer cannot fully understand a
# construct (dynamic command, interpreter -e code, source, unclosed quotes,
# missing perl), it emits `uncertain: 1`. The rule matcher then falls back to
# raw tool_input matching for that rule, so exotic shapes are never weaker than
# the pre-argv0 guard. Fully-parsed read-only greps stay ALLOW (the FP fix).
# CROSS-CHECK INVARIANT (2026-07-21): fail-closed on uncertainty cannot help
# when the parse succeeds into a WRONG answer. An unmodelled wrapper with a
# positional argument (`flock FILE cmd`) makes the scanner confidently call
# the positional "the program". So: a privilege/power word present as a BARE
# token in a stage that the projection never emitted also marks uncertain.
# Any wrapper whose argument grammar is not modelled therefore degrades to
# raw matching instead of hiding everything after it.
# QUOTED PAYLOADS: a quoted token is data for `echo`, and a program for `awk`.
# The exemption is therefore an allowlist of INERT programs (text in, text out,
# arguments never executed), NOT a denylist of known interpreters. A denylist
# fails OPEN for every interpreter nobody thought of (awk, make, and whatever
# ships next), which is the same defect as an unmodelled wrapper one level up.
# So a quoted token carrying a privilege/power word marks uncertain unless the
# stage's program is known inert. Caveat: `git` is inert for its own arguments
# but can run hooks and aliases. It is listed because the message-body false
# positive is common and git does not execute `-m` text.
# Infrastructure errors (missing jq, bad rules) remain fail-open per the header.
ARGV_TEXT=""
ARGV_UNCERTAIN=0
if [ "$CLASS_TOOL" = "Bash" ]; then
  if ! command -v perl >/dev/null 2>&1; then
    ARGV_UNCERTAIN=1
  else
  read -r -d '' ARGV_SCAN_PL <<'PERL_EOF'
my $WRAP  = qr/^(env|command|builtin|exec|nice|ionice|nohup|setsid|time|stdbuf|xargs|timeout|gtimeout|watch|script|unbuffer|rlwrap|strace|ltrace|catchsegv|taskset|chrt|prlimit|flock|chronic|softlimit)$/;
my $PRIV  = qr/^(sudo|doas|pkexec|run0)$/;
my $POWER = qr/^(shutdown|reboot|halt|poweroff)$/;
my $SHELL = qr/^(sh|bash|zsh|dash|ksh|fish)$/;
my $INTERP = qr/^(perl|perl[0-9.]+|python|python[0-9.]+|ruby|node|nodejs|php|lua|osascript)$/;
# Programs whose ARGUMENTS are never executed: text in, text out. Only for
# these is a quoted token safely treated as data. Anything absent from this
# list (awk, make, xargs-with-a-shell, tomorrow's interpreter) has a quoted
# privilege word treated as possible code, which fails CLOSED to raw matching.
# Deliberately an allowlist of safety, not a denylist of danger: the denylist
# shape is exactly what let `flock FILE sudo reboot` through.
my $INERT = qr/^(echo|printf|cat|head|tail|wc|sort|uniq|cut|tr|column|fold|
                 grep|egrep|fgrep|rg|ag|ack|sed|jq|yq|ls|stat|file|diff|comm|
                 tee|git|basename|dirname|realpath|readlink|date|true|false)$/x;
# A privilege/power word anywhere inside a quoted payload, on a word boundary.
# Token equality is not enough here: the payload is a program, not a bare word
# (`BEGIN{system("sudo reboot")}` never equals `sudo`).
my $PRIV_IN_TEXT = qr/(?:^|[^A-Za-z0-9_\/.-])(sudo|doas|pkexec|run0|shutdown|reboot|halt|poweroff)(?:[^A-Za-z0-9_-]|$)/;
# sudo flags that consume the next word; without this, `sudo -u root sh` would
# read `root` as the escalated program.
my $PRIV_VALUE_FLAG = qr/^-[ugpCThDrt]$/;
# Wrapper flags that take a separate value. Without this, `env -u FOO sudo`
# treats FOO as the program and never emits sudo (privilege regression).
my %WRAP_VAL = (
  env      => qr/^(-[uCS]|--unset|--chdir|--split-string)$/,
  timeout  => qr/^(-[sk]|--signal|--kill-after)$/,
  gtimeout => qr/^(-[sk]|--signal|--kill-after)$/,
  nice     => qr/^(-n|--adjustment)$/,
  ionice   => qr/^(-[cnp]|--class|--classdata|--pid)$/,
  stdbuf   => qr/^(-[ioe]|--input|--output|--error)$/,
  xargs    => qr/^(-[nPsILEda]|--max-args|--max-procs|--max-chars|--replace|--arg-file|--delimiter|--max-lines)$/,
  watch    => qr/^(-n|--interval)$/,
  script   => qr/^(-[ct]|--command|--timing)$/,
  strace   => qr/^(-[eopsS]|--trace|--signal|--pid|--output)$/,
  ltrace   => qr/^(-[eops])$/,
  taskset  => qr/^(-[cp]|--cpu-list|--pid)$/,
  chrt     => qr/^(-p|--pid)$/,
  prlimit  => qr/^(-p|--pid)$/,
  flock    => qr/^(-[wE]|--timeout|--conflict-exit-code)$/,
  rlwrap   => qr/^(-[abceN])$/,
  softlimit=> qr/^(-[a-zA-Z])$/,
);
# Wrappers taking a mandatory POSITIONAL argument BEFORE the command. Every
# entry in $WRAP is a new hiding place unless its argument grammar is known:
# unmodelled, the positional is declared the program and the real command
# after it never reaches the projection.
my %WRAP_POS = (
  timeout => 1, gtimeout => 1, flock => 1, taskset => 1, chrt => 1, script => 1,
);
my %seen;
my $uncertain = 0;

sub emit { my ($n) = @_; return if $seen{$n}++; print "argv0: $n\n"; }
sub mark { $uncertain = 1; }

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
  my (@stages, @cur, $tok, $has, $q);
  ($tok, $has, $q) = ('', 0, 0);
  my ($i, $n) = (0, length $s);
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '\\' && $i + 1 < $n) { $tok .= substr($s, $i + 1, 1); $has = 1; $i += 2; next; }
    if ($c eq "'") {
      my $j = index($s, "'", $i + 1);
      if ($j < 0) { mark(); $j = $n; }
      $tok .= substr($s, $i + 1, $j - $i - 1); $has = 1; $q = 1; $i = $j + 1; next;
    }
    if ($c eq '"') {
      $i++;
      while ($i < $n) {
        my $d = substr($s, $i, 1);
        last if $d eq '"';
        if ($d eq '\\' && $i + 1 < $n) { $tok .= substr($s, $i + 1, 1); $i += 2; next; }
        $tok .= $d; $i++;
      }
      mark() if $i >= $n; # unclosed double quote
      $has = 1; $q = 1; $i++; next;
    }
    if ($c =~ /\s/) { push @cur, [$tok, $q] if $has; ($tok, $has, $q) = ('', 0, 0); $i++; next; }
    # Stage break. `(`/`)`/`{`/`}` cover subshells and `$(...)` substitution,
    # whose body is itself a command and must be scanned as one.
    if ($c =~ /[|;&\n()\{\}]/) {
      push @cur, [$tok, $q] if $has; ($tok, $has, $q) = ('', 0, 0);
      push @stages, [@cur] if @cur; @cur = ();
      $i++;
      next;
    }
    $tok .= $c; $has = 1; $i++;
  }
  push @cur, [$tok, $q] if $has;
  push @stages, [@cur] if @cur;
  return @stages;
}

sub scan {
  my ($cmd, $depth) = @_;
  return if $depth > 3 || !defined $cmd;

  # Legacy command substitution: scan backtick bodies, then blank them so the
  # outer lex does not treat `sudo as a token. Unclosed ` marks uncertain.
  my $work = $cmd;
  {
    my ($out, $i, $n) = ('', 0, length $work);
    my $in_sq = 0;
    while ($i < $n) {
      my $c = substr($work, $i, 1);
      if ($c eq '\\' && $i + 1 < $n && !$in_sq) { $out .= substr($work, $i, 2); $i += 2; next; }
      if ($c eq "'" ) { $in_sq = !$in_sq; $out .= $c; $i++; next; }
      if ($c eq '`' && !$in_sq) {
        my $j = index($work, '`', $i + 1);
        if ($j < 0) { mark(); $out .= substr($work, $i); last; }
        scan(substr($work, $i + 1, $j - $i - 1), $depth + 1);
        $out .= ' ';
        $i = $j + 1;
        next;
      }
      $out .= $c; $i++;
    }
    $work = $out;
  }

  for my $st (lex(strip_heredocs($work))) {
    my @t = map { $_->[0] } @$st;
    my @q = map { $_->[1] } @$st;
    my $stage_prog = '';
    my $i = 0;
    $i++ while $i < @t && $t[$i] =~ /^[A-Za-z_][A-Za-z0-9_]*=/;
    while ($i < @t) {
      (my $p = $t[$i]) =~ s{.*/}{};

      # Dynamic command: `$cmd` / `${cmd}` — cannot resolve; fail closed.
      if ($t[$i] =~ /^\$/) { mark(); emit($p); last; }

      # eval "..." — the rest of the stage is a shell snippet; rescan it.
      if ($p eq 'eval') {
        my $body = join ' ', @t[$i + 1 .. $#t];
        scan($body, $depth + 1) if length $body;
        last;
      }

      # source / . file — body not visible; fail closed so raw may still match.
      if ($p eq 'source' || $p eq '.') { mark(); emit($p); last; }

      if ($p =~ $WRAP) {
        $i++;
        my $valre = $WRAP_VAL{$p};
        my $nopos = 0;
        while ($i < @t && $t[$i] =~ /^-/) {
          my $f = $t[$i++];
          last if $f eq '--';
          # `env -S "cmd args"` / `-S"cmd args"`: env splits the string itself
          # and runs it, so the value is a COMMAND, not data. Rescan it.
          if ($p eq 'env' && $f =~ /^(?:-S|--split-string=?)(.*)$/s) {
            if (length $1) { scan($1, $depth + 1); }
            elsif ($i < @t) { scan($t[$i], $depth + 1); $i++; }
            next;
          }
          if ($f =~ /^--[^=]+=/) {
            $nopos = 1 if $f =~ /^--(cpu-list|pid)=/;
            next;
          }
          if ($p =~ /^(script|flock)$/ && $f =~ /^(-c|--command)$/ && $i < @t) {
            scan($t[$i], $depth + 1);
            $i++;
            $nopos = 1;
            next;
          }
          # A flag supplying what the positional would have carried
          # (taskset -c LIST, chrt/prlimit -p PID) removes the positional.
          $nopos = 1 if $f =~ /^(-c|--cpu-list|-p|--pid)$/;
          if (defined $valre && $f =~ $valre && $i < @t && $t[$i] !~ /^-/) {
            $i++;
          }
        }
        # timeout DURATION / flock FILE / taskset MASK / chrt PRIO / script FILE
        if ($WRAP_POS{$p} && !$nopos && $i < @t && $t[$i] !~ /^-/) {
          $i++;
        }
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
      $stage_prog = $p;
      if ($p =~ $SHELL) {
        for my $j ($i + 1 .. $#t) {
          next unless $t[$j] =~ /^-[a-zA-Z]*c$/ && $j < $#t;
          scan($t[$j + 1], $depth + 1);
          last;
        }
      }
      # Interpreter -e/-c code is opaque to the argv0 projection; fail closed
      # so a `sudo` string inside the payload still hits the raw fallback.
      if ($p =~ $INTERP) {
        for my $j ($i + 1 .. $#t) {
          if ($t[$j] =~ /^-[a-zA-Z]*[ecE]$/ || $t[$j] eq '--eval' || $t[$j] eq '-code') {
            mark();
            last;
          }
        }
      }
      last;
    }
    # CROSS-CHECK INVARIANT: a privilege/power word this stage never emitted
    # means the scan walked past the real command (see header). The parse is
    # confidently wrong rather than uncertain, so nothing else here would catch
    # it; mark uncertain and let raw matching take over.
    my $inert = ($stage_prog ne '' && $stage_prog =~ $INERT) ? 1 : 0;
    for my $k (0 .. $#t) {
      if ($q[$k]) {
        # Quoted: data for an inert program, possibly code for anything else.
        next if $inert;
        mark() if $t[$k] =~ $PRIV_IN_TEXT;
        next;
      }
      (my $w = $t[$k]) =~ s{.*/}{};
      next unless $w =~ $PRIV || $w =~ $POWER;
      mark() unless $seen{$w};
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
print "uncertain: 1\n" if $uncertain;
PERL_EOF
  # @sh shell-quotes each argv element, so a pre-tokenized skyline_run call and
  # a raw Bash string go through one and the same tokenizer.
  ARGV_TEXT=$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '
    [ (.command? // empty),
      ((.argv? // []) | select(length > 0) | @sh),
      ((.argv_list? // [])[] | @sh) ]
    | .[] | tostring | @base64' 2>/dev/null \
    | perl -e "$ARGV_SCAN_PL" 2>/dev/null) || ARGV_UNCERTAIN=1
  if printf '%s' "$ARGV_TEXT" | grep -q '^uncertain: 1$'; then
    ARGV_UNCERTAIN=1
    ARGV_TEXT=$(printf '%s\n' "$ARGV_TEXT" | grep -v '^uncertain: 1$' || true)
  fi
  fi
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
  # "argv0" rules see the invoked-program projection, so text that merely names
  # a command cannot match them. When the tokenizer marked the command uncertain
  # (or perl is missing), fall back to a raw word-boundary match derived from
  # the argv0 pattern — never weaker than the pre-argv0 guard on exotic shapes.
  # Any other match scope keeps raw-JSON matching.
  R_PATTERN=$(b64d "$R_PAT_B64")
  if [ "$R_MATCH" = "argv0" ]; then
    HIT=0
    if [ -n "$R_PATTERN" ] && [ -n "$ARGV_TEXT" ]; then
      printf '%s' "$ARGV_TEXT" | grep -qE -- "$R_PATTERN" 2>/dev/null && HIT=1
    fi
    if [ "$HIT" -eq 0 ] && [ "$ARGV_UNCERTAIN" -eq 1 ] && [ -n "$R_PATTERN" ]; then
      # ^argv0: (a|b|c)$  →  (^|[^a-zA-Z_/.])(a|b|c)(["'[:space:]]|$)
      RAW_ALT=$(printf '%s' "$R_PATTERN" | sed -n 's/^\^argv0: (\(.*\))\$$/\1/p')
      if [ -n "$RAW_ALT" ]; then
        printf '%s' "$MATCH_TEXT" | grep -qE -- "(^|[^a-zA-Z_/.])(${RAW_ALT})([\"'[:space:]]|\$)" 2>/dev/null && HIT=1
      fi
    fi
    [ "$HIT" -eq 1 ] || continue
  else
    R_TEXT="$MATCH_TEXT"
    if [ -n "$R_PATTERN" ]; then
      # A malformed pattern makes grep exit 2; `|| continue` keeps that fail-open.
      printf '%s' "$R_TEXT" | grep -qE -- "$R_PATTERN" 2>/dev/null || continue
    fi
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
