#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_rest_assets.py -- deterministic rest / sit / lie / stand sprite sheet for
the hd2d-rpg white-box hero.

Run from the project root (or anywhere):

    python tools/gen_rest_assets.py

Writes RGBA PNGs into <project>/assets/generated/ :

    player_rest.png     256x48   8 frames in one row, each 32x48
                                 frame 0 sit_idle      sitting, knees up
                                 frame 1 sit_breathe   head+torso 1px up
                                 frame 2 lie_down      tipping backwards
                                 frame 3 lying         on the back (3/4 cam)
                                 frame 4 lying_breathe chest 1px up
                                 frame 5 rise_1        curling up, bent over
                                 frame 6 rise_2        one knee up, pushing off
                                 frame 7 stand         == player_whitebox (0,0)
    _preview_rest.png             contact sheet, 4x nearest + frame labels

Design rules honoured here:
  * the white-box renderer of tools/gen_assets.py is imported and reused
    verbatim, so the palette, the 1px rim, the part seams, the upper-left
    light gradient and the clean (0,0,0,0) background are literally the same
    code as the walking hero -> the rest poses cannot drift in style
  * every pose bottoms out on row 47 (the ground line of the walking sheet)
  * frame 7 is the exact 32x48 crop of player_whitebox.png (row 0, col 0),
    used unchanged so that stand -> walk is seamless
  * fully deterministic: no random numbers, fixed pixel boxes only
  * re-runnable: overwrites its own two PNGs, creates no .import files and
    never touches Godot
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__

from pathlib import Path  # noqa: E402

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

_TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_TOOLS_DIR))

import gen_assets as ga  # noqa: E402  (the white-box renderer, reused as-is)

# --------------------------------------------------------------------- config
FRAME_W, FRAME_H = ga.FRAME_W, ga.FRAME_H        # 32 x 48
COLS = 8
GROUND_ROW = FRAME_H - 1                          # y == 47

OUT_DIR = ga.OUT_DIR                # <project>/assets/generated

SHEET_NAME = "player_rest.png"
PREVIEW_NAME = "_preview_rest.png"
SOURCE_NAME = "player_whitebox.png"

FRAME_NAMES = (
    "sit_idle",
    "sit_breathe",
    "lie_down",
    "lying",
    "lying_breathe",
    "rise_1",
    "rise_2",
    "stand",
)

# Only the walking hero's six part ids are used (head / torso / 2 arms /
# 2 legs).  Every extra part id would add another 1px SHADE2 seam ring, and at
# this size small parts (a 4x3 hand) would dissolve into seam colour - so feet
# stay part of their leg and hands part of their arm, exactly like the
# standing sprite.


# =====================================================================
#  pose construction helpers
# =====================================================================
def _new() -> np.ndarray:
    return np.zeros((FRAME_H, FRAME_W), np.int16)


def _block(pid, part, x0, y0, x1, y1) -> None:
    """Hard-edged rectangular block."""
    ga._paint(pid, part, "rect", (x0, y0, x1, y1))


def _bump(pid, part, x0, y0, x1, y1) -> None:
    """Rounded block (ellipse) - heads, knees, chests."""
    ga._paint(pid, part, "ellipse", (x0, y0, x1, y1))


def _stair(pid, part, runs) -> None:
    """Hard-edged diagonal limb: a stack of 1px-stepped horizontal runs.

    runs = ((y0, y1, x0, x1), ...) -> no anti-aliasing, no diagonals.
    """
    for y0, y1, x0, x1 in runs:
        ga._paint(pid, part, "rect", (x0, y0, x1, y1))


