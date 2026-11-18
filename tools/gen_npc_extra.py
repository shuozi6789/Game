#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_npc_extra.py -- three additional NPCs for the 8-colour cast.

New files written into <project>/assets/generated/ :

    npc_orange.png   320x192   10 cols x 4 rows of 32x48   (A-Zuo, carpenter)
    npc_teal.png     320x192                               (A-Xu,  scribe / clock keeper)
    npc_pink.png     320x192                               (A-You, traveller / kite flyer)
    portrait_orange.png   32x32   dialogue bust
    portrait_teal.png     32x32
    portrait_pink.png     32x32
    _preview_npc_extra.png        contact sheet at 4x nearest, labelled

Sheet layout (identical to the existing five NPCs):

    rows   = down / left / right / up
    cols 0 = idle, col 1 = 1px breathing bob
    cols 2-9 = the 8-frame personal action loop
    every frame is 32x48, the ground line is y == 47, 1px #1B1B1B outline,
    flat muted palettes (<= 10 opaque colours), left row = mirror of right

The renderer (Canvas / part-id grid / 1px seams / outline / detail pixels) and
the arm-posing helpers are imported from gen_polish_sprites.py and
gen_npc_actions.py -- the very modules that produced the existing art -- so
these three cannot drift in style.  Nothing existing is modified.

Deterministic: no randomness, re-running gives identical bytes.  No Godot,
no .import files, no temp files.

Action loops (cols 2..9 = frames 0..7):

  orange A-Zuo  carry a plank in, raise the hammer, two strikes, look at the
                angle, measure and mark it, blow the sawdust, put it down,
                settle back to idle
  teal   A-Xu   open the notebook, dip the quill, write (2 frames), look up to
                check, stamp it, close the book, straighten the glasses
  pink   A-You  raise the spool, look up at the kite, pull the string (2
                frames), half a step, laugh at the sky, reel the string in,
                tuck the spool back on the belt
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

_TOOLS = Path(__file__).resolve().parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

import gen_polish_sprites as gp          # noqa: E402  renderer + helpers
import gen_npc_actions as ga             # noqa: E402  arm posing helpers

FRAME_W, FRAME_H = gp.FRAME_W, gp.FRAME_H
GROUND = gp.GROUND
VIEWS = gp.VIEWS
COLS, ROWS = 10, 4
IDLE_COLS = 2
ACTION_COLS = 8
SHEET_W = FRAME_W * COLS                 # 320
SHEET_H = FRAME_H * ROWS                 # 192

OUT_DIR = gp.OUT_DIR
Z = gp.Z
OUTLINE = gp.OUTLINE
SKIN = gp.SKIN
LEATHER = gp.LEATHER
CLEAR = (0, 0, 0, 0)

# ------------------------------------------------------------------ palettes
ORANGE = ((0xE0, 0x9A, 0x5C), (0xC9, 0x7A, 0x3A), (0x9A, 0x55, 0x26))
CREAM1 = ((0xF0, 0xE4, 0xC6),)
CREAM = ((0xF0, 0xE4, 0xC6), (0xC9, 0xB8, 0x93))
TEAL = ((0x5F, 0xB0, 0xA6), (0x3F, 0x8F, 0x86), (0x2A, 0x62, 0x5C))
PINK = ((0xE8, 0xA2, 0xB8), (0xD7, 0x7A, 0x9A), (0xA8, 0x55, 0x70))

rc = gp.rc
el = gp.el
ln = gp.ln
rr = gp.rr


