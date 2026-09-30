"""Alpha-channel stats for RGBA PNGs, standard library only.

Used after every generation to catch the two GPT Image failure modes we have
seen: a "transparent" asset that is actually a full opaque scene, and a soft
semi-transparent halo around the subject (reads as a dark smudge in game).
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
COLOR_TYPE_RGB = 2
COLOR_TYPE_RGBA = 6
TRANSPARENT_MAX = 10      # alpha <= this counts as fully transparent
OPAQUE_MIN = 245          # alpha >= this counts as fully opaque
NOISE_ALPHA_MAX = 24      # alpha <= this is GPT Image noise, zeroed by clean_and_trim
TRIM_PADDING = 4          # px of transparent margin kept around the subject


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def decode_rgba(path: Path) -> tuple[int, int, bytearray] | None:
    """Decodes an 8-bit RGB or RGBA PNG into (width, height, flat RGBA bytes), or None.

    RGB images get alpha 255, so callers always work with 4 bytes per pixel.
    """
    data = path.read_bytes()
    if data[:8] != PNG_SIGNATURE:
        return None
    width, height, bit_depth, color_type = struct.unpack(">IIBB", data[16:26])
    if bit_depth != 8 or color_type not in (COLOR_TYPE_RGB, COLOR_TYPE_RGBA):
        return None
    channels = 4 if color_type == COLOR_TYPE_RGBA else 3
    idat, offset = b"", 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        if data[offset + 4:offset + 8] == b"IDAT":
            idat += data[offset + 8:offset + 8 + length]
        offset += 12 + length
    raw = zlib.decompress(idat)
    stride = width * channels
    pixels = bytearray(width * height * 4)
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = line[x - channels] if x >= channels else 0
            up = previous[x]
            if kind == 1:
                line[x] = (line[x] + left) & 255
            elif kind == 2:
                line[x] = (line[x] + up) & 255
            elif kind == 3:
                line[x] = (line[x] + ((left + up) >> 1)) & 255
            elif kind == 4:
                line[x] = (line[x] + _paeth(left, up, previous[x - channels] if x >= channels else 0)) & 255
        row = y * width * 4
        if channels == 4:
            pixels[row:row + width * 4] = line
        else:
            for px in range(width):
                pixels[row + px * 4:row + px * 4 + 3] = line[px * 3:px * 3 + 3]
                pixels[row + px * 4 + 3] = 255
        previous = line
    return width, height, pixels


def encode_rgba(width: int, height: int, pixels: bytearray) -> bytes:
    """Encodes flat RGBA bytes as a PNG (filter 0, zlib level 9)."""
    stride = width * 4
    raw = b"".join(b"\x00" + bytes(pixels[y * stride:(y + 1) * stride]) for y in range(height))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, COLOR_TYPE_RGBA, 0, 0, 0)
    return PNG_SIGNATURE + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def alpha_stats(path: Path) -> dict | None:
    """Returns {"transparent": %, "semi": %, "opaque": %} or None if not an 8-bit RGBA PNG."""
    decoded = decode_rgba(path)
    if decoded is None:
        return None
    width, height, pixels = decoded
    counts = {"transparent": 0, "semi": 0, "opaque": 0}
    for alpha in pixels[3::4]:
        if alpha <= TRANSPARENT_MAX:
            counts["transparent"] += 1
        elif alpha >= OPAQUE_MIN:
            counts["opaque"] += 1
        else:
            counts["semi"] += 1
    total = width * height
    return {k: round(100 * v / total, 1) for k, v in counts.items()}


def clean_and_trim(path: Path, threshold: int = NOISE_ALPHA_MAX, pad: int = TRIM_PADDING) -> tuple | None:
    """Zeroes near-invisible alpha noise and crops the PNG to its visible content.

    GPT Image scatters alpha 1..24 pixels across "transparent" areas, so a plain
    used-rect crop keeps almost the whole canvas and the subject renders small.
    Rewrites the file in place. Returns ((old_w, old_h), (new_w, new_h)) or None.
    """
    decoded = decode_rgba(path)
    if decoded is None:
        return None
    width, height, pixels = decoded
    x0, y0, x1, y1 = width, height, -1, -1
    for i in range(3, len(pixels), 4):
        if pixels[i] <= threshold:
            pixels[i - 3:i + 1] = b"\x00\x00\x00\x00"
            continue
        p = i // 4
        x, y = p % width, p // width
        x0, x1 = min(x0, x), max(x1, x)
        y0, y1 = min(y0, y), max(y1, y)
    if x1 < 0:
        return None
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(width - 1, x1 + pad), min(height - 1, y1 + pad)
    new_w, new_h = x1 - x0 + 1, y1 - y0 + 1
    cropped = bytearray()
    for y in range(y0, y1 + 1):
        cropped += pixels[(y * width + x0) * 4:(y * width + x1 + 1) * 4]
    path.write_bytes(encode_rgba(new_w, new_h, cropped))
    return (width, height), (new_w, new_h)


def verdict(stats: dict | None, min_transparent: float = 30.0, max_semi: float = 8.0) -> str:
    """Human-readable warning, or "" when the asset looks clean."""
    if stats is None:
        return "no es PNG RGBA de 8 bits"
    if stats["transparent"] < min_transparent:
        return f"casi sin transparencia ({stats['transparent']}%): probablemente dibujó un fondo"
    if stats["semi"] > max_semi:
        return f"halo semitransparente ({stats['semi']}% de píxeles): se verá como mancha"
    return ""
