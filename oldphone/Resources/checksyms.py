#!/usr/bin/env python3
"""Check that every symbol the binary imports really exists in the iOS 9.3 SDK.

A call to something Apple added later links fine against a newer toolchain and then
crashes the moment the old phone touches it, so this walks the stub libraries in the
SDK and makes sure each undefined symbol is named in one of them.

Usage: checksyms.py <path to the sdk> <path to the binary>
"""
import os
import re
import subprocess
import sys

TOKEN = re.compile(r"[A-Za-z0-9_$.]+")


def sdk_names(root):
    names = set()
    for folder, _, files in os.walk(root):
        for name in files:
            if not name.endswith(".tbd"):
                continue
            path = os.path.join(folder, name)
            with open(path, "r", errors="replace") as handle:
                names.update(TOKEN.findall(handle.read()))
    return names


def undefined(binary):
    out = subprocess.check_output(["xcrun", "nm", "-u", binary]).decode("utf-8", "replace")
    return [line.strip() for line in out.splitlines() if line.strip()]


def wanted(symbol):
    """The name to look for: an Objective C class is listed without its mangling."""
    for prefix in ("_OBJC_CLASS_$", "_OBJC_METACLASS_$", "_OBJC_EHTYPE_$", "_OBJC_IVAR_$"):
        if symbol.startswith(prefix):
            return symbol[len(prefix):]
    return symbol


def main(sdk, binary):
    names = sdk_names(sdk)
    if not names:
        print("no stub libraries found under %s" % sdk)
        return 1

    symbols = undefined(binary)
    missing = [s for s in symbols if wanted(s) not in names]

    if missing:
        print("symbols not found in the 9.3 SDK:")
        for symbol in missing:
            print("  %s" % symbol)
        return 1

    print("all %d imported symbols exist in the 9.3 SDK" % len(symbols))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: checksyms.py <sdk> <binary>")
        raise SystemExit(1)
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