# =====================================================================
#  A-Zuo -- carpenter (orange)
# =====================================================================
def spec_orange():
    """Short, sturdy carpenter: orange-brown work apron over rolled sleeves,
    a leather tool belt with a hanging hammer, cropped dark hair."""
    fams = {"skin": SKIN, "cloth": ORANGE, "leather": LEATHER,
            "cream": CREAM1}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "cloth",
             "ARM_L": "cloth", "ARM_R": "cloth", "LEG_L": "cloth",
             "LEG_R": "cloth", "CAPE": "cloth", "ACC": "cream",
             "HAIR": "leather", "BOOT": "leather", "PROP": "leather"}
    front = [
        rc("BOOT", 9, 44, 14, GROUND, bob=False),
        rc("BOOT", 17, 44, 22, GROUND, bob=False),
        rc("LEG_L", 10, 35, 14, 43, bob=False),
        rc("LEG_R", 17, 35, 21, 43, bob=False),
        rr("TORSO", 8, 19, 23, 34, r=1),
        rc("ACC", 12, 20, 13, 26, clip=True),         # apron bib straps
        rc("ACC", 19, 20, 20, 26, clip=True),
        rc("ACC", 8, 29, 23, 30, clip=True),          # apron waistband
        rc("PROP", 8, 31, 23, 32),                    # tool belt
        rc("PROP", 20, 33, 21, 37),                   # hammer on the belt
        rc("PROP", 19, 32, 22, 33),
        rc("ARM_L", 5, 20, 7, 26),
        rc("ARM_R", 24, 20, 26, 26),
        rc("ACC", 5, 27, 7, 27),                      # rolled cuffs
        rc("ACC", 24, 27, 26, 27),
        rc("HAND", 5, 28, 7, 30),
        rc("HAND", 24, 28, 26, 30),
        rr("HEAD", 9, 5, 22, 17, r=2),
        rr("HAIR", 9, 5, 22, 8, r=2, clip=True),
        rc("HAIR", 9, 8, 10, 12, clip=True),
        rc("HAIR", 21, 8, 22, 12, clip=True),
    ]
    side = [
        rc("BOOT", 10, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 21, GROUND, bob=False),
        rc("LEG_L", 11, 35, 16, 43, bob=False),
        rc("LEG_R", 15, 35, 20, 43, bob=False),
        rr("TORSO", 10, 19, 21, 34, r=1),
        rc("ACC", 14, 20, 15, 26, clip=True),
        rc("ACC", 10, 29, 21, 30, clip=True),
        rc("PROP", 10, 31, 21, 32),
        rc("PROP", 18, 33, 19, 37),
        rc("PROP", 17, 32, 20, 33),
        rc("ARM_R", 17, 20, 19, 26),
        rc("ACC", 17, 27, 19, 27),
        rc("HAND", 17, 28, 19, 30),
        rr("HEAD", 10, 5, 21, 17, r=2),
        rr("HAIR", 10, 5, 21, 8, r=2, clip=True),
        rc("HAIR", 10, 8, 11, 12, clip=True),
    ]
    back = [
        rc("BOOT", 9, 44, 14, GROUND, bob=False),
        rc("BOOT", 17, 44, 22, GROUND, bob=False),
        rc("LEG_L", 10, 35, 14, 43, bob=False),
        rc("LEG_R", 17, 35, 21, 43, bob=False),
        rr("TORSO", 8, 19, 23, 34, r=1),
        rc("ACC", 12, 19, 19, 21, clip=True),         # apron strap at the back
        rc("ACC", 13, 21, 14, 28),
        rc("ACC", 18, 21, 19, 28),
        rc("PROP", 8, 31, 23, 32),
        rc("PROP", 21, 32, 24, 36),
        rc("ARM_L", 5, 20, 7, 26),
        rc("ARM_R", 24, 20, 26, 26),
        rc("ACC", 5, 27, 7, 27),
        rc("ACC", 24, 27, 26, 27),
        rc("HAND", 5, 28, 7, 30),
        rc("HAND", 24, 28, 26, 30),
        rr("HEAD", 9, 5, 22, 17, r=2),
        rr("HAIR", 9, 5, 22, 17, r=2, clip=True),
    ]
    details = {
        "down": [(OUTLINE, [(13, 13), (18, 13)], True),
                 (SKIN[1], [(15, 16), (16, 16)], True)],
        "right": [(OUTLINE, [(14, 13)], True),
                  (SKIN[1], [(15, 16)], True)],
        "up": [],
    }
    return dict(name="npc_orange", title="A-Zuo (carpenter)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


# =====================================================================
#  A-Xu -- scribe / clock keeper (teal)
# =====================================================================
def spec_teal():
    """Neat, upright scribe: long teal coat with a cream placket and collar,
    round spectacles, a notebook in the left hand and a quill in the right."""
    fams = {"skin": SKIN, "cloth": TEAL, "cream": CREAM,
            "leather": LEATHER}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "cloth",
             "ARM_L": "cloth", "ARM_R": "cloth", "LEG_L": "cloth",
             "LEG_R": "cloth", "CAPE": "cloth", "ACC": "cream",
             "HAIR": "leather", "BOOT": "leather", "PROP": "leather"}
    front = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 14, 43, bob=False),
        rc("LEG_R", 17, 40, 19, 43, bob=False),
        rc("TORSO", 11, 18, 20, 36),
        rc("TORSO", 9, 36, 22, 39),
        rc("TORSO", 10, 39, 21, 40),
        rc("ACC", 12, 17, 19, 18, clip=True),         # neat cream collar
        rc("ACC", 15, 19, 16, 34, clip=True),         # cream placket
        rc("PROP", 4, 31, 9, 36),                     # notebook (left hand)
        rc("ACC", 8, 32, 9, 35),                      # page edge
        rc("ARM_L", 8, 19, 10, 32),
        rc("ARM_R", 21, 19, 23, 32),
        rc("ACC", 8, 33, 10, 33),                     # cream cuffs
        rc("ACC", 21, 33, 23, 33),
        rc("HAND", 8, 34, 10, 36),
        rc("HAND", 21, 34, 23, 36),
        rr("HEAD", 10, 4, 21, 16, r=2),
        rr("HAIR", 10, 4, 21, 8, r=2, clip=True),
        rc("HAIR", 10, 8, 11, 11, clip=True),
        rc("HAIR", 20, 8, 21, 11, clip=True),
    ]
    side = [
        rc("BOOT", 11, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 16, 43, bob=False),
        rc("LEG_R", 15, 40, 19, 43, bob=False),
        rc("TORSO", 10, 18, 21, 36),
        rc("TORSO", 8, 36, 22, 39),
        rc("TORSO", 9, 39, 21, 40),
        rc("ACC", 11, 17, 20, 18, clip=True),
        rc("ACC", 15, 19, 16, 34, clip=True),
        rc("ARM_R", 17, 19, 19, 32),
        rc("ACC", 17, 33, 19, 33),
        rc("HAND", 17, 34, 19, 36),
        rc("PROP", 20, 31, 26, 36),
        rc("ACC", 25, 32, 26, 35),
        rr("HEAD", 10, 4, 21, 16, r=2),
        rr("HAIR", 10, 4, 21, 8, r=2, clip=True),
        rc("HAIR", 10, 8, 11, 11, clip=True),
    ]
    back = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 40, 14, 43, bob=False),
        rc("LEG_R", 17, 40, 19, 43, bob=False),
        rc("TORSO", 11, 18, 20, 36),
        rc("TORSO", 9, 36, 22, 39),
        rc("TORSO", 10, 39, 21, 40),
        rc("ACC", 12, 17, 19, 18, clip=True),
        rc("ARM_L", 8, 19, 10, 32),
        rc("ARM_R", 21, 19, 23, 32),
        rc("ACC", 8, 33, 10, 33),
        rc("ACC", 21, 33, 23, 33),
        rc("HAND", 8, 34, 10, 36),
        rc("HAND", 21, 34, 23, 36),
        rr("HEAD", 10, 4, 21, 16, r=2),
        rr("HAIR", 10, 4, 21, 16, r=2, clip=True),
    ]
    glasses = [(11, 9), (12, 9), (13, 9), (11, 10), (13, 10), (11, 11),
               (12, 11), (13, 11),
               (18, 9), (19, 9), (20, 9), (18, 10), (20, 10), (18, 11),
               (19, 11), (20, 11),
               (14, 10), (15, 10), (16, 10), (17, 10), (10, 10), (21, 10)]
    glasses_side = [(17, 9), (18, 9), (19, 9), (17, 10), (19, 10), (17, 11),
                    (18, 11), (19, 11), (11, 10), (12, 10), (13, 10),
                    (14, 10), (15, 10), (16, 10)]
    details = {
        "down": [(LEATHER[1], glasses, True),
                 (OUTLINE, [(12, 10), (19, 10)], True),
                 (SKIN[1], [(15, 14), (16, 14)], True)],
        "right": [(LEATHER[1], glasses_side, True),
                  (OUTLINE, [(18, 10)], True),
                  (SKIN[1], [(15, 14)], True)],
        "up": [],
    }
    return dict(name="npc_teal", title="A-Xu (scribe)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


# =====================================================================
#  A-You -- traveller / kite flyer (pink)
# =====================================================================
def spec_pink():
    """Laid-back traveller: pink shawl over a loose tunic, cream scarf, messy
    hair, a light knapsack on the back and a kite-string spool in hand."""
    fams = {"skin": SKIN, "cloth": PINK, "cream": CREAM1,
            "leather": LEATHER}
    roles = {"HEAD": "skin", "HAND": "skin", "TORSO": "cloth",
             "ARM_L": "cloth", "ARM_R": "cloth", "LEG_L": "cloth",
             "LEG_R": "cloth", "CAPE": "cloth", "ACC": "cream",
             "HAIR": "leather", "BOOT": "leather", "PROP": "leather"}
    front = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 41, 14, 43, bob=False),
        rc("LEG_R", 17, 41, 19, 43, bob=False),
        rc("TORSO", 10, 19, 21, 33),
        rc("TORSO", 8, 33, 23, 37),
        rc("TORSO", 7, 37, 10, 40),                   # loose, uneven hem
        rc("TORSO", 11, 37, 15, 41),
        rc("TORSO", 16, 37, 20, 40),
        rc("TORSO", 21, 37, 24, 39),
        rc("CAPE", 9, 17, 22, 21),                    # pink shawl
        rc("CAPE", 20, 21, 23, 27),
        rc("ACC", 11, 16, 20, 18, clip=True),         # cream scarf
        rc("ACC", 9, 18, 11, 22),
        rc("ARM_L", 7, 21, 9, 33),
        rc("ARM_R", 22, 21, 24, 33),
        rc("HAND", 7, 33, 9, 35),
        rc("HAND", 22, 33, 24, 35),
        rr("HEAD", 9, 5, 22, 17, r=2),
        rr("HAIR", 9, 5, 22, 9, r=2, clip=True),
        rc("HAIR", 8, 7, 9, 11),                      # loose side tufts
        rc("HAIR", 21, 8, 22, 12),
        rc("HAIR", 11, 3, 12, 5),                     # cowlick
    ]
    side = [
        rc("BOOT", 11, 44, 16, GROUND, bob=False),
        rc("BOOT", 15, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 41, 16, 43, bob=False),
        rc("LEG_R", 15, 41, 19, 43, bob=False),
        rc("TORSO", 10, 19, 21, 33),
        rc("TORSO", 8, 33, 22, 37),
        rc("TORSO", 6, 36, 10, 42),
        rc("TORSO", 11, 37, 20, 41),
        rc("CAPE", 9, 17, 21, 21),
        rc("CAPE", 8, 21, 10, 27),
        rc("ACC", 10, 16, 21, 18, clip=True),
        rc("ACC", 7, 18, 9, 24),
        rc("ARM_R", 16, 21, 18, 33),
        rc("HAND", 16, 33, 18, 35),
        rr("HEAD", 9, 5, 22, 17, r=2),
        rr("HAIR", 9, 5, 22, 9, r=2, clip=True),
        rc("HAIR", 9, 7, 10, 12),
    ]
    back = [
        rc("BOOT", 11, 44, 15, GROUND, bob=False),
        rc("BOOT", 16, 44, 20, GROUND, bob=False),
        rc("LEG_L", 12, 41, 14, 43, bob=False),
        rc("LEG_R", 17, 41, 19, 43, bob=False),
        rc("TORSO", 10, 19, 21, 33),
        rc("TORSO", 8, 33, 23, 37),
        rc("TORSO", 7, 37, 10, 40),
        rc("TORSO", 11, 37, 15, 41),
        rc("TORSO", 16, 37, 20, 40),
        rc("TORSO", 21, 37, 24, 39),
        rc("CAPE", 9, 17, 22, 21),
        rc("ACC", 11, 16, 20, 18, clip=True),
        rc("PROP", 11, 20, 20, 30),                   # knapsack on the back
        rc("ACC", 13, 21, 14, 29),                    # straps
        rc("ACC", 18, 21, 19, 29),
        rc("ARM_L", 7, 21, 9, 33),
        rc("ARM_R", 22, 21, 24, 33),
        rc("HAND", 7, 33, 9, 35),
        rc("HAND", 22, 33, 24, 35),
        rr("HEAD", 9, 5, 22, 17, r=2),
        rr("HAIR", 9, 5, 22, 17, r=2, clip=True),
        rc("HAIR", 8, 7, 9, 12),
        rc("HAIR", 21, 8, 22, 12),
    ]
    details = {
        "down": [(OUTLINE, [(13, 13), (18, 13)], True),
                 (SKIN[1], [(15, 16), (16, 16)], True)],
        "right": [(OUTLINE, [(14, 13)], True),
                  (SKIN[1], [(15, 16)], True)],
        "up": [],
    }
    return dict(name="npc_pink", title="A-You (kite flyer)", fams=fams,
                roles=roles, front=front, side=side, back=back,
                details=details)


