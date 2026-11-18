"""Generate an 8-direction x 4-frame wooden-puppet walk sheet for the HD2D hero.
Direction rows: down, down-right, right, up-right, up, up-left, left, down-left.
"""
from PIL import Image, ImageDraw
import os

W, H = 32, 48
ROWS = 8
COLS = 4
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "player_puppet_8dir.png")
INK = (52, 32, 19, 255)
WOOD = (170, 121, 73, 255)
WOOD_L = (207, 164, 108, 255)
WOOD_D = (116, 76, 42, 255)
BRASS = (200, 154, 66, 255)
SCARF = (68, 101, 158, 255)
SCARF_D = (40, 63, 112, 255)
HAT = (213, 179, 103, 255)
HAT_D = (160, 124, 64, 255)
HEART = (36, 23, 15, 255)


def rect(d, x, y, w, h, fill, outline=INK, width=1):
    d.rectangle((x, y, x + w - 1, y + h - 1), fill=fill, outline=outline, width=width)


def px(d, x, y, fill):
    d.point((x, y), fill=fill)


def draw_legs(d, cx, side, phase, profile):
    # alternate raised leg; profile view gets a horizontal stride
    lift_l = 1 if phase in (1, 2) else 0
    lift_r = 1 if phase in (3, 0) else 0
    base_y = 33
    for i, (xoff, lift) in enumerate(((-4, lift_l), (4, lift_r))):
        x = cx + xoff
        y = base_y - lift
        if profile:
            x += (-2 if i == 0 else 2) + (1 if phase in (1, 2) else -1)
        rect(d, x - 2, y, 4, 9, WOOD_D)
        px(d, x - 1, y + 9, INK)
        px(d, x + 1, y + 9, INK)
        rect(d, x - 3, y + 10, 6, 3, (93, 60, 34, 255))


def draw_arm(d, x, y, phase, i, profile):
    swing = (-2, 0, 2, 0)[phase]
    if i == 0:
        swing = -swing
    rect(d, x, y + swing, 3, 10, WOOD_L)
    rect(d, x, y + 9 + swing, 4, 3, WOOD)


def draw_puppet(d, direction, phase):
    side = direction in ("right", "up-right", "down-right")
    left = direction in ("left", "up-left", "down-left")
    diagonal = direction not in ("down", "up", "left", "right")
    back = direction in ("up", "up-left", "up-right")
    profile = direction in ("left", "right")
    shift = 2 if side else (-2 if left else 0)
    if side and direction == "right":
        shift = 3
    if left:
        shift = -3
    cx = 16 + shift
    bob = 1 if phase % 2 == 1 else 0

    draw_legs(d, cx, side, phase, profile)
    # torso
    tw = 9 if profile else (10 if diagonal else 11)
    rect(d, cx - tw // 2, 21 + bob, tw, 13, WOOD, width=1)
    # waist
    rect(d, cx - tw // 2, 31 + bob, tw, 3, WOOD_D)
    # heart-shaped cavity on front-facing / 3/4 frames
    if not (back or profile):
        hx = cx
        hy = 24 + bob
        rect(d, hx - 2, hy, 2, 2, HEART, outline=None)
        rect(d, hx, hy, 2, 2, HEART, outline=None)
        d.polygon([(hx - 2, hy + 1), (hx + 2, hy + 1), (hx, hy + 5)], fill=HEART)
        px(d, hx - 3, hy, BRASS)
        px(d, hx + 2, hy, BRASS)
        px(d, hx, hy + 5, BRASS)
    # arms
    draw_arm(d, cx - tw // 2 - 4, 22 + bob, phase, 0, profile)
    draw_arm(d, cx + tw // 2 + 1, 22 + bob, phase, 1, profile)
    # neck / scarf
    rect(d, cx - 2, 18 + bob, 4, 4, WOOD_L, width=0)
    rect(d, cx - tw // 2 - 1, 18 + bob, tw + 2, 3, SCARF, width=0)
    if direction in ("down", "down-right", "down-left"):
        rect(d, cx + 4, 19 + bob, 2, 7, SCARF_D, width=0)
    # head
    hx = cx + (1 if side else (-1 if left else 0))
    hy = 8 + bob
    d.ellipse((hx - 5, hy, hx + 5, hy + 11), fill=WOOD_L, outline=INK)
    # hair cap / hat
    d.arc((hx - 6, hy - 2, hx + 6, hy + 8), 180, 360, fill=WOOD_D, width=3)
    d.ellipse((hx - 8, hy - 2, hx + 8, hy + 3), fill=HAT, outline=INK)
    rect(d, hx - 4, hy - 6, 8, 4, HAT, width=1)
    rect(d, hx - 5, hy - 2, 10, 2, HAT_D, width=0)
    # face or back of head
    if not back:
        eye_y = hy + 5
        if profile:
            d.rectangle((hx + 1, eye_y, hx + 2, eye_y + 1), fill=INK)
            d.point((hx, eye_y + 4), fill=(180, 100, 78, 255))
        else:
            d.rectangle((hx - 4, eye_y, hx - 3, eye_y + 1), fill=INK)
            d.rectangle((hx + 2, eye_y, hx + 3, eye_y + 1), fill=INK)
            d.point((hx - 3, eye_y + 1), fill=(240, 226, 195, 255))
            d.point((hx + 3, eye_y + 1), fill=(240, 226, 195, 255))
            d.rectangle((hx - 4, eye_y + 4, hx - 3, eye_y + 4), fill=(174, 92, 74, 255))
            d.rectangle((hx + 3, eye_y + 4, hx + 4, eye_y + 4), fill=(174, 92, 74, 255))
            d.line((hx - 1, eye_y + 5, hx + 1, eye_y + 5), fill=INK)
    else:
        # back seams and hair
        d.line((hx, hy + 2, hx, hy + 8), fill=WOOD_D)
        d.line((hx - 4, hy + 7, hx + 4, hy + 7), fill=WOOD_D)
    # brass shoulder pins
    px(d, cx - tw // 2 - 2, 23 + bob, BRASS)
    px(d, cx + tw // 2 + 1, 23 + bob, BRASS)


def main():
    image = Image.new("RGBA", (W * COLS, H * ROWS), (0, 0, 0, 0))
    directions = ["down", "down-right", "right", "up-right", "up", "up-left", "left", "down-left"]
    for row, direction in enumerate(directions):
        for col in range(COLS):
            frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            d = ImageDraw.Draw(frame)
            draw_puppet(d, direction, col)
            image.alpha_composite(frame, (col * W, row * H))
    image.save(os.path.abspath(OUT))
    print("wrote", os.path.abspath(OUT), image.size)


if __name__ == "__main__":
    main()
