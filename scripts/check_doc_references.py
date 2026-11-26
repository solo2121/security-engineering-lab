#!/usr/bin/env python3
"""
check_doc_references.py — Catch dangling filenames in doc index entries.

`markdown-link-check` (see .markdown-link-check.json / `make docs`) only
validates real Markdown links: `[text](path)`. It does NOT look at plain
backtick-quoted filenames used as the "row label" of a documentation index,
e.g.:

    - **`docs/network-map.md`** – Network topology and host details.
    | `docs/attack-guide.md` | Full attack-chain walkthrough for this lab |

If that file is renamed or deleted, `markdown-link-check` has nothing to
flag — the reference is just text, not a link. That's exactly how a stale
reference to a nonexistent `docs/network-map.md` went unnoticed in
`labs/security/README.md` until a manual review caught it.

This script closes that specific gap. It intentionally only matches two
patterns — a bulleted, bolded filename, and a table's first cell — because
those are the actual doc-index conventions used across this repo's
READMEs. It deliberately does NOT scan arbitrary inline code spans or
fenced code blocks, since those routinely contain hypothetical filenames
from tutorial examples (e.g. `app.py`, `docker-compose.yml` in a guide)
that were never meant to exist in this repository.

Resolution is suffix-aware: a reference like `docs/attack-guide.md` is
considered valid if ANY file in the repo ends with that relative path
(e.g. `labs/security/ad-pentest/docs/attack-guide.md`), since several
lab-level READMEs use lab-relative shorthand rather than full repo-root
paths.

Usage:
    python3 scripts/check_doc_references.py
    python3 scripts/check_doc_references.py --verbose

Exit status:
    0  no dangling references found
    1  one or more dangling references found
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

# A bulleted, bolded backtick filename at the start of a list item, e.g.:
#   - **`docs/attack-guide.md`** – Full attack-chain walkthrough...
BULLET_PATTERN = re.compile(r"^\s*-\s+\*\*`([^`]+)`\*\*")

# A backtick filename as the first cell of a Markdown table row, e.g.:
#   | `docs/attack-guide.md` | Full attack-chain walkthrough... |
TABLE_PATTERN = re.compile(r"^\|\s*`([^`]+)`\s*\|")

# Only treat these as path references (skip e.g. `v1.12`, `HARBOR_PASS`).
CANDIDATE_EXTENSIONS = {
    ".md",
    ".py",
    ".sh",
    ".yml",
    ".yaml",
    ".json",
    ".toml",
    ".txt",
}


def looks_like_path_reference(candidate: str) -> bool:
    if any(ch in candidate for ch in (" ", "\t")):
        return False
    if "://" in candidate or candidate.startswith(("http", "mailto:")):
        return False
    return Path(candidate).suffix in CANDIDATE_EXTENSIONS


def build_repo_file_index() -> list[Path]:
    """All tracked-looking files under the repo, excluding .git and vagrant state."""
    return [p for p in REPO_ROOT.rglob("*") if p.is_file() and ".git" not in p.parts and ".vagrant" not in p.parts]


def resolves_somewhere(candidate: str, referencing_file: Path, repo_files: list[Path]) -> bool:
    # 1. Relative to the referencing file's own directory.
    if (referencing_file.parent / candidate).exists():
        return True
    # 2. Relative to the repo root.
    if (REPO_ROOT / candidate).exists():
        return True
    # 3. Suffix match anywhere in the repo (handles lab-relative shorthand
    #    like `docs/attack-guide.md` used from a parent README).
    candidate_parts = Path(candidate).parts
    for f in repo_files:
        if f.parts[-len(candidate_parts) :] == candidate_parts:
            return True
    return False


def find_dangling_references(md_file: Path, repo_files: list[Path], verbose: bool) -> list[str]:
    problems = []
    lines = md_file.read_text(encoding="utf-8", errors="ignore").splitlines()

    for lineno, line in enumerate(lines, start=1):
        match = BULLET_PATTERN.match(line) or TABLE_PATTERN.match(line)
        if not match:
            continue
        candidate = match.group(1).strip()
        if not looks_like_path_reference(candidate):
            continue

        if resolves_somewhere(candidate, md_file, repo_files):
            if verbose:
                try:
                    shown = md_file.relative_to(REPO_ROOT)
                except ValueError:
                    shown = md_file
                print(f"    ok: {shown}:{lineno} -> `{candidate}`")
            continue

        try:
            rel = md_file.relative_to(REPO_ROOT)
        except ValueError:
            rel = md_file  # e.g. under test, outside REPO_ROOT
        problems.append(f"{rel}:{lineno}: `{candidate}` does not exist on disk")

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="check_doc_references.py",
        description=(
            "Scan doc-index bullets/tables for backtick filenames that don't "
            "resolve to a real file (catches drift markdown-link-check can't see)."
        ),
    )
    parser.add_argument("--verbose", action="store_true", help="print each reference checked")
    args = parser.parse_args()

    md_files = sorted(p for p in REPO_ROOT.rglob("*.md") if ".git" not in p.parts)
    repo_files = build_repo_file_index()

    all_problems: list[str] = []
    for md_file in md_files:
        if args.verbose:
            print(f"Checking {md_file.relative_to(REPO_ROOT)}")
        all_problems.extend(find_dangling_references(md_file, repo_files, args.verbose))

    if all_problems:
        print(f"FAIL: {len(all_problems)} dangling doc reference(s) found:\n")
        for problem in all_problems:
            print(f"  - {problem}")
        return 1

    print(f"PASS: no dangling doc references found ({len(md_files)} files scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