SPECS = (spec_orange, spec_teal, spec_pink)

# which hand carries the permanent prop of each NPC
CARRY = {"npc_orange": "R", "npc_teal": "R", "npc_pink": "R"}
# idle-body PROP ops replaced by the animated prop
DROP_PROP = {
    "npc_orange": lambda box: box[3] >= 33,      # the hammer hanging on the belt
    "npc_teal": lambda box: box[0] <= 4,         # the notebook at the left hip
    "npc_pink": lambda box: False,               # knapsack stays on the back
}


# =====================================================================
#  held props
# =====================================================================
def prop_orange(c, tag, fr, rh, lh):
    """A plank held in front, a hammer / ruler in the right hand."""
    det = []
    if fr.get("plank") and tag != "up":
        c.rect(Z["ACC"], 9, 25, 19, 28)                     # pale pine board
        det.append((OUTLINE, [(11, 26), (14, 26), (17, 26)], False))
    p = fr.get("prop")
    x, y = rh
    if p == "hammer":
        c.rect(Z["PROP"], x, y - 4, x + 1, y)               # handle
        c.rect(Z["PROP"], x - 2, y - 6, x + 3, y - 4)       # head up
    elif p == "hammer_down":
        c.rect(Z["PROP"], x, y - 4, x + 1, y)               # handle
        c.rect(Z["PROP"], x - 2, y, x + 3, y + 2)           # head down
    elif p == "ruler":
        c.rect(Z["ACC"], x - 5, y - 1, x + 1, y)            # cream ruler
        det.append((OUTLINE, [(x - 4, y - 1), (x - 2, y - 1), (x, y - 1)],
                    False))
    return det


