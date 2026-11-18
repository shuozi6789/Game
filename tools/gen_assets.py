#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_assets.py -- deterministic placeholder pixel-art generator for hd2d-rpg.

Run from the project root (or anywhere):

    python tools/gen_assets.py

Writes RGBA PNGs into <project>/assets/generated/ :

    player_whitebox.png   128x192  4 cols x 4 rows of 32x48 frames
                                   rows = facing down / left / right / up
                                   cols = walk frames 0..3 (0 = standing)
    blob_shadow.png        64x64   soft radial black ellipse (Godot Decal)
    grass_ground.png      512x512  seamless hand-painted style grass albedo
    grass_blade.png        16x32   binary-alpha cutout, 3 blades, wind billboard
    flower_white.png        8x8    binary-alpha cutout
    flower_yellow.png       8x8    binary-alpha cutout
    _preview.png                   contact sheet, every asset at 4x nearest

Art rules honoured here:
  * hard pixel edges only, no anti-aliasing anywhere in the sprites
  * small fixed palettes (the player is a literal white-box character:
    white body, subtle grey shading, 1px #B8B8B8 rim, no face, no costume)
  * the grass tile is built from periodic (wrapped) value noise plus
    per-pixel grain and wrapped strands, so opposite borders match
  * fully deterministic: every random stream is seeded below.

The script is re-runnable; it overwrites its own outputs and creates no
.import files and never touches Godot.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------------------------- config
SEED = 20260101

FRAME_W, FRAME_H = 32, 48
COLS, ROWS = 4, 4
VIEWS = ("down", "left", "right", "up")

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "generated"

# ------------------------------------------------------------------- palettes
WHITE = (255, 255, 255, 255)
SHADE1 = (242, 242, 242, 255)   # #F2F2F2
SHADE2 = (228, 228, 228, 255)   # #E4E4E4
SHADE3 = (212, 212, 212, 255)   # #D4D4D4
RIM = (184, 184, 184, 255)      # #B8B8B8
CLEAR = (0, 0, 0, 0)

PLAYER_PALETTE = {WHITE, SHADE1, SHADE2, SHADE3, RIM, CLEAR}

# part ids used for internal shading seams
P_HEAD, P_BODY, P_ARM_L, P_ARM_R, P_LEG_L, P_LEG_R = 1, 2, 3, 4, 5, 6


# =====================================================================
#  1. player white-box sprite sheet
# =====================================================================
# Walk cycles.  dx / dy are pixel offsets applied to that limb; dy < 0 lifts
# the limb (the planted foot always stays exactly on row 47 = ground line).
FRONT_WALK = (
    # legL_dx, legL_dy, legR_dx, legR_dy, armL_dx, armL_dy, armR_dx, armR_dy
    (0, 0, 0, 0, 0, 0, 0, 0),        # 0 standing
    (-1, -2, 1, 0, 0, 1, 0, -1),     # 1 left leg lifted back, right arm swings
    (0, -1, 0, 0, 0, 0, 0, 0),       # 2 passing pose
    (1, 0, -1, -2, 0, -1, 0, 1),     # 3 mirrored stride
)

SIDE_WALK = (
    # frontLeg_dx, frontLeg_dy, backLeg_dx, backLeg_dy, arm_dx, arm_dy
    (0, 0, 0, 0, 0, 0),              # 0 standing (legs together)
    (2, 0, -2, -1, -2, -1),          # 1 front leg forward, arm back
    (0, -1, 0, 0, -1, 0),            # 2 passing pose
    (-2, 0, 2, -1, 2, 1),            # 3 opposite stride, arm forward
)


def _paint(pid: np.ndarray, part: int, kind: str, box) -> None:
    """Stamp one body part into the part-id grid (later stamps overwrite)."""
    m = Image.new("L", (FRAME_W, FRAME_H), 0)
    d = ImageDraw.Draw(m)
    if kind == "ellipse":
        d.ellipse(box, fill=1)
    elif kind == "rect":
        d.rectangle(box, fill=1)
    else:  # pragma: no cover
        raise ValueError(kind)
    pid[np.asarray(m) > 0] = part


def _paint_leg(pid, part, x0, y_top, dx, dy, flare) -> None:
    """4px-wide leg plus a 1px flared foot; flare = -1 (left) or +1 (right)."""
    x1 = x0 + 3
    _paint(pid, part, "rect", (x0 + dx, y_top + dy, x1 + dx, 47 + dy))
    if flare < 0:
        _paint(pid, part, "rect", (x0 - 1 + dx, 45 + dy, x1 + dx, 47 + dy))
    else:
        _paint(pid, part, "rect", (x0 + dx, 45 + dy, x1 + 1 + dx, 47 + dy))


def _paint_side_leg(pid, part, x0, y_top, dx, dy, flare, width=6) -> None:
    """Side-view leg (default 6px wide) plus a 1px flared foot."""
    x1 = x0 + width - 1
    _paint(pid, part, "rect", (x0 + dx, y_top + dy, x1 + dx, 47 + dy))
    if flare < 0:
        _paint(pid, part, "rect", (x0 - 1 + dx, 45 + dy, x1 + dx, 47 + dy))
    else:
        _paint(pid, part, "rect", (x0 + dx, 45 + dy, x1 + 1 + dx, 47 + dy))


def _build_front(frame: int, back: bool) -> np.ndarray:
    legL_dx, legL_dy, legR_dx, legR_dy, aL_dx, aL_dy, aR_dx, aR_dy = FRONT_WALK[frame]
    pid = np.zeros((FRAME_H, FRAME_W), np.int16)
    # legs -> torso -> arms -> head : later parts cut seams into earlier ones
    _paint_leg(pid, P_LEG_L, 11, 32, legL_dx, legL_dy, flare=-1)
    _paint_leg(pid, P_LEG_R, 17, 32, legR_dx, legR_dy, flare=+1)
    _paint(pid, P_BODY, "rect", (11, 13, 20, 31))
    arm_out = -1 if back else 0        # back view: arms sit 1px further out
    _paint(pid, P_ARM_L, "rect", (7 + arm_out + aL_dx, 15 + aL_dy,
                                  10 + arm_out + aL_dx, 29 + aL_dy))
    _paint(pid, P_ARM_R, "rect", (21 - arm_out + aR_dx, 15 + aR_dy,
                                  24 - arm_out + aR_dx, 29 + aR_dy))
    _paint(pid, P_HEAD, "ellipse", (8, 0, 23, 15))
    return pid


def _build_side(frame: int, bob: int) -> np.ndarray:
    """Side view facing right.  bob shifts head/torso/arm down by 1px only."""
    f_dx, f_dy, b_dx, b_dy, a_dx, a_dy = SIDE_WALK[frame]
    pid = np.zeros((FRAME_H, FRAME_W), np.int16)
    # 6px-deep legs that overlap by 2px -> reads as a leg pair seen from the side
    _paint_side_leg(pid, P_LEG_R, 15, 32, f_dx, f_dy, flare=+1, width=6)  # front
    _paint_side_leg(pid, P_LEG_L, 11, 32, b_dx, b_dy, flare=-1, width=6)  # back
    # 13px-deep torso (deeper than the front view) + arm on the front edge
    _paint(pid, P_BODY, "rect", (10, 13 + bob, 22, 31 + bob))
    _paint(pid, P_ARM_R, "rect", (18 + a_dx, 14 + a_dy + bob,
                                  23 + a_dx, 29 + a_dy + bob))
    _paint(pid, P_HEAD, "ellipse", (8, 0 + bob, 23, 15 + bob))
    return pid


def _render_frame(pid: np.ndarray) -> Image.Image:
    """Turn a part-id grid into an RGBA frame: flat shading + seams + rim."""
    h, w = pid.shape
    sil = pid > 0
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    # stable directional light from the upper-left, in *frame* space so the
    # shading does not flicker between animation frames
    t = 0.62 * (ys / (FRAME_H - 1.0)) + 0.38 * (xs / (FRAME_W - 1.0))

    rgb = np.full((h, w, 3), 255, np.uint8)          # white-box body
    rgb[t >= 0.62] = SHADE1[:3]
    rgb[t >= 0.78] = SHADE2[:3]
    rgb[t >= 0.90] = SHADE3[:3]

    # internal seams where two different body parts touch
    pad = np.pad(pid, 1)
    seam = np.zeros((h, w), bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nb = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        seam |= sil & (nb > 0) & (nb != pid)
    rgb[seam] = SHADE2[:3]

    # subtle darker underside: 2 rows above the bottom edge of every column
    # (legs / arm tips), which also guarantees #D4D4D4 appears in the sheet
    rows = np.arange(h)[:, None]
    last_row = np.where(sil, rows, -1).max(axis=0)
    underside = np.zeros((h, w), bool)
    for x in range(w):
        lr = int(last_row[x])
        if lr >= 2:
            underside[max(0, lr - 2):lr, x] = True
    rgb[underside] = SHADE3[:3]

    # 1px rim / outline, painted inside the silhouette
    npad = np.pad(sil, 1)
    inner = (npad[:-2, 1:-1] & npad[2:, 1:-1]
             & npad[1:-1, :-2] & npad[1:-1, 2:])
    rgb[sil & ~inner] = RIM[:3]

    # compose alpha explicitly: transparent pixels are a clean (0,0,0,0)
    rgb[~sil] = 0
    alpha = np.where(sil, 255, 0).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]))


