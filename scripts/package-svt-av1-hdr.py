#!/usr/bin/env python3
"""Repack an upstream SVT-AV1-HDR source archive into a deterministic tarball.

HandBrake names the extracted directory after the tarball (minus the archive
extension), so the output is always rooted at a single ``--root`` directory.
Metadata is normalised so the resulting archive can be byte-for-byte
reproduced and verified by its sha256.
"""

from __future__ import annotations

import argparse
import copy
import gzip
import tarfile


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"error: {message}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="upstream .tar.gz archive")
    parser.add_argument("--output", required=True, help="deterministic archive to write")
    parser.add_argument("--root", required=True, help="top-level directory in the output")
    return parser.parse_args()


def normalise(member: tarfile.TarInfo, name: str) -> tarfile.TarInfo:
    member.name = name
    member.uid = 0
    member.gid = 0
    member.uname = ""
    member.gname = ""
    member.mtime = 0
    member.pax_headers = {}
    if member.isdir():
        member.mode = 0o755
    else:
        member.mode = 0o755 if member.mode & 0o111 else 0o644
    return member


def main() -> int:
    args = parse_args()

    with tarfile.open(args.input, "r:*") as source:
        members = source.getmembers()
        if not members:
            fail(f"{args.input} is empty")

        roots = {m.name.split("/", 1)[0] for m in members if m.name not in ("", ".")}
        if len(roots) != 1:
            fail(f"expected a single top-level directory, found: {sorted(roots)}")
        source_root = roots.pop()

        members.sort(key=lambda m: m.name)

        with open(args.output, "wb") as raw:
            # mtime=0 and an empty filename make the gzip wrapper reproducible.
            with gzip.GzipFile(
                filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0
            ) as gz:
                with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as out:
                    root = tarfile.TarInfo(args.root)
                    root.type = tarfile.DIRTYPE
                    root.mode = 0o755
                    out.addfile(root)

                    for original in members:
                        if original.name == source_root:
                            continue
                        if not original.name.startswith(source_root + "/"):
                            fail(f"entry outside {source_root!r}: {original.name}")

                        relative = original.name[len(source_root) + 1 :]
                        if not relative:
                            continue

                        member = normalise(
                            copy.copy(original), f"{args.root}/{relative}"
                        )

                        if member.islnk() and member.linkname:
                            _, separator, tail = member.linkname.partition("/")
                            member.linkname = args.root + (
                                "/" + tail if separator else ""
                            )

                        if member.isfile():
                            handle = source.extractfile(original)
                            if handle is None:
                                fail(f"cannot read {original.name}")
                            with handle:
                                out.addfile(member, handle)
                        else:
                            out.addfile(member)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