def prop_teal(c, tag, fr, rh, lh):
    """The notebook (open or shut) plus the quill and the seal."""
    det = []
    book = fr.get("book")
    p = fr.get("prop")
    x, y = rh
    if book == "open" and tag != "up":
        c.rect(Z["PROP"], 11, 23, 19, 29)                   # book cover
        c.rect(Z["ACC"], 12, 24, 18, 28)                    # pages
        det.append((OUTLINE, [(15, 24), (15, 25), (15, 26), (15, 27),
                              (15, 28)], False))            # spine
    elif book == "shut" and tag != "up":
        c.rect(Z["PROP"], 12, 26, 18, 30)                   # shut book
        c.rect(Z["ACC"], 17, 27, 18, 29)                    # page edge
    if p == "quill":
        c.rect(Z["ACC"], x, y - 5, x, y - 1)                # feather
        det.append((OUTLINE, [(x, y - 6)], False))          # nib
    elif p == "stamp":
        c.rect(Z["PROP"], x - 1, y - 2, x + 2, y + 1)       # seal
        det.append((ACC_DARK, [(x, y), (x + 1, y)], False))
    return det


def prop_pink(c, tag, fr, rh, lh):
    """A kite-string spool; the string is drawn by OVERLAY (it is in the air)."""
    p = fr.get("prop")
    if p in ("spool", "pull", "reel", "tuck"):
        x, y = rh
        c.rect(Z["PROP"], x - 1, y - 2, x + 1, y + 2)       # spool
        return [(CREAM1[0], [(x - 1, y - 1), (x + 1, y - 1),
                             (x - 1, y + 1), (x + 1, y + 1)], False)]
    return []