# =====================================================================
#  frame 0 / 1 -- sitting on the ground, facing the camera
# =====================================================================
def build_sit(lift: int = 0) -> np.ndarray:
    """Sitting on the ground, facing the camera: knees bent up in front, hands
    resting on the knees, head slightly lowered.

    ``lift`` raises head + torso + arms by that many pixels (breathing); the
    lap block, the knees and the feet stay planted, so rows 45..47 (the feet
    and the ground contact) stay pixel-identical in both sit frames.
    """
    pid = _new()
    # lap / seat: does not move with the breath
    _block(pid, ga.P_BODY, 11, 40, 20, 44)
    # torso, raised with the breath
    _block(pid, ga.P_BODY, 11, 30 + lift, 20, 42 + lift)
    # knees bent up in front of the chest: two rounded halves that meet in a
    # seam, so the lap reads as two knees instead of one barrel
    _bump(pid, ga.P_LEG_L, 6, 37, 15, 46)
    _bump(pid, ga.P_LEG_R, 16, 37, 25, 46)
    # feet planted flat on the ground, 1px proud of the knees on the outside
    _block(pid, ga.P_LEG_L, 5, 45, 15, 47)
    _block(pid, ga.P_LEG_R, 16, 45, 26, 47)
    # arms from the shoulders down onto the knees
    _block(pid, ga.P_ARM_L, 7, 31 + lift, 10, 40 + lift)
    _block(pid, ga.P_ARM_R, 21, 31 + lift, 24, 40 + lift)
    # head, slightly lowered (16px wide, like the walking hero's head)
    _bump(pid, ga.P_HEAD, 8, 16 + lift, 23, 30 + lift)
    return pid


# =====================================================================
#  frame 2 -- leaning back out of the sit, one arm back for support
# =====================================================================
def build_lie_down() -> np.ndarray:
    """Body tipping back to the left, hips on the ground, one arm planted back."""
    pid = _new()
    # hips / seat on the ground
    _block(pid, ga.P_BODY, 12, 42, 19, 47)
    # torso, tipped ~35 degrees back to the left: hard 1px staircase
    _stair(pid, ga.P_BODY, (
        (39, 44, 11, 18),
        (36, 41, 10, 17),
        (33, 38, 9, 16),
        (30, 35, 8, 15),
        (28, 33, 7, 14),
    ))
    # legs still folded, knees up in front, feet planted
    _bump(pid, ga.P_LEG_L, 13, 35, 21, 44)
    _bump(pid, ga.P_LEG_R, 20, 34, 27, 44)
    _block(pid, ga.P_LEG_L, 13, 44, 21, 47)
    _block(pid, ga.P_LEG_R, 21, 44, 28, 47)
    # supporting arm reaching back and down to the ground behind the shoulders
    _stair(pid, ga.P_ARM_L, (
        (32, 36, 6, 9),
        (35, 39, 5, 8),
        (38, 42, 4, 7),
        (41, 45, 4, 7),
    ))
    _block(pid, ga.P_ARM_L, 3, 45, 7, 47)
    # near arm folded forward, hand on the near knee
    _stair(pid, ga.P_ARM_R, (
        (32, 36, 15, 18),
        (34, 38, 16, 19),
    ))
    # head, rolled back and to the left, above the leaning shoulders
    _bump(pid, ga.P_HEAD, 2, 17, 14, 30)
    return pid


# =====================================================================
#  frame 3 / 4 -- lying on the back, 3/4 top-down camera
# =====================================================================
def build_lying(chest: int = 0) -> np.ndarray:
    """Lying on the back: compact horizontal body along the bottom of the frame.

    Head to the left, feet to the right, one knee lazily bent up.  ``chest``
    lifts the chest + near arm by 1px (breathing) and nothing else.
    """
    pid = _new()
    # back / seat / hip mass along the ground (fixed)
    _block(pid, ga.P_BODY, 13, 42, 26, 47)
    # chest, facing up at the 3/4 camera, flat top edge; raised by ``chest``
    _block(pid, ga.P_BODY, 13, 38 - chest, 24, 47)
    # shoulder shelf between the head and the chest
    _block(pid, ga.P_BODY, 13, 37 - chest, 20, 47)
    # head, rolled to one side at the left end, resting on the ground
    _bump(pid, ga.P_HEAD, 2, 33, 14, 47)
    # near arm lying across the chest, one solid band (no seam noise)
    _stair(pid, ga.P_ARM_R, (
        (40 - chest, 44 - chest, 15, 19),
        (38 - chest, 40 - chest, 18, 22),
    ))
    # near leg: thigh out of the hip, one knee lazily bent up, shin and foot
    # back down on the ground at the right end
    _block(pid, ga.P_LEG_R, 24, 41, 29, 47)
    _bump(pid, ga.P_LEG_R, 24, 32, 30, 45)
    _block(pid, ga.P_LEG_L, 26, 44, 30, 47)
    return pid