def build_player_sheet() -> Image.Image:
    sheet = np.zeros((ROWS * FRAME_H, COLS * FRAME_W, 4), np.uint8)
    for r, view in enumerate(VIEWS):
        for c in range(COLS):
            if view == "down":
                pid = _build_front(c, back=False)
            elif view == "up":
                pid = _build_front(c, back=True)
            elif view == "right":
                pid = _build_side(c, bob=0)
            else:  # left = mirrored right side view, 1px body bob so it reads
                pid = np.fliplr(_build_side(c, bob=1))
            frame = _render_frame(pid)
            sheet[r * FRAME_H:(r + 1) * FRAME_H,
                  c * FRAME_W:(c + 1) * FRAME_W] = np.asarray(frame)
    return Image.fromarray(sheet)


# =====================================================================
#  2. blob shadow decal
# =====================================================================
def build_blob_shadow() -> Image.Image:
    size = 64
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) / 2.0
    rx, ry = 29.0, 19.0
    d2 = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    a = np.clip(1.0 - d2, 0.0, 1.0) ** 0.65          # 1 in the middle, 0 outside
    alpha = np.round(a * 255.0).astype(np.uint8)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., 3] = alpha                              # RGB stays black
    return Image.fromarray(rgba)


# =====================================================================
#  3. seamless grass ground (512x512)
# =====================================================================
def _periodic_noise(rng: np.random.Generator, size: int, cells: int) -> np.ndarray:
    """Smooth value noise whose lattice wraps -> result tiles seamlessly."""
    lat = rng.random((cells, cells)).astype(np.float32)
    coord = np.arange(size, dtype=np.float32) * (cells / float(size))
    i0 = np.floor(coord).astype(np.int32) % cells
    i1 = (i0 + 1) % cells
    fr = coord - np.floor(coord)
    sm = fr * fr * (3.0 - 2.0 * fr)                   # smoothstep
    a = lat[np.ix_(i0, i0)]
    b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]
    d = lat[np.ix_(i1, i1)]
    top = a + (b - a) * sm[None, :]
    bot = c + (d - c) * sm[None, :]
    return top + (bot - top) * sm[:, None]