ACC_DARK = CREAM[1]
PROPS = {"npc_orange": prop_orange, "npc_teal": prop_teal,
         "npc_pink": prop_pink}


def overlay_orange(fr, rh, lh):
    """Sawdust blown off the plank: 1px cream specks in the air."""
    if fr.get("prop") != "dust":
        return []
    return [(CREAM1[0], [(11, 22), (13, 21), (16, 22), (18, 23)])]


def overlay_pink(fr, rh, lh):
    """The kite line runs from the spool up out of the frame."""
    p = fr.get("prop")
    if p not in ("spool", "pull"):
        return []
    x, y = rh
    return [(CREAM1[0], [(x, yy) for yy in range(0, y - 3)])]


OVERLAY = {"npc_orange": overlay_orange, "npc_teal": lambda f, r, l: [],
           "npc_pink": overlay_pink}


# =====================================================================
#  action frames
# =====================================================================
ORANGE_FRAMES = [
    dict(dy=1, L=(4, -1), R=(0, 0), plank=True),          # 0 carry the plank in
    dict(dy=0, L=(4, -1), R=(1, -17), plank=True,
         prop="hammer"),                                   # 1 raise the hammer
    dict(dy=1, L=(4, -1), R=(-7, -6), plank=True,
         prop="hammer_down"),                              # 2 strike
    dict(dy=1, L=(4, -1), R=(-7, -5), plank=True,
         prop="hammer_down"),                              # 3 strike again
    dict(dy=-1, L=(4, -1), R=(-4, -10), plank=True,
         prop="hammer"),                                   # 4 look at the angle
    dict(dy=1, L=(4, -1), R=(-8, -4), plank=True,
         prop="ruler"),                                    # 5 measure & mark
    dict(dy=1, L=(4, -1), R=(-11, -8), plank=True,
         prop="dust"),                                     # 6 blow the sawdust
    dict(dy=0, L=(0, 0), R=(0, 0)),                        # 7 put it down
]

TEAL_FRAMES = [
    dict(dy=0, R=(-3, -9), book="open", prop="quill"),     # 0 open the notebook
    dict(dy=0, R=(-1, -10), book="open", prop="quill"),    # 1 dip the quill
    dict(dy=0, R=(-5, -13), book="open", prop="quill"),    # 2 write
    dict(dy=0, R=(-5, -12), book="open", prop="quill"),    # 3 write on
    dict(dy=-1, R=(-3, -18), book="open", prop="quill"),   # 4 look up to check
    dict(dy=0, R=(-6, -11), book="open", prop="stamp"),    # 5 stamp it
    dict(dy=0, R=(-2, -8), book="shut"),                   # 6 close the book
    dict(dy=0, R=(2, -24), book="shut"),                   # 7 straighten glasses
]

PINK_FRAMES = [
    dict(dy=0, R=(2, -14), prop="spool"),                  # 0 raise the spool
    dict(dy=-1, R=(3, -18), prop="spool"),                 # 1 look up at the kite
    dict(dy=0, R=(1, -13), prop="pull"),                   # 2 pull the string
    dict(dy=1, R=(-1, -10), prop="pull"),                  # 3 pull harder
    dict(dy=1, R=(3, -10), prop="spool"),                  # 4 half a step
    dict(dy=-1, R=(2, -17), prop="spool"),                 # 5 laugh at the sky
    dict(dy=0, R=(2, -7), prop="reel"),                    # 6 reel it in
    dict(dy=0, R=(1, -2), prop="tuck"),                    # 7 spool on the belt
]

FRAMES = {"npc_orange": ORANGE_FRAMES, "npc_teal": TEAL_FRAMES,
          "npc_pink": PINK_FRAMES}

TITLES = {"npc_orange": "A-Zuo  orange  carpenter",
          "npc_teal": "A-Xu    teal    scribe",
          "npc_pink": "A-You   pink    kite flyer"}


