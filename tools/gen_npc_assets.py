#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_npc_assets.py -- deterministic NPC / path / dialogue-UI art for hd2d-rpg.

Run from the project root (or anywhere):

    python tools/gen_npc_assets.py

Writes RGBA PNGs into <project>/assets/generated/ :

    npc_red.png            64x192   2 cols x 4 rows of 32x48 frames
    npc_yellow.png         64x192   rows = facing down / left / right / up
    npc_green.png          64x192   cols = idle frame 0, breathing frame 1
    npc_blue.png           64x192
    npc_purple.png         64x192
    path_dirt.png         256x256   seamless dirt/gravel path tile
    ui_panel.png           48x48    nine-slice dialogue panel (8px margins)
    ui_choice_cursor.png    8x8     cream/yellow arrow cursor
    _preview_npc.png                contact sheet at 4x nearest, labelled

Style contract (the same pixel language as gen_assets.py:
player_whitebox.png):

  * hard pixel edges, binary alpha, no anti-aliasing anywhere
  * small fixed palettes per NPC; a 1px #1B1B1B outline is painted *inside*
    the silhouette so the figure reads on the bright grass
  * the figure is built from flat pixel blocks (head / torso / arms / legs /
    costume overlays), then flat-shaded from a stable upper-left light, with
    1px darkened seams where two body parts meet
  * idle frame 1 = 1px breathing bob of head + torso + arms + held props,
    feet stay planted: the ground line is y == 47 in all 8 frames
  * faces are minimal: exactly 2 dark eye pixels, down row only

Every random stream is seeded below; the script is re-runnable and produces
byte-identical PNGs.  It creates no .import files and never touches Godot.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------------------------- config
SEED = 20260202

FRAME_W, FRAME_H = 32, 48
FRAME_COLS, FRAME_ROWS = 2, 4
SHEET_W = FRAME_W * FRAME_COLS          # 64
SHEET_H = FRAME_H * FRAME_ROWS          # 192
VIEWS = ("down", "left", "right", "up")  # row order, top -> bottom

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "generated"

OUTLINE = (0x1B, 0x1B, 0x1B)            # #1B1B1B 1px outline / face pixels
CLEAR = (0, 0, 0, 0)

GROUND_Y = FRAME_H - 1                  # 47, the one and only ground line

# part ids: distinct ids give the renderer its internal seam lines even when
# two parts share the same colour family.
ROLE_NAMES = ["", "HEAD", "BODY", "ARM_L", "ARM_R", "LEG_L", "LEG_R",
              "CAPE", "ACC", "PROP", "HAND", "HAIR"]
ROLE_IDS = {n: i for i, n in enumerate(ROLE_NAMES) if n}


# =====================================================================
#  little draw-op DSL
# =====================================================================
# an op is (kind, role, box, views, bob, clip)
#   kind  : "rect" | "ellipse" | "line"
#   role  : role name (see ROLE_NAMES)
#   box   : (x0, y0, x1, y1) inclusive
#   views : subset of "d" (down), "u" (up), "r" (right = side art).  "left"
#           reuses the side art mirrored, so it is not a tag.
#   bob   : True -> shifted 1px up on idle frame 1 (breathing)
#   clip  : True -> only painted where the silhouette already exists


def fr(role, x0, y0, x1, y1, views="du", bob=True, clip=False):
    return ("rect", role, (x0, y0, x1, y1), views, bob, clip)


def fe(role, x0, y0, x1, y1, views="du", bob=True, clip=False):
    return ("ellipse", role, (x0, y0, x1, y1), views, bob, clip)


def fl(role, x0, y0, x1, y1, views="du", bob=True, clip=False):
    return ("line", role, (x0, y0, x1, y1), views, bob, clip)


def sr(role, x0, y0, x1, y1, views="r", bob=True, clip=False):
    return ("rect", role, (x0, y0, x1, y1), views, bob, clip)


def se(role, x0, y0, x1, y1, views="r", bob=True, clip=False):
    return ("ellipse", role, (x0, y0, x1, y1), views, bob, clip)


def sl(role, x0, y0, x1, y1, views="r", bob=True, clip=False):
    return ("line", role, (x0, y0, x1, y1), views, bob, clip)


def det(color, points, views="d", bob=True):
    """Post-outline detail: exact pixels of a fixed colour (eyes, glasses...)."""
    return (tuple(color), tuple(points), views, bob)


def pix(x0, y0, x1, y1):
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


# =====================================================================
#  frame assembly / rendering
# =====================================================================
def stamp(pid: np.ndarray, rid: int, kind: str, box, clip: bool) -> None:
    """Paint one shape into the part-id grid (later stamps overwrite)."""
    m = Image.new("L", (FRAME_W, FRAME_H), 0)
    d = ImageDraw.Draw(m)
    if kind == "rect":
        d.rectangle(box, fill=1)
    elif kind == "ellipse":
        d.ellipse(box, fill=1)
    elif kind == "line":
        d.line([(box[0], box[1]), (box[2], box[3])], fill=1)
    else:  # pragma: no cover
        raise ValueError(kind)
    mask = np.asarray(m) > 0
    if clip:
        mask &= pid > 0
    pid[mask] = rid


def assemble(ops, view: str, frame: int) -> np.ndarray:
    pid = np.zeros((FRAME_H, FRAME_W), np.int16)
    for kind, role, box, views, bob, clip in ops:
        if view not in views:
            continue
        dy = -1 if (frame == 1 and bob) else 0
        x0, y0, x1, y1 = box
        stamp(pid, ROLE_IDS[role], kind, (x0, y0 + dy, x1, y1 + dy), clip)
    return pid


