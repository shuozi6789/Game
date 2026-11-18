#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_polish_sprites.py -- refined deterministic pixel art for hd2d-rpg.

This is an *additional* generator: it never touches gen_assets.py,
gen_npc_assets.py or gen_rest_assets.py, it only re-writes the sprite files
listed below into <project>/assets/generated/ .

    player_whitebox.png     128x192   4 cols x 4 rows of 32x48
                                      rows = facing down / left / right / up
                                      cols = walk frames 0..3 (0 = standing)
    npc_red.png             64x192    2 cols x 4 rows of 32x48
    npc_yellow.png                    rows = down / left / right / up
    npc_green.png                     cols = idle 0 / breathe 1
    npc_blue.png
    npc_purple.png
    portrait_player.png     32x32     dialogue bust of the white-box hero
    portrait_red.png        32x32     dialogue busts, 1px #1B1B1B outline
    portrait_yellow.png
    portrait_green.png
    portrait_blue.png
    portrait_purple.png
    _preview_polish.png               contact sheet, 4x nearest, labelled

What "polish" means here (same style contract, finer execution):

  * same 32x48 frames / same 128x192 + 64x192 sheets / same 32x32 portraits,
    same low-res scale (1 art pixel == 1 screen pixel), no anti-aliasing
  * better proportions: rounded-box heads, a real neck, a shoulder line,
    tapered torso, five-pixel legs with separate boots and readable hands
  * every shape is stamped as a *part*, so 1px seams fall exactly where two
    body parts meet; props and accessories get their own 1px dark edge
  * richer but still restrained shading: a per-part upper-left light ramp
    (3-4 flat tones) plus a 1px contact shadow on the bottom row of a part
  * the hero keeps the pure white-box palette: body #FFFFFF, #F2F2F2 /
    #E4E4E4 / #D4D4D4 shading, 1px #B8B8B8 rim, no face, no clothes
  * NPCs keep their identities, silhouettes and *exact* muted palettes from
    gen_npc_assets.py -- only the linework, shapes and props are refined
  * idle frame 1 is a 1px breathing bob of head / torso / arms / held props;
    legs and boots never move, so the feet stay pixel-identical
  * the ground line is y == 47 in every single frame

Fully deterministic: no random numbers are used anywhere, the output is
byte-identical on every run.  No .import files, no Godot, no temp files.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------------------------- config
FRAME_W, FRAME_H = 32, 48
GROUND = FRAME_H - 1                      # y == 47, the one and only ground line
VIEWS = ("down", "left", "right", "up")   # sheet row order, top -> bottom

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "generated"

# ------------------------------------------------------------------ palettes
# white-box hero: exactly these five colours, nothing else, ever
WHITE = (0xFF, 0xFF, 0xFF)
SHADE1 = (0xF2, 0xF2, 0xF2)
SHADE2 = (0xE4, 0xE4, 0xE4)
SHADE3 = (0xD4, 0xD4, 0xD4)
RIM = (0xB8, 0xB8, 0xB8)
PLAYER_RAMP = (WHITE, SHADE1, SHADE2, SHADE3)
PLAYER_COLOURS = {WHITE, SHADE1, SHADE2, SHADE3, RIM}

OUTLINE = (0x1B, 0x1B, 0x1B)              # shared 1px outline for the NPCs

# NPC palettes -- deliberately the *same* hex values as gen_npc_assets.py so
# the mood / mean colour of every sheet is unchanged.
SKIN = ((0xE9, 0xB9, 0x8F), (0xC9, 0x97, 0x6D))
LEATHER = ((0x8A, 0x6A, 0x44), (0x63, 0x48, 0x2C))
LEATHER_PLAIN = ((0x6B, 0x51, 0x36),)
RED = ((0xF0, 0x7A, 0x55), (0xCE, 0x4B, 0x33), (0x9E, 0x35, 0x24))
BRIGHT_RED = ((0xEE, 0x6A, 0x4A),)
OCHRE = ((0xE0, 0xB4, 0x4E), (0xB9, 0x8A, 0x2E), (0x8A, 0x64, 0x1F))
CREAM = ((0xF0, 0xE4, 0xC6), (0xC9, 0xB8, 0x93))
OLIVE = ((0xA8, 0xC4, 0x6A), (0x86, 0xA2, 0x4E), (0x63, 0x7A, 0x38))
STRAW = ((0xE4, 0xD0, 0x9C), (0xBF, 0xA7, 0x6E))
BLOOM = ((0xE8, 0xA2, 0xB4),)
NAVY = ((0x3B, 0x5C, 0x8C), (0x26, 0x40, 0x6B), (0x18, 0x2B, 0x4C))
BRASS = ((0xF2, 0xC9, 0x4C), (0xB9, 0x8A, 0x2E))
HAIR_DARK = ((0x2E, 0x2A, 0x26),)
PURPLE = ((0x9C, 0x6F, 0xD0), (0x7A, 0x4F, 0xA8), (0x56, 0x35, 0x7A))
LILAC = ((0xC9, 0xA6, 0xE8), (0x9A, 0x79, 0xBE))
PAPER = ((0xEF, 0xE6, 0xCC),)

# --------------------------------------------------------------- role tables
PLAYER_ROLES = ["", "HEAD", "NECK", "TORSO", "ARM_L", "ARM_R", "LEG_L", "LEG_R"]
P = {n: i for i, n in enumerate(PLAYER_ROLES) if n}

NPC_ROLES = ["", "HEAD", "HAIR", "ACC", "TORSO", "CAPE", "ARM_L", "ARM_R",
             "HAND", "LEG_L", "LEG_R", "BOOT", "PROP"]
Z = {n: i for i, n in enumerate(NPC_ROLES) if n}
NPC_SEAM = {Z[n] for n in ("HEAD", "TORSO", "CAPE", "ARM_L", "ARM_R",
                           "LEG_L", "LEG_R", "BOOT")}
NPC_EDGE = {Z[n] for n in ("HAIR", "ACC", "PROP", "BOOT")}

# shading cut points: how many flat tones a family has -> ramp thresholds
CUTS = {1: (), 2: (0.56,), 3: (0.30, 0.72), 4: (0.27, 0.58, 0.84)}


# =====================================================================
#  drawing primitives -- hard pixel edges only, never any anti-aliasing
# =====================================================================
def _box(x0, y0, x1, y1, w, h):
    x0 = max(0, int(x0))
    y0 = max(0, int(y0))
    x1 = min(w - 1, int(x1))
    y1 = min(h - 1, int(y1))
    if x1 < x0 or y1 < y0:
        return None
    return x0, y0, x1, y1


def m_rect(x0, y0, x1, y1, w, h, _extra=0):
    m = np.zeros((h, w), bool)
    b = _box(x0, y0, x1, y1, w, h)
    if b is not None:
        m[b[1]:b[3] + 1, b[0]:b[2] + 1] = True
    return m