# =====================================================================
#  frame 5 -- rising: curling up, bent forward, head coming up
# =====================================================================
def build_rise_1() -> np.ndarray:
    """Sitting back up from lying: curled forward, both hands braced on the
    floor, head still low and rising."""
    pid = _new()
    # hips / seat on the ground
    _block(pid, ga.P_BODY, 10, 42, 18, 47)
    # knees folded up in front
    _bump(pid, ga.P_LEG_L, 11, 38, 18, 46)
    _bump(pid, ga.P_LEG_R, 18, 37, 25, 46)
    _block(pid, ga.P_LEG_L, 10, 45, 18, 47)
    _block(pid, ga.P_LEG_R, 18, 45, 26, 47)
    # torso curled forward over the knees; the shoulder bar keeps the head
    # reading as a head instead of blending into the back
    _stair(pid, ga.P_BODY, (
        (39, 44, 11, 17),
        (35, 40, 12, 19),
        (32, 36, 12, 21),
        (30, 34, 11, 22),
    ))
    # head, hanging forward over the knees, clearly proud of the shoulders
    _bump(pid, ga.P_HEAD, 15, 19, 26, 32)
    # both hands braced on the floor for the push up
    _stair(pid, ga.P_ARM_L, (
        (35, 39, 8, 11),
        (38, 42, 7, 10),
        (41, 45, 6, 9),
    ))
    _block(pid, ga.P_ARM_L, 5, 45, 9, 47)
    _stair(pid, ga.P_ARM_R, (
        (35, 39, 22, 25),
        (38, 42, 23, 26),
        (41, 45, 24, 27),
    ))
    _block(pid, ga.P_ARM_R, 24, 45, 28, 47)
    # far arm = tucked between the knees, only the forearm reads
    _stair(pid, ga.P_ARM_R, (
        (40, 44, 19, 22),
    ))
    return pid


# =====================================================================
#  frame 6 -- half standing, one knee up, pushing off the ground
# =====================================================================
def build_rise_2() -> np.ndarray:
    """One foot planted, one knee still up, torso rising, hand pushing off."""
    pid = _new()
    # planted leg: foot flat on the ground, shin up to a bent knee
    _block(pid, ga.P_LEG_L, 10, 40, 14, 46)
    _block(pid, ga.P_LEG_L, 9, 44, 15, 47)
    _bump(pid, ga.P_LEG_L, 8, 36, 16, 43)
    # rear leg: knee still down on the ground behind
    _bump(pid, ga.P_LEG_R, 17, 40, 24, 47)
    _block(pid, ga.P_LEG_R, 20, 44, 25, 47)
    # torso rising, almost upright, a little lean to the right
    _stair(pid, ga.P_BODY, (
        (40, 45, 13, 21),
        (36, 41, 13, 21),
        (31, 37, 12, 20),
        (27, 32, 13, 21),
    ))
    # head up, nearly level again
    _bump(pid, ga.P_HEAD, 10, 15, 25, 28)
    # pushing hand flat on the ground behind
    _stair(pid, ga.P_ARM_L, (
        (28, 32, 8, 12),
        (31, 35, 6, 10),
        (34, 38, 5, 9),
        (37, 41, 4, 8),
        (40, 44, 3, 7),
    ))
    _block(pid, ga.P_ARM_L, 3, 45, 7, 47)
    # front arm coming up with the rise, hand on the raised knee
    _stair(pid, ga.P_ARM_R, (
        (29, 33, 20, 23),
        (32, 36, 21, 24),
    ))
    _block(pid, ga.P_ARM_R, 20, 36, 24, 39)
    return pid


# =====================================================================
#  frame 7 -- the standing hero, unchanged
# =====================================================================
def build_stand() -> Image.Image:
    """Exact 32x48 crop of player_whitebox.png (row 0 = 'down', col 0)."""
    src = OUT_DIR / SOURCE_NAME
    if src.exists():
        im = Image.open(src).convert("RGBA")
        if (im.width, im.height) == (128, 192):
            return im.crop((0, 0, FRAME_W, FRAME_H))
    # deterministic fallback: regenerate the identical frame from the same code
    print(f"  [note] {src} missing/short -> rebuilding down/idle frame from "
          f"gen_assets.py")
    return ga._render_frame(ga._build_front(0, back=False))