def build_grass_ground(rng: np.random.Generator) -> Image.Image:
    size = 512
    n = (0.50 * _periodic_noise(rng, size, 3)
         + 0.24 * _periodic_noise(rng, size, 7)
         + 0.14 * _periodic_noise(rng, size, 19)
         + 0.12 * _periodic_noise(rng, size, 71))
    span = float(n.max() - n.min())
    n = (n - n.min()) / (span if span > 1e-6 else 1.0)
    grain = rng.random((size, size)).astype(np.float32)
    n = np.clip(n * 0.93 + 0.07 * grain, 0.0, 1.0).astype(np.float32)

    c_dark = np.array([0x3E, 0x66, 0x30], np.float32)   # #3E6630
    c_base = np.array([0x4C, 0x7A, 0x3A], np.float32)   # #4C7A3A
    c_lite = np.array([0x5C, 0x8A, 0x45], np.float32)   # #5C8A45
    lo = np.clip(n / 0.5, 0.0, 1.0)[..., None]
    hi = np.clip((n - 0.5) / 0.5, 0.0, 1.0)[..., None]
    rgb = np.where(n[..., None] < 0.5,
                   c_dark + (c_base - c_dark) * lo,
                   c_base + (c_lite - c_base) * hi).astype(np.float32)

    # fine per-pixel speckle: tileable by construction
    r2 = rng.random((size, size))
    rgb[r2 < 0.030] += np.array([9, 13, 5], np.float32)
    rgb[(r2 >= 0.030) & (r2 < 0.062)] -= np.array([8, 11, 5], np.float32)

    # hand-painted clumps / short strands, wrapped so borders stay seamless
    strand_light = np.array([0x66, 0x96, 0x50], np.float32)
    strand_dark = np.array([0x33, 0x56, 0x28], np.float32)
    for _ in range(110):
        cx = int(rng.integers(0, size))
        cy = int(rng.integers(0, size))
        for _s in range(int(rng.integers(2, 5))):
            ox = int(rng.integers(-2, 3))
            bend = int(rng.integers(-1, 2))
            length = int(rng.integers(2, 5))
            col = strand_light if rng.random() < 0.55 else strand_dark
            for i in range(length):
                x = (cx + ox + (bend if i >= length // 2 else 0)) % size
                y = (cy - i) % size
                rgb[y, x] = col

    out = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    rgba = np.dstack([out, np.full((size, size, 1), 255, np.uint8)])
    return Image.fromarray(rgba)


# =====================================================================
#  4. grass blade cutout (16x32)
# =====================================================================
def build_grass_blade() -> Image.Image:
    w, h = 16, 32
    rgba = np.zeros((h, w, 4), np.uint8)
    base = np.array([0x33, 0x5E, 0x2C], np.float32)
    tip = np.array([0x93, 0xBE, 0x6C], np.float32)
    blades = (  # base_x, tip_x, top_y, half_width
        (5.0, 2.0, 4, 1.7),
        (8.5, 8.0, 1, 2.0),
        (12.0, 14.6, 6, 1.5),
    )
    for bx, tx, top, half_w in blades:
        for y in range(top, h):
            u = (h - 1 - y) / float(h - 1)                 # 0 base .. 1 tip
            cx = bx + (tx - bx) * (u ** 1.35)              # taper / curve
            half = half_w * max(0.0, 1.0 - u) ** 0.85
            x0 = int(round(cx - half))
            x1 = int(round(cx + half))
            col = np.round(base + (tip - base) * (u ** 0.8)).astype(np.uint8)
            for x in range(max(0, x0), min(w, x1 + 1)):
                rgba[y, x, :3] = col
                rgba[y, x, 3] = 255
    return Image.fromarray(rgba)


# =====================================================================
#  5. flowers (8x8 cutouts)
# =====================================================================
FLOWER_ART = {
    "white": (
        "........",
        "...W....",
        ".W.W.W..",
        "..WWW...",
        ".WWCWW..",
        "..wWw...",
        "...g....",
        "...g....",
    ),
    "yellow": (
        "........",
        "...W....",
        ".W.W.W..",
        "..WWW...",
        ".WWCWW..",
        "..wWw...",
        "...g....",
        "...g....",
    ),
}

FLOWER_COLORS = {
    "white": {
        "W": (255, 255, 255, 255),
        "w": (233, 233, 233, 255),
        "C": (232, 194, 90, 255),
        "g": (0x3E, 0x66, 0x30, 255),
    },
    "yellow": {
        "W": (242, 201, 76, 255),
        "w": (214, 166, 56, 255),
        "C": (176, 106, 40, 255),
        "g": (0x3E, 0x66, 0x30, 255),
    },
}


def build_flower(kind: str) -> Image.Image:
    rows = FLOWER_ART[kind]
    pal = FLOWER_COLORS[kind]
    h = len(rows)
    w = max(len(r) for r in rows)
    rgba = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            col = pal.get(ch)
            if col is not None:
                rgba[y, x] = col
    return Image.fromarray(rgba)


# =====================================================================
#  6. contact sheet preview (4x nearest neighbour)
# =====================================================================
def _checker(w: int, h: int, cell: int = 16) -> Image.Image:
    a = np.array([0x22, 0x22, 0x22, 255], np.uint8)
    b = np.array([0x2C, 0x2C, 0x2C, 255], np.uint8)
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((yy // cell) + (xx // cell)) % 2 == 0
    arr = np.zeros((h, w, 4), np.uint8)
    arr[m] = a
    arr[~m] = b
    return Image.fromarray(arr)


def _font(size: int = 20):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # older Pillow
        return ImageFont.load_default()


def build_preview(assets: dict) -> Image.Image:
    """Contact sheet: every asset at 4x nearest, labels measured so they cannot
    overlap each other (player + small props stacked left, grass tile right)."""
    k = 4
    margin, gap, label_gap = 24, 26, 6
    font = _font(20)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))

    def tw(text: str) -> int:
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[2] - b[0])

    def th(text: str) -> int:
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[3] - b[1])

    line_h = th("Ag") + 6

    scaled = {name: img.resize((img.width * k, img.height * k),
                               Image.Resampling.NEAREST)
              for name, img in assets.items()}

    player_lines = (
        "player_whitebox.png  128x192  = 4 x 4 frames of 32x48",
        "rows: down / left / right / up     columns: walk frames 0..3",
    )
    grass_lines = ("grass_ground.png  512x512  seamless tile",)
    small = (
        ("blob_shadow", "blob_shadow.png  64x64"),
        ("grass_blade", "grass_blade.png  16x32"),
        ("flower_white", "flower_white.png  8x8"),
        ("flower_yellow", "flower_yellow.png  8x8"),
    )

    player = scaled["player_whitebox"]
    grass = scaled["grass_ground"]
    left_w = max(player.width, *(tw(t) for t in player_lines))
    for name, label in small:
        left_w = max(left_w, scaled[name].width, tw(label))

    left_x = margin
    right_x = margin + left_w + gap
    width = right_x + grass.width + margin

    placements = [("player_whitebox", left_x, margin, player_lines)]
    y = margin + player.height + label_gap + line_h * len(player_lines) + gap
    for name, label in small:
        placements.append((name, left_x, y, (label,)))
        y += scaled[name].height + label_gap + line_h + gap
    left_bottom = y - gap

    placements.append(("grass_ground", right_x, margin, grass_lines))
    grass_bottom = (margin + grass.height + label_gap
                    + line_h * len(grass_lines))

    height = max(left_bottom, grass_bottom) + margin

    canvas = _checker(width, height)
    draw = ImageDraw.Draw(canvas)
    for name, x, top, lines in placements:
        img = scaled[name]
        canvas.alpha_composite(img, (x, top))
        ty = top + img.height + label_gap
        for line in lines:
            draw.text((x, ty), line, fill=(235, 235, 235, 255), font=font)
            ty += line_h
    return canvas