def build_action_frame(spec, tag, fr):
    """One action frame: idle body with the arms and held props re-drawn."""
    ops = ga.view_ops(spec, tag)
    dy = int(fr.get("dy", 0))
    name = spec["name"]
    drop = DROP_PROP[name]
    c = gp.Canvas()
    for kind, role, (x0, y0, x1, y1), extra, bob, clip in ops:
        if role in ("ARM_L", "ARM_R", "HAND"):
            continue
        if role == "PROP" and drop((x0, y0, x1, y1)):
            continue
        d = dy if bob else 0
        mask = gp.MASKERS[kind](x0, y0 + d, x1, y1 + d, FRAME_W, FRAME_H,
                                extra)
        c.stamp(Z[role], mask, clip)

    geo = ga.arm_geo(ops)
    side = tag == "right"
    carry = CARRY[name]
    free = "L" if carry == "R" else "R"
    carry_off = fr.get(carry, (0, 0))
    free_off = fr.get(free, (0, 0))
    if "ARM_" + carry in geo:
        plan = [(carry, carry_off)]
        if "ARM_" + free in geo:
            plan.append((free, free_off))
    else:
        plan = [("R" if "ARM_R" in geo else "L", carry_off)]

    hands = {}
    for key, (dx, dyy) in plan:
        g = geo["ARM_" + key]
        if side:
            dx = int(round(dx * 0.72))
        hx, hy = g["hx"] + dx, g["hy"] + dyy + dy
        hands[key] = (hx, hy)
        ga.stamp_arm(c, g["sx"], g["sy"] + dy, "ARM_" + key, (hx, hy))
    rh = hands.get("R", (16, GROUND - 6))
    lh = hands.get("L", rh)

    det_extra = PROPS[name](c, tag, fr, rh, lh)

    pid = c.pid
    det = []
    for color, pts, bob in spec["details"].get(tag, []):
        d = dy if bob else 0
        det.append((color, [(x, y + d) for x, y in pts], False))
    det += det_extra
    spec2 = dict(spec, details={tag: det})
    arr = gp.render_npc(pid, spec2, tag, False)
    # free-floating 1px marks (kite string, sawdust) live outside the
    # silhouette, so they are composited straight onto the RGBA frame
    for color, pts in OVERLAY[name](fr, rh, lh):
        for x, y in pts:
            if 0 <= x < FRAME_W and 0 <= y < FRAME_H and arr[y, x, 3] == 0:
                arr[y, x] = (color[0], color[1], color[2], 255)
    return arr


def build_sheet(spec):
    """320x192: cols 0-1 from the plain 64x192 sheet, cols 2-9 the action loop."""
    idle = np.asarray(gp.build_npc_sheet(spec))       # 64x192, 2 cols
    sheet = np.zeros((SHEET_H, SHEET_W, 4), np.uint8)
    sheet[:, :IDLE_COLS * FRAME_W] = idle
    for r, view in enumerate(VIEWS):
        tag = ("down" if view == "down" else
               ("up" if view == "up" else "right"))
        for i, fr in enumerate(FRAMES[spec["name"]]):
            arr = build_action_frame(spec, tag, fr)
            if view == "left":
                arr = np.ascontiguousarray(np.fliplr(arr))
            c = IDLE_COLS + i
            sheet[r * FRAME_H:(r + 1) * FRAME_H,
                  c * FRAME_W:(c + 1) * FRAME_W] = arr
    return Image.fromarray(sheet)


# =====================================================================
#  portraits (32x32 busts)
# =====================================================================
def make_portrait(spec):
    c = gp.Canvas(32, 32)
    gp._bust(c)
    k = spec["name"]
    details = []
    eyes = [(12, 14), (13, 14), (12, 15), (13, 15),
            (18, 14), (19, 14), (18, 15), (19, 15)]
    if k == "npc_orange":
        c.rrect(Z["HAIR"], 9, 4, 22, 11, r=2, clip=True)
        c.rect(Z["HAIR"], 9, 10, 22, 11, clip=True)   # hairline
        c.rect(Z["HAIR"], 9, 10, 10, 18, clip=True)   # sideburns
        c.rect(Z["HAIR"], 21, 10, 22, 18, clip=True)
        c.rect(Z["ACC"], 12, 24, 13, 31, clip=True)   # apron straps
        c.rect(Z["ACC"], 18, 24, 19, 31, clip=True)
        c.rect(Z["ACC"], 13, 24, 18, 25)              # collar
        details = [(OUTLINE, eyes, False),
                   (SKIN[1], [(15, 19), (16, 19)], False)]
    elif k == "npc_teal":
        c.rrect(Z["HAIR"], 9, 4, 22, 10, r=2, clip=True)
        c.rect(Z["HAIR"], 9, 10, 10, 17, clip=True)
        c.rect(Z["HAIR"], 21, 10, 22, 17, clip=True)
        c.rect(Z["ACC"], 10, 20, 21, 24, clip=True)   # cream collar
        c.rect(Z["ACC"], 14, 24, 17, 31, clip=True)   # placket
        c.rect(Z["PROP"], 21, 26, 29, 31)             # notebook corner
        c.rect(Z["ACC"], 28, 27, 29, 30)
        rings = [(11, 11), (12, 11), (13, 11), (11, 12), (13, 12),
                 (11, 13), (12, 13), (13, 13),
                 (18, 11), (19, 11), (20, 11), (18, 12), (20, 12),
                 (18, 13), (19, 13), (20, 13),
                 (14, 12), (15, 12), (16, 12), (17, 12), (10, 12), (21, 12)]
        details = [(LEATHER[1], rings, False),
                   (OUTLINE, [(12, 12), (19, 12)], False),
                   (SKIN[1], [(15, 18), (16, 18)], False)]
    else:  # npc_pink
        c.rrect(Z["HAIR"], 9, 4, 22, 10, r=2, clip=True)
        c.rect(Z["HAIR"], 8, 8, 9, 15)                # loose tufts
        c.rect(Z["HAIR"], 22, 8, 23, 16)
        c.rect(Z["HAIR"], 10, 2, 12, 4)               # cowlick
        c.rect(Z["HAIR"], 20, 1, 21, 3)
        c.rect(Z["CAPE"], 5, 25, 26, 27)              # shawl
        c.rect(Z["CAPE"], 6, 27, 9, 31)
        c.rect(Z["ACC"], 10, 21, 21, 24, clip=True)   # cream scarf
        c.rect(Z["ACC"], 8, 24, 10, 30)
        details = [(OUTLINE, eyes, False),
                   (SKIN[1], [(15, 19), (16, 19)], False)]
    pid = c.pid
    return gp.render_npc(pid, dict(spec, details={"portrait": details}),
                         "portrait", False)


