#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_polish_materials.py -- deterministic material-polish pass for hd2d-rpg.

This generator is additive: it does NOT touch tools/gen_assets.py or
tools/gen_npc_assets.py.  It rewrites only its own material set inside
<project>/assets/generated/ with a denser, more painterly take on the same
soft warm mood:

    grass_ground.png      512x512  seamless painterly grass (both axes)
    path_dirt.png         256x256  seamless worn dirt path   (both axes)
    grass_blade.png        16x32   3-blade alpha cutout, green gradient
    flower_white.png         8x8   white petal flower, alpha cutout
    flower_yellow.png        8x8   yellow petal flower, alpha cutout
    ui_panel.png           48x48   nine-slice dialogue panel (8px margins)
    ui_choice_cursor.png     8x8   cream/yellow play arrow (binary alpha)
    particle_dust.png      16x16   soft radial white dot
    particle_pollen.png      8x8   warm pale-yellow soft dot
    particle_firefly.png     8x8   yellow-green glow: halo + brighter core
    _preview_materials.png         contact sheet, everything at 4x nearest

Art rules honoured here
-----------------------
  * brightness / hue family is preserved: both ground tiles are generated,
    then their per-channel mean is shifted by a tiny global offset so that it
    matches the measured pre-polish mean (target within 0.05 per channel in
    normalised 0..1 units; in practice within ~0.5/255).  The old files are
    loaded into memory BEFORE they are overwritten, and the comparison against
    both the file on disk and the fixed reference is printed by the built-in
    verification.  Using the fixed reference as the shift target (instead of
    the file currently on disk) is what keeps re-runs byte-for-byte identical.
  * pixel-craft cutouts (blade, flowers, cursor) keep hard, binary alpha --
    no anti-aliasing anywhere in the sprite palette.
  * soft particle sprites are the deliberate exception: they are meant to be
    blended as glows, so their alpha falls off smoothly to exactly 0 at the
    corners.
  * every tile detail (strands, clumps, stones, ruts, specks) is stamped with
    modulo coordinates, so the wrap seam has the same local statistics as any
    other adjacent pixel pair (verified: wrap ratio < 3 on both axes).
  * fully deterministic: every random stream is seeded below, no wall clock,
    no environment dependent ordering.
  * re-runnable: overwrites its own outputs, creates no .import files, no
    __pycache__, never runs Godot.

Run from anywhere:

    python tools/gen_polish_materials.py

