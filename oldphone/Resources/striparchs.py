#!/usr/bin/env python3
"""Take the simulator architectures out of every stub library in an iOS SDK.

The theos mirror of the iOS 9.3 SDK lists i386 and x86_64 in the .tbd stubs, but the
device SDK has no simulator slices behind those names, and a current linker treats the
mismatch as an error. Removing the two names leaves the arm side untouched.

Usage: striparchs.py <path to the sdk>
"""
import os
import re
import sys

DROP = ("i386", "x86_64")
ARCH_LINE = re.compile(r"^(\s*(?:-\s+)?archs:\s*\[)([^\]]*)(\].*)$")


def strip_line(line):
    match = ARCH_LINE.match(line)
    if match is None:
        return line, False
    names = [name.strip() for name in match.group(2).split(",") if name.strip()]
    kept = [name for name in names if name not in DROP]
    if kept == names:
        return line, False
    if not kept:
        kept = names  # never leave a stub with no architectures at all
    return "%s %s %s" % (match.group(1), ", ".join(kept), match.group(3).lstrip()), True


def strip_file(path):
    with open(path, "r", errors="replace") as handle:
        lines = handle.read().splitlines(True)

    touched = False
    out = []
    for line in lines:
        ending = "\n" if line.endswith("\n") else ""
        fixed, changed = strip_line(line.rstrip("\n"))
        touched = touched or changed
        out.append(fixed + ending)

    if touched:
        with open(path, "w") as handle:
            handle.write("".join(out))
    return touched


def main(root):
    count = 0
    for folder, _, names in os.walk(root):
        for name in names:
            if name.endswith(".tbd") and strip_file(os.path.join(folder, name)):
                count += 1
    print("patched %d stub libraries" % count)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: striparchs.py <sdk>")
        raise SystemExit(1)
    main(sys.argv[1])