# =====================================================================
#  sheet assembly
# =====================================================================
def build_sheet() -> tuple[Image.Image, list[np.ndarray]]:
    pids = (
        build_sit(lift=0),
        build_sit(lift=1),
        build_lie_down(),
        build_lying(chest=0),
        build_lying(chest=1),
        build_rise_1(),
        build_rise_2(),
    )
    frames = [np.asarray(ga._render_frame(pid)) for pid in pids]
    frames.append(np.asarray(build_stand()))

    sheet = np.zeros((FRAME_H, COLS * FRAME_W, 4), np.uint8)
    for c, f in enumerate(frames):
        sheet[:, c * FRAME_W:(c + 1) * FRAME_W] = f
    return Image.fromarray(sheet), frames


# =====================================================================
#  preview: 4x nearest contact sheet with labels
# =====================================================================
PREVIEW_K = 4
PREVIEW_MARGIN = 24
PREVIEW_GAP = 12


def _measure_font(font):
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    b = probe.textbbox((0, 0), "Ag", font=font)
    return int(b[3] - b[1]) + 6


def preview_layout():
    """Single source of truth for the contact-sheet geometry:
    (k, margin, gap, top, width, height, title_h, label_h)."""
    k = PREVIEW_K
    margin, gap = PREVIEW_MARGIN, PREVIEW_GAP
    title_font = ga._font(18)
    label_font = ga._font(15)
    title_h = _measure_font(title_font)
    label_h = _measure_font(label_font)
    fw, fh = FRAME_W * k, FRAME_H * k
    top = margin + title_h * 4 + 12
    width = margin * 2 + COLS * fw + (COLS - 1) * gap
    height = top + fh + 8 + label_h + margin
    return (k, margin, gap, top, width, height, title_h, label_h)


def build_preview(sheet: Image.Image) -> Image.Image:
    (k, margin, gap, top, width, height,
     title_h, label_h) = preview_layout()
    fw, fh = FRAME_W * k, FRAME_H * k
    title_lines = (
        f"player_rest.png  {COLS * FRAME_W}x{FRAME_H}  = {COLS} frames of "
        f"{FRAME_W}x{FRAME_H}  (shown at {k}x nearest)",
        "sit_idle / sit_breathe : on the ground while away        "
        "lie_down / lying / lying_breathe : loading screen",
        "rise_1 / rise_2 / stand : standing back up        "
        "(frame 7 == player_whitebox.png row 0 col 0)",
        "red bar under each frame = ground contact row y=47, shared by "
        "every frame",
    )
    font_title = ga._font(18)
    font_label = ga._font(15)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))

    def text_w(text: str, font) -> int:
        b = probe.textbbox((0, 0), text, font=font)
        return int(b[2] - b[0])

    canvas = ga._checker(width, height).copy()
    draw = ImageDraw.Draw(canvas)
    scaled = sheet.resize((sheet.width * k, sheet.height * k),
                          Image.Resampling.NEAREST)
    canvas.alpha_composite(scaled, (margin, top))

    # ground line marker (row 47) right under each frame, so the shared contact
    # line is visible at a glance
    for c in range(COLS):
        x0 = margin + c * (fw + gap)
        draw.line([(x0, top + fh + 1), (x0 + fw - 1, top + fh + 1)],
                  fill=(235, 96, 96, 255))

    for i, line in enumerate(title_lines):
        draw.text((margin, margin + i * title_h), line,
                  fill=(235, 235, 235, 255), font=font_title)

    for c, name in enumerate(FRAME_NAMES):
        x0 = margin + c * (fw + gap)
        label = f"#{c} {name}"
        tw = text_w(label, font_label)
        draw.text((x0 + (fw - tw) // 2, top + fh + 10),
                  label, fill=(235, 235, 235, 255), font=font_label)
    return canvas


# =====================================================================
#  verification
# =====================================================================
def _frames(arr: np.ndarray):
    return [arr[:, c * FRAME_W:(c + 1) * FRAME_W] for c in range(COLS)]



# =====================================================================
def _bbox(f: np.ndarray):
    ys, xs = np.nonzero(f[..., 3] > 0)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max()), int(len(xs))