Exit code 0 only when every verification check is green.
"""

from __future__ import annotations

import math
import sys

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__

from pathlib import Path  # noqa: E402

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

# --------------------------------------------------------------------- config
SEED = 20261108

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "generated"

# Means of the pre-polish files, measured in 0..255 units.  Used as the
# brightness target (and as a fallback if a file is missing on a fresh clone).
REFERENCE_MEANS_255 = {
    "grass_ground.png": (77.839, 123.337, 59.220),
    "path_dirt.png": (140.666, 108.556, 70.681),
}

MEAN_TOL = 0.05   # normalised 0..1 per channel, as requested
SEAM_TOL = 3.0    # wrap ratio limit on both axes

# ------------------------------------------------------------------- palettes
# Grass stays inside the original #3E6630 / #4C7A3A / #5C8A45 family; the extra
# stops only extend the same line a little darker / lighter so strokes have
# somewhere to go without changing the hue.
GRASS_STOPS = (
    (0.00, (0x35, 0x59, 0x2A)),
    (0.26, (0x3E, 0x66, 0x30)),   # original dark
    (0.55, (0x4C, 0x7A, 0x3A)),   # original base
    (0.80, (0x5C, 0x8A, 0x45)),   # original light
    (1.00, (0x6E, 0x9A, 0x52)),
)
GRASS_SOIL = (
    (0x46, 0x34, 0x1F),
    (0x4E, 0x3A, 0x24),
    (0x59, 0x44, 0x2A),
    (0x39, 0x2B, 0x19),
)
GRASS_PALE_FLOWER = (
    (0xE9, 0xE4, 0xC6),
    (0xF3, 0xEF, 0xD8),
    (0xE4, 0xD9, 0xB4),
)

PATH_STOPS = (
    (0.00, (0x54, 0x3F, 0x2A)),
    (0.22, (0x6B, 0x51, 0x36)),   # original dark
    (0.52, (0x8A, 0x6A, 0x44)),   # original base
    (0.78, (0xA9, 0x85, 0x5A)),   # original light
    (1.00, (0xBE, 0x9C, 0x6E)),
)
PATH_STONE_BODY = (
    (0xC2, 0xA1, 0x77),
    (0xB4, 0x95, 0x6C),
    (0xA8, 0x8B, 0x62),
    (0x94, 0x80, 0x6B),
)
PATH_STONE_DARK = np.array((0x4A, 0x38, 0x26), np.float32)
PATH_STONE_LIGHT = np.array((0xCB, 0xB4, 0x8C), np.float32)
PATH_RUT_DARK = np.array((0x5E, 0x45, 0x2C), np.float32)
PATH_RUT_MID = np.array((0x67, 0x4C, 0x30), np.float32)
PATH_RUT_SOFT = np.array((0x76, 0x59, 0x38), np.float32)
PATH_RUT_RIM = np.array((0xB0, 0x8E, 0x62), np.float32)
PATH_VERGE = np.array((0x5B, 0x70, 0x42), np.float32)
PATH_VERGE_DARK = np.array((0x3E, 0x54, 0x2E), np.float32)
PATH_MOSS = (
    np.array((0x55, 0x68, 0x3C), np.float32),
    np.array((0x4A, 0x5C, 0x35), np.float32),
)

BLADE_STOPS = (
    (0.00, (0x28, 0x47, 0x20)),
    (0.18, (0x36, 0x5C, 0x2C)),
    (0.55, (0x55, 0x84, 0x40)),
    (0.82, (0x78, 0xA8, 0x58)),
    (1.00, (0xA6, 0xD0, 0x7C)),
)
BLADE_SHADE = np.array((0x24, 0x42, 0x1E), np.float32)
BLADE_RIM = np.array((0xB4, 0xD8, 0x8A), np.float32)

# 5-petal rosette: a top petal, two upper diagonal petals, two wide side
# petals and one lower petal around the centre pixel; the right/lower petals
# are shaded (light comes from the upper left).  2px stem + one leaf.
# P/lit petal, p/shaded petal, C/centre, g/stem, l/leaf.
FLOWER_ART = (
    "........",
    "...P....",
    ".P.P.P..",
    "..PPP...",
    ".PPCpp..",
    "..pPp...",
    "...g....",
    "..lg....",
)
FLOWER_PALETTES = {
    "white": {
        "P": (0xFF, 0xFB, 0xE8, 255),   # warm white
        "p": (0xD9, 0xD3, 0xBC, 255),   # warm grey shade
        "C": (0xE8, 0xC2, 0x5A, 255),   # gold centre
        "g": (0x3E, 0x66, 0x30, 255),   # stem
        "l": (0x5C, 0x8A, 0x45, 255),   # leaf
    },
    "yellow": {
        "P": (0xF2, 0xC9, 0x4C, 255),   # #F2C94C
        "p": (0xD2, 0xA6, 0x3C, 255),
        "C": (0x8E, 0x5A, 0x2C, 255),   # brown seed centre
        "g": (0x4A, 0x6E, 0x36, 255),
        "l": (0x6A, 0x94, 0x4C, 255),
    },
}

# right-pointing play arrow: cream base column, yellow body, amber lower rim
CURSOR_ART = (
    "........",
    ".cY.....",
    ".cYY....",
    ".cYYY...",
    ".cYYYY..",
    ".cYYa...",
    ".cYa....",
    "........",
)
CURSOR_COLORS = {
    "c": (0xE8, 0xDC, 0xC0, 255),   # cream #E8DCC0
    "Y": (0xF2, 0xC9, 0x4C, 255),   # yellow #F2C94C
    "a": (0xD2, 0xA6, 0x3C, 255),   # amber shade
}

# nine-slice panel
PANEL_CREAM = (0xE8, 0xDC, 0xC0)    # #E8DCC0
PANEL_INNER = (0x0E, 0x14, 0x20)    # dark blue-black
PANEL_SHADOW = (0x05, 0x07, 0x0C)
PANEL_ALPHA = 210
PANEL_MARGIN = 8

DUST_COLOR = (255, 255, 255)
POLLEN_COLOR = (0xF6, 0xE9, 0xA8)   # warm pale yellow
FIREFLY_HALO = np.array((0xA8, 0xDE, 0x48), np.float32)   # yellow-green
FIREFLY_CORE = np.array((0xF2, 0xFF, 0x9C), np.float32)   # near-white core

EXPECTED_SIZES = {
    "grass_ground.png": (512, 512),
    "path_dirt.png": (256, 256),
    "grass_blade.png": (16, 32),
    "flower_white.png": (8, 8),
    "flower_yellow.png": (8, 8),
    "ui_panel.png": (48, 48),
    "ui_choice_cursor.png": (8, 8),
    "particle_dust.png": (16, 16),
    "particle_pollen.png": (8, 8),
    "particle_firefly.png": (8, 8),
}

PREVIEW_NAME = "_preview_materials.png"


# =====================================================================
#  generic helpers
# =====================================================================
def _periodic_noise(rng: np.random.Generator, size: int, cells: int) -> np.ndarray:
    """Smooth value noise whose lattice wraps -> the result tiles seamlessly."""
    lat = rng.random((cells, cells)).astype(np.float32)
    coord = np.arange(size, dtype=np.float32) * (cells / float(size))
    i0 = np.floor(coord).astype(np.int32) % cells
    i1 = (i0 + 1) % cells
    fr = coord - np.floor(coord)
    sm = fr * fr * (3.0 - 2.0 * fr)                  # smoothstep
    a = lat[np.ix_(i0, i0)]
    b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]
    d = lat[np.ix_(i1, i1)]
    top = a + (b - a) * sm[None, :]
    bot = c + (d - c) * sm[None, :]
    return top + (bot - top) * sm[:, None]


def _ramp(t: np.ndarray, stops) -> np.ndarray:
    """Vectorised colour ramp: t (H,W) -> rgb (H,W,3)."""
    pos = np.array([p for p, _ in stops], np.float32)
    cols = np.array([c for _, c in stops], np.float32)
    out = np.empty(t.shape + (3,), np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, cols[:, ch])
    return out


def _ramp_at(t: float, stops) -> np.ndarray:
    """Scalar colour ramp used by the stroke / stone loops."""
    pos = [p for p, _ in stops]
    t = min(max(float(t), 0.0), 1.0)
    for i in range(len(stops) - 1):
        if t <= pos[i + 1]:
            k = (t - pos[i]) / (pos[i + 1] - pos[i])
            c0 = np.array(stops[i][1], np.float32)
            c1 = np.array(stops[i + 1][1], np.float32)
            return c0 + (c1 - c0) * k
    return np.array(stops[-1][1], np.float32)


def _match_mean(rgb: np.ndarray, target_255) -> np.ndarray:
    """Shift the whole tile by one global offset per channel until its mean
    matches the target.  The offset is tiny (a couple of levels); hue and
    contrast structure are untouched."""
    target = np.asarray(target_255, np.float32)
    rgb = rgb.astype(np.float32)
    for _ in range(8):
        cur = rgb.reshape(-1, 3).mean(0)
        delta = target - cur
        if float(np.abs(delta).max()) < 0.01:
            break
        rgb = np.clip(rgb + delta, 0.0, 255.0)
    return rgb


def _read_mean_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as im:
        arr = np.asarray(im.convert("RGBA"), dtype=np.float32)
    return arr[..., :3].reshape(-1, 3).mean(0)


def _to_rgba(rgb: np.ndarray, alpha: int = 255) -> Image.Image:
    out = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    rgba = np.dstack((out, np.full(out.shape[:2] + (1,), alpha, np.uint8)))
    return Image.fromarray(rgba)


def _save(img: Image.Image, name: str) -> Path:
    path = OUT_DIR / name
    img.save(path)
    print(f"[wrote] {name:<24} {img.width:>4}x{img.height:<4} "
          f"{path.stat().st_size:>8} bytes")
    return path


# =====================================================================
#  1. grass_ground.png -- 512x512 seamless painterly grass
# =====================================================================
def build_grass_ground(rng: np.random.Generator, target_mean_255) -> Image.Image:
    size = 512
    n = (0.34 * _periodic_noise(rng, size, 2)
         + 0.28 * _periodic_noise(rng, size, 4)
         + 0.20 * _periodic_noise(rng, size, 9)
         + 0.11 * _periodic_noise(rng, size, 23)
         + 0.07 * _periodic_noise(rng, size, 64))
    span = float(n.max() - n.min())
    n = (n - n.min()) / (span if span > 1e-6 else 1.0)

    # soft, wide mottling -- subtle, like the old tile
    mottle = 0.54
    t = np.clip(0.52 + (n - 0.5) * mottle, 0.0, 1.0)
    rgb = _ramp(t, GRASS_STOPS)
    tone = t.copy()

    # fine per-pixel grain (independent per pixel -> tileable by construction)
    grain = rng.random((size, size), dtype=np.float32) - 0.5
    rgb += grain[..., None] * np.array([3.4, 3.4, 2.9], np.float32)

    # ---- layered fine strokes ------------------------------------------
    for _ in range(2000):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        base_t = float(tone[y, x])
        d = float(rng.uniform(0.06, 0.21)) * (1.0 if rng.random() < 0.56 else -1.0)
        col = _ramp_at(base_t + d, GRASS_STOPS)
        length = int(rng.integers(2, 6))
        lean = int(rng.integers(-1, 2))
        wide = rng.random() < 0.22
        for j in range(length):
            xx = (x + (lean if j >= length // 2 else 0)) % size
            yy = (y - j) % size
            rgb[yy, xx] = col
            if wide and j == 0:
                rgb[yy, (xx + 1) % size] = col * 0.94

    # a few short horizontal tuft dashes so the field does not read as rain
    for _ in range(120):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        base_t = float(tone[y, x])
        d = float(rng.uniform(0.05, 0.16)) * (1.0 if rng.random() < 0.6 else -1.0)
        col = _ramp_at(base_t + d, GRASS_STOPS)
        rgb[y, x] = col
        rgb[y, (x + 1) % size] = col * 0.96

    # ---- small clumps with a dark root shadow --------------------------
    for _ in range(68):
        cx = int(rng.integers(0, size))
        cy = int(rng.integers(0, size))
        base_t = float(tone[cy, cx])
        root = _ramp_at(base_t - 0.27, GRASS_STOPS) * 0.82
        rgb[cy, cx] = root
        rgb[cy, (cx + 1) % size] = root
        for _s in range(int(rng.integers(3, 7))):
            ox = int(rng.integers(-2, 3))
            oy = int(rng.integers(-1, 2))
            x = (cx + ox) % size
            y = (cy + oy) % size
            d = float(rng.uniform(0.08, 0.27)) * (1.0 if rng.random() < 0.62 else -1.0)
            col = _ramp_at(base_t + d, GRASS_STOPS)
            length = int(rng.integers(2, 6))
            lean = int(rng.integers(-1, 2))
            for j in range(length):
                xx = (x + (lean if j >= length // 2 else 0)) % size
                yy = (y - j) % size
                rgb[yy, xx] = col

    # ---- tiny soil specks ----------------------------------------------
    for _ in range(95):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        c = np.array(GRASS_SOIL[int(rng.integers(0, 4))], np.float32)
        rgb[y, x] = c
        if rng.random() < 0.33:
            rgb[y, (x + 1) % size] = c * 0.92
        if rng.random() < 0.45:
            hl = np.array((0x6B, 0x55, 0x35), np.float32)
            yy = (y + 1) % size
            rgb[yy, x] = rgb[yy, x] * 0.55 + hl * 0.45

    # ---- faint tiny flowers --------------------------------------------
    for _ in range(12):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        pale = np.array(GRASS_PALE_FLOWER[int(rng.integers(0, 3))], np.float32)
        local = rgb[y, x]
        c = local * 0.58 + pale * 0.42          # faint: mostly the local tone
        rgb[y, x] = c
        rgb[y, (x + 1) % size] = c * 0.97
        if rng.random() < 0.5:
            rgb[(y - 1) % size, x] = c * 0.98
        if rng.random() < 0.6:
            stem = _ramp_at(0.45, GRASS_STOPS) * 0.8
            rgb[(y + 1) % size, x] = stem

    rgb = _match_mean(rgb, target_mean_255)
    return _to_rgba(rgb, 255)


# =====================================================================
#  2. path_dirt.png -- 256x256 seamless worn dirt path
# =====================================================================
def build_path_dirt(rng: np.random.Generator, target_mean_255) -> Image.Image:
    size = 256
    n = (0.40 * _periodic_noise(rng, size, 2)
         + 0.26 * _periodic_noise(rng, size, 5)
         + 0.18 * _periodic_noise(rng, size, 11)
         + 0.10 * _periodic_noise(rng, size, 27)
         + 0.06 * _periodic_noise(rng, size, 64))
    span = float(n.max() - n.min())
    n = (n - n.min()) / (span if span > 1e-6 else 1.0)
    t = np.clip(0.50 + (n - 0.5) * 0.52, 0.0, 1.0)
    rgb = _ramp(t, PATH_STOPS)
    tone = t.copy()

    # fine per-pixel grain keeps the "sandy" reading of the old tile; a second,
    # coarser grain layer adds body without hiding the worn ruts
    g1 = rng.random((size, size), dtype=np.float32) - 0.5
    rgb += g1[..., None] * np.array([4.4, 4.2, 3.6], np.float32)
    g2 = _periodic_noise(rng, size, 128) - 0.5
    rgb += g2[..., None] * np.array([3.0, 3.0, 2.6], np.float32)

    # fine grit speckles (single pixel, both directions)
    for _ in range(1200):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        amp = float(rng.uniform(5.0, 12.0)) * (1.0 if rng.random() < 0.5 else -1.0)
        rgb[y, x] += amp

    # ---- softly worn ruts (periodic in y so the horizontal borders match) --
    for track_x, phase, strength in ((72, 0.0, 1.0), (182, 2.1, 0.82)):
        for y in range(size):
            u = 2.0 * math.pi * y / size
            cx = (track_x + 7.0 * math.sin(2.0 * u + phase)
                  + 2.0 * math.sin(4.0 * u + phase * 1.7))
            for dxx, mix, col in ((-3, 0.04, PATH_RUT_RIM),
                                  (-2, 0.07, PATH_RUT_SOFT),
                                  (-1, 0.14, PATH_RUT_MID),
                                  (0, 0.26, PATH_RUT_DARK),
                                  (1, 0.14, PATH_RUT_MID),
                                  (2, 0.07, PATH_RUT_SOFT),
                                  (3, 0.04, PATH_RUT_RIM)):
                x = int(round(cx + dxx)) % size
                m = mix * strength
                rgb[y, x] = rgb[y, x] * (1.0 - m) + col * m

    # ---- small stones: body + top light + bottom/side shadow ------------
    for _ in range(85):
        cx = int(rng.integers(0, size))
        cy = int(rng.integers(0, size))
        w = int(rng.choice((1, 1, 2, 2, 3)))
        h = int(rng.choice((1, 1, 2)))
        body = np.array(PATH_STONE_BODY[int(rng.integers(0, 4))], np.float32)
        for yy in range(h):
            for xx in range(w):
                k = 0.18 if (yy == 0 and h > 1) else 0.0
                rgb[(cy + yy) % size, (cx + xx) % size] = (
                    body * (1.0 - k) + PATH_STONE_DARK * k)
        for xx in range(w):
            yt = (cy - 1) % size
            yb = (cy + h) % size
            rgb[yt, (cx + xx) % size] = (rgb[yt, (cx + xx) % size] * 0.76
                                         + PATH_STONE_LIGHT * 0.24)
            rgb[yb, (cx + xx) % size] = (rgb[yb, (cx + xx) % size] * 0.68
                                         + PATH_STONE_DARK * 0.32)
        rgb[cy % size, (cx + w) % size] = (rgb[cy % size, (cx + w) % size] * 0.78
                                           + PATH_STONE_DARK * 0.22)

    # ---- moss / grass specks: a handful near the tile edges (path verge),
    #      a few more around stones --------------------------------------
    for _ in range(30):
        side = int(rng.integers(0, 4))
        if side < 2:
            x = int(rng.integers(0, 9)) if side == 0 else size - 1 - int(rng.integers(0, 9))
            y = int(rng.integers(0, size))
        else:
            y = int(rng.integers(0, 9)) if side == 2 else size - 1 - int(rng.integers(0, 9))
            x = int(rng.integers(0, size))
        length = int(rng.integers(1, 4))
        for j in range(length):
            yy = (y - j) % size
            col = PATH_VERGE if j else PATH_VERGE_DARK
            rgb[yy, x] = rgb[yy, x] * 0.22 + col * 0.78
        if rng.random() < 0.5:
            yy = (y - length) % size
            rgb[yy, x] = rgb[yy, x] * 0.30 + PATH_VERGE_DARK * 0.70
    for _ in range(20):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        c = PATH_MOSS[int(rng.integers(0, 2))]
        rgb[y, x] = rgb[y, x] * 0.35 + c * 0.65
        if rng.random() < 0.40:
            rgb[y, (x + 1) % size] = rgb[y, (x + 1) % size] * 0.35 + c * 0.60

    rgb = _match_mean(rgb, target_mean_255)
    return _to_rgba(rgb, 255)


# =====================================================================
#  3. grass_blade.png -- 16x32 three-blade alpha cutout
# =====================================================================
def build_grass_blade() -> Image.Image:
    w, h = 16, 32
    rgba = np.zeros((h, w, 4), np.uint8)
    # base_x, tip_x, top_y, base_half_width, curve_power, tone
    # The three bases overlap slightly and the widths taper smoothly, so the
    # blades merge into one clump at the root and separate higher up.
    blades = (
        (4.8, 2.1, 7, 2.05, 1.45, 0.96),
        (8.5, 8.9, 1, 2.25, 1.30, 1.00),
        (12.1, 14.5, 9, 1.90, 1.50, 0.90),
    )
    for bx, tx, top, half_base, curve, tone in blades:
        for y in range(top, h):
            u = (h - 1 - y) / float(h - 1)          # 0 base .. 1 tip
            cx = bx + (tx - bx) * (u ** curve)
            half = half_base * max(0.0, 1.0 - u) ** 0.92
            x0 = int(math.floor(cx - half + 0.5))
            x1 = int(math.floor(cx + half + 0.5)) - 1
            if x1 < x0:
                x1 = x0
            width = x1 - x0 + 1
            col = _ramp_at(u, BLADE_STOPS) * tone
            for x in range(max(0, x0), min(w - 1, x1) + 1):
                if width >= 2 and x == x0:
                    c = col * 0.80 + BLADE_SHADE * 0.20
                elif width >= 2 and x == x1:
                    c = col * 0.82 + BLADE_RIM * 0.18
                else:
                    c = col
                rgba[y, x, :3] = np.clip(np.round(c), 0, 255).astype(np.uint8)
                rgba[y, x, 3] = 255
    return Image.fromarray(rgba)


# =====================================================================
#  4. flowers -- 8x8 alpha cutouts
# =====================================================================
def build_flower(kind: str) -> Image.Image:
    pal = FLOWER_PALETTES[kind]
    h = len(FLOWER_ART)
    w = max(len(row) for row in FLOWER_ART)
    rgba = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(FLOWER_ART):
        for x, ch in enumerate(row):
            col = pal.get(ch)
            if col is not None:
                rgba[y, x] = col
    return Image.fromarray(rgba)


# =====================================================================
#  5. ui_panel.png -- 48x48 nine-slice
# =====================================================================
def build_ui_panel() -> Image.Image:
    w = h = 48
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., :3] = np.array(PANEL_INNER, np.uint8)
    arr[..., 3] = PANEL_ALPHA
    # 2px cream border
    arr[0:2, :, :3] = PANEL_CREAM
    arr[h - 2:, :, :3] = PANEL_CREAM
    arr[:, 0:2, :3] = PANEL_CREAM
    arr[:, w - 2:, :3] = PANEL_CREAM
    arr[0:2, :, 3] = 255
    arr[h - 2:, :, 3] = 255
    arr[:, 0:2, 3] = 255
    arr[:, w - 2:, 3] = 255
    # 1px inner shadow just inside the border (same alpha -> interior stays 210)
    sh = PANEL_SHADOW + (PANEL_ALPHA,)
    arr[2, 2:w - 2] = sh
    arr[h - 3, 2:w - 2] = sh
    arr[2:h - 2, 2] = sh
    arr[2:h - 2, w - 3] = sh
    # beveled corners: a 3-step stair of transparent pixels per corner,
    # all inside the 8px nine-slice margin
    bevel = ((0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (0, 2),
             (w - 1, 0), (w - 2, 0), (w - 3, 0), (w - 1, 1), (w - 2, 1), (w - 1, 2),
             (0, h - 1), (1, h - 1), (2, h - 1), (0, h - 2), (1, h - 2), (0, h - 3),
             (w - 1, h - 1), (w - 2, h - 1), (w - 3, h - 1),
             (w - 1, h - 2), (w - 2, h - 2), (w - 1, h - 3))
    for x, y in bevel:
        arr[y, x] = 0
    return Image.fromarray(arr)


# =====================================================================
#  6. ui_choice_cursor.png -- 8x8 play arrow
# =====================================================================
def build_cursor() -> Image.Image:
    h = len(CURSOR_ART)
    w = max(len(row) for row in CURSOR_ART)
    arr = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(CURSOR_ART):
        for x, ch in enumerate(row):
            col = CURSOR_COLORS.get(ch)
            if col is not None:
                arr[y, x] = col
    return Image.fromarray(arr)


# =====================================================================
#  7. particle sprites (soft alpha falloff, exact 0 at the corners)
# =====================================================================
def _radial_field(size: int, radius: float, power: float) -> np.ndarray:
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2.0
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    t = np.clip(1.0 - (r / radius) ** 2, 0.0, 1.0)
    return t ** power


def _soft_dot(size: int, radius: float, power: float, max_alpha: float,
              color) -> Image.Image:
    a = _radial_field(size, radius, power) * max_alpha
    alpha = np.clip(np.round(a), 0, 255).astype(np.uint8)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = np.array(color, np.uint8)
    rgba[..., 3] = alpha
    rgba[alpha == 0] = 0                  # clean transparent corners
    return Image.fromarray(rgba)


def build_particle_dust() -> Image.Image:
    return _soft_dot(16, 7.3, 1.55, 236.0, DUST_COLOR)


def build_particle_pollen() -> Image.Image:
    return _soft_dot(8, 3.50, 1.30, 246.0, POLLEN_COLOR)


def build_particle_firefly() -> Image.Image:
    size = 8
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2.0
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    # soft yellow-green halo ...
    halo_t = np.clip(1.0 - (r / 3.8) ** 2, 0.0, 1.0)
    halo_a = halo_t ** 1.6 * 150.0
    # ... plus a small, almost white core (kept bright at the centre pixel)
    core_t = np.clip(1.0 - (r / 2.2) ** 2, 0.0, 1.0)
    core_a = core_t ** 0.32 * 255.0
    alpha = np.clip(np.round(np.maximum(halo_a, core_a)), 0, 255).astype(np.uint8)
    w_core = np.clip(1.0 - r / 2.0, 0.0, 1.0)[..., None]
    rgb = FIREFLY_HALO + (FIREFLY_CORE - FIREFLY_HALO) * w_core
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    rgba[..., 3] = alpha
    rgba[alpha == 0] = 0
    return Image.fromarray(rgba)


# =====================================================================
#  8. contact sheet at 4x nearest with labels
# =====================================================================
def _checker(w: int, h: int, cell: int = 16) -> Image.Image:
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((yy // cell) + (xx // cell)) % 2 == 0
    arr = np.zeros((h, w, 4), np.uint8)
    arr[m] = (0x22, 0x22, 0x22, 255)
    arr[~m] = (0x2C, 0x2C, 0x2C, 255)
    return Image.fromarray(arr)


def _font(size: int = 18):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # older Pillow
        return ImageFont.load_default()


def build_preview(assets: dict) -> Image.Image:
    labels = {
        "grass_ground": (
            "grass_ground.png  512x512  seamless painterly grass",
            "layered strokes + soft mottling + soil specks + faint flowers"),
        "path_dirt": (
            "path_dirt.png  256x256  seamless worn dirt path",
            "soft ruts, small stones with light/shadow, verge grass specks"),
        "grass_blade": (
            "grass_blade.png  16x32  3-blade alpha cutout",
            "green gradient, dark left edge + light right rim"),
        "flower_white": (
            "flower_white.png  8x8  white petals + gold centre",
            "alpha cutout, 1px stem + leaf"),
        "flower_yellow": (
            "flower_yellow.png  8x8  yellow petals + brown centre",
            "alpha cutout, 1px stem + leaf"),
        "ui_panel": (
            "ui_panel.png  48x48  nine-slice panel",
            "2px cream border, 1px inner shadow, stair bevels"),
        "ui_choice_cursor": (
            "ui_choice_cursor.png  8x8  play arrow",
            "cream base + yellow body + amber lower rim"),
        "particle_dust": (
            "particle_dust.png  16x16  soft radial white dot",
            "smooth alpha falloff, transparent corners"),
        "particle_pollen": (
            "particle_pollen.png  8x8  warm pale-yellow dot",
            "smooth alpha falloff"),
        "particle_firefly": (
            "particle_firefly.png  8x8  glowing dot",
            "yellow-green halo + near-white core"),
    }

    k = 4
    margin, gap, label_gap = 26, 30, 8
    font = _font(18)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))

    def tw(text: str) -> int:
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[2] - b[0])

    def th(text: str) -> int:
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[3] - b[1])

    line_h = th("Ag") + 6
    title = "material polish contact sheet -- 4x nearest"
    top0 = margin + line_h + 14

    scaled = {name: img.resize((img.width * k, img.height * k),
                               Image.Resampling.NEAREST)
              for name, img in assets.items()}

    left_names = ("grass_blade", "flower_white", "flower_yellow", "ui_panel",
                  "ui_choice_cursor", "particle_dust", "particle_pollen",
                  "particle_firefly")
    right_names = ("grass_ground", "path_dirt")

    left_w = tw(title)
    for name in left_names:
        left_w = max(left_w, scaled[name].width, tw(labels[name][0]),
                     tw(labels[name][1]))

    right_x = margin + left_w + gap
    right_w = max(scaled[name].width for name in right_names)
    width = right_x + right_w + margin

    # right column: grass tile then path tile
    right_y = top0
    right_pos = {}
    for name in right_names:
        right_pos[name] = right_y
        right_y += scaled[name].height + label_gap + line_h * len(labels[name]) + gap

    # left column: the small cutouts / UI / particles
    left_y = top0
    left_pos = {}
    for name in left_names:
        left_pos[name] = left_y
        left_y += scaled[name].height + label_gap + line_h * len(labels[name]) + gap

    height = max(left_y, right_y) - gap + margin

    canvas = _checker(width, height)
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, margin), title, fill=(235, 235, 235, 255), font=font)

    for name in left_names:
        img = scaled[name]
        x, y = margin, left_pos[name]
        draw.rectangle((x - 1, y - 1, x + img.width, y + img.height),
                       outline=(70, 70, 70, 255))
        canvas.alpha_composite(img, (x, y))
        ty = y + img.height + label_gap
        for line in labels[name]:
            draw.text((x, ty), line, fill=(230, 230, 230, 255), font=font)
            ty += line_h

    for name in right_names:
        img = scaled[name]
        x, y = right_x, right_pos[name]
        draw.rectangle((x - 1, y - 1, x + img.width, y + img.height),
                       outline=(70, 70, 70, 255))
        canvas.alpha_composite(img, (x, y))
        ty = y + img.height + label_gap
        for line in labels[name]:
            draw.text((x, ty), line, fill=(230, 230, 230, 255), font=font)
            ty += line_h

    return canvas


# =====================================================================
#  verification
# =====================================================================
def _mean255(arr_rgba: np.ndarray) -> np.ndarray:
    return arr_rgba[..., :3].reshape(-1, 3).mean(0)


def _seam_ratios(arr_rgba: np.ndarray):
    rgb = arr_rgba[..., :3].astype(np.float32)
    x_seam = float(np.abs(rgb[:, 0, :] - rgb[:, -1, :]).mean())
    x_adj = float(np.abs(rgb[:, 1:, :] - rgb[:, :-1, :]).mean())
    y_seam = float(np.abs(rgb[0, :, :] - rgb[-1, :, :]).mean())
    y_adj = float(np.abs(rgb[1:, :, :] - rgb[:-1, :, :]).mean())
    return (x_seam / max(x_adj, 1e-6), y_seam / max(y_adj, 1e-6),
            x_seam, x_adj, y_seam, y_adj)


def _fmt3(v) -> str:
    return f"({float(v[0]):7.3f}, {float(v[1]):7.3f}, {float(v[2]):7.3f})"


def verify_all(old_means: dict) -> bool:
    failures = []
    total = 0

    def check(ok: bool, tag: str, msg: str) -> None:
        nonlocal total
        total += 1
        if ok:
            print(f"[ok]   {tag:<18} {msg}")
        else:
            failures.append(f"{tag}: {msg}")
            print(f"[FAIL] {tag:<18} {msg}")

    print("\n--- verification " + "-" * 62)

    # ---- load what is actually on disk ---------------------------------
    imgs = {}
    missing = False
    for name, exp in EXPECTED_SIZES.items():
        path = OUT_DIR / name
        if not path.exists():
            check(False, "dimensions", f"{name} missing")
            missing = True
            continue
        im = Image.open(path)
        imgs[name] = im.convert("RGBA")
        got = im.size
        check(got == exp, "dimensions",
              f"{name:<24} {got[0]}x{got[1]} (expected {exp[0]}x{exp[1]})")

    if not missing:
        # ---- seamless wrap ratio ---------------------------------------
        for name in ("grass_ground.png", "path_dirt.png"):
            arr = np.asarray(imgs[name], np.float32)
            rx, ry, x_seam, x_adj, y_seam, y_adj = _seam_ratios(arr)
            check(rx < SEAM_TOL and ry < SEAM_TOL, "seamless",
                  f"{name:<24} x ratio={rx:.2f} ({x_seam:.2f}/{x_adj:.2f})  "
                  f"y ratio={ry:.2f} ({y_seam:.2f}/{y_adj:.2f})  "
                  f"(limit {SEAM_TOL:.1f})")

        # ---- opaque ground tiles ---------------------------------------
        for name in ("grass_ground.png", "path_dirt.png"):
            a = np.asarray(imgs[name])[..., 3]
            check(bool(np.all(a == 255)), "alpha-opaque",
                  f"{name:<24} all alpha == 255")

        # ---- mean brightness preserved ---------------------------------
        for name in ("grass_ground.png", "path_dirt.png"):
            arr = np.asarray(imgs[name], np.float32)
            new_mean = _mean255(arr)
            old_mean = np.asarray(old_means[name], np.float32)
            d_norm = np.abs(new_mean - old_mean) / 255.0
            ok = bool(np.all(d_norm <= MEAN_TOL))
            print(f"[mean] {name}")
            print(f"         old  = {_fmt3(old_mean)}  (0..255)")
            print(f"         new  = {_fmt3(new_mean)}  (0..255)")
            print(f"         |delta| normalised = {_fmt3(d_norm)}  "
                  f"(limit {MEAN_TOL:.3f} per channel)")
            old_std = old_means[name + ":std"] if (name + ":std") in old_means else None
            if old_std is not None:
                new_std = arr[..., :3].reshape(-1, 3).std(0)
                print(f"         std  old={_fmt3(old_std)} new={_fmt3(new_std)} (info only)")
            check(ok, "mean-preserved",
                  f"{name:<24} max |delta| = {float(d_norm.max()):.4f} <= {MEAN_TOL:.3f}")

        # ---- binary alpha cutouts --------------------------------------
        for name in ("grass_blade.png", "flower_white.png",
                     "flower_yellow.png", "ui_choice_cursor.png"):
            a = np.asarray(imgs[name])[..., 3]
            vals = np.unique(a)
            binary = bool(np.all((a == 0) | (a == 255)))
            coverage = float((a > 0).mean() * 100.0)
            check(binary, "alpha-binary",
                  f"{name:<24} values={list(int(v) for v in vals)} "
                  f"coverage={coverage:.1f}%")

        # ---- ui_panel detail -------------------------------------------
        panel = np.asarray(imgs["ui_panel.png"], np.uint8)
        cream = np.array(PANEL_CREAM + (255,), np.uint8)
        straight = True
        for y in (0, 1):                                    # top border
            straight &= bool(np.all(panel[y, 3:45] == cream))
        for y in (46, 47):                                  # bottom border
            straight &= bool(np.all(panel[y, 3:45] == cream))
        for x in (0, 1):                                    # left border
            straight &= bool(np.all(panel[3:45, x] == cream))
        for x in (46, 47):                                  # right border
            straight &= bool(np.all(panel[3:45, x] == cream))
        check(straight, "panel-border",
              "2px cream #E8DCC0 border uniform on all four straight sides")

        interior = np.array(PANEL_INNER + (PANEL_ALPHA,), np.uint8)
        centre = panel[8:40, 8:40]
        uniform = bool(np.all(centre == interior))
        check(uniform, "panel-interior",
              f"central 32x32 uniform #0E1420 alpha {PANEL_ALPHA}")

        # nine-patch safety: every 8px margin band must be constant along the
        # axis it will be stretched on
        nine_ok = True
        for y in range(8):
            nine_ok &= bool(np.all(panel[y, 8:40] == panel[y, 8]))
        for y in range(40, 48):
            nine_ok &= bool(np.all(panel[y, 8:40] == panel[y, 8]))
        for x in range(8):
            nine_ok &= bool(np.all(panel[8:40, x] == panel[8, x]))
        for x in range(40, 48):
            nine_ok &= bool(np.all(panel[8:40, x] == panel[8, x]))
        check(nine_ok, "panel-9patch",
              "8px margins are constant along both axes (safe nine-slice)")

        shadow = np.array(PANEL_SHADOW + (PANEL_ALPHA,), np.uint8)
        shadow_ok = (np.all(panel[2, 24] == shadow)
                     and np.all(panel[45, 24] == shadow)
                     and np.all(panel[24, 2] == shadow)
                     and np.all(panel[24, 45] == shadow))
        check(shadow_ok, "panel-shadow",
              "1px inner shadow present just inside the border")

        bevel_ok = all(int(panel[y, x, 3]) == 0 for x, y in
                       ((0, 0), (1, 0), (0, 1), (47, 0), (0, 47)))
        check(bevel_ok, "panel-bevel",
              "beveled corners are transparent")

        # ---- particle sprites ------------------------------------------
        for name, size in (("particle_dust.png", 16),
                           ("particle_pollen.png", 8),
                           ("particle_firefly.png", 8)):
            a = np.asarray(imgs[name])[..., 3]
            corners = (int(a[0, 0]), int(a[0, -1]), int(a[-1, 0]), int(a[-1, -1]))
            centre_a = int(a[size // 2, size // 2])
            edge_a = int(a[0, size // 2])
            check(corners == (0, 0, 0, 0) and centre_a > 0, "particle",
                  f"{name:<24} corners={corners} centre={centre_a} "
                  f"edge-mid={edge_a} (alpha 0 at corners, >0 at centre)")
            check(centre_a >= 200, "particle-bright",
                  f"{name:<24} centre alpha {centre_a} >= 200")
            check(bool(np.any((a > 0) & (a < 255))), "particle-soft",
                  f"{name:<24} has intermediate alpha (soft falloff)")

        # ---- preview ---------------------------------------------------
        prev_path = OUT_DIR / PREVIEW_NAME
        prev_ok = prev_path.exists()
        if prev_ok:
            with Image.open(prev_path) as pim:
                prev_ok = pim.width >= 2000 and pim.height >= 2000
                check(prev_ok, "preview",
                      f"{PREVIEW_NAME} {pim.width}x{pim.height} written")
        else:
            check(False, "preview", f"{PREVIEW_NAME} missing")

    print("\n--- result " + "-" * 68)
    if failures:
        print(f"RESULT: FAIL - {len(failures)} of {total} checks failed")
        for f in failures:
            print("  -", f)
        return False
    print(f"RESULT: PASS - all {total} checks green")
    return True


# =====================================================================
#  main
# =====================================================================
def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # IMPORTANT: read the old tiles into memory BEFORE overwriting them, so
    # the brightness comparison is against the real previous material.
    old_means = {}
    print("[input] previous material means (loaded before overwrite):")
    for name in ("grass_ground.png", "path_dirt.png"):
        path = OUT_DIR / name
        if path.exists():
            mean = _read_mean_rgb(path)
            old_means[name] = mean
            arr = np.asarray(Image.open(path).convert("RGBA"), np.float32)
            std = arr[..., :3].reshape(-1, 3).std(0)
            old_means[name + ":std"] = std
            src = "file on disk"
        else:
            mean = np.array(REFERENCE_MEANS_255[name], np.float32)
            old_means[name] = mean
            src = "embedded reference"
        print(f"         {name:<24} {_fmt3(mean)}  ({src})")
        print(f"         {'':<24} brightness target = "
              f"{_fmt3(REFERENCE_MEANS_255[name])} (measured pre-polish mean)")

    print("\n--- build " + "-" * 69)
    assets = {}

    # The mean-matching target is the fixed pre-polish reference, not the file
    # that happens to be on disk: that keeps re-runs byte-for-byte identical.
    grass = build_grass_ground(np.random.default_rng(SEED + 11),
                               REFERENCE_MEANS_255["grass_ground.png"])
    _save(grass, "grass_ground.png")
    assets["grass_ground"] = grass

    path = build_path_dirt(np.random.default_rng(SEED + 12),
                           REFERENCE_MEANS_255["path_dirt.png"])
    _save(path, "path_dirt.png")
    assets["path_dirt"] = path

    blade = build_grass_blade()
    _save(blade, "grass_blade.png")
    assets["grass_blade"] = blade

    flower_w = build_flower("white")
    _save(flower_w, "flower_white.png")
    assets["flower_white"] = flower_w

    flower_y = build_flower("yellow")
    _save(flower_y, "flower_yellow.png")
    assets["flower_yellow"] = flower_y

    panel = build_ui_panel()
    _save(panel, "ui_panel.png")
    assets["ui_panel"] = panel

    cursor = build_cursor()
    _save(cursor, "ui_choice_cursor.png")
    assets["ui_choice_cursor"] = cursor

    dust = build_particle_dust()
    _save(dust, "particle_dust.png")
    assets["particle_dust"] = dust

    pollen = build_particle_pollen()
    _save(pollen, "particle_pollen.png")
    assets["particle_pollen"] = pollen

    firefly = build_particle_firefly()
    _save(firefly, "particle_firefly.png")
    assets["particle_firefly"] = firefly

    preview = build_preview(assets)
    _save(preview, PREVIEW_NAME)

    ok = verify_all(old_means)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