# =====================================================================
#  verification helpers
# =====================================================================
def _frame_boxes(arr: np.ndarray):
    boxes = []
    for r in range(ROWS):
        for c in range(COLS):
            f = arr[r * FRAME_H:(r + 1) * FRAME_H,
                    c * FRAME_W:(c + 1) * FRAME_W]
            a = f[..., 3] > 0
            if not a.any():
                boxes.append((r, c, None))
                continue
            ys, xs = np.nonzero(a)
            boxes.append((r, c, (int(xs.min()), int(xs.max()),
                                 int(ys.min()), int(ys.max()), int(a.sum()))))
    return boxes


def verify_player(img: Image.Image) -> bool:
    arr = np.asarray(img)
    ok = True
    expect = (COLS * FRAME_W, ROWS * FRAME_H)
    size_ok = (img.width, img.height) == expect
    ok &= size_ok
    print(f"  sheet size {img.width}x{img.height} (expected "
          f"{expect[0]}x{expect[1]}): {'PASS' if size_ok else 'FAIL'}")

    boxes = _frame_boxes(arr)
    empty = [(r, c) for r, c, b in boxes if b is None]
    if empty:
        ok = False
        print(f"  FAIL fully transparent frames: {empty}")
    else:
        print("  all 16 frames non-empty: PASS")

    grounds = [b[3] for _, _, b in boxes if b]
    ground_ok = all(g == FRAME_H - 1 for g in grounds)
    ok &= ground_ok
    print(f"  ground line identical: max alpha y == {FRAME_H - 1} in all "
          f"{len(grounds)} frames: {'PASS' if ground_ok else 'FAIL'}")
    print(f"  ground rows seen: {sorted(set(grounds))}")

    tops = [b[2] for _, _, b in boxes if b]
    empty_rows = [FRAME_H - (b[3] - b[2] + 1) for _, _, b in boxes if b]
    print(f"  fully transparent rows inside a frame: max {max(empty_rows)} "
          f"(0 => content spans the full {FRAME_H}px height)")
    widths = [b[1] - b[0] + 1 for _, _, b in boxes if b]
    print(f"  content width per frame: {min(widths)}..{max(widths)} px "
          f"(limit {FRAME_W}): {'PASS' if max(widths) <= FRAME_W else 'FAIL'}")
    ok &= max(widths) <= FRAME_W

    # 4x4 grid sanity: every grid row and every grid column has content
    for r in range(ROWS):
        band = arr[r * FRAME_H:(r + 1) * FRAME_H]
        if not (band[..., 3] > 0).any():
            ok = False
            print(f"  FAIL grid row {r} ({VIEWS[r]}) is empty")
    for c in range(COLS):
        band = arr[:, c * FRAME_W:(c + 1) * FRAME_W]
        if not (band[..., 3] > 0).any():
            ok = False
            print(f"  FAIL grid column {c} (frame {c}) is empty")
    print("  4x4 grid: every row and column populated: "
          f"{'PASS' if ok else 'FAIL'}")

    # palette discipline / no AA: judge only the *visible* pixels.  Fully
    # transparent pixels carry no colour and are reported separately.
    opaque = arr[arr[..., 3] > 0]
    pal_rgb = {c[:3] for c in PLAYER_PALETTE if c[3] == 255}
    cols = {tuple(int(v) for v in px[:3]) for px in np.unique(opaque, axis=0)}
    extra = cols - pal_rgb
    pal_ok = not extra
    ok &= pal_ok
    print(f"  opaque colours: {len(cols)} (white-box palette: "
          f"{'PASS' if pal_ok else 'FAIL ' + str(sorted(extra)[:4])})")
    trans = arr[arr[..., 3] == 0]
    trans_max = int(trans[:, :3].max()) if trans.size else 0
    print(f"  transparent pixels: {len(trans)} (all RGB 0: "
          f"{'PASS' if trans_max == 0 else 'FAIL rgb_max=' + str(trans_max)})")
    ok &= trans_max == 0
    return ok