def m_ellipse(x0, y0, x1, y1, w, h, _extra=0):
    m = np.zeros((h, w), bool)
    b = _box(x0, y0, x1, y1, w, h)
    if b is None:
        return m
    x0, y0, x1, y1 = b
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    rx, ry = (x1 - x0 + 1) / 2.0, (y1 - y0 + 1) / 2.0
    yy, xx = np.mgrid[0:h, 0:w]
    m |= (((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2) <= 1.0
    return m


def m_line(x0, y0, x1, y1, w, h, _extra=0):
    """1px Bresenham line -- stepped, never anti-aliased."""
    m = np.zeros((h, w), bool)
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    x, y = x0, y0
    while True:
        if 0 <= x < w and 0 <= y < h:
            m[y, x] = True
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy
    return m


def m_rrect(x0, y0, x1, y1, w, h, r=1):
    """Rect with r pixel chamfered corners (rounded heads / shoulders)."""
    m = m_rect(x0, y0, x1, y1, w, h)
    b = _box(x0, y0, x1, y1, w, h)
    if b is None:
        return m
    x0, y0, x1, y1 = b
    r = max(0, min(int(r), (x1 - x0) // 2, (y1 - y0) // 2))
    for i in range(r):
        span = r - i
        m[y0 + i, x0:x0 + span] = False
        m[y0 + i, x1 - span + 1:x1 + 1] = False
        m[y1 - i, x0:x0 + span] = False
        m[y1 - i, x1 - span + 1:x1 + 1] = False
    return m


MASKERS = {"rect": m_rect, "ellipse": m_ellipse, "line": m_line,
           "rrect": m_rrect}


class Canvas:
    """Part-id grid: every shape is stamped with a role id."""

    def __init__(self, w=FRAME_W, h=FRAME_H):
        self.w, self.h = w, h
        self.pid = np.zeros((h, w), np.int16)

    def stamp(self, rid, mask, clip=False):
        if clip:
            mask = mask & (self.pid > 0)
        self.pid[mask] = rid

    def rect(self, rid, x0, y0, x1, y1, clip=False):
        self.stamp(rid, m_rect(x0, y0, x1, y1, self.w, self.h), clip)

    def rrect(self, rid, x0, y0, x1, y1, r=1, clip=False):
        self.stamp(rid, m_rrect(x0, y0, x1, y1, self.w, self.h, r), clip)

    def ellipse(self, rid, x0, y0, x1, y1, clip=False):
        self.stamp(rid, m_ellipse(x0, y0, x1, y1, self.w, self.h), clip)

    def line(self, rid, x0, y0, x1, y1, clip=False):
        self.stamp(rid, m_line(x0, y0, x1, y1, self.w, self.h), clip)


# =====================================================================
#  shading / linework
# =====================================================================
def _grad(pid, rid):
    """Upper-left light ramp, normalised inside the part's own bounding box so
    every limb reads as its own rounded volume (no global wash)."""
    mask = pid == rid
    ys, xs = np.nonzero(mask)
    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    h, w = pid.shape
    yy, xx = np.mgrid[0:h, 0:w]
    v = (yy - y0) / float(max(1, y1 - y0))
    u = (xx - x0) / float(max(1, x1 - x0))
    return 0.60 * v + 0.40 * u


def _bottom_rows(mask):
    """1px bottom-most row of a part (contact shadow under a limb / prop)."""
    out = np.zeros_like(mask)
    for x in range(mask.shape[1]):
        col = np.nonzero(mask[:, x])[0]
        if col.size:
            out[col[-1], x] = True
    return out


def _inner(sil):
    """Pixels whose 4-neighbours are all inside the silhouette."""
    pad = np.pad(sil, 1)
    return (pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])


def _self_edge(mask):
    """1px boundary of one part mask."""
    return mask & ~_inner(mask)


def _seam(pid, allowed):
    """1px seam, painted only on the *lower* role id side of every boundary so
    two touching parts share a single line instead of a 2px gutter."""
    sil = pid > 0
    h, w = pid.shape
    pad = np.pad(pid, 1)
    apad = np.pad(np.isin(pid, list(allowed)), 1)
    seam = np.zeros((h, w), bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nb = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        na = apad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        seam |= sil & (nb > pid) & na
    return seam


def _ramp(fam):
    return np.asarray(fam, np.uint8), CUTS[len(fam)]


def _finish(rgb, sil, outline, details, dy):
    """Paint the 1px outline inside the silhouette, then exact detail pixels."""
    rgb[sil & ~_inner(sil)] = outline
    h, w = sil.shape
    for color, pts, bob in details:
        off = dy if bob else 0
        for x, y in pts:
            yy = y + off
            if 0 <= x < w and 0 <= yy < h and sil[yy, x]:
                rgb[yy, x] = color


def _ramp_fill(rgb, pid, rid, fam, sil):
    cols, cuts = _ramp(fam)
    s = _grad(pid, rid)
    h, w = pid.shape
    idx = np.zeros((h, w), np.int32)
    for c in cuts:
        idx += (s >= c).astype(np.int32)
    mask = pid == rid
    rgb[mask] = cols[idx[mask]]
    rgb[_bottom_rows(mask) & sil] = fam[-1]


def render_player(pid, back=False):
    """White-box hero: 4 grey ramp + 1px #B8B8B8 rim, no outline, no face."""
    h, w = pid.shape
    sil = pid > 0
    rgb = np.zeros((h, w, 3), np.uint8)
    for rid in range(1, len(PLAYER_ROLES)):
        if not (pid == rid).any():
            continue
        _ramp_fill(rgb, pid, rid, PLAYER_RAMP, sil)
    rgb[_seam(pid, set(range(1, len(PLAYER_ROLES))))] = SHADE2
    if back:              # flat back: a single soft spine plane on the "up" row
        band = np.zeros((h, w), bool)
        band[18:27, 15:17] = True
        rgb[band & sil] = SHADE1
    _finish(rgb, sil, RIM, [], 0)
    rgb[~sil] = 0
    alpha = np.where(sil, 255, 0).astype(np.uint8)
    return np.dstack([rgb, alpha])


def render_npc(pid, spec, tag, bobbing):
    """NPC frame: flat family ramp + 1px seams + 1px #1B1B1B outline."""
    h, w = pid.shape
    sil = pid > 0
    rgb = np.zeros((h, w, 3), np.uint8)
    fams, roles = spec["fams"], spec["roles"]
    role_fam = {Z[n]: fams[f] for n, f in roles.items()}
    for rid, fam in role_fam.items():
        if not (pid == rid).any():
            continue
        _ramp_fill(rgb, pid, rid, fam, sil)
    # 1px seams where two different body parts meet
    seam = _seam(pid, NPC_SEAM)
    for rid, fam in role_fam.items():
        m = seam & (pid == rid)
        if m.any():
            rgb[m] = fam[-1]
    # props / accessories / hair get their own 1px dark edge so they read
    for rid in NPC_EDGE:
        fam = role_fam.get(rid)
        if fam is None:
            continue
        mask = pid == rid
        if mask.any():
            rgb[_self_edge(mask) & sil] = fam[-1]
    dy = -1 if bobbing else 0
    _finish(rgb, sil, OUTLINE, spec["details"].get(tag, []), dy)
    rgb[~sil] = 0
    alpha = np.where(sil, 255, 0).astype(np.uint8)
    return np.dstack([rgb, alpha])


# =====================================================================
#  part 1 -- the white-box hero (128x192)
# =====================================================================
# Walk tables.  The planted foot always sits on the ground line (47); only the
# clearly lifted swing foot of the passing pose leaves it.
#   front: (legL_dx, legL_lift, legR_dx, legR_lift, armL_dy, armR_dy, body_dy)
FRONT_WALK = (
    (0, 0, 0, 0, 0, 0, 0),        # 0 standing (also the rest-pose stand frame)
    (-2, 0, 2, 0, 1, -1, 1),      # 1 contact: wide stance, body dips 1px
    (0, -2, 0, 0, 0, 0, 0),       # 2 passing: left foot lifted
    (2, 0, -2, 0, -1, 1, 1),      # 3 contact, mirrored stride
)
#   side: (front_dx, front_lift, back_dx, back_lift, arm_dx, arm_dy, body_dy)
SIDE_WALK = (
    (0, 0, 0, 0, 0, 0, 0),        # 0 standing
    (3, 0, -3, 0, -3, -1, 1),     # 1 stride, arm swings back
    (0, -2, 0, 0, 0, 0, 0),       # 2 passing, front foot lifted
    (-3, 0, 3, 0, 3, 1, 1),       # 3 opposite stride
)


def _hero_leg_front(c, role, x0, dx, lift, boot_in):
    """4px leg + 5px boot; boot_in = -1/+1 widens the boot outwards."""
    c.rect(role, x0 + dx, 32 + lift, x0 + 3 + dx, 43 + lift)
    if boot_in < 0:
        c.rect(role, x0 - 1 + dx, 44 + lift, x0 + 3 + dx, GROUND + lift)
    else:
        c.rect(role, x0 + dx, 44 + lift, x0 + 4 + dx, GROUND + lift)


def _hero_leg_side(c, role, x0, dx, lift, toe):
    c.rect(role, x0 + dx, 32 + lift, x0 + 4 + dx, 43 + lift)
    c.rect(role, x0 + dx, 44 + lift, x0 + 5 + dx, GROUND + lift)


def build_hero_front(frame, back=False):
    ldx0, llift0, rdx0, rlift0, aL, aR, body_dy = FRONT_WALK[frame]
    c = Canvas()
    _hero_leg_front(c, P["LEG_L"], 11, ldx0, -llift0, -1)
    _hero_leg_front(c, P["LEG_R"], 17, rdx0, -rlift0, +1)
    # upper body (dips 1px on the contact poses, the feet stay planted)
    c.rrect(P["TORSO"], 11, 13 + body_dy, 20, 31 + body_dy, r=1)
    out = 1 if back else 0
    c.rect(P["ARM_L"], 7 - out, 15 + body_dy + aL, 10 - out,
           27 + body_dy + aL)
    c.rect(P["ARM_L"], 7 - out, 27 + body_dy + aL, 10 - out,
           29 + body_dy + aL)
    c.rect(P["ARM_R"], 21 + out, 15 + body_dy + aR, 24 + out,
           27 + body_dy + aR)
    c.rect(P["ARM_R"], 21 + out, 27 + body_dy + aR, 24 + out,
           29 + body_dy + aR)
    c.ellipse(P["HEAD"], 8, 0 + body_dy, 22, 13 + body_dy)
    return c.pid


def build_hero_side(frame):
    fdx, flift, bdx, blift, adx, ady, body_dy = SIDE_WALK[frame]
    c = Canvas()
    _hero_leg_side(c, P["LEG_L"], 11, bdx, -blift, 0)          # back leg
    _hero_leg_side(c, P["LEG_R"], 14, fdx, -flift, 0)          # front leg
    c.rrect(P["TORSO"], 11, 13 + body_dy, 20, 31 + body_dy, r=1)
    c.rect(P["ARM_R"], 16 + adx, 15 + body_dy + ady, 19 + adx,
           27 + body_dy + ady)
    c.rect(P["ARM_R"], 16 + adx, 27 + body_dy + ady, 19 + adx,
           29 + body_dy + ady)
    c.ellipse(P["HEAD"], 9, 0 + body_dy, 22, 13 + body_dy)
    return c.pid


def build_player_sheet():
    sheet = np.zeros((4 * FRAME_H, 4 * FRAME_W, 4), np.uint8)
    for r, view in enumerate(VIEWS):
        for col in range(4):
            if view == "down":
                arr = render_player(build_hero_front(col))
            elif view == "up":
                arr = render_player(build_hero_front(col, back=True), back=True)
            elif view == "right":
                arr = render_player(build_hero_side(col))
            else:                                   # left = exact mirror
                arr = np.ascontiguousarray(
                    np.fliplr(render_player(build_hero_side(col))))
            sheet[r * FRAME_H:(r + 1) * FRAME_H,
                  col * FRAME_W:(col + 1) * FRAME_W] = arr
    return Image.fromarray(sheet)


# =====================================================================
#  part 2 -- NPC sprite sheets (64x192)
# =====================================================================
def rc(role, x0, y0, x1, y1, bob=True, clip=False):
    return ("rect", role, (x0, y0, x1, y1), 0, bob, clip)


def el(role, x0, y0, x1, y1, bob=True, clip=False):
    return ("ellipse", role, (x0, y0, x1, y1), 0, bob, clip)


def ln(role, x0, y0, x1, y1, bob=True, clip=False):
    return ("line", role, (x0, y0, x1, y1), 0, bob, clip)


def rr(role, x0, y0, x1, y1, r=1, bob=True, clip=False):
    return ("rrect", role, (x0, y0, x1, y1), r, bob, clip)


def assemble(ops, bobbing):
    c = Canvas()
    for kind, role, (x0, y0, x1, y1), extra, bob, clip in ops:
        dy = -1 if (bobbing and bob) else 0
        mask = MASKERS[kind](x0, y0 + dy, x1, y1 + dy, FRAME_W, FRAME_H, extra)
        c.stamp(Z[role], mask, clip)
    return c.pid


def build_npc_sheet(spec):
    sheet = np.zeros((4 * FRAME_H, 2 * FRAME_W, 4), np.uint8)
    for r, view in enumerate(VIEWS):
        for col in range(2):
            if view == "down":
                ops, tag = spec["front"], "down"
            elif view == "up":
                ops, tag = spec["back"], "up"
            else:
                ops, tag = spec["side"], "right"
            pid = assemble(ops, bobbing=(col == 1))
            arr = render_npc(pid, spec, tag, bobbing=(col == 1))
            if view == "left":
                arr = np.ascontiguousarray(np.fliplr(arr))
            sheet[r * FRAME_H:(r + 1) * FRAME_H,
                  col * FRAME_W:(col + 1) * FRAME_W] = arr
    return Image.fromarray(sheet)


# --------------------------------------------------------------- 阿燃 courier
def spec_red():
    """Short, stocky courier: bright red-orange short cape + headband,
    cropped dark hair, cross-body mail strap, leather satchel on the hip."""
    fams = {"skin": SKIN, "cloth": RED, "accent": BRIGHT_RED,
            "leather": LEATHER}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "cloth",
             "ARM_L": "cloth", "ARM_R": "cloth", "LEG_L": "cloth",
             "LEG_R": "cloth", "CAPE": "accent", "ACC": "accent",
             "HAIR": "leather", "BOOT": "leather", "PROP": "leather"}
    front = [
        rc("BOOT", 9, 44, 14, GROUND, bob=False),
        rc("BOOT", 17, 44, 22, GROUND, bob=False),
        rc("LEG_L", 10, 35, 14, 43, bob=False),
        rc("LEG_R", 17, 35, 21, 43, bob=False),
        rr("TORSO", 9, 19, 22, 21, r=1),
        rc("TORSO", 8, 21, 23, 34),
        rc("PROP", 8, 32, 23, 33),                    # belt
        rc("CAPE", 9, 18, 22, 20),
        rc("CAPE", 6, 20, 25, 23),
        rc("CAPE", 5, 23, 26, 26),
        rc("CAPE", 6, 26, 9, 27),                     # ragged short hem
        rc("CAPE", 12, 26, 19, 27),
        rc("CAPE", 22, 26, 25, 27),
        rc("PROP", 19, 28, 25, 36),                   # satchel
        rc("PROP", 19, 28, 25, 30),                   # satchel flap
        ln("PROP", 10, 20, 21, 31),                   # cross-body strap
        ln("PROP", 11, 20, 22, 31),
        rc("ARM_L", 5, 20, 7, 31),
        rc("ARM_R", 24, 20, 26, 31),
        rc("HAND", 5, 31, 7, 33),
        rc("HAND", 24, 31, 26, 33),
        rr("HEAD", 9, 6, 22, 18, r=2),
        rr("HAIR", 9, 6, 22, 10, r=2, clip=True),
        rc("HAIR", 9, 9, 10, 15, clip=True),
        rc("HAIR", 21, 9, 22, 15, clip=True),
        rc("ACC", 9, 10, 22, 12, clip=True),          # headband
        rc("ACC", 7, 10, 9, 13),                      # knot
        rc("ACC", 7, 13, 8, 16),                      # headband tail
    ]
    side = [
        rc("BOOT", 10, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 21, GROUND, bob=False),
        rc("LEG_L", 11, 35, 16, 43, bob=False),
        rc("LEG_R", 15, 35, 20, 43, bob=False),
        rc("TORSO", 10, 19, 21, 34),
        rc("PROP", 10, 32, 21, 33),
        rc("CAPE", 10, 18, 20, 20),
        rc("CAPE", 8, 19, 11, 29),                    # cape trails behind
        rc("CAPE", 9, 29, 12, 31),
        rc("PROP", 18, 28, 24, 36),
        rc("PROP", 18, 28, 24, 30),
        ln("PROP", 11, 20, 21, 31),
        rc("ARM_R", 17, 20, 19, 31),
        rc("HAND", 17, 31, 19, 33),
        rr("HEAD", 10, 6, 21, 18, r=2),
        rr("HAIR", 10, 6, 21, 10, r=2, clip=True),
        rc("HAIR", 10, 9, 11, 15, clip=True),
        rc("ACC", 10, 10, 21, 12, clip=True),
        rc("ACC", 9, 12, 10, 15),
    ]
    back = [
        rc("BOOT", 9, 44, 14, GROUND, bob=False),
        rc("BOOT", 17, 44, 22, GROUND, bob=False),
        rc("LEG_L", 10, 35, 14, 43, bob=False),
        rc("LEG_R", 17, 35, 21, 43, bob=False),
        rr("TORSO", 9, 19, 22, 21, r=1),
        rc("TORSO", 8, 21, 23, 34),
        rc("PROP", 8, 32, 23, 33),
        rc("CAPE", 9, 18, 22, 20),
        rc("CAPE", 6, 20, 25, 23),
        rc("CAPE", 6, 23, 25, 26),
        rc("CAPE", 6, 26, 9, 27),
        rc("CAPE", 12, 26, 19, 27),
        rc("CAPE", 22, 26, 25, 27),
        ln("PROP", 9, 20, 21, 32),
        ln("PROP", 10, 20, 22, 32),
        rc("PROP", 21, 28, 27, 36),
        rc("PROP", 21, 28, 27, 30),
        rc("ARM_L", 4, 20, 6, 31),
        rc("ARM_R", 25, 20, 27, 31),
        rc("HAND", 4, 31, 6, 33),
        rc("HAND", 25, 31, 27, 33),
        rr("HEAD", 9, 6, 22, 18, r=2),
        rr("HAIR", 9, 6, 22, 13, r=2, clip=True),
        rr("HAIR", 9, 6, 22, 18, r=2, clip=True),
        rc("ACC", 9, 10, 22, 12, clip=True),
    ]
    details = {
        "down": [(OUTLINE, [(13, 14), (18, 14)], True),
                 (SKIN[1], [(15, 17), (16, 17)], True)],
        "right": [(OUTLINE, [(14, 14)], True),
                  (SKIN[1], [(15, 17)], True)],
        "up": [],
    }
    return dict(name="npc_red", title="A-Ran (courier)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


# ------------------------------------------------------------- 阿衡 watchmaker
def spec_yellow():
    """Tall, lean watchmaker: long ochre coat with a flared hem, cream scarf,
    round spectacles, a small leather book held in the left hand."""
    fams = {"skin": SKIN, "ochre": OCHRE, "cream": CREAM,
            "leather": LEATHER_PLAIN}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "ochre",
             "ARM_L": "ochre", "ARM_R": "ochre", "LEG_L": "ochre",
             "LEG_R": "ochre", "CAPE": "ochre", "ACC": "cream",
             "HAIR": "leather", "BOOT": "leather", "PROP": "leather"}
    front = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 14, 43, bob=False),
        rc("LEG_R", 17, 40, 19, 43, bob=False),
        rc("TORSO", 11, 18, 20, 19),
        rc("TORSO", 11, 19, 20, 35),
        rc("TORSO", 9, 35, 22, 39),                   # flared coat hem
        rc("TORSO", 10, 39, 21, 40),
        rc("ACC", 11, 16, 20, 18, clip=True),         # scarf wrap
        rc("ACC", 10, 18, 12, 26),                    # scarf tail
        rc("ACC", 9, 26, 11, 28),
        rc("ARM_L", 8, 19, 10, 33),
        rc("ARM_R", 21, 19, 23, 33),
        rc("PROP", 4, 31, 8, 36),                     # book
        rc("ACC", 7, 32, 8, 35),                      # page edge
        rc("HAND", 8, 33, 10, 35),
        rc("HAND", 21, 33, 23, 35),
        rc("HEAD", 14, 14, 17, 17),                   # neck
        rr("HEAD", 10, 2, 21, 15, r=2),
        rr("HAIR", 10, 2, 21, 7, r=2, clip=True),
        rc("HAIR", 10, 6, 11, 10, clip=True),
        rc("HAIR", 20, 6, 21, 10, clip=True),
    ]
    side = [
        rc("BOOT", 11, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 16, 43, bob=False),
        rc("LEG_R", 15, 40, 19, 43, bob=False),
        rc("TORSO", 10, 18, 21, 19),
        rc("TORSO", 10, 19, 21, 35),
        rc("TORSO", 8, 35, 22, 39),
        rc("TORSO", 9, 39, 21, 40),
        rc("ACC", 10, 16, 21, 18, clip=True),
        rc("ACC", 8, 18, 10, 27),                     # scarf trails behind
        rc("ARM_R", 17, 19, 19, 33),
        rc("HAND", 17, 33, 19, 35),
        rc("PROP", 20, 31, 26, 36),
        rc("ACC", 25, 32, 26, 35),
        rc("HEAD", 14, 14, 17, 17),
        rr("HEAD", 10, 2, 21, 15, r=2),
        rr("HAIR", 10, 2, 21, 7, r=2, clip=True),
        rc("HAIR", 10, 6, 11, 11, clip=True),
    ]
    back = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 14, 43, bob=False),
        rc("LEG_R", 17, 40, 19, 43, bob=False),
        rc("TORSO", 11, 18, 20, 19),
        rc("TORSO", 11, 19, 20, 35),
        rc("TORSO", 9, 35, 22, 39),
        rc("TORSO", 10, 39, 21, 40),
        rc("ACC", 11, 16, 20, 18, clip=True),
        rc("ACC", 14, 18, 17, 29),                    # scarf down the back
        rc("ACC", 15, 29, 18, 31),
        rc("ARM_L", 8, 19, 10, 33),
        rc("ARM_R", 21, 19, 23, 33),
        rc("HAND", 8, 33, 10, 35),
        rc("HAND", 21, 33, 23, 35),
        rc("HEAD", 14, 14, 17, 17),
        rr("HEAD", 10, 2, 21, 15, r=2),
        rr("HAIR", 10, 2, 21, 15, r=2, clip=True),
    ]
    glasses = [(11, 9), (12, 9), (13, 9), (11, 10), (13, 10), (11, 11),
               (12, 11), (13, 11),
               (18, 9), (19, 9), (20, 9), (18, 10), (20, 10), (18, 11),
               (19, 11), (20, 11),
               (14, 10), (15, 10), (16, 10), (17, 10), (10, 10), (21, 10)]
    glasses_side = [(17, 9), (18, 9), (19, 9), (17, 10), (19, 10), (17, 11),
                    (18, 11), (19, 11), (11, 10), (12, 10), (13, 10),
                    (14, 10), (15, 10), (16, 10)]
    lapel = [(15, y) for y in range(20, 35)]
    details = {
        "down": [(LEATHER_PLAIN[0], glasses, True),
                 (OUTLINE, [(12, 10), (19, 10)], True),
                 (SKIN[1], [(15, 13), (16, 13)], True),
                 (OCHRE[2], lapel, True)],
        "right": [(LEATHER_PLAIN[0], glasses_side, True),
                  (OUTLINE, [(18, 10)], True),
                  (SKIN[1], [(15, 13)], True)],
        "up": [],
    }
    return dict(name="npc_yellow", title="A-Heng (watchmaker)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


# --------------------------------------------------------------- 阿禾 gardener
def spec_green():
    """Round, gentle gardener: broad straw hat, olive tunic + linen apron,
    a flowering branch carried in the right hand."""
    fams = {"skin": SKIN, "olive": OLIVE, "straw": STRAW, "bloom": BLOOM}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "olive",
             "ARM_L": "olive", "ARM_R": "olive", "LEG_L": "olive",
             "LEG_R": "olive", "CAPE": "olive", "ACC": "straw",
             "HAIR": "olive", "BOOT": "straw", "PROP": "bloom"}
    front = [
        rc("BOOT", 10, 44, 14, GROUND, bob=False),
        rc("BOOT", 17, 44, 21, GROUND, bob=False),
        rc("LEG_L", 11, 39, 14, 43, bob=False),
        rc("LEG_R", 17, 39, 20, 43, bob=False),
        rr("TORSO", 9, 20, 22, 24, r=1),              # rounded shoulders
        el("TORSO", 8, 22, 23, 39),                   # round belly
        rc("ACC", 13, 24, 18, 36, clip=True),         # linen apron
        rc("ACC", 12, 21, 13, 25, clip=True),         # apron straps
        rc("ACC", 18, 21, 19, 25, clip=True),
        rc("LEG_R", 25, 22, 26, 34),                  # branch stem (held)
        rc("LEG_R", 27, 25, 28, 26),                  # leaf
        rc("LEG_R", 24, 29, 25, 30),                  # leaf
        el("PROP", 24, 17, 28, 21),                   # blossom
        rc("ARM_L", 5, 22, 7, 33),
        rc("ARM_R", 24, 22, 26, 33),
        rc("HAND", 5, 33, 7, 35),
        rc("HAND", 24, 33, 26, 35),
        rr("HEAD", 9, 7, 22, 19, r=3),
        el("ACC", 5, 9, 26, 13),                      # broad straw brim
        el("ACC", 11, 3, 20, 10),                     # straw crown
    ]
    side = [
        rc("BOOT", 10, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 21, GROUND, bob=False),
        rc("LEG_L", 11, 39, 16, 43, bob=False),
        rc("LEG_R", 15, 39, 20, 43, bob=False),
        rc("TORSO", 10, 20, 21, 24),
        el("TORSO", 9, 22, 22, 39),
        rc("ACC", 14, 24, 19, 36, clip=True),
        rc("ARM_R", 17, 22, 19, 33),
        rc("HAND", 17, 33, 19, 35),
        rc("LEG_R", 20, 22, 21, 33),
        el("PROP", 19, 18, 23, 22),
        rr("HEAD", 10, 7, 21, 19, r=3),
        el("ACC", 5, 9, 26, 13),
        el("ACC", 12, 3, 21, 10),
    ]
    back = [
        rc("BOOT", 10, 44, 14, GROUND, bob=False),
        rc("BOOT", 17, 44, 21, GROUND, bob=False),
        rc("LEG_L", 11, 39, 14, 43, bob=False),
        rc("LEG_R", 17, 39, 20, 43, bob=False),
        rr("TORSO", 9, 20, 22, 24, r=1),
        el("TORSO", 8, 22, 23, 39),
        rc("ACC", 13, 21, 18, 24, clip=True),         # apron knot at the back
        rc("ACC", 12, 23, 13, 28),
        rc("ACC", 18, 23, 19, 28),
        rc("LEG_R", 25, 22, 26, 28),
        el("PROP", 24, 18, 28, 22),
        rc("ARM_L", 5, 22, 7, 33),
        rc("ARM_R", 24, 22, 26, 33),
        rc("HAND", 5, 33, 7, 35),
        rc("HAND", 24, 33, 26, 35),
        rr("HEAD", 9, 7, 22, 19, r=3),
        el("ACC", 5, 9, 26, 13),
        el("ACC", 11, 3, 20, 10),
    ]
    details = {
        "down": [(OUTLINE, [(13, 15), (19, 15)], True),
                 (SKIN[1], [(15, 18), (16, 18)], True)],
        "right": [(OUTLINE, [(14, 15)], True),
                  (SKIN[1], [(15, 18)], True)],
        "up": [],
    }
    return dict(name="npc_green", title="A-He (gardener)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


# ------------------------------------------------------------- 阿砚 road-keeper
def spec_blue():
    """Upright road-keeper: deep navy cloak with a flared hem, flat-brim hat,
    brass-trimmed collar and a brass lantern hanging from the left hand."""
    fams = {"skin": SKIN, "navy": NAVY, "brass": BRASS, "hair": HAIR_DARK}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "navy",
             "ARM_L": "navy", "ARM_R": "navy", "LEG_L": "navy",
             "LEG_R": "navy", "CAPE": "navy", "ACC": "brass",
             "HAIR": "hair", "BOOT": "navy", "PROP": "brass"}
    front = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 14, 43, bob=False),
        rc("LEG_R", 17, 40, 19, 43, bob=False),
        rr("CAPE", 9, 21, 22, 24, r=1),
        rc("CAPE", 8, 24, 23, 34),
        rr("CAPE", 7, 34, 24, 38, r=1),
        rc("CAPE", 8, 38, 23, 39),
        rc("TORSO", 13, 22, 18, 37, clip=True),       # uniform front panel
        rc("ACC", 12, 21, 19, 22, clip=True),         # brass collar
        rc("ACC", 14, 24, 15, 25, clip=True),         # brass clasp
        rc("ARM_L", 6, 22, 8, 33),
        rc("ARM_R", 23, 22, 25, 33),
        rc("PROP", 6, 35, 7, 37),                     # lantern handle
        rc("PROP", 5, 37, 8, 38),                     # lantern cap
        rc("PROP", 5, 38, 8, 43),                     # lantern body
        rc("HAND", 6, 33, 8, 35),
        rc("HAND", 23, 33, 25, 35),
        rc("HEAD", 14, 19, 17, 21),                   # neck
        rr("HEAD", 10, 8, 21, 20, r=2),
        rc("HAIR", 10, 11, 21, 12, clip=True),        # fringe under the brim
        rc("HAIR", 10, 11, 11, 15, clip=True),
        rc("HAIR", 20, 11, 21, 15, clip=True),
        el("CAPE", 8, 6, 23, 10),                     # flat hat brim
        rr("CAPE", 11, 2, 20, 8, r=1),                # hat crown
    ]
    side = [
        rc("BOOT", 11, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 16, 43, bob=False),
        rc("LEG_R", 15, 40, 19, 43, bob=False),
        rc("CAPE", 9, 21, 21, 24),
        rc("CAPE", 9, 24, 21, 34),
        rr("CAPE", 8, 34, 22, 38, r=1),
        rc("CAPE", 9, 38, 21, 39),
        rc("ARM_R", 16, 22, 18, 33),
        rc("PROP", 17, 35, 18, 37),
        rc("PROP", 16, 37, 19, 38),
        rc("PROP", 16, 38, 19, 43),
        rc("HAND", 16, 33, 18, 35),
        rc("HEAD", 14, 19, 17, 21),
        rr("HEAD", 10, 8, 21, 20, r=2),
        rc("HAIR", 10, 11, 21, 12, clip=True),
        rc("HAIR", 10, 11, 11, 15, clip=True),
        el("CAPE", 7, 6, 24, 10),
        rr("CAPE", 12, 2, 21, 8, r=1),
    ]
    back = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 14, 43, bob=False),
        rc("LEG_R", 17, 40, 19, 43, bob=False),
        rr("CAPE", 9, 21, 22, 24, r=1),
        rc("CAPE", 8, 24, 23, 34),
        rr("CAPE", 7, 34, 24, 38, r=1),
        rc("CAPE", 8, 38, 23, 39),
        rc("ARM_L", 6, 22, 8, 33),
        rc("ARM_R", 23, 22, 25, 33),
        rc("HAND", 6, 33, 8, 35),
        rc("HAND", 23, 33, 25, 35),
        rc("HEAD", 14, 19, 17, 21),
        rr("HEAD", 10, 8, 21, 20, r=2),
        rr("HAIR", 10, 11, 21, 20, r=2, clip=True),
        el("CAPE", 8, 6, 23, 10),
        rr("CAPE", 11, 2, 20, 8, r=1),
    ]
    glass = (OUTLINE, [(5, 40), (6, 40), (7, 40), (8, 40)])
    glass_s = (OUTLINE, [(16, 40), (17, 40), (18, 40), (19, 40)])
    details = {
        "down": [(OUTLINE, [(13, 16), (18, 16)], True),
                 (SKIN[1], [(15, 19), (16, 19)], True),
                 (glass[0], glass[1], True),
                 (BRASS[0], [(6, 38), (7, 38)], True)],
        "right": [(OUTLINE, [(14, 16)], True),
                  (SKIN[1], [(15, 19)], True),
                  (glass_s[0], glass_s[1], True),
                  (BRASS[0], [(17, 38), (18, 38)], True)],
        "up": [],
    }
    return dict(name="npc_blue", title="A-Yan (road-keeper)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


# ------------------------------------------------------------------ 阿遥 painter
def spec_purple():
    """Romantic painter: wide lilac hat, lilac scarf, purple coat with a
    fluttering hem, sketchbook strapped on the back, ink brush in hand."""
    fams = {"skin": SKIN, "purple": PURPLE, "lilac": LILAC, "paper": PAPER}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "purple",
             "ARM_L": "purple", "ARM_R": "purple", "LEG_L": "purple",
             "LEG_R": "purple", "CAPE": "purple", "ACC": "lilac",
             "HAIR": "purple", "BOOT": "purple", "PROP": "paper"}
    front = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 41, 14, 43, bob=False),
        rc("LEG_R", 17, 41, 19, 43, bob=False),
        rc("TORSO", 10, 19, 21, 21),
        rc("TORSO", 10, 21, 21, 33),
        rc("TORSO", 8, 33, 23, 37),                   # flared coat
        rc("TORSO", 7, 37, 10, 40),                   # fluttering hem
        rc("TORSO", 11, 37, 15, 41),
        rc("TORSO", 16, 37, 20, 40),
        rc("TORSO", 21, 37, 24, 39),
        rc("ACC", 11, 17, 20, 19, clip=True),         # scarf
        rc("ACC", 9, 19, 11, 26),                     # scarf tail
        rc("ACC", 8, 26, 10, 29),
        rc("ARM_L", 7, 21, 9, 33),
        rc("ARM_R", 22, 21, 24, 33),
        rc("PROP", 24, 27, 25, 34),                   # brush handle
        rc("HAND", 7, 33, 9, 35),
        rc("HAND", 22, 33, 24, 35),
        rc("HEAD", 14, 17, 17, 20),                   # neck
        rr("HEAD", 10, 6, 21, 18, r=2),
        rr("HAIR", 10, 6, 21, 9, r=2, clip=True),
        rc("HAIR", 10, 9, 11, 17, clip=True),
        rc("HAIR", 20, 9, 21, 17, clip=True),
        el("ACC", 4, 5, 27, 9),                       # wide lilac brim
        rr("ACC", 11, 1, 20, 6, r=1),                 # hat crown
    ]
    side = [
        rc("BOOT", 11, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 41, 16, 43, bob=False),
        rc("LEG_R", 15, 41, 19, 43, bob=False),
        rc("TORSO", 10, 19, 21, 21),
        rc("TORSO", 10, 21, 21, 33),
        rc("TORSO", 8, 33, 22, 37),
        rc("TORSO", 6, 36, 10, 42),                   # hem flutters behind
        rc("TORSO", 11, 37, 20, 41),
        rc("ACC", 10, 17, 21, 19, clip=True),
        rc("ACC", 6, 19, 8, 28),
        rc("ACC", 5, 28, 7, 31),
        rc("ARM_R", 16, 21, 18, 33),
        rc("PROP", 18, 27, 19, 34),
        rc("HAND", 16, 33, 18, 35),
        rc("HEAD", 14, 17, 17, 20),
        rr("HEAD", 10, 6, 21, 18, r=2),
        rr("HAIR", 10, 6, 21, 9, r=2, clip=True),
        rc("HAIR", 10, 9, 11, 17, clip=True),
        el("ACC", 3, 5, 28, 9),
        rr("ACC", 11, 1, 20, 6, r=1),
    ]
    back = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 41, 14, 43, bob=False),
        rc("LEG_R", 17, 41, 19, 43, bob=False),
        rc("TORSO", 10, 19, 21, 21),
        rc("TORSO", 10, 21, 21, 33),
        rc("TORSO", 8, 33, 23, 37),
        rc("TORSO", 7, 37, 10, 40),
        rc("TORSO", 11, 37, 15, 41),
        rc("TORSO", 16, 37, 20, 40),
        rc("TORSO", 21, 37, 24, 39),
        rc("ACC", 11, 17, 20, 19, clip=True),
        rc("ACC", 14, 19, 16, 27),
        rc("PROP", 11, 20, 20, 33),                   # sketchbook on the back
        ln("ACC", 12, 20, 12, 32),                    # shoulder straps
        ln("ACC", 19, 20, 19, 32),
        rc("ARM_L", 7, 21, 9, 33),
        rc("ARM_R", 22, 21, 24, 33),
        rc("HAND", 7, 33, 9, 35),
        rc("HAND", 22, 33, 24, 35),
        rr("HEAD", 10, 6, 21, 18, r=2),
        rr("HAIR", 10, 6, 21, 18, r=2, clip=True),
        el("ACC", 4, 5, 27, 9),
        rr("ACC", 11, 1, 20, 6, r=1),
    ]
    details = {
        "down": [(OUTLINE, [(13, 13), (18, 13)], True),
                 (SKIN[1], [(15, 16), (16, 16)], True),
                 (OUTLINE, [(24, 25), (25, 25), (24, 26), (25, 26)], True)],
        "right": [(OUTLINE, [(14, 13)], True),
                  (SKIN[1], [(15, 16)], True),
                  (OUTLINE, [(18, 25), (19, 25), (18, 26), (19, 26)], True)],
        "up": [(OUTLINE, [(15, 21), (15, 22), (15, 23), (15, 24), (15, 25),
                          (15, 26), (15, 27), (15, 28), (15, 29), (15, 30),
                          (15, 31), (15, 32)], True),
               (OUTLINE, [(11, 23), (20, 23), (11, 30), (20, 30)], True)],
    }
    return dict(name="npc_purple", title="A-Yao (painter)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


NPC_SPECS = (spec_red, spec_yellow, spec_green, spec_blue, spec_purple)


# =====================================================================
#  part 3 -- 32x32 dialogue portraits
# =====================================================================
def _bust(c):
    """Shared bust underlay: shoulders, neck, head."""
    c.rect(Z["TORSO"], 5, 27, 26, 31)
    c.rrect(Z["TORSO"], 7, 24, 24, 31, r=1)
    c.rect(Z["HEAD"], 14, 21, 17, 26)
    c.rrect(Z["HEAD"], 9, 4, 22, 21, r=3)


def _player_heart_pixels():
    """(ox, oy, mask, boundary) for the small heart charm on the chest."""
    ox, oy, hw, hh = 12, 24, 9, 8
    mask = np.zeros((hh, hw), bool)
    for y in range(hh):
        for x in range(hw):
            nx = (x + 0.5 - hw / 2.0) / (hw / 2.0) * 1.15
            ny = ((hh / 2.0) - (y + 0.5)) / (hh / 2.0) * 1.15
            mask[y, x] = (nx * nx + ny * ny - 1.0) ** 3 - nx * nx * ny * ny * ny <= 0.0
    boundary = np.zeros_like(mask)
    for y in range(hh):
        for x in range(hw):
            if not mask[y, x]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    xx, yy = x + dx, y + dy
                    if xx < 0 or yy < 0 or xx >= hw or yy >= hh or not mask[yy, xx]:
                        boundary[y, x] = True
    return ox, oy, mask, boundary


def build_portrait_player():
    """White-box bust with a silver necklace and heart-charm outline."""
    c = Canvas(32, 32)
    _bust(c)
    pid = c.pid
    h, w = pid.shape
    sil = pid > 0
    rgb = np.zeros((h, w, 3), np.uint8)
    for rid in range(1, len(PLAYER_ROLES)):
        if not (pid == rid).any():
            continue
        _ramp_fill(rgb, pid, rid, PLAYER_RAMP, sil)
    rgb[_seam(pid, set(range(1, len(PLAYER_ROLES))))] = SHADE2
    _finish(rgb, sil, RIM, [], 0)
    rgb[~sil] = 0

    # Necklace + heart outline; the coloured fill lives in a separate overlay
    # texture so the white bust itself never needs to be tinted.
    outline = np.array([150, 150, 150], np.uint8)
    for x, y in ((16, 22), (16, 23), (15, 24), (16, 24), (17, 24)):
        rgb[y, x] = outline
    ox, oy, _mask, boundary = _player_heart_pixels()
    for y in range(boundary.shape[0]):
        for x in range(boundary.shape[1]):
            if boundary[y, x]:
                rgb[oy + y, ox + x] = outline

    alpha = np.where(sil, 255, 0).astype(np.uint8)
    return np.dstack([rgb, alpha])


def build_portrait_player_charm():
    """Tinted heart-fill overlay for the hero's portrait (white pixels)."""
    ox, oy, mask, boundary = _player_heart_pixels()
    arr = np.zeros((32, 32, 4), np.uint8)
    for y in range(mask.shape[0]):
        for x in range(mask.shape[1]):
            if mask[y, x] and not boundary[y, x]:
                arr[oy + y, ox + x] = (255, 255, 255, 255)
    return Image.fromarray(arr)


def make_portrait(spec):
    """Per-NPC bust built from the NPC's own palette + signature details."""
    k = spec["name"]
    c = Canvas(32, 32)
    _bust(c)
    details = []
    if k == "npc_red":
        c.rrect(Z["HAIR"], 9, 4, 22, 10, r=2, clip=True)
        c.rect(Z["HAIR"], 9, 9, 10, 16, clip=True)
        c.rect(Z["HAIR"], 21, 9, 22, 16, clip=True)
        c.rect(Z["ACC"], 9, 9, 22, 12, clip=True)     # headband
        c.rect(Z["ACC"], 6, 10, 9, 14)                # knot
        c.rect(Z["ACC"], 6, 14, 7, 18)                # tail
        c.rect(Z["CAPE"], 5, 25, 26, 27)              # short cape
        c.rect(Z["CAPE"], 6, 27, 10, 31)
        c.rect(Z["CAPE"], 21, 27, 25, 31)
        c.line(Z["PROP"], 10, 27, 18, 31)             # mail strap
        c.rect(Z["PROP"], 21, 28, 27, 31)             # satchel corner
        details = [(OUTLINE, [(12, 14), (13, 14), (19, 14), (20, 14),
                              (12, 15), (19, 15)], False),
                   (SKIN[1], [(15, 18), (16, 18)], False)]
    elif k == "npc_yellow":
        c.rrect(Z["HAIR"], 9, 4, 22, 10, r=2, clip=True)
        c.rect(Z["HAIR"], 9, 9, 10, 15, clip=True)
        c.rect(Z["HAIR"], 21, 9, 22, 15, clip=True)
        c.rect(Z["ACC"], 10, 20, 21, 23, clip=True)   # scarf
        c.rect(Z["ACC"], 19, 23, 22, 30)              # scarf tail
        c.rect(Z["PROP"], 2, 27, 9, 31)               # book corner
        c.rect(Z["ACC"], 7, 28, 8, 30)
        rings = [(11, 11), (12, 11), (13, 11), (11, 12), (13, 12),
                 (11, 13), (12, 13), (13, 13),
                 (18, 11), (19, 11), (20, 11), (18, 12), (20, 12),
                 (18, 13), (19, 13), (20, 13),
                 (14, 12), (15, 12), (16, 12), (17, 12), (10, 12), (21, 12)]
        details = [(LEATHER_PLAIN[0], rings, False),
                   (OUTLINE, [(12, 12), (19, 12)], False),
                   (SKIN[1], [(15, 17), (16, 17)], False)]
    elif k == "npc_green":
        c.rect(Z["ACC"], 12, 21, 13, 26, clip=True)   # apron straps
        c.rect(Z["ACC"], 18, 21, 19, 26, clip=True)
        c.rect(Z["ACC"], 13, 25, 18, 31, clip=True)   # apron
        c.rect(Z["LEG_R"], 26, 22, 27, 30)            # branch stem
        c.rect(Z["PROP"], 24, 20, 28, 23)             # blossom
        c.el_hat = None
        c.ellipse(Z["ACC"], 2, 9, 29, 14)             # broad straw brim
        c.ellipse(Z["ACC"], 10, 3, 21, 12)            # crown
        details = [(OUTLINE, [(12, 16), (13, 16), (19, 16), (20, 16),
                              (12, 17), (19, 17)], False),
                   (SKIN[1], [(15, 19), (16, 19)], False)]
    elif k == "npc_blue":
        c.rect(Z["HAIR"], 10, 12, 21, 13, clip=True)
        c.rect(Z["HAIR"], 10, 12, 11, 17, clip=True)
        c.rect(Z["HAIR"], 20, 12, 21, 17, clip=True)
        c.rect(Z["ACC"], 12, 23, 19, 24)              # brass collar
        c.rect(Z["PROP"], 2, 23, 7, 25)               # lantern top
        c.rect(Z["PROP"], 2, 25, 7, 31)               # lantern body
        c.rect(Z["ACC"], 14, 25, 15, 26, clip=True)   # clasp
        c.ellipse(Z["CAPE"], 8, 8, 23, 12)            # flat brim
        c.rrect(Z["CAPE"], 11, 3, 20, 9, r=1)         # crown
        details = [(OUTLINE, [(12, 16), (13, 16), (19, 16), (20, 16),
                              (12, 17), (19, 17)], False),
                   (SKIN[1], [(15, 19), (16, 19)], False),
                   (OUTLINE, [(3, 28), (4, 28), (5, 28), (6, 28)], False),
                   (BRASS[0], [(3, 25), (4, 25)], False)]
    else:  # npc_purple
        c.rect(Z["HAIR"], 9, 9, 10, 21, clip=True)
        c.rect(Z["HAIR"], 21, 9, 22, 21, clip=True)
        c.rrect(Z["HAIR"], 9, 4, 22, 9, r=2, clip=True)
        c.rect(Z["ACC"], 10, 21, 21, 24, clip=True)   # scarf
        c.rect(Z["ACC"], 8, 24, 11, 30)               # scarf tail
        c.rect(Z["PROP"], 21, 24, 28, 31)             # sketchbook corner
        c.line(Z["ACC"], 20, 25, 20, 30)
        c.ellipse(Z["ACC"], 3, 6, 28, 11)             # wide lilac brim
        c.rrect(Z["ACC"], 10, 1, 21, 7, r=1)          # crown
        details = [(OUTLINE, [(12, 15), (13, 15), (19, 15), (20, 15),
                              (12, 16), (19, 16)], False),
                   (SKIN[1], [(15, 19), (16, 19)], False),
                   (OUTLINE, [(21, 26), (21, 27), (21, 28), (21, 29)],
                    False)]
    pid = c.pid
    return render_npc(pid, spec, "portrait", False)


# =====================================================================
#  part 4 -- contact sheet preview (4x nearest, labelled)
# =====================================================================
def _checker(w, h, cell=16):
    a = np.array([0x22, 0x22, 0x22, 255], np.uint8)
    b = np.array([0x2C, 0x2C, 0x2C, 255], np.uint8)
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((yy // cell) + (xx // cell)) % 2 == 0
    arr = np.zeros((h, w, 4), np.uint8)
    arr[m] = a
    arr[~m] = b
    return Image.fromarray(arr)


def _font(size=18):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:                                   # very old Pillow
        return ImageFont.load_default()


def build_preview(player, npcs, portraits):
    k = 4
    margin, gap, lgap, line_h = 24, 22, 6, 22
    font = _font(18)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))

    def tw(text):
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[2] - b[0])

    specs = [m() for m in NPC_SPECS]
    names = [s["name"] for s in specs]
    titles = {s["name"]: s["title"] for s in specs}
    pnames = ["portrait_player"] + ["portrait_" + n.split("_")[1]
                                    for n in names]
    plabels = ["player"] + [t.split(" ")[0] for s, t in
                            ((s, s["title"]) for s in specs)]

    ps = player.resize((player.width * k, player.height * k),
                       Image.Resampling.NEAREST)
    nps = {n: npcs[n].resize((npcs[n].width * k, npcs[n].height * k),
                             Image.Resampling.NEAREST) for n in names}
    pts = {n: portraits[n].resize((portraits[n].width * k,
                                   portraits[n].height * k),
                                  Image.Resampling.NEAREST) for n in pnames}

    legend = ("each sheet: 32x48 frames   |   rows: down / left / right / up"
              "   |   cols: walk 0..3 (hero) / idle 0 + breathe 1 (NPC)")
    header = ("gen_polish_sprites.py -- refined white-box hero, 5 NPCs, "
              "6 dialogue portraits  (all at 4x nearest)")

    # row A = hero sheet + 5 NPC sheets
    row_a_w = ps.width + gap + sum(nps[n].width + gap for n in names) - gap
    # row B = 6 portraits, tile width grows if the label needs it
    tile_w = max(pts[pnames[0]].width, tw("portrait_yellow.png 32x32") + 8)
    row_b_w = len(pnames) * tile_w - (tile_w - pts[pnames[0]].width)
    width = max(row_a_w, row_b_w, tw(legend), tw(header)) + margin * 2

    header_h = line_h + 8
    a_top = margin + header_h
    a_bottom = a_top + ps.height + lgap + line_h * 3
    b_top = a_bottom + gap
    b_bottom = b_top + pts[pnames[0]].height + lgap + line_h * 2
    height = b_bottom + margin

    canvas = _checker(width, height)
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, margin), header, fill=(235, 235, 235, 255), font=font)

    x = margin
    canvas.alpha_composite(ps, (x, a_top))
    draw.text((x, a_top + ps.height + lgap),
              "player_whitebox.png  128x192", fill=(235, 235, 235, 255),
              font=font)
    draw.text((x, a_top + ps.height + lgap + line_h),
              "white-box hero - 4 x 4 walk frames",
              fill=(200, 210, 220, 255), font=font)
    x += ps.width + gap
    for n in names:
        canvas.alpha_composite(nps[n], (x, a_top))
        draw.text((x, a_top + ps.height + lgap), "%s.png  64x192" % n,
                  fill=(235, 235, 235, 255), font=font)
        draw.text((x, a_top + ps.height + lgap + line_h), titles[n],
                  fill=(200, 210, 220, 255), font=font)
        x += nps[n].width + gap
    draw.text((margin, a_top + ps.height + lgap + line_h * 2 + 4), legend,
              fill=(210, 218, 226, 255), font=font)

    # row B = the six dialogue portraits
    for i, n in enumerate(pnames):
        x = margin + i * tile_w
        canvas.alpha_composite(pts[n], (x, b_top))
        draw.text((x, b_top + pts[n].height + lgap), "%s.png  32x32" % n,
                  fill=(235, 235, 235, 255), font=font)
        draw.text((x, b_top + pts[n].height + lgap + line_h),
                  plabels[i], fill=(200, 210, 220, 255), font=font)
    return canvas


