"""Generate one 2D standing illustration per NPC, matching their personality.
These are transparent 128x192 pixel-art PNGs used by the dialogue illustration
panel and as the reference for the 3D model silhouettes.
"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated")
SIZE = (128, 192)
INK = (32, 23, 17, 255)


def rgba(hex_color):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def dark(color, amount=0.35):
    return tuple(int(c * (1.0 - amount)) for c in color[:3]) + (255,)


def light(color, amount=0.25):
    return tuple(min(255, int(c + (255 - c) * amount)) for c in color[:3]) + (255,)


def poly(draw, pts, fill, outline=INK, width=2):
    draw.polygon(pts, fill=fill, outline=outline, width=width)


def rect(draw, box, fill, outline=INK, width=2):
    draw.rectangle(box, fill=fill, outline=outline, width=width)


def ellipse(draw, box, fill, outline=INK, width=2):
    draw.ellipse(box, fill=fill, outline=outline, width=width)


def line(draw, pts, fill=INK, width=2):
    draw.line(pts, fill=fill, width=width, joint="curve")


def make_base(width, height, skin, cloth, pants, boot, hair):
    img = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # soft colour halo so the portrait separates from the scenery
    d.ellipse((12, 10, 116, 180), fill=cloth[:3] + (18,))
    # legs
    leg_top = 122
    lx = 64 - width // 2
    for side in (-1, 1):
        x = 64 + side * (width // 3)
        rect(d, (x - 7, leg_top, x + 7, 162), pants)
        rect(d, (x - 10, 161, x + 10, 173), boot)
    # torso silhouette
    shoulder = 74
    poly(d, [(64 - width // 2, shoulder), (64 + width // 2, shoulder),
             (64 + width // 2 + 3, 126), (64 - width // 2 - 3, 126)], cloth)
    # arms
    for side in (-1, 1):
        x = 64 + side * (width // 2 + 2)
        rect(d, (x - 6, shoulder + 4, x + 6, 122), cloth)
        ellipse(d, (x - 7, 120, x + 7, 134), skin)
    # neck
    rect(d, (56, 64, 72, 78), skin)
    # head
    if height < 1.0:
        head_box = (46, 20, 82, 58)
    elif height > 1.03:
        head_box = (44, 16, 84, 57)
    else:
        head_box = (45, 18, 83, 58)
    ellipse(d, head_box, skin)
    # hair/hats are added by the caller on top
    return img, d


def add_face(d, look="neutral", glasses=False, freckles=False, smile=1):
    # eyes
    d.ellipse((53, 38, 59, 44), fill=INK)
    d.ellipse((69, 38, 75, 44), fill=INK)
    d.ellipse((51, 33, 57, 36), fill=INK)
    d.ellipse((71, 33, 77, 36), fill=INK)
    # nose/mouth
    line(d, [(64, 45), (62, 49)], width=1)
    if smile:
        line(d, [(59, 53), (64, 55), (69, 53)], width=1)
    else:
        line(d, [(60, 54), (68, 54)], width=1)
    if freckles:
        for x in (51, 56, 72, 77):
            d.point((x, 49), fill=(150, 92, 68, 255))
    if glasses:
        d.ellipse((49, 35, 61, 47), outline=(65, 60, 48, 255), width=2)
        d.ellipse((67, 35, 79, 47), outline=(65, 60, 48, 255), width=2)
        line(d, [(61, 41), (67, 41)], width=2)


def add_hat(d, brim_w, crown_w, crown_h, colour, band=None):
    ellipse(d, (64 - brim_w // 2, 16, 64 + brim_w // 2, 27), colour)
    rect(d, (64 - crown_w // 2, 5, 64 + crown_w // 2, 5 + crown_h), colour)
    if band:
        rect(d, (64 - crown_w // 2 - 1, 5 + crown_h - 5, 64 + crown_w // 2 + 1, 5 + crown_h), band, width=1)


def add_long_hair(d, colour, side_bob=True):
    poly(d, [(44, 32), (40, 70), (50, 76), (52, 50)], colour)
    poly(d, [(84, 32), (88, 70), (78, 76), (76, 50)], colour)
    if side_bob:
        ellipse(d, (37, 34, 52, 72), colour)
        ellipse(d, (76, 34, 91, 72), colour)


def add_satchel(d, colour, strap_colour):
    rect(d, (86, 100, 110, 126), colour)
    rect(d, (89, 97, 108, 102), light(colour, 0.15))
    line(d, [(46, 76), (96, 104)], strap_colour, width=3)


def add_apron(d, colour, pocket=None):
    poly(d, [(48, 88), (80, 88), (84, 128), (44, 128)], colour)
    line(d, [(48, 88), (58, 76)], INK, 2)
    line(d, [(80, 88), (70, 76)], INK, 2)
    if pocket:
        rect(d, (54, 104, 74, 116), pocket, width=1)


def add_scarf(d, colour):
    rect(d, (48, 70, 80, 80), colour)
    poly(d, [(55, 79), (64, 100), (70, 79)], colour)


def make_red():
    cloth = rgba("b43a32")
    img, d = make_base(34, 1.02, rgba("e0b08a"), cloth, rgba("4a3330"), rgba("3a261f"), rgba("3a261c"))
    add_long_hair(d, rgba("3d271b"), False)
    add_face(d, smile=1)
    add_hat(d, 50, 34, 8, rgba("c94338"))
    # scarf tail
    poly(d, [(76, 76), (90, 94), (82, 99), (72, 82)], rgba("e0c37a"))
    add_satchel(d, rgba("6d4328"), rgba("3b281c"))
    # letters
    rect(d, (98, 88, 110, 98), rgba("e9d6a8"), width=1)
    line(d, [(100, 91), (108, 91)], rgba("8b6b45"), 1)
    return img


def make_yellow():
    cloth = rgba("c59a30")
    img, d = make_base(30, 0.95, rgba("e4b990"), cloth, rgba("403b3a"), rgba("332a23"), rgba("30241a"))
    # side-parted hair
    poly(d, [(44, 24), (64, 13), (84, 24), (88, 43), (78, 37), (68, 29), (56, 35), (44, 43)], rgba("35261b"))
    add_face(d, glasses=True, smile=1)
    # white shirt + deep vest
    poly(d, [(50, 74), (78, 74), (82, 120), (46, 120)], rgba("e7dfc9"))
    poly(d, [(48, 76), (64, 90), (80, 76), (84, 120), (44, 120)], rgba("3b3732"))
    rect(d, (46, 121, 82, 126), rgba("6b4b2b"))
    # cravat and watch chain
    poly(d, [(58, 72), (64, 84), (70, 72)], rgba("d8c49a"))
    for i in range(4):
        d.point((76 + i, 100 + i * 2), fill=(228, 188, 70, 255))
    d.ellipse((82, 106, 89, 113), fill=(220, 170, 55, 255), outline=INK)
    return img


def make_green():
    cloth = rgba("4f8538")
    img, d = make_base(38, 0.97, rgba("d9a87e"), cloth, rgba("4a4532"), rgba("443020"), rgba("3b291b"))
    add_long_hair(d, rgba("5c3c22"), True)
    add_face(d, freckles=True, smile=1)
    add_hat(d, 60, 36, 20, rgba("d5b35e"), rgba("a85a42"))
    # apron
    add_apron(d, rgba("e4ddc4"), rgba("c8bea1"))
    # flower badge
    d.ellipse((74, 78, 82, 86), fill=(232, 152, 154, 255), outline=INK)
    d.ellipse((77, 76, 81, 80), fill=(246, 218, 112, 255), outline=INK)
    # gloves
    for x in (40, 88):
        ellipse(d, (x - 7, 115, x + 7, 128), rgba("b0a081"))
    return img


def make_blue():
    cloth = rgba("2d4b74")
    img, d = make_base(32, 1.04, rgba("d4a57e"), cloth, rgba("30343c"), rgba("2b2827"), rgba("1f1b1a"))
    # long coat
    add_long_hair(d, rgba("231f1c"), False)
    add_face(d, smile=0)
    add_hat(d, 48, 32, 13, rgba("2b3b55"), rgba("b34b3e"))
    # coat lapels and tails
    poly(d, [(48, 74), (64, 90), (80, 74), (84, 128), (44, 128)], cloth)
    line(d, [(58, 76), (64, 91), (70, 76)], rgba("d4bf9e"), 2)
    rect(d, (42, 120, 58, 142), dark(cloth))
    rect(d, (70, 120, 86, 142), dark(cloth))
    add_scarf(d, rgba("b34a38"))
    # small lantern
    rect(d, (90, 94, 105, 120), rgba("5b5144"))
    rect(d, (93, 97, 102, 116), rgba("f3c963"))
    line(d, [(97, 90), (97, 95)], INK, 2)
    return img


def make_purple():
    cloth = rgba("74549c")
    img, d = make_base(30, 1.0, rgba("dfb08d"), cloth, rgba("393346"), rgba("3a2a24"), rgba("4a2d21"))
    add_long_hair(d, rgba("6f422c"), True)
    add_face(d, smile=1)
    add_hat(d, 66, 34, 14, rgba("5f437f"), rgba("c99c50"))
    # paint smock
    poly(d, [(48, 86), (80, 86), (84, 130), (44, 130)], rgba("e9e3d2"))
    for x, y, c in [(52, 96, "b34a5a"), (60, 112, "4e82b3"), (72, 102, "d9a54b"),
                    (76, 120, "9b5a86"), (56, 122, "6e9a64")]:
        d.rectangle((x, y, x + 6, y + 4), fill=rgba(c), outline=None)
    # brush
    line(d, [(84, 72), (100, 42)], rgba("5b3b25"), 4)
    line(d, [(100, 42), (105, 31)], rgba("e4c46a"), 3)
    # palette
    ellipse(d, (88, 112, 110, 128), rgba("b98a58"))
    for x, y, c in [(93, 116, "c64b51"), (101, 114, "4b8fb5"), (97, 121, "e0c45d")]:
        d.ellipse((x, y, x + 5, y + 5), fill=rgba(c), outline=None)
    return img


def make_orange():
    cloth = rgba("bd7338")
    img, d = make_base(42, 1.02, rgba("d8a37b"), cloth, rgba("4b4030"), rgba("3d2b1d"), rgba("3a281b"))
    add_long_hair(d, rgba("3b271b"), False)
    add_face(d, smile=1)
    add_hat(d, 46, 34, 7, rgba("8f5b32"))
    add_apron(d, rgba("76502f"), rgba("5d3f27"))
    # belt and tools
    rect(d, (43, 120, 85, 126), rgba("3b2a1e"))
    for x, c in [(49, "a5a49c"), (60, "d0b46a"), (72, "8d6a48")]:
        rect(d, (x, 116, x + 6, 125), rgba(c))
    # hammer
    line(d, [(88, 100), (101, 120)], rgba("5a452f"), 4)
    rect(d, (97, 117, 108, 125), rgba("66615a"))
    # gloves
    for x in (40, 88):
        ellipse(d, (x - 7, 113, x + 7, 127), rgba("9d8769"))
    return img


def make_pink():
    cloth = rgba("c97083")
    img, d = make_base(28, 0.94, rgba("e5b795"), cloth, rgba("5a4a4c"), rgba("40302b"), rgba("6d3d2c"))
    # loose hair + feather
    add_long_hair(d, rgba("8a5134"), True)
    add_face(d, smile=1)
    line(d, [(78, 18), (98, 2)], rgba("e2c36e"), 4)
    line(d, [(82, 19), (103, 9)], rgba("f0e0b0"), 2)
    add_scarf(d, rgba("e39aa6"))
    # poncho
    poly(d, [(46, 80), (82, 80), (92, 132), (36, 132)], rgba("d9b49b"))
    line(d, [(46, 128), (82, 128)], rgba("9d6f5b"), 2)
    # kite spool
    ellipse(d, (86, 116, 108, 130), rgba("7a5533"))
    line(d, [(96, 126), (114, 92)], rgba("d8c7a1"), 1)
    poly(d, [(104, 82), (114, 94), (104, 102), (96, 92)], rgba("d87289"))
    return img


def make_teal():
    cloth = rgba("38776f")
    img, d = make_base(28, 1.03, rgba("d9ab84"), cloth, rgba("3b3f40"), rgba("2e2924"), rgba("2e241e"))
    # bun and high collar
    ellipse(d, (52, 12, 76, 32), rgba("3b2a1e"))
    line(d, [(64, 22), (64, 12)], INK, 2)
    add_face(d, glasses=True, smile=0)
    # long robe
    poly(d, [(46, 76), (82, 76), (86, 138), (42, 138)], cloth)
    rect(d, (46, 72, 82, 82), dark(cloth, 0.35))
    line(d, [(58, 82), (64, 96), (70, 82)], rgba("d8ccb2"), 2)
    # book satchel
    rect(d, (82, 102, 108, 128), rgba("5a3d26"))
    rect(d, (86, 99, 104, 104), rgba("d0bf9b"))
    line(d, [(44, 78), (92, 106)], rgba("5a3d26"), 3)
    # bookmark
    rect(d, (88, 109, 94, 127), rgba("d8c277"), width=1)
    line(d, [(90, 109), (90, 124)], rgba("8e4b42"), 2)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    builders = {
        "red": make_red, "yellow": make_yellow, "green": make_green, "blue": make_blue,
        "purple": make_purple, "orange": make_orange, "pink": make_pink, "teal": make_teal,
    }
    for npc_id, builder in builders.items():
        image = builder()
        path = os.path.join(OUT, "npc_illustration_%s.png" % npc_id)
        image.save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
