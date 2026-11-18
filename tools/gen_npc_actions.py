#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_npc_actions.py -- 10-column NPC sprite sheets with 8-frame action loops.

Run from anywhere:

    python tools/gen_npc_actions.py

Reads the *current* 64x192 NPC sheets, keeps their 8 idle frames untouched and
rewrites the same five files as 320x192:

    npc_red.png     320x192   10 cols x 4 rows of 32x48
    npc_yellow.png            rows = down / left / right / up
    npc_green.png             cols 0-1  = the previous idle / breathe frames,
    npc_blue.png                         copied *pixel for pixel*
    npc_purple.png            cols 2-9  = 8-frame personal action loop
    _preview_npc_actions.png  contact sheet, 4x nearest, labelled

Nothing else is touched: not the portraits, not the hero, not the rest sheet,
not the other generators, no .import files, no Godot.

Design rules honoured here:

  * the 1px outline / seam / shading renderer is imported from
    gen_polish_sprites.py (the module that produced the current sheets), so
    the action frames cannot drift in style
  * only colours that already exist in the old sheets are used -- the palettes
    are the very same family tuples, nothing new is introduced
  * the body is the existing idle body; only the arms and the held props move,
    plus a 1px whole-upper-body bob (the same "breathing" channel)
  * feet never move: the ground line is y == 47 in all 40 frames
  * left row is the exact mirror of the right row
  * deterministic: no randomness anywhere, re-running gives identical bytes

The action loops (frame 0 .. 7 = columns 2 .. 9):

  red    A-Ran   reach into the mail bag, pull a letter out, roll it, hold it
                 up to read, look up to scout, stuff it back, straighten the
                 headband, settle back to idle
  yellow A-Heng  raise the magnifier to the eye, lean to the bench, twist a
                 part (2 frames of hand jitter), look up and lower the glass,
                 hold the part to the light, note it down, settle
  green  A-He    lift the watering can, tilt it, pour (3 frames + drops),
                 lower it and brush the blossom, wipe the brow, settle
  blue   A-Yan   lift the lantern, raise it high (2 frames), polish the glass,
                 check the flame, lower it, shade the eyes to look down the
                 road, settle
  purple A-Yao   raise the brush (2 frames), three brush strokes, lean back
                 and step away, dip the brush, look up at the sky, settle
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

_TOOLS = Path(__file__).resolve().parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

import gen_polish_sprites as gp          # noqa: E402  (renderer + palettes)

FRAME_W, FRAME_H = gp.FRAME_W, gp.FRAME_H
GROUND = gp.GROUND
VIEWS = gp.VIEWS
COLS, ROWS = 10, 4
IDLE_COLS = 2                            # cols 0-1 are the untouched idle art
ACTION_COLS = 8                          # cols 2..9
SHEET_W = FRAME_W * COLS                 # 320
SHEET_H = FRAME_H * ROWS                 # 192

OUT_DIR = gp.OUT_DIR
Z = gp.Z
OUTLINE = gp.OUTLINE
BRASS_LIGHT = (0xF2, 0xC9, 0x4C)          # the "flame" pixel, already a palette colour

SPECS = (gp.spec_red, gp.spec_yellow, gp.spec_green, gp.spec_blue,
         gp.spec_purple)

# which hand carries the permanent prop of each NPC ("R" unless stated)
CARRY = {"npc_red": "R", "npc_yellow": "R", "npc_green": "R",
         "npc_blue": "L", "npc_purple": "R"}


# =====================================================================
#  the idle body: reuse the existing ops, minus the parts that animate
# =====================================================================
def view_ops(spec, tag):
    if tag == "down":
        return spec["front"]
    if tag == "up":
        return spec["back"]
    return spec["side"]