def render_frame(pid: np.ndarray, spec: dict, view: str, frame: int) -> Image.Image:
    """Part-id grid -> RGBA frame: flat shading + seams + 1px outline."""
    h, w = pid.shape
    sil = pid > 0
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    # stable directional light from the upper-left, in frame space, so the
    # shading never flickers between the two idle frames
    t = 0.62 * (ys / (h - 1.0)) + 0.38 * (xs / (w - 1.0))

    rgb = np.zeros((h, w, 3), np.uint8)
    roles, fams = spec["roles"], spec["families"]

    for rid in range(1, len(ROLE_NAMES)):
        m = pid == rid
        if not m.any():
            continue
        fam = fams[roles[ROLE_NAMES[rid]]]
        if len(fam) == 1:                       # flat colour (e.g. bright band)
            rgb[m] = fam[0]
        elif len(fam) == 2:                     # base + dark
            rgb[m & (t < 0.74)] = fam[0]
            rgb[m & (t >= 0.74)] = fam[1]
        else:                                   # light + base + dark
            rgb[m & (t < 0.22)] = fam[0]
            rgb[m & (t >= 0.22) & (t < 0.74)] = fam[1]
            rgb[m & (t >= 0.74)] = fam[2]

    # internal seams where two different body parts touch (1px dark line)
    pad = np.pad(pid, 1)
    seam = np.zeros((h, w), bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nb = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        seam |= sil & (nb > 0) & (nb != pid)
    for rid in range(1, len(ROLE_NAMES)):
        m = pid == rid
        if not m.any():
            continue
        fam = fams[roles[ROLE_NAMES[rid]]]
        rgb[seam & m] = fam[-1]

    # 1px outline painted inside the silhouette
    npad = np.pad(sil, 1)
    inner = (npad[:-2, 1:-1] & npad[2:, 1:-1]
             & npad[1:-1, :-2] & npad[1:-1, 2:])
    rgb[sil & ~inner] = OUTLINE

    # minimal face / prop details, painted after the outline
    for color, pts, dviews, bob in spec["details"]:
        if view not in dviews:
            continue
        dy = -1 if (frame == 1 and bob) else 0
        for x, y in pts:
            yy = y + dy
            if 0 <= x < w and 0 <= yy < h and sil[yy, x]:
                rgb[yy, x] = color

    alpha = np.where(sil, 255, 0).astype(np.uint8)
    rgb[~sil] = 0
    return Image.fromarray(np.dstack([rgb, alpha]))


def build_sheet(spec: dict) -> Image.Image:
    tag_of = {"down": "d", "left": "r", "right": "r", "up": "u"}
    sheet = np.zeros((SHEET_H, SHEET_W, 4), np.uint8)
    for r, view in enumerate(VIEWS):
        tag = tag_of[view]
        for c in range(FRAME_COLS):
            ops = spec["front"] if view in ("down", "up") else spec["side"]
            pid = assemble(ops, tag, c)
            img = render_frame(pid, spec, tag, c)
            arr = np.asarray(img)
            if view == "left":
                arr = np.ascontiguousarray(np.fliplr(arr))
            sheet[r * FRAME_H:(r + 1) * FRAME_H,
                  c * FRAME_W:(c + 1) * FRAME_W] = arr
    return Image.fromarray(sheet)


# =====================================================================
#  NPC specs
# =====================================================================
# Palettes: family -> shades ordered light -> base -> dark (3 entries) or
# base -> dark (2 entries).  + #1B1B1B outline == 4..10 opaque colours.
# =====================================================================

SKIN = ((0xE9, 0xB9, 0x8F), (0xC9, 0x97, 0x6D))          # shared skin tone


def spec_red() -> dict:
    """阿燃 -- eager courier.  Short + stocky, bright short cape, mail bag,
    red headband over short dark hair."""
    fams = {
        "skin": SKIN,
        "red": ((0xF0, 0x7A, 0x55), (0xCE, 0x4B, 0x33), (0x9E, 0x35, 0x24)),
        "bright": ((0xEE, 0x6A, 0x4A),),          # cape + headband accent
        "leather": ((0x8A, 0x6A, 0x44), (0x63, 0x48, 0x2C)),
        "hair": ((0x63, 0x48, 0x2C),),            # same tone as leather dark
    }
    roles = {"HEAD": "skin", "HAND": "skin", "BODY": "red", "ARM_L": "red",
             "ARM_R": "red", "CAPE": "bright", "LEG_L": "red",
             "LEG_R": "red", "PROP": "leather", "ACC": "bright",
             "HAIR": "hair"}
    front = [
        # planted legs (2px gap so the pair reads) + boots
        fr("LEG_L", 10, 35, 13, GROUND_Y, bob=False),
        fr("LEG_R", 17, 35, 20, GROUND_Y, bob=False),
        fr("PROP", 9, 44, 13, GROUND_Y, bob=False),
        fr("PROP", 17, 44, 21, GROUND_Y, bob=False),
        # short stocky tunic torso
        fr("BODY", 9, 19, 22, 39),
        # bright short cape over the shoulders
        fr("CAPE", 6, 18, 25, 26),
        fr("CAPE", 5, 26, 26, 29),
        # mail bag hangs at the right hip behind the arm
        fr("PROP", 19, 32, 26, 40),
        # arms + hands
        fr("ARM_L", 5, 21, 8, 31), fr("ARM_R", 23, 21, 26, 31),
        fr("HAND", 5, 30, 8, 32), fr("HAND", 23, 30, 26, 32),
        # head: skin + short dark hair + red headband + 2 eye pixels
        fe("HEAD", 9, 5, 22, 20),
        fe("HAIR", 9, 5, 22, 9, views="d", clip=True),
        fe("HAIR", 9, 5, 22, 18, views="u", clip=True),
        fr("ACC", 9, 9, 22, 11, clip=True),
        # cross-body mail strap
        fl("PROP", 12, 20, 20, 31),
        fl("PROP", 13, 20, 21, 31),
    ]
    side = [
        # side legs overlap by 2px like the player's side view
        sr("LEG_L", 11, 35, 16, GROUND_Y, bob=False),
        sr("LEG_R", 15, 35, 20, GROUND_Y, bob=False),
        sr("PROP", 10, 44, 16, GROUND_Y, bob=False),
        sr("PROP", 15, 44, 21, GROUND_Y, bob=False),
        sr("BODY", 10, 19, 21, 39),
        sr("CAPE", 9, 18, 19, 28),
        sr("PROP", 18, 32, 25, 40),
        sr("ARM_R", 17, 21, 20, 31),
        sr("HAND", 17, 30, 20, 32),
        se("HEAD", 10, 5, 21, 20),
        se("HAIR", 10, 5, 21, 12, clip=True),
        sr("ACC", 10, 9, 21, 11, clip=True),
    ]
    details = [det(OUTLINE, [(13, 14), (18, 14)], "d")]
    return dict(name="npc_red", title="A-Ran (courier)", families=fams,
                roles=roles, front=front, side=side, details=details)


def spec_yellow() -> dict:
    """阿衡 -- watchmaker/scholar.  Tall + lean, long ochre coat, scarf,
    round brown-rimmed glasses, a small book in hand."""
    fams = {
        "skin": SKIN,
        "ochre": ((0xE0, 0xB4, 0x4E), (0xB9, 0x8A, 0x2E), (0x8A, 0x64, 0x1F)),
        "cream": ((0xF0, 0xE4, 0xC6), (0xC9, 0xB8, 0x93)),
        "leather": ((0x6B, 0x51, 0x36),),
        "hair": ((0x6B, 0x51, 0x36),),            # same tone as the book cover
    }
    roles = {"HEAD": "skin", "HAND": "skin", "BODY": "ochre", "CAPE": "ochre",
             "ARM_L": "ochre", "ARM_R": "ochre", "LEG_L": "ochre",
             "LEG_R": "ochre", "PROP": "leather", "ACC": "cream",
             "HAIR": "hair"}
    front = [
        fr("LEG_L", 12, 36, 14, GROUND_Y, bob=False),
        fr("LEG_R", 17, 36, 19, GROUND_Y, bob=False),
        fr("PROP", 11, 44, 14, GROUND_Y, bob=False),
        fr("PROP", 17, 44, 20, GROUND_Y, bob=False),
        # long lean coat with a flared hem
        fr("BODY", 11, 18, 20, 39),
        fr("BODY", 9, 38, 22, 41),
        fr("ARM_L", 8, 20, 10, 36), fr("ARM_R", 21, 20, 23, 36),
        fr("HAND", 8, 35, 10, 37), fr("HAND", 21, 35, 23, 37),
        fe("HEAD", 10, 2, 21, 16),
        fr("HEAD", 13, 15, 18, 19),          # thin neck
        fe("HAIR", 10, 2, 21, 8, views="d", clip=True),
        fe("HAIR", 10, 2, 21, 15, views="u", clip=True),
        fr("ACC", 11, 16, 20, 19, clip=True),  # scarf wrap
        fr("ACC", 18, 18, 20, 27),           # scarf tail
        # small book held in the left hand
        fr("PROP", 4, 31, 9, 37),
        fr("ACC", 8, 32, 9, 36),             # page edge of the book
    ]
    side = [
        sr("LEG_L", 11, 36, 16, GROUND_Y, bob=False),
        sr("LEG_R", 15, 36, 20, GROUND_Y, bob=False),
        sr("PROP", 10, 44, 16, GROUND_Y, bob=False),
        sr("PROP", 15, 44, 21, GROUND_Y, bob=False),
        sr("BODY", 10, 18, 21, 39),
        sr("BODY", 8, 38, 22, 41),
        sr("ARM_R", 17, 20, 20, 36),
        sr("HAND", 17, 35, 20, 37),
        se("HEAD", 10, 2, 21, 16),
        sr("HEAD", 14, 15, 17, 19),
        se("HAIR", 10, 2, 21, 8, clip=True),
        sr("ACC", 11, 16, 20, 19, clip=True),
        sr("ACC", 10, 18, 12, 28),           # scarf tail trails behind
        sr("PROP", 20, 31, 25, 37),          # book carried in front
        sr("ACC", 24, 32, 25, 36),
    ]
    glasses = [
        # left lens ring (3x3), right lens ring (3x3), bridge, temples
        (12, 9), (13, 9), (14, 9), (12, 10), (14, 10), (12, 11), (13, 11), (14, 11),
        (17, 9), (18, 9), (19, 9), (17, 10), (19, 10), (17, 11), (18, 11), (19, 11),
        (15, 10), (16, 10), (11, 10), (20, 10),
    ]
    details = [
        det((0x6B, 0x51, 0x36), glasses, "d"),        # brown spectacle rims
        det(OUTLINE, [(13, 10), (18, 10)], "d"),      # 2 eye pixels behind the lenses
    ]
    return dict(name="npc_yellow", title="A-Heng (watchmaker)",
                families=fams, roles=roles, front=front, side=side,
                details=details)


def spec_green() -> dict:
    """阿禾 -- gentle gardener.  Round build, straw hat, linen apron,
    flower branch in hand."""
    fams = {
        "skin": SKIN,
        "olive": ((0xA8, 0xC4, 0x6A), (0x86, 0xA2, 0x4E), (0x63, 0x7A, 0x38)),
        "straw": ((0xE4, 0xD0, 0x9C), (0xBF, 0xA7, 0x6E)),
        "flower": ((0xE8, 0xA2, 0xB4),),
    }
    roles = {"HEAD": "skin", "HAND": "skin", "BODY": "olive", "CAPE": "olive",
             "ARM_L": "olive", "ARM_R": "olive", "LEG_L": "olive",
             "LEG_R": "olive", "PROP": "flower", "ACC": "straw"}
    front = [
        fr("LEG_L", 10, 34, 14, GROUND_Y, bob=False),
        fr("LEG_R", 17, 34, 21, GROUND_Y, bob=False),
        fr("LEG_L", 9, 45, 14, GROUND_Y, bob=False),
        fr("LEG_R", 17, 45, 22, GROUND_Y, bob=False),
        # round body: box shoulders + belly ellipse
        fr("BODY", 8, 17, 23, 33),
        fe("BODY", 7, 26, 24, 40),
        fr("ARM_L", 5, 20, 8, 32), fr("ARM_R", 23, 20, 26, 32),
        fr("HAND", 5, 31, 8, 33), fr("HAND", 23, 31, 26, 33),
        # straw hat (broad brim + crown) over the head
        fe("HEAD", 10, 5, 21, 18),
        fe("ACC", 4, 8, 27, 13),
        fe("ACC", 11, 2, 20, 9),
        # linen apron, front only; knotted at the back on the up row
        fr("ACC", 12, 22, 19, 37, views="d", clip=True),
        fr("ACC", 11, 19, 12, 23, views="d", clip=True),
        fr("ACC", 19, 19, 20, 23, views="d", clip=True),
        fr("ACC", 14, 26, 17, 28, views="u", clip=True),
        fr("ACC", 13, 28, 14, 31, views="u", clip=True),
        fr("ACC", 17, 28, 18, 31, views="u", clip=True),
        # flower branch in the right hand (2px stem so it survives outlining)
        fr("LEG_L", 25, 30, 26, 32),
        fr("LEG_L", 26, 27, 27, 30),
        fr("LEG_L", 26, 24, 27, 27),
        fe("PROP", 26, 18, 30, 23),
    ]
    side = [
        sr("LEG_L", 11, 34, 15, GROUND_Y, bob=False),
        sr("LEG_R", 16, 34, 20, GROUND_Y, bob=False),
        sr("LEG_L", 10, 45, 15, GROUND_Y, bob=False),
        sr("LEG_R", 16, 45, 21, GROUND_Y, bob=False),
        sr("BODY", 9, 17, 22, 33),
        se("BODY", 8, 26, 23, 40),
        sr("ARM_R", 16, 20, 19, 32),
        sr("HAND", 16, 31, 19, 33),
        se("HEAD", 10, 5, 21, 18),
        se("ACC", 4, 8, 27, 13),
        se("ACC", 11, 2, 20, 9),
        sr("ACC", 13, 22, 18, 37, clip=True),
        # flower branch carried in front
        sr("LEG_L", 19, 30, 20, 32),
        sr("LEG_L", 20, 27, 21, 30),
        sr("LEG_L", 20, 24, 21, 27),
        se("PROP", 20, 18, 24, 23),
    ]
    details = [det(OUTLINE, [(13, 15), (18, 15)], "d")]
    return dict(name="npc_green", title="A-He (gardener)", families=fams,
                roles=roles, front=front, side=side, details=details)


def spec_blue() -> dict:
    """阿砚 -- calm road-keeper.  Upright, deep navy cloak + flat-brim hat,
    brass lantern in hand."""
    fams = {
        "skin": SKIN,
        "navy": ((0x3B, 0x5C, 0x8C), (0x26, 0x40, 0x6B), (0x18, 0x2B, 0x4C)),
        "brass": ((0xF2, 0xC9, 0x4C), (0xB9, 0x8A, 0x2E)),
    }
    roles = {"HEAD": "skin", "HAND": "skin", "BODY": "navy", "CAPE": "navy",
             "ARM_L": "navy", "ARM_R": "navy", "LEG_L": "navy",
             "LEG_R": "navy", "PROP": "brass", "ACC": "navy"}
    front = [
        fr("LEG_L", 11, 37, 14, GROUND_Y, bob=False),
        fr("LEG_R", 17, 37, 20, GROUND_Y, bob=False),
        fr("LEG_L", 10, 45, 14, GROUND_Y, bob=False),
        fr("LEG_R", 17, 45, 21, GROUND_Y, bob=False),
        # wide-bottom cloak (behind), open front uniform panel on top
        fr("CAPE", 9, 20, 22, 29),
        fr("CAPE", 8, 29, 23, 35),
        fr("CAPE", 7, 35, 24, 40),
        fr("BODY", 12, 20, 19, 37),
        fr("ARM_L", 6, 19, 9, 34), fr("ARM_R", 21, 19, 24, 34),
        fr("HAND", 6, 33, 9, 35), fr("HAND", 21, 33, 24, 35),
        fe("HEAD", 10, 7, 21, 20),
        fe("BODY", 8, 6, 23, 11),            # wide flat hat brim
        fe("BODY", 12, 3, 19, 8),            # hat crown
        fr("PROP", 12, 20, 19, 21),          # brass collar trim
        fr("PROP", 4, 36, 8, 42),            # lantern
    ]
    side = [
        sr("LEG_L", 11, 37, 15, GROUND_Y, bob=False),
        sr("LEG_R", 16, 37, 20, GROUND_Y, bob=False),
        sr("LEG_L", 10, 45, 15, GROUND_Y, bob=False),
        sr("LEG_R", 16, 45, 21, GROUND_Y, bob=False),
        sr("CAPE", 9, 20, 20, 40),
        sr("CAPE", 8, 31, 22, 40),
        sr("BODY", 13, 20, 19, 37),
        sr("ARM_R", 16, 19, 19, 34),
        sr("HAND", 16, 33, 19, 35),
        se("HEAD", 10, 7, 21, 20),
        se("BODY", 8, 6, 23, 11),
        se("BODY", 12, 3, 19, 8),
        sr("PROP", 13, 20, 19, 21),
        sr("PROP", 20, 36, 24, 42),
    ]
    details = [
        det(OUTLINE, [(13, 15), (18, 15)], "d"),
        # lantern frame: dark band across the glass
        det(OUTLINE, [(5, 39), (6, 39), (7, 39)], "du"),
        det(OUTLINE, [(21, 39), (22, 39), (23, 39)], "r"),
    ]
    return dict(name="npc_blue", title="A-Yan (road-keeper)", families=fams,
                roles=roles, front=front, side=side, details=details)


def spec_purple() -> dict:
    """阿遥 -- romantic painter.  Wide purple hat, lilac scarf, sketchbook on
    the back, brush in hand, fluttering coat."""
    fams = {
        "skin": SKIN,
        "purple": ((0x9C, 0x6F, 0xD0), (0x7A, 0x4F, 0xA8), (0x56, 0x35, 0x7A)),
        "lilac": ((0xC9, 0xA6, 0xE8), (0x9A, 0x79, 0xBE)),
        "paper": ((0xEF, 0xE6, 0xCC),),
    }
    roles = {"HEAD": "skin", "HAND": "skin", "BODY": "purple", "CAPE": "purple",
             "ARM_L": "purple", "ARM_R": "purple", "LEG_L": "purple",
             "LEG_R": "purple", "PROP": "paper", "ACC": "lilac"}
    front = [
        fr("LEG_L", 12, 36, 14, GROUND_Y, bob=False),
        fr("LEG_R", 17, 36, 19, GROUND_Y, bob=False),
        fr("LEG_L", 11, 45, 14, GROUND_Y, bob=False),
        fr("LEG_R", 17, 45, 20, GROUND_Y, bob=False),
        fr("BODY", 10, 18, 21, 35),
        fr("BODY", 8, 33, 23, 39),
        fr("BODY", 7, 37, 10, 43),           # fluttering back corner
        fr("ARM_L", 7, 19, 10, 34), fr("ARM_R", 21, 19, 24, 34),
        fr("HAND", 7, 33, 10, 35), fr("HAND", 21, 33, 24, 35),
        fe("HEAD", 10, 4, 21, 17),
        fe("BODY", 3, 5, 28, 10),            # very wide brim
        fe("BODY", 10, 1, 21, 7),            # hat crown
        fr("ACC", 11, 4, 20, 5, clip=True),  # lilac hat band
        fr("ACC", 11, 15, 20, 18, clip=True),  # scarf
        fr("ACC", 17, 18, 20, 24),           # scarf tail
        fr("ACC", 18, 24, 21, 28),
        # sketchbook strapped to the back (up row only) + shoulder strap (down)
        fr("PROP", 11, 20, 20, 31, views="u"),
        fl("ACC", 12, 19, 12, 32, views="u"),
        fl("ACC", 19, 19, 19, 32, views="u"),
        fl("PROP", 12, 19, 21, 30, views="d"),
        # brush in the right hand
        fr("PROP", 24, 32, 25, 34),
        fr("PROP", 25, 29, 26, 32),
        fr("PROP", 26, 26, 27, 29),
    ]
    side = [
        sr("LEG_L", 11, 36, 16, GROUND_Y, bob=False),
        sr("LEG_R", 15, 36, 20, GROUND_Y, bob=False),
        sr("LEG_L", 10, 45, 16, GROUND_Y, bob=False),
        sr("LEG_R", 15, 45, 21, GROUND_Y, bob=False),
        sr("BODY", 10, 18, 21, 35),
        sr("BODY", 7, 33, 23, 39),
        sr("BODY", 7, 36, 11, 43),
        sr("ARM_R", 17, 19, 20, 34),
        sr("HAND", 17, 33, 20, 35),
        se("HEAD", 10, 4, 21, 17),
        se("BODY", 3, 5, 28, 10),
        se("BODY", 10, 1, 21, 7),
        sr("ACC", 11, 4, 20, 5, clip=True),
        sr("ACC", 11, 15, 20, 18, clip=True),
        sr("ACC", 9, 18, 11, 27),
        sr("PROP", 21, 32, 22, 34),
        sr("PROP", 22, 29, 23, 32),
        sr("PROP", 23, 26, 24, 29),
    ]
    details = [
        det(OUTLINE, [(13, 13), (18, 13)], "d"),
        det(OUTLINE, [(23, 25), (24, 25), (23, 24)], "du"),   # brush tip paint
        det(OUTLINE, [(22, 25), (23, 25), (22, 24)], "r"),
        # sketchbook pages / spine on the back
        det(OUTLINE, [(15, 21), (15, 30)], "u"),
        det(OUTLINE, [(11, 22), (20, 22), (11, 29), (20, 29)], "u"),
    ]
    return dict(name="npc_purple", title="A-Yao (painter)", families=fams,
                roles=roles, front=front, side=side, details=details)


SPECS = [spec_red, spec_yellow, spec_green, spec_blue, spec_purple]


# =====================================================================
#  path_dirt.png -- seamless 256x256 dirt / gravel tile
# =====================================================================
def _periodic_noise(rng: np.random.Generator, size: int, cells: int) -> np.ndarray:
    """Smooth value noise whose lattice wraps -> the result tiles seamlessly."""
    lat = rng.random((cells, cells)).astype(np.float32)
    coord = np.arange(size, dtype=np.float32) * (cells / float(size))
    i0 = np.floor(coord).astype(np.int32) % cells
    i1 = (i0 + 1) % cells
    fr = coord - np.floor(coord)
    sm = fr * fr * (3.0 - 2.0 * fr)                 # smoothstep
    a = lat[np.ix_(i0, i0)]
    b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]
    d = lat[np.ix_(i1, i1)]
    top = a + (b - a) * sm[None, :]
    bot = c + (d - c) * sm[None, :]
    return top + (bot - top) * sm[:, None]