# =====================================================================
#  preview (4x nearest, labelled)
# =====================================================================
def build_preview(sheets, portraits):
    k = 4
    margin, gap, line_h = 20, 16, 22
    font = ga._font(18)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))

    def tw(text):
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[2] - b[0])

    tile_w = SHEET_W * k
    title_h = line_h + 6
    block = title_h + SHEET_H * k + gap + line_h
    prow_w = len(portraits) * (32 * k + gap) - gap
    width = max(tile_w, prow_w, tw("gen_npc_extra.py -- orange / teal / pink"))
    width += margin * 2
    ptitle = "portraits 32x32 -- orange A-Zuo / teal A-Xu / pink A-You"
    height = margin * 2 + len(sheets) * block + line_h + 32 * k + line_h

    canvas = ga._checker(width, height)
    draw = ImageDraw.Draw(canvas)
    for i, (name, img) in enumerate(sheets):
        top = margin + i * block
        draw.text((margin, top), "%s.png  320x192  --  %s"
                  % (name, TITLES[name]), fill=(240, 240, 240, 255),
                  font=font)
        big = img.resize((img.width * k, img.height * k),
                         Image.Resampling.NEAREST)
        canvas.alpha_composite(big, (margin, top + title_h))
        base_y = top + title_h + SHEET_H * k + 2
        for col in range(COLS):
            label = ("idle" if col == 0 else
                     ("breath" if col == 1 else "a%d" % (col - 1)))
            draw.text((margin + col * FRAME_W * k, base_y), label,
                      fill=(205, 214, 224, 255), font=font)
    top = margin + len(sheets) * block
    draw.text((margin, top), ptitle, fill=(240, 240, 240, 255), font=font)
    x = margin
    for name, img in portraits:
        big = img.resize((32 * k, 32 * k), Image.Resampling.NEAREST)
        canvas.alpha_composite(big, (x, top + line_h))
        draw.text((x, top + line_h + 32 * k + 2), name,
                  fill=(205, 214, 224, 255), font=font)
        x += 32 * k + gap
    return canvas


# =====================================================================
#  verification
# =====================================================================
def _hex(c):
    return "#%02X%02X%02X" % (int(c[0]), int(c[1]), int(c[2]))


def _frame(arr, r, c):
    return arr[r * FRAME_H:(r + 1) * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W]


def _hsv(rgb):
    r, g, b = (float(v) / 255.0 for v in rgb[:3])
    mx, mn = max(r, g, b), min(r, g, b)
    v = mx
    s = 0.0 if mx == 0 else (mx - mn) / mx
    return s, v


def verify_sheet(name, img):
    arr = np.asarray(img)
    print("[%s.png]  %s" % (name, TITLES[name]))
    ok = (img.width, img.height) == (SHEET_W, SHEET_H)
    print("  sheet size %dx%d (expected %dx%d): %s"
          % (img.width, img.height, SHEET_W, SHEET_H,
             "PASS" if ok else "FAIL"))

    empty = [(r, c) for r in range(ROWS) for c in range(COLS)
             if not (_frame(arr, r, c)[..., 3] > 0).any()]
    ok &= not empty
    print("  all %d frames non-empty: %s"
          % (ROWS * COLS, "PASS" if not empty else "FAIL %s" % empty))
    grid_ok = all((_frame(arr, r, c)[..., 3] > 0).any()
                  for r in range(ROWS) for c in range(COLS))
    ok &= grid_ok
    print("  4 directions x 10 columns populated: %s"
          % ("PASS" if grid_ok else "FAIL"))

    grounds = []
    for r in range(ROWS):
        for c in range(COLS):
            a = _frame(arr, r, c)[..., 3] > 0
            grounds.append(int(np.nonzero(a)[0].max()))
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

    opaque = arr[arr[..., 3] > 0][:, :3]
    cols = sorted({tuple(int(v) for v in px)
                   for px in np.unique(opaque, axis=0)})
    n_ok = 4 <= len(cols) <= 10
    ok &= n_ok
    print("  opaque colours: %d (limit 10): %s"
          % (len(cols), "PASS" if n_ok else "FAIL"))
    hot = [c for c in cols if _hsv(c)[0] >= 0.85 or _hsv(c)[1] >= 0.95]
    hot_ok = not hot
    ok &= hot_ok
    print("  no fluorescent colours (S<0.85, V<0.95): %s"
          % ("PASS" if hot_ok else "FAIL %s" % [_hex(c) for c in hot]))
    print("  palette: %s" % ", ".join(_hex(c) for c in cols))
    mean = opaque.astype(np.float32).mean(axis=0)
    bright = float((0.2126 * opaque[:, 0] + 0.7152 * opaque[:, 1]
                    + 0.0722 * opaque[:, 2]).mean())
    print("  mean RGB (%.1f, %.1f, %.1f)  mean luminance %.1f/255  %s"
          % (mean[0], mean[1], mean[2], bright, _hex(mean.round().astype(int))))

    mirror_ok = all(np.array_equal(_frame(arr, 1, c),
                                   np.fliplr(_frame(arr, 2, c)))
                    for c in range(COLS))
    ok &= mirror_ok
    print("  left row == mirror(right row), all 10 columns: %s"
          % ("PASS" if mirror_ok else "FAIL"))

    diffs = []
    for r in range(ROWS):
        idle = _frame(arr, r, 0)
        diffs.append(sum(0 if np.array_equal(_frame(arr, r, IDLE_COLS + i),
                                             idle) else 1
                         for i in range(ACTION_COLS)))
    diff_ok = all(n >= 6 for n in diffs)
    ok &= diff_ok
    print("  action frames differ from idle (need >= 6/8): %s %s"
          % (diffs, "PASS" if diff_ok else "FAIL"))
    return ok


