"""Trees for the world map (our own, CC0). Run from the project root:

    python tools/make_map_trees.py

One row of 12x14 cells in assets/map/trees.png, each a tree standing upright with its foot at the bottom middle,
lit from the upper left, with a soft shadow to the lower right: three broadleaf (jungle), two palms (coasts), two
pines (high ground). scripts/tree_layer.gd scatters them over the land; the cell order matches its BROADLEAF, PALMS and PINES.
Replace the file with hand-made pixel art in the same layout.
"""
import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
W, H = 12, 14
CLEAR = (0, 0, 0, 0)
SHADOW = (8, 26, 18, 110)
TRUNK = [(70, 46, 30, 255), (104, 72, 44, 255), (138, 100, 62, 255)]
LEAF = [(20, 48, 32, 255), (34, 80, 44, 255), (52, 112, 56, 255), (84, 146, 66, 255), (138, 184, 88, 255)]
PALM = [(30, 66, 34, 255), (62, 118, 48, 255), (102, 156, 62, 255), (160, 198, 92, 255)]
PINE = [(16, 46, 40, 255), (28, 70, 56, 255), (44, 98, 70, 255), (82, 134, 90, 255)]


def shadow(img, cx, cy, rx, ry):
    for y in range(H):
        for x in range(W):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                img.putpixel((x, y), SHADOW)


def trunk(img, x, y0, y1):
    for y in range(y0, y1 + 1):
        img.putpixel((x, y), TRUNK[1])
        if x + 1 < W:
            img.putpixel((x + 1, y), TRUNK[0])


def broadleaf(seed, r):
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, H), CLEAR)
    shadow(img, 7.0, 12.5, 4.2, 1.3)
    trunk(img, 5, 9, 12)
    blobs = [(6.0, 6.0, r)] + [(6.0 + rng.uniform(-2.2, 2.2), 6.0 + rng.uniform(-1.5, 1.0), r * rng.uniform(0.55, 0.75)) for _ in range(3)]
    inside = lambda x, y: any((x + 0.5 - bx) ** 2 + (y + 0.5 - by) ** 2 <= br * br for bx, by, br in blobs)
    for y in range(H):
        for x in range(W):
            if not inside(x, y):
                continue
            # light from the upper left: how far toward it this pixel lies within its nearest clump
            bx, by, br = min(blobs, key=lambda b: (x + 0.5 - b[0]) ** 2 + (y + 0.5 - b[1]) ** 2 - b[2] ** 2)
            t = ((bx - x - 0.5) + (by - y - 0.5)) / (br * 1.4)
            edge = not inside(x + 1, y) or not inside(x, y + 1)
            k = 0 if edge else (4 if t > 0.55 else 3 if t > 0.15 else 2 if t > -0.35 else 1)
            if k == 2 and rng.random() < 0.18:  # leafy speckle
                k = 3
            img.putpixel((x, y), LEAF[k])
    return img


def palm(lean):
    img = Image.new("RGBA", (W, H), CLEAR)
    shadow(img, 7.5, 12.5, 3.5, 1.1)
    top = (6 + lean, 4)
    for y in range(4, 13):  # a thin trunk curving up to the crown
        x = round(6 + lean * ((12 - y) / 8) ** 2)
        img.putpixel((x, y), TRUNK[2] if y % 2 else TRUNK[1])
    for ang, length in [(-150, 5.0), (-30, 5.0), (-105, 3.0), (-75, 3.0), (170, 4.5), (10, 4.5)]:
        a = math.radians(ang)
        i = 0.0
        while i <= length:  # half steps: a frond is one unbroken stroke
            x = round(top[0] + math.cos(a) * i)
            y = round(top[1] + math.sin(a) * i + 0.16 * i * i)  # fronds droop
            if 0 <= x < W and 0 <= y < H:
                img.putpixel((x, y), PALM[3] if i < 1.5 else PALM[2] if math.sin(a) < 0 else PALM[1])
                if i > 2.0 and 0 <= y + 1 < H and img.getpixel((x, y + 1))[3] == 0:
                    img.putpixel((x, y + 1), PALM[0])  # the frond's shaded underside
            i += 0.5
    img.putpixel(top, PALM[3])
    return img


# Pines are small enough to draw by hand: h lit, m mid, d dark, o shade, t/T trunk, s shadow.
PINES = [
    ["............", ".....md.....", ".....hd.....", "....hmdd....", "...hmmddo...", "....hmdo....", "...hmmddd...",
     "..hhmmdddo..", "...hmmddo...", "..hmmmdddd..", ".hhmmmddddo.", "..oooooooo..", ".....tTss...", "....ssss...."],
    ["............", "............", "............", ".....md.....", ".....hd.....", "....hmdd....", "....hmdo....",
     "...hmmddd...", "...hmmddo...", "..hhmmdddd..", "..ooooooo...", ".....tT.....", ".....tTss...", "....ssss...."],
]


def pine(rows):
    img = Image.new("RGBA", (W, H), CLEAR)
    colour = {"h": PINE[3], "m": PINE[2], "d": PINE[1], "o": PINE[0], "t": TRUNK[1], "T": TRUNK[0], "s": SHADOW}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in colour:
                img.putpixel((x, y), colour[ch])
    return img


sheet = Image.new("RGBA", (W * 7, H), CLEAR)
for i, tree in enumerate([broadleaf(1, 4.4), broadleaf(2, 3.8), broadleaf(3, 3.3), palm(1), palm(-1), pine(PINES[0]), pine(PINES[1])]):
    sheet.paste(tree, (i * W, 0))
out = ROOT / "assets" / "map" / "trees.png"
sheet.save(out)
print("wrote", out.relative_to(ROOT))