def build_path_dirt(rng: np.random.Generator) -> Image.Image:
    size = 256
    n = (0.46 * _periodic_noise(rng, size, 3)
         + 0.26 * _periodic_noise(rng, size, 7)
         + 0.16 * _periodic_noise(rng, size, 17)
         + 0.12 * _periodic_noise(rng, size, 61))
    span = float(n.max() - n.min())
    n = (n - n.min()) / (span if span > 1e-6 else 1.0)

    c_dark = np.array([0x6B, 0x51, 0x36], np.float32)   # #6B5136
    c_base = np.array([0x8A, 0x6A, 0x44], np.float32)   # #8A6A44
    c_lite = np.array([0xA9, 0x85, 0x5A], np.float32)   # #A9855A
    lo = np.clip(n / 0.5, 0.0, 1.0)[..., None]
    hi = np.clip((n - 0.5) / 0.5, 0.0, 1.0)[..., None]
    rgb = np.where(n[..., None] < 0.5,
                   c_dark + (c_base - c_dark) * lo,
                   c_base + (c_lite - c_base) * hi).astype(np.float32)

    # fine grain, independent per pixel -> tileable by construction
    grain = (rng.random((size, size)).astype(np.float32) - 0.5) * 14.0
    rgb += grain[..., None]

    # worn ruts: two wavy tracks, periodic in y so opposite borders match
    for track_x, phase, depth in ((74, 0.0, 0.55), (184, 2.1, 0.45)):
        for y in range(size):
            u = 2.0 * math.pi * y / size
            cx = (track_x + 9.0 * math.sin(2.0 * u + phase)
                  + 4.0 * math.sin(5.0 * u + phase * 1.7))
            for dxx, mix, col in ((-2, 0.10, c_lite), (-1, 0.22, c_dark),
                                  (0, depth, c_dark), (1, 0.22, c_dark),
                                  (2, 0.10, c_lite)):
                x = int(round(cx + dxx)) % size
                rgb[y, x] = rgb[y, x] * (1.0 - mix) + col * mix

    # gravel speckles
    r2 = rng.random((size, size))
    rgb[r2 < 0.018] += np.array([16, 12, 8], np.float32)
    rgb[(r2 >= 0.018) & (r2 < 0.036)] -= np.array([13, 10, 7], np.float32)

    # small stones, written with modulo wrap so they survive the tile seam
    stones = ((0xC2, 0xA1, 0x77), (0xA8, 0x8B, 0x62), (0x94, 0x80, 0x6B))
    stone_dark = np.array([0x4A, 0x38, 0x26], np.float32)
    for _ in range(190):
        cx = int(rng.integers(0, size))
        cy = int(rng.integers(0, size))
        w = int(rng.integers(1, 4))
        h = int(rng.integers(1, 3))
        body = np.array(stones[int(rng.integers(0, len(stones)))], np.float32)
        for yy in range(cy, cy + h):
            for xx in range(cx, cx + w):
                shade = 0.0 if yy == cy else 0.25
                rgb[yy % size, xx % size] = body * (1.0 - shade) + stone_dark * shade
        for xx in range(cx, cx + w):
            yy = (cy + h) % size
            rgb[yy, xx % size] = stone_dark * 0.6 + rgb[yy, xx % size] * 0.4

    out = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    rgba = np.dstack([out, np.full((size, size, 1), 255, np.uint8)])
    return Image.fromarray(rgba)


