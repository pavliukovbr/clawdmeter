#!/usr/bin/env python3
"""Put the Thumb bit back on the entry point of an armv7 binary.

On armv7 the processor decides between ARM and Thumb from bit 0 of the address it
branches to. Clang builds main as Thumb code, and the loader reads the entry point out
of the LC_MAIN load command, so that offset has to be odd. The linker that ships today
no longer does this for armv7, since Apple dropped the architecture years ago, and the
result is a phone that jumps into Thumb code in ARM mode and dies on the first
instruction of main.

This reads the symbol table, checks whether main really is Thumb, and sets the bit.
Run it after linking and before signing.

Usage: fixentry.py <mach-o binary>
"""
import struct
import sys

MH_MAGIC = 0xFEEDFACE
LC_SYMTAB = 0x2
LC_SEGMENT = 0x1
LC_MAIN = 0x80000028
N_ARM_THUMB_DEF = 0x0008


def load_commands(data):
    magic, = struct.unpack_from("<I", data, 0)
    if magic != MH_MAGIC:
        raise SystemExit("not a 32 bit little endian Mach-O (magic %08x)" % magic)
    ncmds, = struct.unpack_from("<I", data, 16)
    offset = 28
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, offset)
        yield cmd, offset, size
        offset += size


def main_symbol(data, symoff, nsyms, stroff):
    for i in range(nsyms):
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHI", data, symoff + i * 12)
        end = data.index(b"\0", stroff + n_strx)
        if data[stroff + n_strx:end] == b"_main":
            return n_value, bool(n_desc & N_ARM_THUMB_DEF)
    return None, False


def fix(path):
    with open(path, "rb") as handle:
        data = bytearray(handle.read())

    entry_at = None
    entryoff = None
    text_addr = None
    address = None
    thumb = False

    for cmd, offset, size in load_commands(data):
        if cmd == LC_MAIN:
            entry_at = offset + 8
            entryoff, = struct.unpack_from("<Q", data, entry_at)
        elif cmd == LC_SYMTAB:
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, offset + 8)
            address, thumb = main_symbol(data, symoff, nsyms, stroff)
        elif cmd == LC_SEGMENT:
            name = bytes(data[offset + 8:offset + 24]).rstrip(b"\0")
            if name == b"__TEXT":
                text_addr, = struct.unpack_from("<I", data, offset + 24)

    if entry_at is None:
        raise SystemExit("no LC_MAIN in %s" % path)
    if address is None:
        raise SystemExit("no _main symbol in %s, cannot tell ARM from Thumb" % path)
    if text_addr is None:
        raise SystemExit("no __TEXT segment in %s" % path)

    expected = address - text_addr
    if entryoff & ~1 != expected:
        raise SystemExit("entry point 0x%x does not point at main 0x%x" % (entryoff, address))

    if not thumb:
        print("entry point is ARM code, nothing to set")
        return
    if entryoff & 1:
        print("entry point already carries the Thumb bit")
        return

    struct.pack_into("<Q", data, entry_at, entryoff | 1)
    with open(path, "wb") as handle:
        handle.write(data)
    print("set the Thumb bit on the entry point: 0x%x becomes 0x%x" % (entryoff, entryoff | 1))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: fixentry.py <binary>")
        raise SystemExit(1)
    fix(sys.argv[1])