def arm_geo(ops):
    """Per arm: hand centre/bottom (= the resting hand) and the shoulder.

    The idle sheets store the hands as separate HAND boxes, so the hand that
    belongs to an arm is picked by x-overlap with that arm's box -- otherwise
    both arms would be anchored at the centre of the body.
    """
    hands = [b for k, r, b, e, bob, clip in ops if r == "HAND"]
    geo = {}
    for role in ("ARM_L", "ARM_R"):
        arm = [b for k, r, b, e, bob, clip in ops if r == role]
        if not arm:
            continue
        ax0 = min(b[0] for b in arm)
        ax1 = max(b[2] for b in arm)
        ay0 = min(b[1] for b in arm)
        best = None
        for hb in hands:
            if hb[0] <= ax1 and hb[2] >= ax0:
                best = hb
        if best is None:
            best = arm[0]
        geo[role] = dict(hx=(best[0] + best[2]) // 2,
                         hy=best[3],
                         sx=(ax0 + ax1) // 2, sy=ay0 + 1)
    return geo


def _shift_h(mask, dx):
    out = np.zeros_like(mask)
    if dx > 0:
        out[:, dx:] = mask[:, :-dx]
    elif dx < 0:
        out[:, :dx] = mask[:, -dx:]
    else:
        out = mask.copy()
    return out


def stamp_arm(c, sx, sy, role, target, w=3, hand_role="HAND"):
    """Blocky 3px arm + 3x2 hand.  A raised hand bends at the elbow so the
    silhouette reads as an arm instead of a diagonal sash."""
    hx, hy = target
    hx = max(2, min(FRAME_W - 3, int(hx)))
    hy = max(3, min(GROUND - 2, int(hy)))
    if hy < sy + 5:                       # raised: shoulder -> elbow -> hand
        ex = sx + (1 if hx >= sx else -1)
        ey = sy + 5
        m = gp.m_line(sx, sy, ex, ey, FRAME_W, FRAME_H)
        m |= gp.m_line(ex, ey, hx, hy - 1, FRAME_W, FRAME_H)
    else:                                 # hanging / lowered: straight arm
        m = gp.m_line(sx, sy, hx, hy - 1, FRAME_W, FRAME_H)
    thick = np.zeros_like(m)
    for k in range(w):
        thick |= _shift_h(m, k - w // 2)
    c.stamp(Z[role], thick)
    c.rect(Z[hand_role], hx - 1, hy - 1, hx + 1, hy)


# =====================================================================
#  held props -- one small blocky drawing per NPC, drawn at the hand
# =====================================================================
def prop_red(c, tag, fr, rh, lh):
    """A leather envelope / a rolled letter."""
    p = fr.get("prop")
    x, y = rh
    if p == "letter":
        c.rect(Z["PROP"], x - 2, y - 3, x + 1, y - 1)     # 4x3 envelope
        return [(OUTLINE, [(x - 2, y - 2), (x - 1, y - 2), (x + 1, y - 2),
                           (x, y - 1)], False)]
    if p == "roll":
        c.rect(Z["PROP"], x - 1, y - 4, x, y)             # 2x5 rolled letter
        return [(OUTLINE, [(x, y - 3)], False)]
    return []


def prop_yellow(c, tag, fr, rh, lh):
    """A brass-rimmed 5x5 magnifier, a tiny watch part, a pencil."""
    p = fr.get("prop")
    x, y = rh
    det = []
    if p == "magnifier":
        cx, cy = x, y - 6                                 # lens centre
        c.rect(Z["CAPE"], cx - 2, cy - 2, cx + 2, cy - 2)
        c.rect(Z["CAPE"], cx - 2, cy + 2, cx + 2, cy + 2)
        c.rect(Z["CAPE"], cx - 2, cy - 1, cx - 2, cy + 1)
        c.rect(Z["CAPE"], cx + 2, cy - 1, cx + 2, cy + 1)
        c.rect(Z["ACC"], cx - 1, cy - 1, cx + 1, cy + 1)  # cream lens
        c.rect(Z["PROP"], x, y - 3, x, y - 2)             # leather handle
        det.append((OUTLINE, [(cx, cy - 1)], False))      # glint
    elif p == "part":
        c.rect(Z["CAPE"], x - 1, y - 3, x, y - 2)         # watch part
        det.append((OUTLINE, [(x - 1, y - 3)], False))
    elif p == "pencil":
        c.rect(Z["ACC"], x, y - 4, x, y - 3)              # pencil
        det.append((OUTLINE, [(x, y - 5)], False))
    return det


def prop_green(c, tag, fr, rh, lh):
    """A straw watering can with a spout, plus falling water."""
    p = fr.get("prop")
    x, y = rh
    det = []
    if p in ("can", "pour"):
        c.rect(Z["ACC"], x - 2, y + 1, x + 2, y + 4)      # 5x4 body
        if p == "can":
            c.rect(Z["ACC"], x + 3, y + 1, x + 4, y + 2)  # upright spout
        else:
            c.rect(Z["ACC"], x - 4, y + 3, x - 3, y + 5)  # tilted spout
            for dx, dyy in fr.get("drops", ()):
                c.rect(Z["ACC"], x + dx, y + dyy, x + dx, y + dyy)
        det.append((OUTLINE, [(x - 1, y + 2), (x, y + 2), (x + 1, y + 2)],
                    False))
    return det


def prop_blue(c, tag, fr, rh, lh):
    """The brass lantern always hangs from the carrying hand; the other hand
    can carry a dark polishing cloth."""
    x, y = lh
    det = []
    c.rect(Z["PROP"], x, y + 1, x + 1, y + 1)             # handle
    c.rect(Z["PROP"], x - 1, y + 2, x + 2, y + 2)         # cap
    c.rect(Z["PROP"], x - 1, y + 3, x + 2, y + 7)         # body 4x5
    det.append((OUTLINE, [(x - 1, y + 5), (x, y + 5), (x + 1, y + 5)],
                False))                                    # glass bar
    det.append((BRASS_LIGHT, [(x, y + 4)], False))         # flame
    if fr.get("cloth"):
        cx, cy = rh
        c.rect(Z["TORSO"], cx - 1, cy, cx + 1, cy + 1)    # cloth
    return det


def prop_purple(c, tag, fr, rh, lh):
    """A short paper-handled ink brush, tip up, held in the right hand."""
    p = fr.get("prop")
    if p == "brush":
        x, y = rh
        c.rect(Z["PROP"], x - 1, y - 3, x, y - 1)         # handle 2x3
        c.rect(Z["TORSO"], x - 1, y - 5, x, y - 3)        # ink tip 2x2
    return []


PROPS = {"npc_red": prop_red, "npc_yellow": prop_yellow,
         "npc_green": prop_green, "npc_blue": prop_blue,
         "npc_purple": prop_purple}

# which PROP ops of the idle body are replaced by the animated prop
DROP_PROP = {
    "npc_red": lambda box: False,
    "npc_yellow": lambda box: False,
    "npc_green": lambda box: False,
    "npc_blue": lambda box: box[1] >= 34,        # the hanging lantern
    "npc_purple": lambda box: box[0] >= 18,      # the brush (back: sketchbook)
}


# =====================================================================
#  the eight action poses of each NPC
# =====================================================================
# A frame is:
#   dy   : 1px whole-upper-body offset (the breathing channel; feet stay)
#   R/L  : hand target as an offset from that hand's resting position
#   prop : what the hand holds in that frame
#   drops: 1px water drops (green), relative to the right hand
#   cloth: the right hand carries the lantern cloth (blue)
#   lit  : the lantern glass is lit (blue)
#
# cols 2..9 -> frames 0..7; frame 7 returns to the idle pose.

RED_FRAMES = [
    dict(dy=1, R=(-3, -3), L=(0, 0), prop=None),          # 0 reach in the bag
    dict(dy=0, R=(2, -8), L=(0, 0), prop="letter"),       # 1 pull a letter out
    dict(dy=0, R=(1, -5), L=(0, 0), prop="roll"),         # 2 roll / tie it
    dict(dy=-1, R=(2, -15), L=(0, 0), prop="letter"),     # 3 hold it up, read
    dict(dy=-1, R=(-2, -23), L=(0, 0), prop=None),        # 4 look up, scout
    dict(dy=0, R=(-3, -3), L=(0, 0), prop=None),          # 5 stuff it back
    dict(dy=0, R=(-2, -22), L=(0, 0), prop=None),         # 6 straighten band
    dict(dy=0, R=(0, 0), L=(0, 0), prop=None),            # 7 settle
]

YELLOW_FRAMES = [
    dict(dy=0, R=(-3, -20), L=(0, 0), prop="magnifier"),  # 0 glass to the eye
    dict(dy=1, R=(-5, -8), L=(4, -8), prop=None),         # 1 lean to the bench
    dict(dy=1, R=(-7, -9), L=(5, -8), prop="part"),       # 2 twist the part
    dict(dy=1, R=(-7, -8), L=(5, -7), prop="part"),       # 3 twist it back
    dict(dy=-1, R=(-2, -15), L=(0, 0), prop="magnifier"),  # 4 look up, lower
    dict(dy=-1, R=(-4, -25), L=(0, 0), prop="part"),      # 5 part to the light
    dict(dy=0, R=(-11, -5), L=(0, 0), prop="pencil"),     # 6 note it down
    dict(dy=0, R=(0, 0), L=(0, 0), prop=None),            # 7 settle
]

GREEN_FRAMES = [
    dict(dy=0, R=(-3, -8), L=(0, 0), prop="can"),         # 0 lift the can
    dict(dy=0, R=(-5, -10), L=(0, 0), prop="pour"),       # 1 tilt it
    dict(dy=0, R=(-7, -10), L=(0, 0), prop="pour",
         drops=((-5, 6), (-3, 8))),                       # 2 pour
    dict(dy=0, R=(-7, -10), L=(0, 0), prop="pour",
         drops=((-6, 8), (-4, 10), (-5, 12))),            # 3 pour
    dict(dy=0, R=(-7, -9), L=(0, 0), prop="pour",
         drops=((-6, 10), (-4, 12), (-5, 14))),           # 4 pour
    dict(dy=0, R=(-2, -11), L=(0, 0), prop="can"),        # 5 lower, touch bloom
    dict(dy=1, R=(0, 0), L=(9, -22), prop=None),          # 6 wipe the brow
    dict(dy=0, R=(0, 0), L=(0, 0), prop=None),            # 7 settle
]

BLUE_FRAMES = [
    dict(dy=0, R=(0, 0), L=(1, -7), lit=True),            # 0 lift the lantern
    dict(dy=0, R=(0, 0), L=(0, -17), lit=True),           # 1 raise it high
    dict(dy=-1, R=(0, 0), L=(0, -19), lit=True),          # 2 hold it high
    dict(dy=0, R=(-14, -9), L=(0, -13), cloth=True,
         lit=True),                                       # 3 polish the glass
    dict(dy=0, R=(-13, -10), L=(0, -18), lit=True),       # 4 check the flame
    dict(dy=0, R=(0, 0), L=(0, -5), lit=True),            # 5 lower it
    dict(dy=-1, R=(-6, -23), L=(0, 0), lit=True),         # 6 look down the road
    dict(dy=0, R=(0, 0), L=(0, 0), lit=True),             # 7 settle
]

PURPLE_FRAMES = [
    dict(dy=0, R=(-2, -13), L=(0, 0), prop="brush"),      # 0 raise the brush
    dict(dy=0, R=(-2, -17), L=(0, 0), prop="brush"),      # 1 raise it higher
    dict(dy=0, R=(-6, -14), L=(0, 0), prop="brush"),      # 2 brush stroke
    dict(dy=0, R=(-7, -13), L=(0, 0), prop="brush"),      # 3 brush stroke
    dict(dy=0, R=(-6, -15), L=(0, 0), prop="brush"),      # 4 brush stroke
    dict(dy=-1, R=(-1, -11), L=(0, 0), prop="brush"),     # 5 lean back, look
    dict(dy=0, R=(0, -4), L=(0, 0), prop="brush"),        # 6 dip the brush
    dict(dy=-1, R=(0, 0), L=(0, 0), prop=None),           # 7 look at the sky
]

FRAMES = {"npc_red": RED_FRAMES, "npc_yellow": YELLOW_FRAMES,
          "npc_green": GREEN_FRAMES, "npc_blue": BLUE_FRAMES,
          "npc_purple": PURPLE_FRAMES}

TITLES = {"npc_red": "A-Ran  courier     mail loop",
          "npc_yellow": "A-Heng watchmaker  bench loop",
          "npc_green": "A-He   gardener    watering loop",
          "npc_blue": "A-Yan  road-keeper lantern loop",
          "npc_purple": "A-Yao  painter     brush loop"}


# =====================================================================
#  frame assembly
# =====================================================================
def build_action_frame(spec, tag, fr):
    ops = view_ops(spec, tag)
    dy = int(fr.get("dy", 0))
    name = spec["name"]
    drop = DROP_PROP[name]
    c = gp.Canvas()
    for kind, role, (x0, y0, x1, y1), extra, bob, clip in ops:
        if role in ("ARM_L", "ARM_R", "HAND"):
            continue                     # re-drawn below, in the action pose
        if role == "PROP" and drop((x0, y0, x1, y1)):
            continue                     # replaced by the animated prop
        d = dy if bob else 0
        mask = gp.MASKERS[kind](x0, y0 + d, x1, y1 + d, FRAME_W, FRAME_H,
                                extra)
        c.stamp(Z[role], mask, clip)

    geo = arm_geo(ops)
    side = tag == "right"                # the side art is narrower
    carry = CARRY[name]
    free = "L" if carry == "R" else "R"
    carry_off = fr.get(carry, (0, 0))
    free_off = fr.get(free, (0, 0))

    # in the side view only the near (right) arm exists, so it carries the prop
    if "ARM_" + carry in geo:
        plan = [(carry, carry_off)]
        if "ARM_" + free in geo:
            plan.append((free, free_off))
    else:
        plan = [("R" if "ARM_R" in geo else "L", carry_off)]

    hands = {}
    for key, (dx, dyy) in plan:
        g = geo["ARM_" + key]
        if side:                          # compress the sideways reach
            dx = int(round(dx * 0.72))
        hx, hy = g["hx"] + dx, g["hy"] + dyy + dy
        hands[key] = (hx, hy)
        stamp_arm(c, g["sx"], g["sy"] + dy, "ARM_" + key, (hx, hy))
    rh = hands.get("R", (16, GROUND - 6))
    lh = hands.get("L", rh)

    # the props sit in the hand, so they are drawn over the arm
    det_extra = []
    if name == "npc_blue":
        det_extra = PROPS[name](c, tag, fr, rh, lh)
    elif fr.get("prop"):
        det_extra = PROPS[name](c, tag, fr, rh, lh)

    pid = c.pid
    # the face pixels follow the 1px body offset
    det = []
    for color, pts, bob in spec["details"].get(tag, []):
        d = dy if bob else 0
        det.append((color, [(x, y + d) for x, y in pts], False))
    det += det_extra
    spec2 = dict(spec, details={tag: det})
    return gp.render_npc(pid, spec2, tag, False)


def build_sheet(spec, old):
    sheet = np.zeros((SHEET_H, SHEET_W, 4), np.uint8)
    # cols 0-1: the previous idle / breathe frames, copied pixel for pixel
    for r in range(ROWS):
        for c in range(2):
            src = old[r * FRAME_H:(r + 1) * FRAME_H,
                      c * FRAME_W:(c + 1) * FRAME_W]
            sheet[r * FRAME_H:(r + 1) * FRAME_H,
                  c * FRAME_W:(c + 1) * FRAME_W] = src
    # cols 2-9: the action loop
    for r, view in enumerate(VIEWS):
        tag = "down" if view == "down" else ("up" if view == "up" else "right")
        for i, fr in enumerate(FRAMES[spec["name"]]):
            arr = build_action_frame(spec, tag, fr)
            if view == "left":
                arr = np.ascontiguousarray(np.fliplr(arr))
            c = IDLE_COLS + i
            sheet[r * FRAME_H:(r + 1) * FRAME_H,
                  c * FRAME_W:(c + 1) * FRAME_W] = arr
    return Image.fromarray(sheet)


# =====================================================================
#  contact sheet preview (4x nearest, labelled)
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
    except TypeError:
        return ImageFont.load_default()


def build_preview(sheets):
    k = 4
    margin, gap, line_h = 20, 16, 22
    font = _font(18)
    tile_w = SHEET_W * k
    title_h = line_h + 6
    block = title_h + SHEET_H * k + gap + line_h
    width = tile_w + margin * 2
    height = margin * 2 + len(sheets) * block
    canvas = _checker(width, height)
    draw = ImageDraw.Draw(canvas)
    for i, (name, img) in enumerate(sheets):
        top = margin + i * block
        draw.text((margin, top), "%s.png  320x192  --  %s"
                  % (name, TITLES[name]), fill=(240, 240, 240, 255), font=font)
        big = img.resize((img.width * k, img.height * k),
                         Image.Resampling.NEAREST)
        canvas.alpha_composite(big, (margin, top + title_h))
        base_y = top + title_h + SHEET_H * k + 2
        for c in range(COLS):
            label = ("idle" if c == 0 else
                     ("breath" if c == 1 else "a%d" % (c - 1)))
            draw.text((margin + c * FRAME_W * k, base_y), label,
                      fill=(205, 214, 224, 255), font=font)
    return canvas


# =====================================================================
#  verification
# =====================================================================
def _hex(c):
    return "#%02X%02X%02X" % (int(c[0]), int(c[1]), int(c[2]))


def _frame(arr, r, c):
    return arr[r * FRAME_H:(r + 1) * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W]


def verify(name, new, old):
    arr = np.asarray(new)
    print("[%s.png]  %s" % (name, TITLES[name]))
    ok = (new.width, new.height) == (SHEET_W, SHEET_H)
    print("  sheet size %dx%d (expected %dx%d): %s"
          % (new.width, new.height, SHEET_W, SHEET_H,
             "PASS" if ok else "FAIL"))

    empty = []
    for r in range(ROWS):
        for c in range(COLS):
            if not (_frame(arr, r, c)[..., 3] > 0).any():
                empty.append((r, c))
    ok &= not empty
    print("  all %d frames non-empty: %s"
          % (ROWS * COLS, "PASS" if not empty else "FAIL %s" % empty))
    grid_ok = all((_frame(arr, r, c)[..., 3] > 0).any()
                  for r in range(ROWS) for c in range(COLS))
    ok &= grid_ok
    print("  4 directions x 10 columns populated: %s"
          % ("PASS" if grid_ok else "FAIL"))

    same = True
    for r in range(ROWS):
        for c in range(2):
            if not np.array_equal(_frame(arr, r, c),
                                  old[r * FRAME_H:(r + 1) * FRAME_H,
                                      c * FRAME_W:(c + 1) * FRAME_W]):
                same = False
    ok &= same
    print("  cols 0-1 pixel-identical to the old idle/breathe frames: %s"
          % ("PASS" if same else "FAIL"))

    diff_counts = []
    for r in range(ROWS):
        idle = _frame(arr, r, 0)
        n = sum(0 if np.array_equal(_frame(arr, r, IDLE_COLS + i), idle)
                else 1 for i in range(ACTION_COLS))
        diff_counts.append(n)
    diff_ok = all(n >= 6 for n in diff_counts)
    ok &= diff_ok
    print("  action frames different from idle (need >= 6/8 per direction): "
          "%s %s" % (diff_counts, "PASS" if diff_ok else "FAIL"))

    grounds = []
    for r in range(ROWS):
        for c in range(COLS):
            a = _frame(arr, r, c)[..., 3] > 0
            ys = np.nonzero(a)[0]
            grounds.append(int(ys.max()))
    ground_ok = all(g == GROUND for g in grounds)
    ok &= ground_ok
    print("  ground line: max alpha y == %d in all %d frames: %s"
          % (GROUND, len(grounds), "PASS" if ground_ok else
             "FAIL %s" % sorted(set(grounds))))

    vals = sorted(set(int(v) for v in np.unique(arr[..., 3])))
    bin_ok = set(vals) <= {0, 255}
    ok &= bin_ok
    print("  binary alpha (no AA): %s: %s"
          % (vals, "PASS" if bin_ok else "FAIL"))
    trans = arr[arr[..., 3] == 0]
    tmax = int(trans[:, :3].max()) if trans.size else 0
    ok &= tmax == 0
    print("  transparent pixels exactly (0,0,0,0): %s"
          % ("PASS" if tmax == 0 else "FAIL rgb_max=%d" % tmax))

    old_cols = {tuple(int(v) for v in px)
                for px in np.unique(old[old[..., 3] > 0][:, :3], axis=0)}
    new_cols = {tuple(int(v) for v in px)
                for px in np.unique(arr[arr[..., 3] > 0][:, :3], axis=0)}
    extra = new_cols - old_cols
    pal_ok = not extra
    ok &= pal_ok
    print("  palette: %d colours, all already in the old sheet: %s"
          % (len(new_cols), "PASS" if pal_ok else "FAIL %s" % sorted(extra)))

    mirror_ok = all(np.array_equal(_frame(arr, 1, c),
                                   np.fliplr(_frame(arr, 2, c)))
                    for c in range(COLS))
    ok &= mirror_ok
    print("  left row == mirror(right row) in all 10 columns: %s"
          % ("PASS" if mirror_ok else "FAIL"))
    return ok


# =====================================================================
#  main
# =====================================================================
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("=" * 74)
    print("gen_npc_actions.py   out=%s" % OUT_DIR)
    print("=" * 74)

    # read the current sheets into memory BEFORE overwriting them.  On the
    # first run they are the original 64x192 sheets; on a re-run they are the
    # already-expanded 320x192 sheets, whose columns 0-1 are the preserved
    # idle frames -- either way only those two columns are used as the source.
    old = {}
    for make in SPECS:
        spec = make()
        p = OUT_DIR / (spec["name"] + ".png")
        img = Image.open(p).convert("RGBA")
        arr = np.asarray(img)
        if img.size == (2 * FRAME_W, SHEET_H):
            idle = arr
            src = "original 2-column sheet"
        elif img.size == (SHEET_W, SHEET_H):
            idle = np.ascontiguousarray(arr[:, :IDLE_COLS * FRAME_W])
            src = "previous 10-column sheet, idle columns reused"
        else:
            print("ERROR: %s is %dx%d, expected 64x192 or %dx%d"
                  % (p.name, img.width, img.height, SHEET_W, SHEET_H))
            return 1
        old[spec["name"]] = idle
        print("[read ] %-18s %4dx%-4d %s"
              % (p.name, img.width, img.height, src))

    sheets = []
    for make in SPECS:
        spec = make()
        img = build_sheet(spec, old[spec["name"]])
        img.save(OUT_DIR / (spec["name"] + ".png"))
        sheets.append((spec["name"], img))
        print("[wrote] %-18s %dx%d %s"
              % (spec["name"] + ".png", img.width, img.height, img.mode))

    preview = build_preview(sheets)
    preview.save(OUT_DIR / "_preview_npc_actions.png")
    print("[wrote] %-18s %dx%d %s"
          % ("_preview_npc_actions.png", preview.width, preview.height,
             preview.mode))

    print("\n--- verification " + "-" * 55)
    ok = True
    for name, img in sheets:
        ok &= verify(name, img, old[name])
        print()
    ok &= (OUT_DIR / "_preview_npc_actions.png").is_file()

    print("--- action description " + "-" * 49)
    for name in ("npc_red", "npc_yellow", "npc_green", "npc_blue",
                 "npc_purple"):
        print("  %-11s %s" % (name + ":", TITLES[name]))
        for i, fr in enumerate(FRAMES[name]):
            bits = ["col %d" % (IDLE_COLS + i)]
            if fr.get("prop"):
                bits.append("prop=%s" % fr["prop"])
            if fr.get("cloth"):
                bits.append("cloth")
            print("      f%d  %-16s dy=%+d  R%+d,%+d  L%+d,%+d"
                  % (i, " ".join(bits), fr.get("dy", 0),
                     fr.get("R", (0, 0))[0], fr.get("R", (0, 0))[1],
                     fr.get("L", (0, 0))[0], fr.get("L", (0, 0))[1]))
    print("\nRESULT:", "PASS - all checks green" if ok
          else "FAIL - see above")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
