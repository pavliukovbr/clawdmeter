#!/usr/bin/env python3
"""Write the app icon: Clawd on the same grid the app draws him on.

Plain 8 bit RGBA PNG, written by hand so the build needs nothing but python3.
Usage: mkicon.py <path> <size>
"""
import struct
import sys
import zlib

CLAY = (215, 119, 87, 255)
CLAY_LIGHT = (236, 150, 118, 255)
CLAY_DEEP = (190, 92, 62, 255)
INK = (20, 16, 14, 255)
TOP = (52, 43, 39)
BOTTOM = (29, 25, 23)

# x, y, width, height, colour. Same squares as CMClawd draws.
PARTS = [
    (3, 7, 1, 3, CLAY_DEEP),
    (5, 7, 1, 3, CLAY_DEEP),
    (10, 7, 1, 3, CLAY_DEEP),
    (12, 7, 1, 3, CLAY_DEEP),
    (0, 4, 2, 2, CLAY_DEEP),
    (14, 4, 2, 2, CLAY_DEEP),
    (2, 0, 12, 8, CLAY),
    (3, 0, 10, 1, CLAY_LIGHT),
    (4, 2, 1, 2, INK),
    (11, 2, 1, 2, INK),
]

GRID_W = 16.0
GRID_H = 10.0


def colour_at(x, y, size):
    cell = size / 20.0
    left = (size - GRID_W * cell) / 2.0
    top = (size - GRID_H * cell) / 2.0
    gx = (x - left) / cell
    gy = (y - top) / cell

    for px, py, pw, ph, colour in PARTS:
        if px <= gx < px + pw and py <= gy < py + ph:
            return colour

    slide = y / float(size - 1)
    return (int(TOP[0] + (BOTTOM[0] - TOP[0]) * slide),
            int(TOP[1] + (BOTTOM[1] - TOP[1]) * slide),
            int(TOP[2] + (BOTTOM[2] - TOP[2]) * slide),
            255)


def write_png(path, size):
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter type 0
        for x in range(size):
            row += bytes(colour_at(x, y, size))
        rows.append(bytes(row))

    def chunk(tag, data):
        head = struct.pack(">I", len(data)) + tag + data
        return head + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
            + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(blob)
    print("wrote %s (%d bytes, %dx%d)" % (path, len(blob), size, size))


if __name__ == "__main__":
    write_png(sys.argv[1], int(sys.argv[2]))