# =====================================================================
#  ui_panel.png -- 48x48 nine-slice dialogue panel
# =====================================================================
PANEL_CREAM = (0xE8, 0xDC, 0xC0)        # #E8DCC0
PANEL_INNER = (0x0E, 0x14, 0x20)        # dark blue-black
PANEL_SHADOW = (0x05, 0x07, 0x0C)
PANEL_ALPHA = 210
PANEL_MARGIN = 8


def build_panel() -> Image.Image:
    w = h = 48
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., :3] = PANEL_INNER
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
    # beveled corners: 3 transparent pixels per corner
    for x, y in ((0, 0), (1, 0), (0, 1), (47, 0), (46, 0), (47, 1),
                 (0, 47), (1, 47), (0, 46), (47, 47), (46, 47), (47, 46)):
        arr[y, x] = 0
    # 1px inner shadow just inside the border
    sh = PANEL_SHADOW + (220,)
    arr[2, 2:w - 2] = sh
    arr[h - 3, 2:w - 2] = sh
    arr[2:h - 2, 2] = sh
    arr[2:h - 2, w - 3] = sh
    return Image.fromarray(arr)


# =====================================================================
#  ui_choice_cursor.png -- 8x8 cream/yellow arrow
# =====================================================================
CURSOR_ART = (
    "........",
    ".XX.....",
    ".XXXX...",
    ".XXXXXX.",
    ".XXXXXXX",
    ".XXXXXX.",
    ".XXXX...",
    ".XX.....",
)


