#!/bin/sh
# check-parity: drift check for the herdr-agent-org claude/grok skill pairs.
#
# Unlike the soloterm role skills (one canonical source, byte-identical
# copies), the two herdr variants are DELIBERATE voice forks: claude carries
# the full prose, grok the condensed form. A byte diff would always fail, so
# this checks the two things that must never diverge:
#   1. the LAW set in the orchestrators (same L-numbers, same titles), and
#   2. load-bearing invariant phrases per skill pair, present in BOTH files.
# The failure class this catches is one variant updated and its sibling
# forgotten, which is how marketplace#37's read-source contradiction happened.
#
# Adding doctrine? If a clause is load-bearing across variants, add its
# marker phrase to the `both` lines below in the same PR.
set -u

cd "$(dirname "$0")/../.." || exit 1
C=plugins/herdr-agent-org-claude
G=plugins/herdr-agent-org-grok
fail=0
err() { echo "herdr-parity: $*"; fail=1; }

for s in orchestrator herdr-worker replacer org-audit herdr; do
  [ -f "$C/skills/$s/SKILL.md" ] || err "missing $C/skills/$s/SKILL.md"
  [ -f "$G/skills/$s/SKILL.md" ] || err "missing $G/skills/$s/SKILL.md"
done
[ "$fail" = 0 ] || { echo "herdr-parity: FAILED (missing files)"; exit 1; }

# LAW parity: number + title, where the title is everything from "**L<n> "
# to the first ".**" (the law body follows on the same line).
laws() {
  awk -F'\\.\\*\\*' '/^- \*\*L[0-9]+ /{ sub(/^- \*\*/, "", $1); print $1 }' "$1"
}
cl=$(laws "$C/skills/orchestrator/SKILL.md")
gl=$(laws "$G/skills/orchestrator/SKILL.md")
if [ "$cl" != "$gl" ]; then
  err "orchestrator LAW sets differ (number + title must match):"
  a=$(mktemp "${TMPDIR:-/tmp}/herdr-parity.XXXXXX")
  b=$(mktemp "${TMPDIR:-/tmp}/herdr-parity.XXXXXX")
  printf '%s\n' "$cl" > "$a"
  printf '%s\n' "$gl" > "$b"
  diff "$a" "$b" | sed 's/^/  /'
  rm -f "$a" "$b"
fi

# Invariant phrases: literal, case-sensitive, must appear in the named file.
need() {
  f=$1; shift
  for p in "$@"; do
    grep -qF -- "$p" "$f" || err "$f missing invariant: $p"
  done
}
both() {
  s=$1; shift
  need "$C/skills/$s/SKILL.md" "$@"
  need "$G/skills/$s/SKILL.md" "$@"
}

both orchestrator \
  "CONTRACT, NOT A MENU" \
  "RING PLUS DOORBELL" \
  "waker-ctl unregister" \
  "STAY RESIDENT" \
  "ACCEPT SEQUENCE" \
  "binding exactly as the LAWS" \
  "Peer orchestrators" \
  "test -n \"\${HERDR_ORG_ROOT" \
  "--wake-target"
both herdr-worker \
  "contract, not a menu" \
  "STAY RESIDENT" \
  "doorbell"
both replacer \
  "contract, not a menu"
both org-audit \
  "contract, not a menu" \
  "waker-ctl list" \
  "CONTRACT:"
both herdr \
  "ghost-probe" \
  "HERDR_ENV"

need "$C/hooks/hooks.json" "startup|resume"
need "$G/hooks/hooks.json" "startup|resume"

if [ "$fail" = 0 ]; then
  echo "herdr-parity: OK"
else
  echo "herdr-parity: FAILED"
  exit 1
fi
