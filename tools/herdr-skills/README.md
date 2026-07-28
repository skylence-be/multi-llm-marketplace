# herdr-skills

Drift check for the `herdr-agent-org-claude` / `herdr-agent-org-grok` skill
pairs. Unlike `tools/soloterm-skills` (one canonical source, generated
copies), the two herdr variants are deliberate voice forks: claude carries the
full prose, grok the condensed form, and both must stay self-contained and
installable as-is. So instead of a byte diff, `check-parity.sh` verifies:

1. the orchestrators agree on the LAW set (same `L<n>` numbers and titles), and
2. load-bearing invariant phrases appear in BOTH members of each skill pair
   (for example `STAY RESIDENT`, `waker-ctl unregister`, the contract-not-menu
   sections, the `startup|resume` priming matcher).

```bash
sh tools/herdr-skills/check-parity.sh   # exits 1 on drift, naming each miss
```

Wired in `.githooks/pre-commit` and `.github/workflows/checks.yml`. When a PR
adds doctrine that both variants must carry, add its marker phrase to the
`both` lines in the script in the same PR; the check is only as strong as
that list.