def build_cursor() -> Image.Image:
    w = h = 8
    cream = (0xE8, 0xDC, 0xC0, 255)
    yellow = (0xF2, 0xC9, 0x4C, 255)
    arr = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(CURSOR_ART):
        for x, ch in enumerate(row):
            if ch == "X":
                arr[y, x] = yellow if x >= 4 else cream
    return Image.fromarray(arr)


# =====================================================================
#  contact sheet preview (4x nearest)
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


def _font(size: int = 18):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # older Pillow
        return ImageFont.load_default()


def build_preview(assets: dict, path_img: Image.Image,
                  panel: Image.Image, cursor: Image.Image) -> Image.Image:
    k = 4
    margin, gap, lgap = 22, 22, 6
    font = _font(18)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))

    def tw(text: str) -> int:
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[2] - b[0])

    line_h = 24
    names = [s["name"] for s in
             (spec_red(), spec_yellow(), spec_green(), spec_blue(), spec_purple())]
    titles = {s["name"]: s["title"] for s in
              (spec_red(), spec_yellow(), spec_green(), spec_blue(), spec_purple())}

    sheet_w, sheet_h = SHEET_W * k, SHEET_H * k
    row_a_w = len(names) * sheet_w + (len(names) - 1) * gap

    label0 = "%s.png  64x192"
    legend = ("each sheet: 2 cols x 4 rows of 32x48   |   rows: down / left / "
              "right / up   |   cols: idle 0 / breathe 1")

    right_w = max(panel.width * k, cursor.width * k,
                  tw("ui_panel.png 48x48 nine-slice"),
                  tw("ui_choice_cursor.png 8x8"))
    width = max(row_a_w, path_img.width * k + gap + right_w,
                tw(legend)) + margin * 2

    header = ("gen_npc_assets.py -- NPC sheets 64x192, path 256x256, "
              "panel 48x48, cursor 8x8 (all at 4x nearest)")
    header_h = line_h + 6
    row_a_top = margin + header_h
    row_a_bottom = row_a_top + sheet_h + lgap + line_h * 3 + 8
    row_b_top = row_a_bottom + gap
    path_h = path_img.height * k
    row_b_bottom = row_b_top + path_h + lgap + line_h
    height = row_b_bottom + margin

    canvas = _checker(width, height)
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, margin), header, fill=(235, 235, 235, 255), font=font)

    # --- row A: the five NPC sheets
    for i, name in enumerate(names):
        img = assets[name].resize((sheet_w, sheet_h), Image.Resampling.NEAREST)
        x = margin + i * (sheet_w + gap)
        canvas.alpha_composite(img, (x, row_a_top))
        ty = row_a_top + sheet_h + lgap
        draw.text((x, ty), label0 % name, fill=(235, 235, 235, 255), font=font)
        draw.text((x, ty + line_h), titles[name],
                  fill=(200, 210, 220, 255), font=font)
    draw.text((margin, row_a_top + sheet_h + lgap + line_h * 2 + 6), legend,
              fill=(210, 218, 226, 255), font=font)

    # --- row B: path tile + panel + cursor
    path_scaled = path_img.resize((path_img.width * k, path_h),
                                  Image.Resampling.NEAREST)
    px = margin
    canvas.alpha_composite(path_scaled, (px, row_b_top))
    draw.text((px, row_b_top + path_h + lgap),
              "path_dirt.png 256x256 seamless dirt path tile (repeat both axes)",
              fill=(235, 235, 235, 255), font=font)

    rx = margin + path_img.width * k + gap
    panel_scaled = panel.resize((panel.width * k, panel.height * k),
                                Image.Resampling.NEAREST)
    canvas.alpha_composite(panel_scaled, (rx, row_b_top))
    draw.text((rx, row_b_top + panel.height * k + lgap),
              "ui_panel.png 48x48 nine-slice",
              fill=(235, 235, 235, 255), font=font)

    cy = row_b_top + panel.height * k + lgap + line_h + 10
    cursor_scaled = cursor.resize((cursor.width * k, cursor.height * k),
                                  Image.Resampling.NEAREST)
    canvas.alpha_composite(cursor_scaled, (rx, cy))
    draw.text((rx, cy + cursor.height * k + lgap),
              "ui_choice_cursor.png 8x8",
              fill=(235, 235, 235, 255), font=font)
    return canvas


