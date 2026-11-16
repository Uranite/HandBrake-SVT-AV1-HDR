#!/usr/bin/env python3
"""Generate patches/0004-change-repo-url.patch from HandBrake's module.defs.

Regenerating the patch against the current HandBrake tree keeps it applying
when HandBrake bumps its bundled SVT-AV1 version (which changes the lines the
patch replaces).
"""

from __future__ import annotations

import argparse
import difflib
import re
from pathlib import Path

FETCH_LINE = re.compile(r"^SVT-AV1\.FETCH\.(?:url|sha256)\b")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="HandBrake module.defs")
    parser.add_argument("--url", required=True, help="SVT-AV1-HDR tarball URL")
    parser.add_argument("--sha256", required=True, help="SVT-AV1-HDR tarball sha256")
    parser.add_argument("--output", required=True, help="patch file to write")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    original = Path(args.input).read_text(encoding="utf-8").splitlines(keepends=True)
    updated: list[str] = []
    replaced = False

    index = 0
    while index < len(original):
        if not FETCH_LINE.match(original[index]):
            updated.append(original[index])
            index += 1
            continue

        if replaced:
            raise SystemExit("error: found more than one SVT-AV1.FETCH block")

        while index < len(original) and FETCH_LINE.match(original[index]):
            index += 1

        updated.append(f"SVT-AV1.FETCH.url      = {args.url}\n")
        updated.append(f"SVT-AV1.FETCH.sha256   = {args.sha256}\n")
        replaced = True

    if not replaced:
        raise SystemExit("error: no SVT-AV1.FETCH lines found in module.defs")

    diff = difflib.unified_diff(
        original,
        updated,
        fromfile="a/contrib/svt-av1/module.defs",
        tofile="b/contrib/svt-av1/module.defs",
        n=3,
    )
    body = "".join(diff)
    if not body:
        Path(args.output).write_text("", encoding="utf-8")
        return 0

    patch = (
        "diff --git a/contrib/svt-av1/module.defs b/contrib/svt-av1/module.defs\n"
        + body
    )
    if not patch.endswith("\n"):
        patch += "\n"

    Path(args.output).write_text(patch, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
