"""Pixel-art post-processing for GPT Image output, standard library only.

GPT Image draws "pixel art" at ~1024 px, so each art pixel is a ~10 px block.
This module turns that into real pixel art on a shared grid:

    raw PNG -> clean alpha noise -> (slice sheet into frames) -> align frames on
    a common box -> area-downscale to the asset's pixel height -> hard alpha

Godot then scales every asset by the SAME integer factor with nearest filtering,
so all art shares one pixel density — that is what makes it read as one game.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import png_alpha

HARD_ALPHA_CUTOFF = 128     # after downscale: alpha >= this -> 255, else 0 (crisp pixel edges)
BORDER_BLEED_WARN = 0.02    # fraction of a cell border that may touch content before warning
FLOOR_SEARCH_FROM = 0.55    # only the lower part of a level segment can hold the ground line
FLOOR_MIN_EDGE = 40         # median RGB change a row needs to count as the ground edge
GLOW_CELL = 24               # art-pixel cell size scanned for light sources
GLOW_MIN_LUMA = 150          # brightness a cell needs to count as a light source
GLOW_LIMIT = 14              # most light sources kept per image
FEET_BAND = 0.15            # bottom fraction of a frame scanned to find where the feet are


@dataclass
class Image:
    """Flat RGBA image."""
    width: int
    height: int
    pixels: bytearray

    @staticmethod
    def load(path: Path) -> "Image":
        decoded = png_alpha.decode_rgba(path)
        if decoded is None:
            raise ValueError(f"unsupported PNG: {path}")
        return Image(*decoded)

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(png_alpha.encode_rgba(self.width, self.height, self.pixels))

    def alpha(self, x: int, y: int) -> int:
        return self.pixels[(y * self.width + x) * 4 + 3]


def clean_alpha(img: Image, threshold: int = png_alpha.NOISE_ALPHA_MAX) -> None:
    """Zeroes GPT Image's near-invisible alpha noise, in place."""
    p = img.pixels
    for i in range(3, len(p), 4):
        if p[i] <= threshold:
            p[i - 3:i + 1] = b"\x00\x00\x00\x00"


def bbox(img: Image, x0: int = 0, y0: int = 0, x1: int | None = None, y1: int | None = None):
    """Bounding box (x0, y0, x1, y1 inclusive) of non-transparent pixels inside a region, or None."""
    x1 = img.width - 1 if x1 is None else x1
    y1 = img.height - 1 if y1 is None else y1
    bx0, by0, bx1, by1 = x1 + 1, y1 + 1, -1, -1
    for y in range(y0, y1 + 1):
        row = y * img.width
        for x in range(x0, x1 + 1):
            if img.pixels[(row + x) * 4 + 3]:
                bx0, bx1 = min(bx0, x), max(bx1, x)
                by0, by1 = min(by0, y), max(by1, y)
    return None if bx1 < 0 else (bx0, by0, bx1, by1)


def crop(img: Image, x0: int, y0: int, x1: int, y1: int) -> Image:
    """Crops to the inclusive rect; areas outside the image become transparent."""
    w, h = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(w * h * 4)
    for y in range(h):
        sy = y0 + y
        if not 0 <= sy < img.height:
            continue
        for x in range(w):
            sx = x0 + x
            if 0 <= sx < img.width:
                s = (sy * img.width + sx) * 4
                d = (y * w + x) * 4
                out[d:d + 4] = img.pixels[s:s + 4]
    return Image(w, h, out)


def downscale_area(img: Image, new_w: int, new_h: int, hard_alpha: bool = True) -> Image:
    """Area-average downscale with premultiplied alpha (no dark fringes)."""
    new_w, new_h = max(1, new_w), max(1, new_h)
    sx, sy = img.width / new_w, img.height / new_h
    out = bytearray(new_w * new_h * 4)
    src = img.pixels
    for ty in range(new_h):
        ya, yb = int(ty * sy), max(int(ty * sy) + 1, int((ty + 1) * sy))
        for tx in range(new_w):
            xa, xb = int(tx * sx), max(int(tx * sx) + 1, int((tx + 1) * sx))
            r = g = b = a = 0
            count = 0
            for y in range(ya, min(yb, img.height)):
                base = y * img.width
                for x in range(xa, min(xb, img.width)):
                    i = (base + x) * 4
                    al = src[i + 3]
                    r += src[i] * al
                    g += src[i + 1] * al
                    b += src[i + 2] * al
                    a += al
                    count += 1
            d = (ty * new_w + tx) * 4
            if a == 0 or count == 0:
                continue
            alpha = a // count
            if hard_alpha:
                alpha = 255 if alpha >= HARD_ALPHA_CUTOFF else 0
                if alpha == 0:
                    continue
            out[d] = r // a
            out[d + 1] = g // a
            out[d + 2] = b // a
            out[d + 3] = alpha
    return Image(new_w, new_h, out)


def to_pixel_height(img: Image, pixel_height: int, hard_alpha: bool = True) -> Image:
    """Downscales keeping aspect so the image is [pixel_height] art pixels tall."""
    new_w = max(1, round(img.width * pixel_height / img.height))
    return downscale_area(img, new_w, pixel_height, hard_alpha)


