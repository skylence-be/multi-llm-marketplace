#!/bin/sh
# ctl_unregister_drop.sh: the waker-ctl side of the unregister audit
# invariant. parked_retry.sh case 6 proves the waker's own cmd_unregister
# logs dropped:unregistered per purged pending file; waker-ctl reimplements
# that purge client-side (see its header: "keep the two in sync"), and its
# copy shipped as a silent rm. Runs BOTH org-plugin copies via a stub herdr
# that only answers `plugin config-dir`; no jq needed by the script under
# test, jq validates the emitted JSON when present.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
failed=0

for CTL in \
  "$ROOT/plugins/herdr-agent-org-claude/scripts/waker-ctl" \
  "$ROOT/plugins/herdr-agent-org-grok/scripts/waker-ctl"
do
  name=$(printf '%s' "$CTL" | sed 's|.*/plugins/||; s|/scripts.*||')
  STUB_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/waker-ctl-drop_stub.XXXXXX")
  CFG="$STUB_ROOT/cfg"
  mkdir -p "$CFG/pending" "$CFG/registry" "$CFG/state" "$CFG/log"

  FAKE="$STUB_ROOT/fake_herdr"
  cat > "$FAKE" <<FAKE
#!/bin/sh
if [ "\${1:-} \${2:-}" = "plugin config-dir" ]; then
  printf '%s\n' "$CFG"
fi
exit 0
FAKE
  chmod +x "$FAKE"
  export HERDR_BIN_PATH="$FAKE"

  printf 'wE:p2\tprobe\t\torch\t1\t/org\t2026-01-01T00:00:00Z\n' \
    > "$CFG/registry/probe.row"
  # Text carries a quote and a backslash so escaping is exercised, not assumed.
  printf 'orch\n[WAKE g1] lane probe -> idle. says "hi" via C:\\tmp\n' \
    > "$CFG/pending/1000-probe-g1.msg"
  printf 'orch\nclaimed wake\n' > "$CFG/pending/1001-probe-g2.msg.claim"
  # Sibling lane must survive (rev-<lane> reviewer naming / suffix safety).
  printf 'orch\nsibling wake\n' > "$CFG/pending/1002-rev-probe-g1.msg"

  "$CTL" unregister --lane probe >/dev/null

  got=$(grep -c '"outcome":"dropped:unregistered"' "$CFG/log/rings.jsonl" 2>/dev/null || true)
  if [ "$got" = "2" ]; then
    echo "ok $name: dropped:unregistered count=2 (.msg + .msg.claim)"
  else
    echo "FAIL $name: expected 2 dropped:unregistered lines, got ${got:-0}"
    failed=1
  fi
  if [ -e "$CFG/pending/1000-probe-g1.msg" ] || [ -e "$CFG/pending/1001-probe-g2.msg.claim" ]; then
    echo "FAIL $name: purged pending files still present"
    failed=1
  else
    echo "ok $name: lane pending files removed"
  fi
  if [ -e "$CFG/pending/1002-rev-probe-g1.msg" ]; then
    echo "ok $name: sibling rev-probe wake untouched"
  else
    echo "FAIL $name: sibling rev-probe wake was purged"
    failed=1
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$CFG/log/rings.jsonl" >/dev/null 2>&1 \
      && [ "$(jq -rs '.[0].text' "$CFG/log/rings.jsonl")" = '[WAKE g1] lane probe -> idle. says "hi" via C:\tmp' ]; then
      echo "ok $name: ring lines are valid JSON, text round-trips"
    else
      echo "FAIL $name: rings.jsonl invalid JSON or text mangled"
      failed=1
    fi
  fi

  rm -rf "$STUB_ROOT"
done

if [ "$failed" = 0 ]; then
  echo "ctl_unregister_drop.sh: OK"
else
  echo "ctl_unregister_drop.sh: FAILED"
  exit 1
fi