def verify_grass(img: Image.Image) -> bool:
    arr = np.asarray(img).astype(np.float32)
    rgb = arr[..., :3]
    h = rgb.shape[0]
    w = rgb.shape[1]
    wrap_h = float(np.abs(rgb[:, 0, :] - rgb[:, w - 1, :]).mean())
    typ_h = float(np.abs(rgb[:, 1:, :] - rgb[:, :-1, :]).mean())
    wrap_v = float(np.abs(rgb[0, :, :] - rgb[h - 1, :, :]).mean())
    typ_v = float(np.abs(rgb[1:, :, :] - rgb[:-1, :, :]).mean())
    ratio = max(wrap_h / max(typ_h, 1e-6), wrap_v / max(typ_v, 1e-6))
    ok = ratio < 3.0
    print(f"  seam: horizontal wrap |d|={wrap_h:.2f} (typical neighbour "
          f"{typ_h:.2f})")
    print(f"  seam: vertical   wrap |d|={wrap_v:.2f} (typical neighbour "
          f"{typ_v:.2f})")
    print(f"  seam ratio {ratio:.2f} (< 3 => seamless): {'PASS' if ok else 'FAIL'}")
    print(f"  alpha channel: all 255: {'PASS' if int(arr[..., 3].min()) == 255 else 'FAIL'}")
    return ok