# =====================================================================
#  verification
# =====================================================================
def _hex(c):
    return "#%02X%02X%02X" % (int(c[0]), int(c[1]), int(c[2]))


def _frames(arr, fw, fh, cols, rows):
    boxes = []
    for r in range(rows):
        for c in range(cols):
            f = arr[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
            a = f[..., 3] > 0
            if not a.any():
                boxes.append((r, c, None))
                continue
            ys, xs = np.nonzero(a)
            boxes.append((r, c, (int(xs.min()), int(xs.max()),
                                 int(ys.min()), int(ys.max()))))
    return boxes


def _common_frame_checks(arr, cols, rows, label):
    ok = True
    boxes = _frames(arr, FRAME_W, FRAME_H, cols, rows)
    empty = [(r, c) for r, c, b in boxes if b is None]
    if empty:
        ok = False
        print("  FAIL empty frames %s: %s" % (label, empty))
    else:
        print("  all %d frames non-empty: PASS" % (cols * rows))
    grounds = [b[3] for _, _, b in boxes if b]
    ground_ok = (len(grounds) == cols * rows
                 and all(g == GROUND for g in grounds))
    ok &= ground_ok
    print("  ground line: max alpha y == %d in all %d frames: %s"
          % (GROUND, len(grounds), "PASS" if ground_ok else
             "FAIL " + str(sorted(set(grounds)))))
    widths = [b[1] - b[0] + 1 for _, _, b in boxes if b]
    heights = [b[3] - b[2] + 1 for _, _, b in boxes if b]
    fit = max(widths) <= FRAME_W and max(heights) <= FRAME_H
    ok &= fit
    print("  frame content max %dx%d px (<= %dx%d): %s"
          % (max(widths), max(heights), FRAME_W, FRAME_H,
             "PASS" if fit else "FAIL"))
    grid_ok = True
    for r in range(rows):
        band = arr[r * FRAME_H:(r + 1) * FRAME_H]
        if not (band[..., 3] > 0).any():
            grid_ok = False
            print("  FAIL grid row %d (%s) is empty" % (r, VIEWS[r]))
    for c in range(cols):
        band = arr[:, c * FRAME_W:(c + 1) * FRAME_W]
        if not (band[..., 3] > 0).any():
            grid_ok = False
            print("  FAIL grid column %d is empty" % c)
    ok &= grid_ok
    print("  4 directions x %d frames populated: %s"
          % (cols, "PASS" if grid_ok else "FAIL"))
    mirror_ok = True
    for c in range(cols):
        left = arr[1 * FRAME_H:2 * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W]
        right = arr[2 * FRAME_H:3 * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W]
        if not np.array_equal(left, np.fliplr(right)):
            mirror_ok = False
    ok &= mirror_ok
    print("  left row == mirror(right row): %s"
          % ("PASS" if mirror_ok else "FAIL"))
    alpha_vals = sorted(set(int(v) for v in np.unique(arr[..., 3])))
    bin_ok = set(alpha_vals) <= {0, 255}
    ok &= bin_ok
    print("  binary alpha (no AA): %s: %s"
          % (alpha_vals, "PASS" if bin_ok else "FAIL"))
    trans = arr[arr[..., 3] == 0]
    tmax = int(trans[:, :3].max()) if trans.size else 0
    ok &= tmax == 0
    print("  transparent pixels exactly (0,0,0,0): %s"
          % ("PASS" if tmax == 0 else "FAIL rgb_max=%d" % tmax))
    return ok


def verify_player(img):
    arr = np.asarray(img)
    print("[player_whitebox.png]  128x192")
    ok = (img.width, img.height) == (128, 192)
    print("  sheet size %dx%d (expected 128x192): %s"
          % (img.width, img.height, "PASS" if ok else "FAIL"))
    ok &= _common_frame_checks(arr, 4, 4, "hero")
    opaque = arr[arr[..., 3] > 0][:, :3]
    cols = {tuple(int(v) for v in px) for px in np.unique(opaque, axis=0)}
    extra = cols - PLAYER_COLOURS
    pal_ok = not extra
    ok &= pal_ok
    print("  palette: %d colours, only the white-box greys: %s"
          % (len(cols), "PASS" if pal_ok else "FAIL " + str(sorted(extra))))
    print("  colours used: %s" % ", ".join(_hex(c) for c in sorted(cols)))
    return ok


def verify_npc(spec, img):
    arr = np.asarray(img)
    print("[%s.png]  %s" % (spec["name"], spec["title"]))
    size_ok = (img.width, img.height) == (64, 192)
    print("  sheet size %dx%d (expected 64x192): %s"
          % (img.width, img.height, "PASS" if size_ok else "FAIL"))
    ok = size_ok
    ok &= _common_frame_checks(arr, 2, 4, spec["name"])
    opaque = arr[arr[..., 3] > 0][:, :3]
    cols = {tuple(int(v) for v in px) for px in np.unique(opaque, axis=0)}
    n_ok = 5 <= len(cols) <= 10
    ok &= n_ok
    print("  opaque colours: %d (need 5..10): %s"
          % (len(cols), "PASS" if n_ok else "FAIL"))
    print("  palette: %s" % ", ".join(_hex(c) for c in sorted(cols)))
    hits = total = 0
    for r in range(4):
        for c in range(2):
            f = arr[r * FRAME_H:(r + 1) * FRAME_H,
                    c * FRAME_W:(c + 1) * FRAME_W]
            sil = f[..., 3] > 0
            npad = np.pad(sil, 1)
            inner = (npad[:-2, 1:-1] & npad[2:, 1:-1]
                     & npad[1:-1, :-2] & npad[1:-1, 2:])
            boundary = sil & ~inner
            is_out = np.all(f[..., :3] == np.array(OUTLINE, np.uint8), axis=-1)
            hits += int((boundary & is_out).sum())
            total += int(boundary.sum())
    ratio = hits / max(total, 1)
    out_ok = ratio >= 0.95
    ok &= out_ok
    print("  outline #1B1B1B: %.1f%% of boundary px: %s"
          % (ratio * 100.0, "PASS" if out_ok else "FAIL"))
    bob_ok = True
    for r in range(4):
        f0 = arr[r * FRAME_H:(r + 1) * FRAME_H, 0:FRAME_W]
        f1 = arr[r * FRAME_H:(r + 1) * FRAME_H, FRAME_W:2 * FRAME_W]
        if np.array_equal(f0, f1):
            bob_ok = False
            print("  FAIL row %d: breathe frame identical to idle" % r)
        if not np.array_equal(f0[44:], f1[44:]):
            bob_ok = False
            print("  FAIL row %d: feet moved between idle frames" % r)
    ok &= bob_ok
    print("  breathing bob present, feet pixel-identical: %s"
          % ("PASS" if bob_ok else "FAIL"))
    mean = opaque.mean(axis=0)
    print("  mean opaque RGB: (%.1f, %.1f, %.1f)  %s"
          % (mean[0], mean[1], mean[2], _hex(mean.round().astype(int))))
    return ok


def verify_portrait(name, img, is_player):
    arr = np.asarray(img)
    print("[%s.png]  32x32" % name)
    size_ok = (img.width, img.height) == (32, 32)
    print("  size %dx%d (expected 32x32): %s"
          % (img.width, img.height, "PASS" if size_ok else "FAIL"))
    ok = size_ok
    filled = (arr[..., 3] > 0).any()
    ok &= filled
    print("  non-empty: %s" % ("PASS" if filled else "FAIL"))
    opaque = arr[arr[..., 3] > 0][:, :3]
    cols = {tuple(int(v) for v in px) for px in np.unique(opaque, axis=0)}
    if is_player:
        pal_ok = cols <= PLAYER_COLOURS
        print("  palette: %d colours, only white-box greys (tintable): %s"
              % (len(cols), "PASS" if pal_ok else
                 "FAIL " + str(sorted(cols - PLAYER_COLOURS))))
    else:
        pal_ok = len(cols) <= 12
        print("  palette: %d colours (<= 12): %s"
              % (len(cols), "PASS" if pal_ok else "FAIL"))
    ok &= pal_ok
    alpha_vals = sorted(set(int(v) for v in np.unique(arr[..., 3])))
    bin_ok = set(alpha_vals) <= {0, 255}
    ok &= bin_ok
    print("  binary alpha: %s: %s" % (alpha_vals, "PASS" if bin_ok else "FAIL"))
    trans = arr[arr[..., 3] == 0]
    tmax = int(trans[:, :3].max()) if trans.size else 0
    ok &= tmax == 0
    print("  transparent pixels exactly (0,0,0,0): %s"
          % ("PASS" if tmax == 0 else "FAIL"))
    sil = arr[..., 3] > 0
    npad = np.pad(sil, 1)
    inner = (npad[:-2, 1:-1] & npad[2:, 1:-1]
             & npad[1:-1, :-2] & npad[1:-1, 2:])
    boundary = sil & ~inner
    want = np.array(RIM if is_player else OUTLINE, np.uint8)
    is_line = np.all(arr[..., :3] == want, axis=-1)
    ratio = float((boundary & is_line).sum()) / max(int(boundary.sum()), 1)
    line_ok = ratio >= 0.90
    ok &= line_ok
    print("  1px %s %s on the silhouette: %.1f%%: %s"
          % (_hex(want), "rim" if is_player else "outline", ratio * 100.0,
             "PASS" if line_ok else "FAIL"))
    return ok


# =====================================================================
#  main
# =====================================================================
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("=" * 74)
    print("gen_polish_sprites.py   out=%s" % OUT_DIR)
    print("=" * 74)

    player = build_player_sheet()
    player.save(OUT_DIR / "player_whitebox.png")
    print("[wrote] %-22s %4dx%-4d %s"
          % ("player_whitebox.png", player.width, player.height, player.mode))

    npcs, portraits = {}, {}
    for make in NPC_SPECS:
        spec = make()
        img = build_npc_sheet(spec)
        img.save(OUT_DIR / (spec["name"] + ".png"))
        npcs[spec["name"]] = img
        print("[wrote] %-22s %4dx%-4d %s"
              % (spec["name"] + ".png", img.width, img.height, img.mode))
        pname = "portrait_" + spec["name"].split("_")[1]
        pimg = Image.fromarray(make_portrait(spec))
        pimg.save(OUT_DIR / (pname + ".png"))
        portraits[pname] = pimg
        print("[wrote] %-22s %4dx%-4d %s"
              % (pname + ".png", pimg.width, pimg.height, pimg.mode))

    pp = Image.fromarray(build_portrait_player())
    pp.save(OUT_DIR / "portrait_player.png")
    portraits["portrait_player"] = pp
    print("[wrote] %-22s %4dx%-4d %s"
          % ("portrait_player.png", pp.width, pp.height, pp.mode))
    pc = build_portrait_player_charm()
    pc.save(OUT_DIR / "portrait_player_charm.png")
    print("[wrote] %-22s %4dx%-4d %s"
          % ("portrait_player_charm.png", pc.width, pc.height, pc.mode))

    preview = build_preview(player, npcs, portraits)
    preview.save(OUT_DIR / "_preview_polish.png")
    print("[wrote] %-22s %4dx%-4d %s"
          % ("_preview_polish.png", preview.width, preview.height,
             preview.mode))

    print("\n--- verification " + "-" * 55)
    ok = True
    ok &= verify_player(player)
    print()
    for make in NPC_SPECS:
        spec = make()
        ok &= verify_npc(spec, npcs[spec["name"]])
        print()
    for n in ("portrait_player", "portrait_red", "portrait_yellow",
              "portrait_green", "portrait_blue", "portrait_purple"):
        ok &= verify_portrait(n, portraits[n], n == "portrait_player")
        print()
    ok &= (OUT_DIR / "_preview_polish.png").is_file()

    print("--- palette / mean colour summary " + "-" * 38)
    print("  hero    : #FFFFFF body, #F2F2F2 / #E4E4E4 / #D4D4D4 shading, "
          "#B8B8B8 rim")
    for make in NPC_SPECS:
        spec = make()
        arr = np.asarray(npcs[spec["name"]])
        opaque = arr[arr[..., 3] > 0][:, :3]
        cols = {tuple(int(v) for v in px)
                for px in np.unique(opaque, axis=0)}
        mean = opaque.mean(axis=0)
        print("  %-11s %2d colours, mean RGB (%5.1f, %5.1f, %5.1f)"
              % (spec["name"] + ":", len(cols), mean[0], mean[1], mean[2]))
    print("  portraits  : 32x32 busts, player bust greys only (tintable),")
    print("               NPC busts use the NPC palette + 1px #1B1B1B outline")

    print("\n--- godot import notes " + "-" * 52)
    print("  player_whitebox / npc_*.png : Filter = Nearest, Mipmaps = off,")
    print("    Compression = Lossless, Repeat = Disabled (frames are 32x48)")
    print("  portrait_*.png : Filter = Nearest, Mipmaps = off, Lossless")
    print("    player portrait is white; portrait_player_charm.png is the tinted heart fill")

    print("\nRESULT:", "PASS - all checks green" if ok
          else "FAIL - see above")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