def slice_grid(img: Image, columns: int, rows: int) -> tuple[list[Image], list[str]]:
    """Cuts a sheet into columns x rows frames (left-to-right, top-to-bottom).

    All frames are cropped with ONE shared box (the union of every cell's content,
    in cell-local coordinates), so the character keeps the same size and the same
    feet baseline in every frame — no jitter when the animation plays.
    Returns (frames, warnings).
    """
    cell_w, cell_h = img.width // columns, img.height // rows
    boxes, warnings = [], []
    for r in range(rows):
        for c in range(columns):
            x0, y0 = c * cell_w, r * cell_h
            box = bbox(img, x0, y0, x0 + cell_w - 1, y0 + cell_h - 1)
            index = r * columns + c
            if box is None:
                warnings.append(f"frame {index} vacío")
                boxes.append(None)
                continue
            boxes.append((box[0] - x0, box[1] - y0, box[2] - x0, box[3] - y0))
            touching = _border_touch(img, x0, y0, cell_w, cell_h)
            if touching > BORDER_BLEED_WARN:
                warnings.append(f"frame {index} toca el borde de su celda ({touching:.0%}): puede estar cortado")
    valid = [b for b in boxes if b]
    if not valid:
        return [], warnings + ["sin contenido"]
    ux0 = min(b[0] for b in valid)
    uy0 = min(b[1] for b in valid)
    ux1 = max(b[2] for b in valid)
    uy1 = max(b[3] for b in valid)
    frames = []
    for r in range(rows):
        for c in range(columns):
            x0, y0 = c * cell_w, r * cell_h
            frames.append(crop(img, x0 + ux0, y0 + uy0, x0 + ux1, y0 + uy1))
    return frames, warnings


def _border_touch(img: Image, x0: int, y0: int, w: int, h: int) -> float:
    """Fraction of a cell's perimeter pixels that are opaque (content cut by the cell edge)."""
    hits = total = 0
    for x in range(x0, x0 + w):
        for y in (y0, y0 + h - 1):
            total += 1
            hits += img.alpha(x, y) > 0
    for y in range(y0, y0 + h):
        for x in (x0, x0 + w - 1):
            total += 1
            hits += img.alpha(x, y) > 0
    return hits / total if total else 0.0


def feet_anchor(frames: list[Image], band: float = FEET_BAND) -> tuple[int, int]:
    """Where the subject stands, in frame pixels: (median x of the opaque pixels in
    the bottom [band] of every frame, frame height).

    Anchoring on the feet instead of the frame centre keeps the body in place when
    an animation's frames are wider than another's (a wand thrust, a lunge).
    """
    if not frames:
        return 0, 0
    height = frames[0].height
    first_row = max(0, height - max(2, round(height * band)))
    xs: list[int] = []
    for frame in frames:
        for y in range(first_row, frame.height):
            for x in range(frame.width):
                if frame.alpha(x, y):
                    xs.append(x)
    if not xs:
        return frames[0].width // 2, height
    xs.sort()
    return xs[len(xs) // 2], height


def floor_row(img: Image, search_from: float = FLOOR_SEARCH_FROM) -> int | None:
    """Row where the painted ground starts: the strongest horizontal colour edge
    that runs across the WHOLE width, searched in the lower part of the image.

    Per row, it takes the MEDIAN over all columns of the colour change from the row
    above. A bush or a web only changes some columns, so the median ignores it;
    the grass line changes every column. (An opacity-coverage test fails on dense
    undergrowth, which is ~99% opaque well above the ground.)
    """
    width, pixels = img.width, img.pixels
    best_score, best_row = 0, None
    for y in range(max(1, int(img.height * search_from)), img.height):
        diffs = []
        for x in range(width):
            i, j = (y * width + x) * 4, ((y - 1) * width + x) * 4
            diffs.append(abs(pixels[i] - pixels[j]) + abs(pixels[i + 1] - pixels[j + 1]) + abs(pixels[i + 2] - pixels[j + 2]))
        diffs.sort()
        score = diffs[width // 2]
        if score > best_score:
            best_score, best_row = score, y
    return best_row if best_score >= FLOOR_MIN_EDGE else None


def glow_points(img: Image, cell: int = GLOW_CELL, min_luma: int = GLOW_MIN_LUMA,
                limit: int = GLOW_LIMIT) -> list[list[int]]:
    """Bright light sources painted into the art (crystals, fungus, torches).

    Splits the image into cells, keeps cells whose brightest pixel is above
    [min_luma], and returns up to [limit] of the brightest as
    [x, y, r, g, b] (cell centre in art pixels + that pixel's colour), so the
    game can place a real light on each one.
    """
    found = []
    for cy in range(0, img.height, cell):
        for cx in range(0, img.width, cell):
            best, best_px = -1, None
            for y in range(cy, min(cy + cell, img.height)):
                for x in range(cx, min(cx + cell, img.width)):
                    i = (y * img.width + x) * 4
                    if img.pixels[i + 3] < 128:
                        continue
                    r, g, b = img.pixels[i], img.pixels[i + 1], img.pixels[i + 2]
                    luma = (r * 299 + g * 587 + b * 114) // 1000
                    if luma > best:
                        best, best_px = luma, (x, y, r, g, b)
            if best >= min_luma and best_px:
                found.append((best, list(best_px)))
    found.sort(key=lambda item: -item[0])
    return [p for _, p in found[:limit]]


def cover_crop(img: Image, aspect: float) -> Image:
    """Centre-crops an opaque image to [aspect] = width / height."""
    if img.width / img.height > aspect:
        w = round(img.height * aspect)
        x0 = (img.width - w) // 2
        return crop(img, x0, 0, x0 + w - 1, img.height - 1)
    h = round(img.width / aspect)
    y0 = (img.height - h) // 2
    return crop(img, 0, y0, img.width - 1, y0 + h - 1)