def verify_binary_alpha(img: Image.Image, name: str) -> bool:
    a = np.unique(np.asarray(img)[..., 3])
    ok = set(int(v) for v in a) <= {0, 255}
    print(f"  {name}: binary alpha (no AA edges): "
          f"{'PASS' if ok else 'FAIL'} values={[int(v) for v in a][:4]}")
    return ok


# =====================================================================
#  main
# =====================================================================
def main() -> int:
    rng = np.random.default_rng(SEED)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    assets = {
        "player_whitebox": build_player_sheet(),
        "blob_shadow": build_blob_shadow(),
        "grass_ground": build_grass_ground(rng),
        "grass_blade": build_grass_blade(),
        "flower_white": build_flower("white"),
        "flower_yellow": build_flower("yellow"),
    }

    print("=" * 70)
    print("gen_assets.py  seed=%d  out=%s" % (SEED, OUT_DIR))
    print("=" * 70)

    order = ["player_whitebox", "blob_shadow", "grass_ground",
             "grass_blade", "flower_white", "flower_yellow"]
    for name in order:
        img = assets[name]
        img.save(OUT_DIR / f"{name}.png")
        print(f"[wrote] {name + '.png':<22} {img.width:>4}x{img.height:<4} "
              f"{img.mode}")

    preview = build_preview(assets)
    preview.save(OUT_DIR / "_preview.png")
    print(f"[wrote] {'_preview.png':<22} {preview.width:>4}x{preview.height:<4} "
          f"{preview.mode}")

    print("\n--- verification " + "-" * 53)
    ok = True
    print("[player_whitebox.png]")
    ok &= verify_player(assets["player_whitebox"])
    print("[grass_ground.png]")
    ok &= verify_grass(assets["grass_ground"])
    print("[cutouts]")
    for name in ("grass_blade", "flower_white", "flower_yellow"):
        ok &= verify_binary_alpha(assets[name], name + ".png")
    print("[blob_shadow.png]")
    sh = np.asarray(assets["blob_shadow"])[..., 3]
    center_ok = int(sh[31, 31]) >= 250
    edge_ok = int(sh[0, 0]) == 0
    ok &= center_ok and edge_ok
    print(f"  alpha centre={int(sh[31, 31])} (255), corner={int(sh[0, 0])} (0): "
          f"{'PASS' if center_ok and edge_ok else 'FAIL'}")

    print("\n--- palette summary " + "-" * 51)
    print("  player : #FFFFFF body, #F2F2F2 / #E4E4E4 / #D4D4D4 shading, "
          "#B8B8B8 1px rim")
    print("  grass  : #3E6630 / #4C7A3A / #5C8A45 base, muted strands")
    print("  flowers: white #FFFFFF+#E8C25A centre | yellow #F2C94C+#B06A28")
    print("  shadow : black, alpha 255 centre -> 0 rim")

    print("\n--- godot import notes " + "-" * 48)
    print("  player_whitebox / grass_blade / flowers : Filter = Nearest,")
    print("    Mipmaps = off, Compression = Lossless")
    print("  grass_ground                          : Filter = Nearest,")
    print("    Mipmaps = on (3D ground), Lossless, repeat = on")
    print("  blob_shadow                           : Filter = Linear,")
    print("    Mipmaps = off (smooth decal alpha)")

    print("\nRESULT:", "PASS - all checks green" if ok else "FAIL - see above")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