def verify_portrait(name, img):
    arr = np.asarray(img)
    print("[%s.png]  32x32" % name)
    ok = (img.width, img.height) == (32, 32)
    print("  size %dx%d (expected 32x32): %s"
          % (img.width, img.height, "PASS" if ok else "FAIL"))
    filled = bool((arr[..., 3] > 0).any())
    ok &= filled
    print("  non-empty: %s" % ("PASS" if filled else "FAIL"))
    trans = arr[arr[..., 3] == 0]
    tmax = int(trans[:, :3].max()) if trans.size else 0
    has_trans = trans.size > 0
    ok &= tmax == 0 and has_trans
    print("  transparent background %d px, all RGB 0: %s"
          % (len(trans), "PASS" if tmax == 0 and has_trans else "FAIL"))
    vals = sorted(set(int(v) for v in np.unique(arr[..., 3])))
    bin_ok = set(vals) <= {0, 255}
    ok &= bin_ok
    print("  binary alpha: %s: %s" % (vals, "PASS" if bin_ok else "FAIL"))
    opaque = arr[arr[..., 3] > 0][:, :3]
    cols = sorted({tuple(int(v) for v in px)
                   for px in np.unique(opaque, axis=0)})
    n_ok = 4 <= len(cols) <= 12
    ok &= n_ok
    print("  opaque colours: %d (limit 12): %s"
          % (len(cols), "PASS" if n_ok else "FAIL"))
    sil = arr[..., 3] > 0
    npad = np.pad(sil, 1)
    inner = (npad[:-2, 1:-1] & npad[2:, 1:-1]
             & npad[1:-1, :-2] & npad[1:-1, 2:])
    boundary = sil & ~inner
    want = np.array(OUTLINE, np.uint8)
    is_line = np.all(arr[..., :3] == want, axis=-1)
    ratio = float((boundary & is_line).sum()) / max(int(boundary.sum()), 1)
    line_ok = ratio >= 0.90
    ok &= line_ok
    print("  1px #1B1B1B outline on the silhouette: %.1f%%: %s"
          % (ratio * 100.0, "PASS" if line_ok else "FAIL"))
    print("  palette: %s" % ", ".join(_hex(c) for c in cols))
    return ok


# =====================================================================
#  main
# =====================================================================
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("=" * 74)
    print("gen_npc_extra.py   out=%s" % OUT_DIR)
    print("=" * 74)

    sheets, portraits = [], []
    for make in SPECS:
        spec = make()
        img = build_sheet(spec)
        img.save(OUT_DIR / (spec["name"] + ".png"))
        sheets.append((spec["name"], img))
        print("[wrote] %-20s %dx%d %s"
              % (spec["name"] + ".png", img.width, img.height, img.mode))
        pimg = Image.fromarray(make_portrait(spec))
        pname = "portrait_" + spec["name"].split("_")[1]
        pimg.save(OUT_DIR / (pname + ".png"))
        portraits.append((pname, pimg))
        print("[wrote] %-20s %dx%d %s"
              % (pname + ".png", pimg.width, pimg.height, pimg.mode))

    preview = build_preview(sheets, portraits)
    preview.save(OUT_DIR / "_preview_npc_extra.png")
    print("[wrote] %-20s %dx%d %s"
          % ("_preview_npc_extra.png", preview.width, preview.height,
             preview.mode))

    print("\n--- verification " + "-" * 55)
    ok = True
    for name, img in sheets:
        ok &= verify_sheet(name, img)
        print()
    for name, img in portraits:
        ok &= verify_portrait(name, img)
        print()
    ok &= (OUT_DIR / "_preview_npc_extra.png").is_file()

    print("--- action summary " + "-" * 52)
    for name in ("npc_orange", "npc_teal", "npc_pink"):
        print("  %-11s %s" % (name + ":", TITLES[name]))
        for i, fr in enumerate(FRAMES[name]):
            print("      col %d  f%d  dy=%+d  prop=%s"
                  % (IDLE_COLS + i, i, fr.get("dy", 0),
                     fr.get("prop") or "-"))
    print("\nRESULT:", "PASS - all checks green" if ok
          else "FAIL - see above")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