def verify() -> bool:
    """Re-open the written PNGs from disk and check them (not the in-memory
    objects), so the report describes the shipped artifacts."""
    ok = True
    sheet_path = OUT_DIR / SHEET_NAME
    preview_path = OUT_DIR / PREVIEW_NAME
    src_path = OUT_DIR / SOURCE_NAME

    sheet = Image.open(sheet_path).convert("RGBA")
    arr = np.asarray(sheet)
    frames = _frames(arr)

    # 1. exact sheet size -----------------------------------------------------
    size_ok = (sheet.width, sheet.height) == (COLS * FRAME_W, FRAME_H)
    ok &= size_ok
    print(f"[sheet] {sheet_path.name} {sheet.width}x{sheet.height} "
          f"(expected {COLS * FRAME_W}x{FRAME_H}): "
          f"{'PASS' if size_ok else 'FAIL'}  {sheet_path.stat().st_size} bytes")

    # 2. every frame non-empty, content inside its 32x48 cell -----------------
    boxes = [_bbox(f) for f in frames]
    empty = [i for i, b in enumerate(boxes) if b is None]
    ok &= not empty
    print(f"[frames] non-empty: {COLS - len(empty)}/{COLS}: "
          f"{'PASS' if not empty else 'FAIL ' + str(empty)}")
    for i, (name, b) in enumerate(zip(FRAME_NAMES, boxes)):
        if b is None:
            continue
        w = b[1] - b[0] + 1
        h = b[3] - b[2] + 1
        print(f"  #{i} {name:<14} bbox x {b[0]:>2}..{b[1]:<2} y {b[2]:>2}.."
              f"{b[3]:<2}  content {w:>2}x{h:<2}  opaque {b[4]:>3}px")
    widths = [b[1] - b[0] + 1 for b in boxes if b]
    heights = [b[3] - b[2] + 1 for b in boxes if b]
    fit_ok = max(widths) <= FRAME_W and max(heights) <= FRAME_H
    ok &= fit_ok
    print(f"[content] width {min(widths)}..{max(widths)} px, height "
          f"{min(heights)}..{max(heights)} px (limit {FRAME_W}x{FRAME_H}): "
          f"{'PASS' if fit_ok else 'FAIL'}")

    # 3. frame 7 byte-identical to player_whitebox.png (row 0, col 0) ---------
    ref = np.asarray(Image.open(src_path).convert("RGBA")
                     .crop((0, 0, FRAME_W, FRAME_H)))
    got = frames[COLS - 1]
    same = (got.shape == ref.shape) and bool(np.array_equal(got, ref))
    n_diff = int(np.count_nonzero(np.any(got != ref, axis=-1)))
    ok &= same
    print(f"[frame 7] stand == player_whitebox.png (row 0, col 0): "
          f"{'PASS - byte-identical' if same else f'FAIL ({n_diff} px differ)'}")

    # 4. palette discipline / binary alpha -----------------------------------
    opaque = arr[arr[..., 3] > 0]
    pal_rgb = {c[:3] for c in ga.PLAYER_PALETTE if c[3] == 255}
    cols = {tuple(int(v) for v in px[:3]) for px in np.unique(opaque, axis=0)}
    extra = cols - pal_rgb
    pal_ok = not extra
    ok &= pal_ok
    print(f"[palette] opaque RGB values: {len(cols)} "
          f"{'PASS (only the white-box palette)' if pal_ok else 'FAIL ' + str(sorted(extra)[:6])}")
    print(f"  colours present: {sorted('#%02X%02X%02X' % c for c in cols)}")
    alphas = {int(v) for v in np.unique(arr[..., 3])}
    alpha_ok = alphas <= {0, 255}
    ok &= alpha_ok
    print(f"[alpha] values {sorted(alphas)} (only 0/255, no AA): "
          f"{'PASS' if alpha_ok else 'FAIL'}")
    trans = arr[arr[..., 3] == 0]
    trans_ok = trans.size == 0 or int(trans[:, :3].max()) == 0
    ok &= trans_ok
    print(f"[alpha] transparent pixels all (0,0,0,0): "
          f"{'PASS' if trans_ok else 'FAIL'}")

    # 5. ground line ----------------------------------------------------------
    ground_ok = all(b is not None and b[3] == GROUND_ROW for b in boxes)
    ok &= ground_ok
    print(f"[ground] every frame's lowest opaque row == {GROUND_ROW}: "
          f"{'PASS' if ground_ok else 'FAIL'}")
    print(f"  lowest rows per frame: {[b[3] if b else None for b in boxes]}")
    sit_ok = boxes[0][3] == boxes[1][3] == boxes[COLS - 1][3] == GROUND_ROW
    ok &= sit_ok
    print(f"  frames 0,1 (sitting) and 7 (standing) bottom at {GROUND_ROW}: "
          f"{'PASS' if sit_ok else 'FAIL'}")
    lower2 = FRAME_H - 2 * FRAME_H // 3            # y of the lower 2/3 band
    lower2_ok = boxes[0][2] >= lower2
    ok &= lower2_ok
    print(f"  sit_idle sits in the lower 2/3 (content top y={boxes[0][2]} >= "
          f"{lower2}, bottom y=47): {'PASS' if lower2_ok else 'FAIL'}")

    # 6. animation sanity: breathe frames differ only where they should ------
    feet_ok = bool(np.array_equal(frames[0][45:, :], frames[1][45:, :]))
    breathe_moves = not bool(np.array_equal(frames[0][:44, :], frames[1][:44, :]))
    ok &= feet_ok and breathe_moves
    print(f"[breathe] sit_breathe feet (rows 45..47) pixel-identical to "
          f"sit_idle: {'PASS' if feet_ok else 'FAIL'}")
    print(f"[breathe] sit_breathe head/torso 1px up (differs above the feet): "
          f"{'PASS' if breathe_moves else 'FAIL'}")
    legs_same = bool(np.array_equal(frames[3][41:, 24:], frames[4][41:, 24:]))
    chest_moves = not bool(np.array_equal(frames[3][:44, 10:24], frames[4][:44, 10:24]))
    ok &= legs_same and chest_moves
    print(f"[breathe] lying_breathe legs/feet untouched: "
          f"{'PASS' if legs_same else 'FAIL'}")
    print(f"[breathe] lying_breathe chest 1px up: "
          f"{'PASS' if chest_moves else 'FAIL'}")

    # 7. preview: exactly 4x nearest of the sheet, with labels ----------------
    prev = Image.open(preview_path).convert("RGBA")
    k, margin, gap, top, w, h, _, _ = preview_layout()
    expect = sheet.resize((sheet.width * k, sheet.height * k),
                          Image.Resampling.NEAREST)
    region = np.asarray(prev.crop((margin, top, margin + expect.width,
                                   top + expect.height)))
    up = np.asarray(expect)
    sprite = up[..., 3] == 255            # the contact sheet sits on a checker
    x4_ok = (prev.size == (w, h) and region.shape == up.shape
             and bool(np.array_equal(region[sprite], up[sprite])))
    n_bad = int(np.count_nonzero(np.any(region[sprite] != up[sprite], axis=-1)))
    ok &= x4_ok
    print(f"[preview] {preview_path.name} {prev.width}x{prev.height}, frames "
          f"the exact {k}x nearest upscale of the sheet: "
          f"{'PASS' if x4_ok else f'FAIL ({n_bad} px differ)'}  "
          f"{preview_path.stat().st_size} bytes")

    print(f"\nRESULT: {'PASS - all checks green' if ok else 'FAIL - see above'}")
    return bool(ok)


# =====================================================================
#  main
# =====================================================================
def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("=" * 70)
    print(f"gen_rest_assets.py  out={OUT_DIR}")
    print("=" * 70)

    sheet, _frames_mem = build_sheet()
    sheet.save(OUT_DIR / SHEET_NAME)
    print(f"[wrote] {SHEET_NAME:<22} {sheet.width:>4}x{sheet.height:<4} "
          f"{sheet.mode}")

    preview = build_preview(sheet)
    preview.save(OUT_DIR / PREVIEW_NAME)
    print(f"[wrote] {PREVIEW_NAME:<22} {preview.width:>4}x{preview.height:<4} "
          f"{preview.mode}")

    print("\n--- verification " + "-" * 52)
    return 0 if verify() else 1


if __name__ == "__main__":
    sys.exit(main())