# =====================================================================
#  verification
# =====================================================================
def _hex(rgb) -> str:
    return "#%02X%02X%02X" % tuple(int(v) for v in rgb[:3])


def _frame_boxes(arr: np.ndarray):
    boxes = []
    for r in range(FRAME_ROWS):
        for c in range(FRAME_COLS):
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


def verify_npc(spec: dict, img: Image.Image) -> bool:
    arr = np.asarray(img)
    ok = True
    print(f"[{spec['name']}.png]  {spec['title']}")

    size_ok = (img.width, img.height) == (SHEET_W, SHEET_H)
    ok &= size_ok
    print(f"  sheet size {img.width}x{img.height} (expected "
          f"{SHEET_W}x{SHEET_H}): {'PASS' if size_ok else 'FAIL'}")

    boxes = _frame_boxes(arr)
    frames = [(r, c) for r, c, b in boxes]
    empty = [(r, c) for r, c, b in boxes if b is None]
    if empty:
        ok = False
        print(f"  FAIL fully transparent frames: {empty}")
    else:
        print(f"  all {len(frames)}/8 frames non-empty: PASS")

    grounds = [b[3] for _, _, b in boxes if b]
    ground_ok = len(grounds) == 8 and all(g == GROUND_Y for g in grounds)
    ok &= ground_ok
    print(f"  ground line: max alpha y == {GROUND_Y} in all {len(grounds)} "
          f"frames: {'PASS' if ground_ok else 'FAIL ' + str(sorted(set(grounds)))}")

    widths = [b[1] - b[0] + 1 for _, _, b in boxes if b]
    heights = [b[3] - b[2] + 1 for _, _, b in boxes if b]
    fit_ok = max(widths) <= FRAME_W and max(heights) <= FRAME_H
    ok &= fit_ok
    print(f"  frame content max {max(widths)}x{max(heights)} px "
          f"(<= {FRAME_W}x{FRAME_H}): {'PASS' if fit_ok else 'FAIL'}")

    # 4 directions x 2 frames populated (grid rows / columns)
    grid_ok = True
    for r in range(FRAME_ROWS):
        band = arr[r * FRAME_H:(r + 1) * FRAME_H]
        if not (band[..., 3] > 0).any():
            grid_ok = False
            print(f"  FAIL grid row {r} ({VIEWS[r]}) is empty")
    for c in range(FRAME_COLS):
        band = arr[:, c * FRAME_W:(c + 1) * FRAME_W]
        if not (band[..., 3] > 0).any():
            grid_ok = False
            print(f"  FAIL grid column {c} (frame {c}) is empty")
    ok &= grid_ok
    print(f"  4 directions x 2 frames populated: {'PASS' if grid_ok else 'FAIL'}")

    # outline: every silhouette boundary pixel must carry #1B1B1B
    outline_hits = 0
    outline_total = 0
    for r in range(FRAME_ROWS):
        for c in range(FRAME_COLS):
            f = arr[r * FRAME_H:(r + 1) * FRAME_H,
                    c * FRAME_W:(c + 1) * FRAME_W]
            sil = f[..., 3] > 0
            npad = np.pad(sil, 1)
            inner = (npad[:-2, 1:-1] & npad[2:, 1:-1]
                     & npad[1:-1, :-2] & npad[1:-1, 2:])
            boundary = sil & ~inner
            is_out = np.all(f[..., :3] == np.array(OUTLINE, np.uint8), axis=-1)
            outline_hits += int((boundary & is_out).sum())
            outline_total += int(boundary.sum())
    ratio = outline_hits / max(outline_total, 1)
    out_ok = ratio >= 0.95
    ok &= out_ok
    print(f"  outline #1B1B1B: {outline_hits}/{outline_total} boundary px "
          f"({ratio * 100:.1f}%): {'PASS' if out_ok else 'FAIL'}")

    # palette discipline: exact colours, binary alpha, clean transparent RGB
    opaque = arr[arr[..., 3] > 0][:, :3]
    cols = {tuple(int(v) for v in px) for px in np.unique(opaque, axis=0)}
    allowed = {OUTLINE}
    for fam in spec["families"].values():
        allowed.update(tuple(int(v) for v in s) for s in fam)
    extra = cols - allowed
    n_ok = 4 <= len(cols) <= 10 and not extra
    ok &= n_ok
    print(f"  opaque colours: {len(cols)} (need 4..10): "
          f"{'PASS' if 4 <= len(cols) <= 10 else 'FAIL'}")
    print(f"  no stray / anti-aliased colours: {'PASS' if not extra else 'FAIL ' + str(sorted(extra)[:4])}")
    if extra:
        ok = False

    alpha_vals = set(int(v) for v in np.unique(arr[..., 3]))
    bin_ok = alpha_vals <= {0, 255}
    ok &= bin_ok
    print(f"  binary alpha (no AA): {sorted(alpha_vals)}: "
          f"{'PASS' if bin_ok else 'FAIL'}")

    trans = arr[arr[..., 3] == 0]
    trans_max = int(trans[:, :3].max()) if trans.size else 0
    ok &= trans_max == 0
    print(f"  transparent px RGB all 0: {'PASS' if trans_max == 0 else 'FAIL'}")

    # left row must be the exact mirror of right row (consistency)
    mirror_ok = True
    for c in range(FRAME_COLS):
        left = arr[1 * FRAME_H:2 * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W]
        right = arr[2 * FRAME_H:3 * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W]
        if not np.array_equal(left, np.fliplr(right)):
            mirror_ok = False
    ok &= mirror_ok
    print(f"  left row == mirror(right row): {'PASS' if mirror_ok else 'FAIL'}")

    # idle frame 1 is a real (subtle) breathing pose, feet planted
    bob_ok = True
    for r in range(FRAME_ROWS):
        f0 = arr[r * FRAME_H:(r + 1) * FRAME_H, 0:FRAME_W]
        f1 = arr[r * FRAME_H:(r + 1) * FRAME_H, FRAME_W:2 * FRAME_W]
        if np.array_equal(f0, f1):
            bob_ok = False
            print(f"  FAIL row {r} ({VIEWS[r]}): breathe frame identical to idle")
        # feet rows must not move
        if not np.array_equal(f0[44:], f1[44:]):
            bob_ok = False
            print(f"  FAIL row {r} ({VIEWS[r]}): feet moved between frames")
    ok &= bob_ok
    print(f"  breathe bob present, feet planted: {'PASS' if bob_ok else 'FAIL'}")

    print(f"  palette: {', '.join(_hex(c) for c in sorted(cols))}")
    return ok


