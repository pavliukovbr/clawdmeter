#!/usr/bin/env python3
"""Draws the Clawdmeter icon and writes windows/Clawdmeter/Clawdmeter.ico.

Everything is painted by hand at four times the size and then averaged down, so the
pixel art keeps its hard edges while the rounded corners stay smooth.
"""

import struct
import zlib
from pathlib import Path

SIZES = [256, 128, 64, 48, 32, 16]
SCALE = 4

BACK_TOP = (52, 43, 39)
BACK_BOTTOM = (29, 25, 23)
CLAY = (215, 119, 87)
CLAY_LIGHT = (236, 150, 118)
CLAY_DEEP = (190, 92, 62)
EYE = (24, 19, 17)
TRACK = (255, 255, 255, 40)

BODY = [(2, 0, 12, 8), (0, 4, 2, 2), (14, 4, 2, 2)]
LEGS = [(3, 7, 1, 3), (5, 7, 1, 3), (10, 7, 1, 3), (12, 7, 1, 3)]
EYES = [(4, 2, 1, 2), (11, 2, 1, 2)]


def blend(canvas, size, x, y, color):
    if x < 0 or y < 0 or x >= size or y >= size:
        return
    alpha = color[3] if len(color) > 3 else 255
    index = (y * size + x) * 4
    if alpha >= 255:
        canvas[index:index + 4] = bytes((color[0], color[1], color[2], 255))
        return
    for channel in range(3):
        old = canvas[index + channel]
        canvas[index + channel] = (old * (255 - alpha) + color[channel] * alpha) // 255
    canvas[index + 3] = max(canvas[index + 3], alpha)


def fill_rect(canvas, size, left, top, width, height, color):
    for y in range(int(round(top)), int(round(top + height))):
        for x in range(int(round(left)), int(round(left + width))):
            blend(canvas, size, x, y, color)


def fill_round_rect(canvas, size, left, top, width, height, radius, color_at):
    right = left + width
    bottom = top + height
    for y in range(int(top), int(bottom)):
        for x in range(int(left), int(right)):
            dx = 0.0
            dy = 0.0
            if x < left + radius:
                dx = left + radius - x - 0.5
            elif x > right - radius:
                dx = x + 0.5 - (right - radius)
            if y < top + radius:
                dy = top + radius - y - 0.5
            elif y > bottom - radius:
                dy = y + 0.5 - (bottom - radius)
            if dx * dx + dy * dy > radius * radius:
                continue
            blend(canvas, size, x, y, color_at(x, y))


def draw(size):
    canvas = bytearray(size * size * 4)
    unit = size / 16.0

    def background(_x, y):
        ratio = y / size
        return tuple(int(BACK_TOP[c] + (BACK_BOTTOM[c] - BACK_TOP[c]) * ratio) for c in range(3)) + (255,)

    fill_round_rect(canvas, size, 0, 0, size, size, size * 0.22, background)

    # Clawd sits a little above the middle, with room for the meters underneath.
    grid = size / 20.0
    origin_x = (size - grid * 16) / 2
    origin_y = size * 0.13

    for shape, color in ((BODY, CLAY), (LEGS, CLAY_DEEP)):
        for cell in shape:
            fill_rect(canvas, size, origin_x + cell[0] * grid, origin_y + cell[1] * grid,
                      cell[2] * grid, cell[3] * grid, color)
    for cell in EYES:
        fill_rect(canvas, size, origin_x + cell[0] * grid, origin_y + cell[1] * grid,
                  cell[2] * grid, cell[3] * grid, EYE)

    bar_height = unit * 0.85
    bar_left = size * 0.2
    bar_width = size * 0.6
    for index, fraction in enumerate((0.78, 0.42)):
        top = size * 0.72 + index * bar_height * 2.1
        fill_round_rect(canvas, size, bar_left, top, bar_width, bar_height, bar_height / 2,
                        lambda _x, _y: TRACK)
        fill_round_rect(canvas, size, bar_left, top, bar_width * fraction, bar_height, bar_height / 2,
                        lambda x, _y: tuple(
                            int(CLAY_DEEP[c] + (CLAY_LIGHT[c] - CLAY_DEEP[c]) * ((x - bar_left) / bar_width))
                            for c in range(3)) + (255,))
    return canvas


def downscale(canvas, size, factor):
    small = size // factor
    out = bytearray(small * small * 4)
    area = factor * factor
    for y in range(small):
        for x in range(small):
            totals = [0, 0, 0, 0]
            for sy in range(factor):
                for sx in range(factor):
                    index = ((y * factor + sy) * size + x * factor + sx) * 4
                    for channel in range(4):
                        totals[channel] += canvas[index + channel]
            index = (y * small + x) * 4
            for channel in range(4):
                out[index + channel] = totals[channel] // area
    return out


def png(canvas, size):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw.extend(canvas[y * size * 4:(y + 1) * size * 4])

    def chunk(tag, payload):
        data = tag + payload
        return struct.pack(">I", len(payload)) + data + struct.pack(">I", zlib.crc32(data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def main():
    images = []
    for size in SIZES:
        big = draw(size * SCALE)
        images.append((size, png(downscale(big, size * SCALE, SCALE), size)))

    out = Path(__file__).resolve().parent.parent / "Clawdmeter" / "Clawdmeter.ico"
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = b""
    body = b""
    for size, data in images:
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
        body += data
    out.write_bytes(header + entries + body)
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
