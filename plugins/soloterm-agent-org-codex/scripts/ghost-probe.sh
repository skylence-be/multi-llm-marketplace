#!/bin/sh
# ghost-probe — classify a target PTY's input line BEFORE any send_input
# (no-fusion hard law). Discriminates Claude Code suggestion GHOST text
# (placeholder the operator accepts with Tab/→) from REAL operator typing.
# Field-validated recipe 2026-06-10; design doc:
# https://gist.github.com/jonasvanderhaegen/4f6251458e529d290db93ee7afada592
#
# This script never touches the PTY. The caller gathers tails via Solo MCP
# (get_process_output for rendered, get_process_raw_output for raw) and, in
# probe mode, sends ONE space (send_input bytes [32]) between the two tails,
# then a backspace (bytes [127]) afterwards to restore net-zero either way.
#
# Subcommands:
#   zero-touch --rendered FILE --raw FILE
#       Step 1, no PTY interaction. A ghost is drawn out-of-band: Solo strips
#       its styling, so the RAW prompt line is empty while the RENDERED line
#       shows text. Verdicts: EMPTY | GHOST | TYPED | AMBIGUOUS.
#   probe --before FILE --after FILE
#       Step 2, deterministic. before/after = rendered tails around sending
#       ONE space: a ghost VANISHES instantly; real typing is RETAINED.
#       Verdicts: GHOST | TYPED | AMBIGUOUS. Probe ONCE, never in a loop.
#   live --t0 FILE --t1 FILE
#       Guard: two rendered tails moments apart. If the prompt line changed
#       between them, that is LIVE typing — do not probe, do not send.
#       Verdicts: LIVE | STABLE.
#
# Options: --prompt-char C (default "❯", the Claude Code prompt).
# FILE may be - for stdin (at most one input per invocation).
#
# Exit codes: 0 = safe to send (EMPTY, GHOST, STABLE)
#             1 = DO NOT SEND (TYPED, LIVE) — route to the durable channel
#             2 = AMBIGUOUS or usage error — gather better tails, do not send
set -u

PROMPT="❯"
NP="$(printf '\001')NOPROMPT"

usage() {
  awk 'NR > 1 { if (!/^#/) exit; s = $0; sub(/^# ?/, "", s); print s }' "$0"
  exit 2
}

# Last prompt line's content, trimmed; sentinel when no prompt line exists.
prompt_text() {
  awk -v p="$PROMPT" -v np="$NP" '
    { i = index($0, p); if (i) { found = 1; line = substr($0, i + length(p)) } }
    END {
      if (!found) { print np; exit }
      gsub(/^[ \t]+/, "", line); gsub(/[ \t\r]+$/, "", line)
      print line
    }
  ' "$1"
}

[ "$#" -ge 1 ] || usage
cmd=$1; shift
A=""; B=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --rendered|--before|--t0) A=$2; shift 2 ;;
    --raw|--after|--t1)       B=$2; shift 2 ;;
    --prompt-char)            PROMPT=$2; shift 2 ;;
    -h|--help)                usage ;;
    *) echo "ghost-probe: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$A" ] && [ -n "$B" ] || usage
[ "$A" = "-" ] && A=/dev/stdin
[ "$B" = "-" ] && B=/dev/stdin

a=$(prompt_text "$A")
b=$(prompt_text "$B")

case "$cmd" in
  zero-touch)
    # a = rendered prompt text, b = raw prompt text
    [ "$b" = "$NP" ] && { echo AMBIGUOUS; exit 2; }
    [ -n "$b" ] && { echo TYPED; exit 1; }
    [ "$a" = "$NP" ] && { echo AMBIGUOUS; exit 2; }
    if [ -n "$a" ]; then echo GHOST; exit 0; else echo EMPTY; exit 0; fi
    ;;
  probe)
    # a = before, b = after (one space sent in between; trailing space trims)
    { [ "$a" = "$NP" ] || [ "$b" = "$NP" ]; } && { echo AMBIGUOUS; exit 2; }
    [ -z "$a" ] && { echo AMBIGUOUS; exit 2; }
    [ -z "$b" ] && { echo GHOST; exit 0; }
    case "$b" in
      "$a"*) echo TYPED; exit 1 ;;
    esac
    echo AMBIGUOUS; exit 2
    ;;
  live)
    { [ "$a" = "$NP" ] || [ "$b" = "$NP" ]; } && { echo AMBIGUOUS; exit 2; }
    if [ "$a" = "$b" ]; then echo STABLE; exit 0; else echo LIVE; exit 1; fi
    ;;
  *) usage ;;
esac
