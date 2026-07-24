#!/usr/bin/env python3
"""Single source of truth for the soloterm-agent-org doctrine skills.

WHY THIS EXISTS (marketplace#11)
    Five role skills ship in four sibling plugins: 20 files, and until now every
    one of them was hand-maintained. A doctrine edit meant applying the same
    change four times, and the copies drifted silently. The org-audit skill had
    already split into two flavours nobody chose.

HOW TO EDIT DOCTRINE
    1. edit tools/soloterm-skills/src/<skill>/SKILL.md   (the only hand-edited copy)
    2. run  python3 tools/soloterm-skills/sync-skills.py (materializes 20 copies)
    3. commit src/ and the regenerated plugins/... files in the same commit

    Never hand-edit plugins/soloterm-agent-org*/skills/*/SKILL.md. Sync overwrites
    it and --check fails the moment it differs from its source.

    The generated copies stay committed on purpose: a plugin directory is installed
    as-is, with no build step, so each variant must remain self-contained.

VARIANT DELTAS
    A variant that genuinely needs different words declares an OVERLAY below: an
    ordered list of literal (find, replace) pairs applied to that one copy. Every
    `find` must occur exactly once or the run aborts, so a source rewrite can never
    silently no-op an overlay. Do not fork a whole copy; that is the bug this
    script exists to prevent.

VERIFY
    python3 tools/soloterm-skills/sync-skills.py --check
    exit 0: every shipped copy matches its source.
    exit 1: drift, printed as a unified diff (source vs shipped).
"""

from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
SRC = HERE / "src"
PLUGINS = REPO_ROOT / "plugins"

VARIANTS = (
    "soloterm-agent-org",
    "soloterm-agent-org-grok",
    "soloterm-agent-org-codex",
    "soloterm-agent-org-antigravity",
)

SKILLS = (
    "orchestrator",
    "solo-worker",
    "planner",
    "replacer",
    "org-audit",
)

# Variant deltas keyed by (variant, skill). See VARIANT DELTAS above.
# Example of the shape:
#     ("soloterm-agent-org-codex", "solo-worker"): [
#         ("run the gate build", "run the gate build with --full-auto"),
#     ],
OVERLAYS: dict[tuple[str, str], list[tuple[str, str]]] = {}


def source_path(skill: str) -> Path:
    return SRC / skill / "SKILL.md"


def target_path(variant: str, skill: str) -> Path:
    return PLUGINS / variant / "skills" / skill / "SKILL.md"


def render(variant: str, skill: str) -> str:
    """Source text for one skill with that variant's overlay applied."""
    text = source_path(skill).read_bytes().decode("utf-8")
    for find, replace in OVERLAYS.get((variant, skill), []):
        hits = text.count(find)
        if hits != 1:
            sys.exit(
                f"overlay for {variant}/{skill} matched {hits} times, expected 1:\n"
                f"    {find!r}\n"
                f"Fix the overlay in {Path(__file__).name}, or the source text it targets."
            )
        text = text.replace(find, replace)
    return text


def shipped(variant: str, skill: str) -> str | None:
    path = target_path(variant, skill)
    if not path.exists():
        return None
    return path.read_bytes().decode("utf-8")


def unmanaged() -> list[Path]:
    """Skill dirs that exist in a variant but are not in SKILLS: forked copies."""
    found = []
    for variant in VARIANTS:
        for path in sorted((PLUGINS / variant / "skills").glob("*/SKILL.md")):
            if path.parent.name not in SKILLS:
                found.append(path)
    return found


def rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def sync() -> int:
    written = 0
    for variant in VARIANTS:
        for skill in SKILLS:
            want = render(variant, skill)
            if shipped(variant, skill) == want:
                continue
            path = target_path(variant, skill)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(want.encode("utf-8"))
            written += 1
            print(f"wrote {rel(path)}")
    total = len(VARIANTS) * len(SKILLS)
    print(f"{written} of {total} copies updated, {total - written} already current")
    return 0


def check() -> int:
    problems = 0
    for variant in VARIANTS:
        for skill in SKILLS:
            want = render(variant, skill)
            have = shipped(variant, skill)
            if have == want:
                continue
            problems += 1
            target = target_path(variant, skill)
            print(f"DRIFT {rel(target)}")
            sys.stdout.writelines(
                difflib.unified_diff(
                    want.splitlines(keepends=True),
                    (have or "").splitlines(keepends=True),
                    fromfile=f"source  {rel(source_path(skill))}",
                    tofile=f"shipped {rel(target)}",
                )
            )
    for path in unmanaged():
        problems += 1
        print(f"UNMANAGED {rel(path)}: add its dir name to SKILLS, or delete it")
    if problems:
        print(
            f"\n{problems} problem(s). Doctrine is edited in "
            "tools/soloterm-skills/src/<skill>/SKILL.md, then materialized by running "
            "this script with no arguments."
        )
        return 1
    print(f"ok: {len(VARIANTS) * len(SKILLS)} shipped copies match their source")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Materialize the soloterm-agent-org role skills into all four plugin variants.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify only: exit 1 if any shipped copy differs from its source",
    )
    args = parser.parse_args()
    return check() if args.check else sync()


if __name__ == "__main__":
    sys.exit(main())