def verify_path(img: Image.Image) -> bool:
    arr = np.asarray(img).astype(np.float32)
    rgb = arr[..., :3]
    h, w = rgb.shape[:2]
    ok = (img.width, img.height) == (256, 256)
    print(f"[path_dirt.png]  {img.width}x{img.height} (expected 256x256): "
          f"{'PASS' if ok else 'FAIL'}")

    wrap_h = float(np.abs(rgb[:, 0, :] - rgb[:, w - 1, :]).mean())
    typ_h = float(np.abs(rgb[:, 1:, :] - rgb[:, :-1, :]).mean())
    wrap_v = float(np.abs(rgb[0, :, :] - rgb[h - 1, :, :]).mean())
    typ_v = float(np.abs(rgb[1:, :, :] - rgb[:-1, :, :]).mean())
    ratio = max(wrap_h / max(typ_h, 1e-6), wrap_v / max(typ_v, 1e-6))
    seam_ok = ratio < 3.0
    ok &= seam_ok
    print(f"  seam: horizontal wrap |d|={wrap_h:.2f} (typical neighbour "
          f"{typ_h:.2f})")
    print(f"  seam: vertical   wrap |d|={wrap_v:.2f} (typical neighbour "
          f"{typ_v:.2f})")
    print(f"  seam ratio {ratio:.2f} (< 3 => seamless): "
          f"{'PASS' if seam_ok else 'FAIL'}")

    alpha_ok = bool((arr[..., 3] == 255).all())
    ok &= alpha_ok
    print(f"  alpha 255 everywhere: {'PASS' if alpha_ok else 'FAIL'}")
    used = len({tuple(int(v) for v in px) for px in
                np.unique(np.asarray(img).reshape(-1, 4), axis=0)})
    print(f"  colours used: {used} (warm browns + gravel + stones)")
    return ok


def verify_panel(img: Image.Image) -> bool:
    arr = np.asarray(img)
    ok = (img.width, img.height) == (48, 48)
    print(f"[ui_panel.png]  {img.width}x{img.height} (expected 48x48): "
          f"{'PASS' if ok else 'FAIL'}")
    cream = np.array(PANEL_CREAM + (255,), np.uint8)

    # border pixels uniform on all four sides (excluding 3x3 bevel corners)
    sides = {"top": (arr[0:2, 3:45], arr[2, 3:45]),
             "bottom": (arr[46:48, 3:45], arr[45, 3:45]),
             "left": (arr[3:45, 0:2], arr[3:45, 2]),
             "right": (arr[3:45, 46:48], arr[3:45, 45])}
    border_ok = True
    for side, (band, shadow) in sides.items():
        if not np.all(band == cream):
            border_ok = False
            print(f"  FAIL {side} border band not uniform {PANEL_CREAM}")
    ok &= border_ok
    print(f"  2px cream border uniform on all 4 sides: "
          f"{'PASS' if border_ok else 'FAIL'}")

    # 1px inner shadow present on all four sides
    shadow_ok = True
    for side, (band, shadow) in sides.items():
        if not np.all(shadow[..., 3] == 220):
            shadow_ok = False
            print(f"  FAIL {side} inner shadow missing")
    ok &= shadow_ok
    print(f"  1px inner shadow ring: {'PASS' if shadow_ok else 'FAIL'}")

    interior = arr[PANEL_MARGIN:48 - PANEL_MARGIN,
                   PANEL_MARGIN:48 - PANEL_MARGIN]
    uniform = bool(np.all(interior == interior[0, 0]))
    alpha_ok = bool(np.all(interior[..., 3] == PANEL_ALPHA))
    ok &= uniform and alpha_ok
    print(f"  interior {interior.shape[1]}x{interior.shape[0]} uniform "
          f"{_hex(interior[0, 0])} alpha {int(interior[0, 0, 3])}: "
          f"{'PASS' if uniform else 'FAIL'}")
    print(f"  interior alpha == {PANEL_ALPHA}: "
          f"{'PASS' if alpha_ok else 'FAIL'}")

    # NinePatchRect safety: 8px margins contain the whole frame decoration
    safe = True
    for y in range(PANEL_MARGIN, 48 - PANEL_MARGIN):
        for x in range(PANEL_MARGIN, 48 - PANEL_MARGIN):
            if not np.array_equal(arr[y, x], arr[PANEL_MARGIN, PANEL_MARGIN]):
                safe = False
    ok &= safe
    print(f"  9-slice safe with {PANEL_MARGIN}px margins: "
          f"{'PASS' if safe else 'FAIL'}")

    bevel = bool(arr[0, 0, 3] == 0 and arr[47, 47, 3] == 0
                 and arr[0, 47, 3] == 0 and arr[47, 0, 3] == 0)
    ok &= bevel
    print(f"  beveled (cut) corners: {'PASS' if bevel else 'FAIL'}")
    return ok


def verify_cursor(img: Image.Image) -> bool:
    arr = np.asarray(img)
    ok = (img.width, img.height) == (8, 8) and (arr[..., 3] > 0).any()
    print(f"[ui_choice_cursor.png]  {img.width}x{img.height} (expected 8x8): "
          f"{'PASS' if ok else 'FAIL'}")
    alpha_vals = set(int(v) for v in np.unique(arr[..., 3]))
    bin_ok = alpha_vals <= {0, 255}
    ok &= bin_ok
    print(f"  binary alpha {sorted(alpha_vals)}: {'PASS' if bin_ok else 'FAIL'}")
    widths = [int((arr[y, :, 3] > 0).sum()) for y in range(8)]
    arrow_ok = widths == [0, 2, 4, 6, 7, 6, 4, 2]
    ok &= arrow_ok
    print(f"  arrow widths top->bottom {widths}: "
          f"{'PASS' if arrow_ok else 'FAIL'}")
    cols = {tuple(int(v) for v in px) for px in np.unique(arr[arr[..., 3] > 0],
                                                          axis=0)}
    print(f"  colours: {', '.join(_hex(c) for c in sorted(cols))}")
    return ok


# =====================================================================
#  main
# =====================================================================
def main() -> int:
    rng = np.random.default_rng(SEED)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 74)
    print("gen_npc_assets.py  seed=%d  out=%s" % (SEED, OUT_DIR))
    print("=" * 74)

    ok = True
    assets = {}
    for make in SPECS:
        spec = make()
        img = build_sheet(spec)
        img.save(OUT_DIR / (spec["name"] + ".png"))
        assets[spec["name"]] = img
        print(f"[wrote] {spec['name'] + '.png':<22} {img.width:>4}x"
              f"{img.height:<4} {img.mode}")

    path_img = build_path_dirt(rng)
    path_img.save(OUT_DIR / "path_dirt.png")
    print(f"[wrote] {'path_dirt.png':<22} {path_img.width:>4}x"
          f"{path_img.height:<4} {path_img.mode}")

    panel = build_panel()
    panel.save(OUT_DIR / "ui_panel.png")
    print(f"[wrote] {'ui_panel.png':<22} {panel.width:>4}x"
          f"{panel.height:<4} {panel.mode}")

    cursor = build_cursor()
    cursor.save(OUT_DIR / "ui_choice_cursor.png")
    print(f"[wrote] {'ui_choice_cursor.png':<22} {cursor.width:>4}x"
          f"{cursor.height:<4} {cursor.mode}")

    preview = build_preview(assets, path_img, panel, cursor)
    preview.save(OUT_DIR / "_preview_npc.png")
    print(f"[wrote] {'_preview_npc.png':<22} {preview.width:>4}x"
          f"{preview.height:<4} {preview.mode}")

    print("\n--- verification " + "-" * 57)
    for make in SPECS:
        spec = make()
        ok &= verify_npc(spec, assets[spec["name"]])
        print()
    ok &= verify_path(path_img)
    print()
    ok &= verify_panel(panel)
    print()
    ok &= verify_cursor(cursor)
    print()
    preview_ok = (OUT_DIR / "_preview_npc.png").is_file()
    ok &= preview_ok
    print(f"[_preview_npc.png] contact sheet written: "
          f"{'PASS' if preview_ok else 'FAIL'}")

    print("\n--- palette summary " + "-" * 53)
    print("  npc_red    : red-orange #F07A55/#CE4B33/#9E3524, bright band "
          "#EE6A4A, leather #8A6A44/#63482C, skin")
    print("  npc_yellow : mustard #E0B44E/#B98A2E/#8A641F, cream scarf "
          "#F0E4C6/#C9B893, book #6B5136, skin")
    print("  npc_green  : olive #A8C46A/#86A24E/#637A38, straw/linen "
          "#E4D09C/#BFA76E, bloom #E8A2B4, skin")
    print("  npc_blue   : navy #3B5C8C/#26406B/#182B4C, brass lantern "
          "#F2C94C/#B98A2E, skin")
    print("  npc_purple : purple #9C6FD0/#7A4FA8/#56357A, lilac "
          "#C9A6E8/#9A79BE, paper #EFE6CC, skin")
    print("  outline    : #1B1B1B 1px, painted inside every silhouette")
    print("  path_dirt  : #6B5136 / #8A6A44 / #A9855A + gravel + stones")
    print("  ui_panel   : #E8DCC0 2px border, #0E1420 interior alpha 210")
    print("  cursor     : #E8DCC0 cream + #F2C94C yellow tip")

    print("\n--- godot import notes " + "-" * 48)
    print("  every npc_*.png / ui_choice_cursor.png / ui_panel.png :")
    print("    Filter = Nearest, Mipmaps = OFF, Compression = Lossless,")
    print("    Repeat = Disabled (sprite sheets; frame = 32x48)")
    print("  player_whitebox.png stays the tinted player: set "
          "Sprite3D.modulate")
    print("    to the NPC accent to 'dye' the player with that NPC's colour.")
    print("  path_dirt.png : Filter = Nearest, Mipmaps = OFF, Lossless,")
    print("    Repeat = Enabled (tileable; use on the mountain path mesh)")
    print("  ui_panel.png  : NinePatchRect, patch margins 8/8/8/8, "
          "Filter = Nearest")
    print("  ui_choice_cursor.png : 8x8 TextureRect / Sprite2D, Nearest")

    print("\nRESULT:", "PASS - all checks green" if ok else "FAIL - see above")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
