"""Pixel art for the Octopath-style look (our own, CC0). Run from the project root:

    python tools/make_pixel_art.py

HD pixel art: drawn pixel by pixel at full resolution (1 art pixel = 1 screen pixel at normal zoom), with small
ramps of colour, ordered dithering for gradients, and light from the upper left. The top bar icons are the one
exception (16 px, scaled x3). Output:
  assets/ui/pixel/      window frame, buttons, tabs, fields, tooltip, top bar strip (9-slice textures)
  assets/icons/hud/     top bar pictograms (light, for the dark bar)
  assets/ships_side/    side-view ships for the HD-2D battle: hull, hull_damaged, sails, sails_torn + layout.json
  assets/ships/         the map's ships from above: hull, hull_damaged, sails_furled/half/full/torn
  assets/battle/        backdrop props: island, cloud, rock
Replace any file with hand-made pixel art at the same path.
"""
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "assets"

# Octopath-ish window palette: deep navy glass, gold trim.
NAVY = (14, 18, 36, 238)
NAVY_2 = (24, 30, 56, 245)
NAVY_HI = (40, 50, 92, 250)
NAVY_LO = (9, 11, 22, 250)
GOLD = (201, 164, 92, 255)
GOLD_HI = (244, 214, 140, 255)
GOLD_LO = (122, 98, 51, 255)
BLACK = (4, 5, 10, 255)
GREY = (90, 92, 110, 255)
CLEAR = (0, 0, 0, 0)


def up(img, k):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path.relative_to(ROOT))


# ---- UI frames ----------------------------------------------------------------------------

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(len(a)))


def dith(a, b, t, x, y):
    """Ordered dithering between two colours: t=0 all a, t=1 all b."""
    return b if t * 16 > BAYER[y % 4][x % 4] + 0.5 else a


GOLD_4 = [(92, 66, 30, 255), (150, 112, 52, 255), (206, 168, 92, 255), (246, 218, 146, 255), (255, 244, 206, 255)]

# Corner filigree, read from the top-left corner inward: 4 brightest .. 1 darkest gold, . nothing.
CORNER = [
    "....4433........",
    "...43...........",
    "..43..3.........",
    ".43..343........",
    "43..3.4.3.......",
    "4..343.343......",
    "3...4...4.2.....",
    "3..3.3...2......",
    "....3....1......",
    ".....2.21.......",
    "......2.........",
    "................",
]


def ornate_frame(w, h, top, bottom, corner=True, trim=True, bevel=2):
    """A window at full resolution: a dithered glass gradient, a bevelled gold border, an inner trim line and
    filigree corners. Light from the upper left: top and left edges catch it, bottom and right fall in shade."""
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    for y in range(h):  # an even fine dither of two close tones: it tiles, so windows of any size stay crisp
        for x in range(w):
            px[x, y] = top if (x + y) % 2 else bottom
    for y in range(2 + bevel, 6 + bevel):  # a sheen of light across the top of the glass
        for x in range(w):
            px[x, y] = mix(px[x, y], (255, 255, 255, 255), 0.05 * (6 + bevel - y))
    # outline, then the bevel rings
    for x in range(w):
        px[x, 0] = BLACK
        px[x, h - 1] = BLACK
    for y in range(h):
        px[0, y] = BLACK
        px[w - 1, y] = BLACK
    for r in range(1, 1 + bevel):
        lit, mid, shade = GOLD_4[3 if r == 1 else 2], GOLD_4[2], GOLD_4[1 if r == 1 else 0]
        for x in range(r, w - r):
            px[x, r] = lit if x < w - r - 1 else mid
            px[x, h - 1 - r] = shade if x > r else mid
        for y in range(r, h - r):
            px[r, y] = lit if y < h - r - 1 else mid
            px[w - 1 - r, y] = shade if y > r else mid
    r = 1 + bevel
    for x in range(r, w - r):  # a dark line inside the gold, so the glass reads as set in a frame
        px[x, r] = BLACK if top[3] > 200 else (0, 0, 0, 160)
        px[x, h - 1 - r] = (0, 0, 0, 160)
    for y in range(r, h - r):
        px[r, y] = (0, 0, 0, 160)
        px[w - 1 - r, y] = (0, 0, 0, 160)
    if trim:  # a thin inner gold line, broken at the corners where the filigree sits
        k = r + 3
        for x in range(k + 10, w - k - 10):
            px[x, k] = GOLD_4[1]
            px[x, h - 1 - k] = GOLD_4[1]
        for y in range(k + 10, h - k - 10):
            px[k, y] = GOLD_4[1]
            px[w - 1 - k, y] = GOLD_4[1]
    for cx, cy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:  # rounded corners
        px[cx, cy] = CLEAR
    if corner:
        for row, line in enumerate(CORNER):
            for col, ch in enumerate(line):
                if ch == ".":
                    continue
                c = GOLD_4[int(ch)]
                for fx, fy in [(0, 0), (1, 0), (0, 1), (1, 1)]:
                    x = r + 1 + col if fx == 0 else w - 2 - r - col
                    y = r + 1 + row if fy == 0 else h - 2 - r - row
                    if 0 <= x < w and 0 <= y < h:
                        px[x, y] = c
    return im


def button_face(w, h, top, bottom, lit, shade, inset=False):
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = top if (x + y) % 2 else bottom
    for x in range(w):
        px[x, 0] = BLACK
        px[x, h - 1] = BLACK
    for y in range(h):
        px[0, y] = BLACK
        px[w - 1, y] = BLACK
    a, b = (shade, lit) if inset else (lit, shade)
    for x in range(1, w - 1):
        px[x, 1] = a
        px[x, h - 2] = b
    for y in range(1, h - 1):
        px[1, y] = a
        px[w - 2, y] = b
    if not inset:  # a glint of light along the top of the glass
        for x in range(3, w - 3):
            px[x, 2] = mix(top, (255, 255, 255, 255), 0.18)
    for cx, cy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]:
        px[cx, cy] = CLEAR if cx in (0, w - 1) and cy in (0, h - 1) else BLACK
    return im


def make_ui():
    out = A / "ui" / "pixel"
    glass_top, glass_bot = (20, 26, 50, 242), (14, 18, 38, 242)
    save(ornate_frame(64, 64, glass_top, glass_bot), out / "panel.png")                  # 9-slice margin 18
    save(ornate_frame(24, 24, glass_top, glass_bot, corner=False, trim=False, bevel=1), out / "tooltip.png")
    navy_t, navy_b = (32, 41, 76, 255), (26, 33, 62, 255)
    save(button_face(24, 24, navy_t, navy_b, GOLD_4[3], GOLD_4[1]), out / "button.png")  # margin 6
    save(button_face(24, 24, (52, 66, 118, 255), (44, 56, 102, 255), GOLD_4[4], GOLD_4[2]), out / "button_hover.png")
    save(button_face(24, 24, (12, 16, 32, 255), (16, 20, 40, 255), GOLD_4[3], GOLD_4[1], inset=True), out / "button_pressed.png")
    save(button_face(24, 24, (30, 34, 52, 140), (26, 30, 46, 140), (96, 98, 112, 255), (60, 62, 74, 255)), out / "button_disabled.png")
    save(button_face(24, 24, (8, 10, 22, 255), (11, 14, 28, 255), GOLD_4[1], GOLD_4[2], inset=True), out / "field.png")
    save(button_face(24, 24, (24, 31, 58, 255), (20, 26, 50, 255), GOLD_4[2], GOLD_4[0]), out / "tab.png")
    save(button_face(24, 24, (56, 70, 126, 255), (48, 60, 110, 255), GOLD_4[4], GOLD_4[2]), out / "tab_on.png")
    # the top bar: glass that tiles sideways, with a bevelled gold rail and studs along the bottom
    w, h = 32, 68
    bar = Image.new("RGBA", (w, h), CLEAR)
    px = bar.load()
    for y in range(58):  # smooth bands (no dither: the bar can stretch a little in height)
        for x in range(w):
            px[x, y] = mix((8, 10, 22, 248), (28, 36, 68, 248), y / 57)
    rail = [BLACK, GOLD_4[3], GOLD_4[2], GOLD_4[2], GOLD_4[1], GOLD_4[0], BLACK]
    for k, c in enumerate(rail):
        for x in range(w):
            px[x, 57 + k] = c
    for sx in (7, 23):  # studs
        for dx, dy, c in [(0, -1, GOLD_4[4]), (-1, 0, GOLD_4[3]), (0, 0, GOLD_4[4]), (1, 0, GOLD_4[2]), (0, 1, GOLD_4[1])]:
            px[sx + dx, 60 + dy] = c
    for k in range(4):  # a soft shadow under the rail onto the map
        for x in range(w):
            px[x, 64 + k] = (0, 0, 0, 90 - k * 22)
    save(bar, out / "topbar.png")


# ---- HUD icons (16x16, light on dark) ---------------------------------------------------

def icon(draw_fn):
    im = Image.new("RGBA", (16, 16), CLEAR)
    draw_fn(ImageDraw.Draw(im), im)
    # a dark outline around everything drawn, so it reads on any background
    out = im.copy()
    px = im.load()
    for y in range(16):
        for x in range(16):
            if px[x, y][3] == 0 and any(0 <= x + dx < 16 and 0 <= y + dy < 16 and px[x + dx, y + dy][3] > 0
                                        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]):
                out.putpixel((x, y), BLACK)
    return up(out, 3)


IVORY = (236, 228, 205, 255)
SKY = (120, 170, 230, 255)
RED = (214, 82, 64, 255)
GREEN = (110, 190, 110, 255)
BROWN = (150, 100, 56, 255)
BROWN_LO = (98, 62, 34, 255)


def make_icons():
    out = A / "icons" / "hud"
    def gold(d, im):
        d.ellipse([3, 4, 12, 13], fill=GOLD_LO); d.ellipse([3, 3, 12, 12], fill=GOLD); d.ellipse([5, 5, 10, 10], outline=GOLD_HI)
    def crew(d, im):
        d.ellipse([5, 2, 10, 7], fill=IVORY); d.rectangle([3, 9, 12, 14], fill=SKY); d.line([3, 9, 12, 9], fill=IVORY)
    def morale(d, im):  # a tankard
        d.rectangle([4, 4, 10, 14], fill=BROWN); d.rectangle([4, 3, 10, 5], fill=IVORY); d.rectangle([11, 6, 13, 11], outline=BROWN_LO)
        d.line([6, 6, 6, 13], fill=BROWN_LO); d.line([9, 6, 9, 13], fill=BROWN_LO)
    def hold(d, im):  # a barrel
        d.rectangle([4, 2, 11, 14], fill=BROWN); d.line([4, 5, 11, 5], fill=GOLD_LO); d.line([4, 11, 11, 11], fill=GOLD_LO)
        d.line([3, 4, 3, 12], fill=BROWN); d.line([12, 4, 12, 12], fill=BROWN)
    def hull(d, im):
        d.polygon([(1, 8), (14, 8), (12, 13), (3, 13)], fill=BROWN); d.line([2, 9, 13, 9], fill=GOLD); d.line([7, 2, 7, 8], fill=IVORY)
    def sails(d, im):
        d.line([4, 1, 4, 14], fill=BROWN); d.polygon([(5, 2), (13, 4), (12, 12), (5, 12)], fill=IVORY); d.line([6, 7, 11, 7], fill=(190, 182, 160, 255))
    def notoriety(d, im):  # a skull
        d.ellipse([3, 2, 12, 11], fill=IVORY); d.rectangle([5, 10, 10, 13], fill=IVORY)
        d.rectangle([5, 6, 6, 7], fill=BLACK); d.rectangle([9, 6, 10, 7], fill=BLACK); d.point([7, 12], fill=BLACK); d.point([8, 12], fill=BLACK)
    def contracts(d, im):  # a scroll with a seal
        d.rectangle([3, 2, 12, 13], fill=IVORY); d.line([5, 5, 10, 5], fill=GREY); d.line([5, 8, 10, 8], fill=GREY); d.ellipse([9, 10, 13, 14], fill=RED)
    def unrest(d, im):  # crossed cutlasses
        d.line([2, 13, 13, 2], fill=IVORY, width=2); d.line([2, 2, 13, 13], fill=IVORY, width=2); d.point([2, 13], fill=GOLD); d.point([2, 2], fill=GOLD)
    def sick(d, im):  # a bottle with a cross
        d.rectangle([5, 1, 10, 3], fill=BROWN); d.rectangle([4, 4, 11, 14], fill=GREEN); d.line([7, 6, 7, 12], fill=IVORY); d.line([5, 9, 10, 9], fill=IVORY)
    def date(d, im):  # an hourglass
        d.line([3, 1, 12, 1], fill=BROWN); d.line([3, 14, 12, 14], fill=BROWN)
        d.polygon([(4, 2), (11, 2), (8, 8), (7, 8)], fill=IVORY); d.polygon([(7, 8), (8, 8), (11, 13), (4, 13)], fill=GOLD)
    for name, fn in [("gold", gold), ("crew", crew), ("morale", morale), ("hold", hold), ("hull", hull), ("sails", sails),
                     ("notoriety", notoriety), ("contracts", contracts), ("unrest", unrest), ("sick", sick), ("date", date)]:
        save(icon(fn), out / f"{name}.png")


# ---- ships: shared palette and helpers --------------------------------------------------------

W_DD = (34, 20, 12, 255)
W_D = (62, 38, 22, 255)
W_M = (98, 62, 34, 255)
W_L = (136, 92, 52, 255)
W_H = (176, 128, 78, 255)
DECK_L = (190, 146, 96, 255)
DECK_M = (160, 118, 74, 255)
COPPER = [(70, 104, 86, 255), (96, 132, 104, 255)]
S_D = (110, 98, 76, 255)      # sail edge and deepest shade
S_M = (204, 194, 168, 255)
S_L = (232, 224, 202, 255)
S_H = (250, 246, 232, 255)
S_SH = (174, 162, 136, 255)
ROPE = (44, 32, 24, 255)
GILT = (226, 182, 86, 255)
GILT_D = (150, 108, 44, 255)
GLASS = (255, 214, 120, 255)
IRON = (52, 52, 58, 255)


def outline_mask(px, w, h, color, inside):
    """Paints `color` on every transparent pixel that touches an opaque one."""
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 and any(0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][3] > 0 and inside(x + dx, y + dy)
                                        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]):
                edge.append((x, y))
    for x, y in edge:
        px[x, y] = color


def holes(img, rng, count, rmax, burn=(40, 26, 16, 255)):
    """Ragged holes with scorched edges (torn sails, a shot-through deck)."""
    w, h = img.size
    px = img.load()
    done = 0
    tries = 0
    while done < count and tries < count * 40:
        tries += 1
        x, y = rng.randint(2, w - 3), rng.randint(2, h - 3)
        if px[x, y][3] == 0 or px[x, y][:3] == ROPE[:3]:
            continue
        r = rng.uniform(1.0, rmax)
        cut = []
        for dy in range(-int(r) - 2, int(r) + 3):
            for dx in range(-int(r) - 2, int(r) + 3):
                dd = math.hypot(dx, dy * 1.3) + rng.uniform(-0.6, 0.6)
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h and px[xx, yy][3] > 0:
                    if dd < r:
                        cut.append((xx, yy))
                    elif dd < r + 1.2:
                        px[xx, yy] = burn
        for p in cut:
            px[p] = CLEAR
        done += 1


# ---- battle ships, side view (bow to the right) --------------------------------------------------

# length, hull height, masts, rig per mast (s square, g gaff, l lateen), gun decks, ports, stern castle, forecastle, gilt
SIDE = {
    "sloop":      (120, 22, 1, "g", 1, 5, 0, 0, False),
    "schooner":   (128, 20, 2, "gg", 1, 4, 0, 0, False),
    "brigantine": (148, 26, 2, "sg", 1, 7, 1, 0, False),
    "brig":       (160, 28, 2, "ss", 1, 9, 1, 0, False),
    "fluyt":      (168, 36, 3, "ssl", 1, 4, 2, 0, False),
    "frigate":    (208, 36, 3, "ssl", 1, 14, 1, 1, True),
    "galleon":    (224, 48, 3, "ssl", 2, 10, 3, 2, True),
    "man_of_war": (260, 60, 3, "sss", 3, 15, 2, 1, True),
}


def side_ship(type_id, damaged=False, torn=False):
    L, H, masts, rig, decks, ports, castle, fore, gilt = SIDE[type_id]
    rng = random.Random(sum(map(ord, type_id)))
    mast_h = int(L * 0.82) + 24
    W = L + 70
    Ht = mast_h + H + 22
    x0 = 18
    deck = Ht - H - 10
    water = deck + int(H * 0.72)
    hull = Image.new("RGBA", (W, Ht), CLEAR)
    sails = Image.new("RGBA", (W, Ht), CLEAR)
    hp = hull.load()
    sp = sails.load()

    stern_rise = 4 + castle * 2
    bow_rise = 6

    def top(i):
        t = i / L
        return deck - int(stern_rise * max(0.0, 0.25 - t) / 0.25) - int(bow_rise * (max(0.0, t - 0.82) / 0.18) ** 1.6)

    def bot(i):
        t = i / L
        b = deck + H
        if t > 0.78:
            b -= int((H + bow_rise - 2) * ((t - 0.78) / 0.22) ** 2)
        if t < 0.05:
            b -= int(H * 0.35 * (0.05 - t) / 0.05)
        return b

    wale1, wale2 = 5, 5 + max(6, H // 3)
    for i in range(L + 1):
        x = x0 + i
        ty, by = top(i), bot(i)
        for y in range(ty, by + 1):
            rel = (y - ty) / max(1, by - ty)
            d = y - ty
            if y > water:  # copper sheathing below the waterline
                c = dith(COPPER[1], COPPER[0], min(1.0, (y - water) / 6), x, y)
            elif d == 0:
                c = W_H  # the rail cap catches the light
            elif wale1 <= d < wale1 + 2 or wale2 <= d < wale2 + 2:
                c = W_DD  # the wales: heavy dark timbers along the side
            else:
                band = d // 3
                c = dith(W_L, W_M, rel * 1.3, x, y) if d < wale2 else dith(W_M, W_D, (rel - 0.4) * 1.6, x, y)
                if d % 3 == 0 or ((x + band * 13) % 26 == 0):  # plank seams and butt joints
                    c = mix(c, W_DD, 0.55)
            hp[x, y] = c
    # castles: a raised stern (and a forecastle on big ships), with lit gallery windows
    if castle:
        cw = 16 + castle * 7
        ch = castle * 5 + 2
        for x in range(x0 - 1, x0 + cw):
            for y in range(top(0) - ch, top(max(0, x - x0)) + 1):
                d = y - (top(0) - ch)
                hp[x, y] = W_H if d == 0 else (W_DD if d % 4 == 3 else dith(W_L, W_M, d / ch, x, y))
        for k in range(castle):  # stern gallery windows
            gy = top(0) - ch + 3 + k * 5
            for wx in range(x0 + 1, x0 + 1 + 4 * 3, 4):
                for dx in range(2):
                    for dy in range(2):
                        hp[wx + dx, gy + dy] = GLASS
        if gilt:
            for x in range(x0 - 1, x0 + cw):
                hp[x, top(0) - ch + 1] = GILT
    if fore:
        fx = x0 + L - 26
        for x in range(fx, fx + 18):
            for y in range(top(x - x0) - 4 * fore, top(x - x0) + 1):
                d = y - (top(x - x0) - 4 * fore)
                hp[x, y] = W_H if d == 0 else dith(W_L, W_M, d / (4 * fore + 1), x, y)
    # gunports: open, lids up, guns run out
    for k in range(decks):
        py = deck + wale1 + 3 + k * 7 if decks > 1 else deck + (wale1 + wale2) // 2
        for p in range(ports):
            px_ = x0 + 14 + int(p * (L - 34) / max(1, ports - 1)) if ports > 1 else x0 + L // 2
            if py + 4 > water:
                continue
            for dx in range(4):
                for dy in range(4):
                    hp[px_ + dx, py + dy] = (14, 8, 6, 255) if 0 < dx < 3 and 0 < dy < 3 else W_DD
            for dx in range(4):  # the lid, painted red inside
                hp[px_ + dx, py - 2] = (168, 44, 32, 255)
                hp[px_ + dx, py - 3] = (120, 30, 24, 255)
            hp[px_ + 1, py + 1] = IRON
            hp[px_ + 2, py + 1] = (90, 90, 98, 255)
    if gilt:  # a gilded line along the upper wale
        for i in range(4, L - 6):
            hp[x0 + i, top(i) + wale1 - 1] = GILT if i % 6 else GILT_D
    # rail and stanchions above the deck
    for i in range(6, L - 4):
        y = top(i) - 3
        hp[x0 + i, y] = W_M
        if i % 5 == 0:
            for dy in range(1, 3):
                hp[x0 + i, y + dy] = W_D
    # rudder, figurehead, bowsprit and jib boom, stern lantern
    for y in range(deck + H // 3, bot(0) + 1):
        hp[x0 - 1, y] = W_DD
        hp[x0 - 2, y] = W_D
    bx, by = x0 + L, top(L)
    for k in range(4):
        hp[bx - 1 + k // 2, by + 2 + k] = GILT if gilt else W_L
    for k in range(46):
        x = bx - 4 + k
        y = by - 1 - int(k * 0.42)
        if 0 <= x < W and 0 <= y < Ht:
            hp[x, y] = W_D
            if k < 30:
                hp[x, y + 1] = W_M
    lx, ly = x0 + 2, top(0) - (castle * 5 + 2 if castle else 0) - 5
    for dy in range(4):
        hp[lx, ly + dy] = W_DD
        hp[lx + 1, ly + dy] = GLASS if 0 < dy < 3 else W_DD
        hp[lx + 2, ly + dy] = W_DD
    outline_mask(hp, W, Ht, W_DD, lambda x, y: True)

    # masts, tops and yards
    fr = {1: [0.48], 2: [0.64, 0.34], 3: [0.73, 0.49, 0.24]}[masts]
    xs = [x0 + int(L * f) for f in fr]
    tops = []
    for k, mx in enumerate(xs):
        h = mast_h - (k == 0 and masts > 1) * 12 - (k == len(xs) - 1 and masts == 3) * 26
        mt = deck - h
        wide = 3 if L > 150 else 2
        for y in range(mt, deck):
            thin = y < deck - int(h * 0.62)
            for dx in range(wide - (1 if thin and wide > 1 else 0)):
                hp[mx + dx, y] = [W_H, W_M, W_D][min(dx, 2)]
        top_y = deck - int(h * 0.62)
        for dx in range(-4, 5 + wide):  # the top (fighting platform)
            hp[mx + dx, top_y] = W_DD
            hp[mx + dx, top_y + 1] = W_D
        tops.append((mx, mt, top_y))
    # rigging: shrouds with ratlines, stays fore and aft
    def line(a, b, col=ROPE, img=hp):
        (ax, ay), (bx_, by_) = a, b
        n = max(abs(bx_ - ax), abs(by_ - ay))
        for s in range(n + 1):
            x = round(ax + (bx_ - ax) * s / max(1, n))
            y = round(ay + (by_ - ay) * s / max(1, n))
            if 0 <= x < W and 0 <= y < Ht and img[x, y][3] == 0:
                img[x, y] = col
    for mx, mt, ty in tops:
        feet = [mx - 14, mx - 9, mx + 11, mx + 16]
        for fx in feet:
            line((mx + 1, ty), (fx, top(fx - x0) - 2))
        for y in range(ty + 4, deck - 4, 4):  # ratlines between the shrouds
            t = (y - ty) / max(1, deck - ty)
            for side in (-1, 1):
                a = mx + 1 + int(side * (9 if side < 0 else 11) * t)
                b = mx + 1 + int(side * (14 if side < 0 else 16) * t)
                for x in range(min(a, b), max(a, b) + 1):
                    if hp[x, y][3] == 0:
                        hp[x, y] = mix(ROPE, (0, 0, 0, 255), 0.0)[:3] + (200,)
        line((mx + 1, ty), (mx + 1, mt))  # topmast stay to the masthead
    line((tops[0][0] + 1, tops[0][1] + 2), (bx + 40, by - 18))  # forestay to the jib boom
    for a, b in zip(tops, tops[1:]):
        line((a[0], a[1] + 4), (b[0] + 1, b[1] + 6))
    line((tops[-1][0], tops[-1][1] + 3), (x0 + 2, top(2) - 6))  # backstay

    # sails
    def fill_sail(pts_top, pts_bot, x_from, x_to, yard=True):
        """Fills canvas between a top and a bottom edge (dicts x -> y), lit from the upper left."""
        for x in range(x_from, x_to + 1):
            if x not in pts_top or x not in pts_bot:
                continue
            ya, yb = pts_top[x], pts_bot[x]
            u = (x - x_from) / max(1, x_to - x_from)
            for y in range(ya, yb + 1):
                v = (y - ya) / max(1, yb - ya)
                if v < 0.12:
                    c = dith(S_H, S_L, v / 0.12, x, y)
                elif v < 0.55:
                    c = dith(S_L, S_M, (v - 0.12) / 0.43 + u * 0.35, x, y)
                else:
                    c = dith(S_M, S_SH, (v - 0.55) / 0.45 + u * 0.3, x, y)
                if (x - x_from) % 7 == 3 and y % 2 == 0:  # cloth seams
                    c = mix(c, S_D, 0.25)
                sp[x, y] = c
            sp[x, ya] = S_D if not yard else W_DD
            sp[x, yb] = S_D
        for x in (x_from, x_to):
            if x in pts_top and x in pts_bot:
                for y in range(pts_top[x], pts_bot[x] + 1):
                    sp[x, y] = S_D

    for k, (mx, mt, ty) in enumerate(tops):
        kind = rig[k] if k < len(rig) else rig[-1]
        if kind == "s":
            span_total = deck - 6 - (mt + 6)
            courses = 3 if span_total > 90 else 2
            hgt = span_total // courses
            for c in range(courses):
                y1 = mt + 6 + c * hgt
                half = int(L * (0.10 + 0.035 * c)) + 4
                bulge = 2 + c
                tp, bt = {}, {}
                for x in range(mx - half, mx + half + 1):
                    u = (x - (mx - half)) / (2 * half)
                    tp[x] = y1
                    bt[x] = y1 + hgt - 3 + int(bulge * math.sin(math.pi * u))
                fill_sail(tp, bt, mx - half, mx + half)
                for x in range(mx - half - 2, mx + half + 3):  # the yard, a little wider than the sail
                    sp[x, y1] = W_DD
                    sp[x, y1 - 1] = W_M
                for x in range(mx - half + 3, mx + half - 2, 4):  # reef points
                    sp[x, y1 + 4] = S_D
        elif kind == "g":  # gaff mainsail aft of the mast
            length = int(L * (0.42 if masts == 1 else 0.3))
            g0, b0 = ty - (mt - ty) // 6 + 6, deck - 5
            tp, bt = {}, {}
            for x in range(mx - length, mx):
                u = (mx - x) / length
                tp[x] = int(g0 + u * 10 - (mx - x) * 0.0)
                bt[x] = b0 - int(3 * math.sin(math.pi * u))
            # a topsail gaff above: the head of the sail rises toward the peak
            for x in range(mx - length, mx):
                u = (mx - x) / length
                tp[x] = int(mt + 10 + (1 - u) * (g0 - mt - 10) * 0.25 + u * 14)
            fill_sail(tp, bt, mx - length, mx - 1, yard=False)
            for x in range(mx - length - 2, mx):  # gaff and boom
                sp[x, tp.get(x, tp[mx - length])] = W_DD
                sp[x, b0 + 1] = W_DD
        else:  # lateen: a long slanting yard on the mizzen
            yt, yb = mt + 6, deck - 6
            tp, bt = {}, {}
            for x in range(mx - 22, mx + 10):
                u = (x - (mx - 22)) / 32
                tp[x] = int(yb - u * (yb - yt))
                bt[x] = yb
            fill_sail(tp, bt, mx - 22, mx + 9, yard=False)
            line((mx - 24, yb + 2), (mx + 12, yt - 2), W_DD, sp)
    # head sails on the forestay
    fx, ft = tops[0][0], tops[0][1]
    for n, (a, b) in enumerate([(0.15, 0.62), (0.45, 0.95)] if L > 140 else [(0.2, 0.9)]):
        tp, bt = {}, {}
        sx0 = fx + 4
        sx1 = int(bx + 36 * b)
        peak_y = ft + 10 + int((deck - ft) * a * 0.6)
        for x in range(sx0, sx1):
            u = (x - sx0) / max(1, sx1 - sx0)
            stay_y = int(peak_y + u * ((by - 16 * b) - peak_y))
            tp[x] = stay_y
            bt[x] = deck - 4 - int(u * 6)
            if bt[x] < tp[x]:
                bt[x] = tp[x]
        fill_sail(tp, bt, sx0, sx1 - 1, yard=False)

    if damaged:  # shot holes and scorching
        holes(hull, rng, 5 + L // 30, 2.2, burn=(30, 20, 14, 255))
        for _ in range(3):
            x = rng.randint(x0 + 10, x0 + L - 20)
            y = rng.randint(deck + 2, water - 2)
            for dx in range(-5, 6):
                for dy in range(-3, 4):
                    xx, yy = x + dx, y + dy
                    if hp[xx, yy][3] > 0 and (xx + yy) % 2 == 0:
                        hp[xx, yy] = mix(hp[xx, yy], (10, 8, 6, 255), 0.5)
    if torn:
        holes(sails, rng, 14 + L // 10, 4.5, burn=(80, 62, 40, 255))
    outline_mask(sp, W, Ht, S_D, lambda x, y: sp[x, y][:3] != W_DD[:3])
    layout = {"size": [W, Ht], "waterline": water, "flag": [tops[min(1, len(tops) - 1)][0] + 1, tops[min(1, len(tops) - 1)][1]],
              "masts": [[t[0], t[1]] for t in tops]}
    return hull, sails, layout


# ---- map ships, from above (bow up) --------------------------------------------------------------

# length, beam, masts, rig, guns per side, gilt
TOP = {
    "sloop":      (34, 11, 1, "g", 4, False),
    "schooner":   (36, 10, 2, "gg", 3, False),
    "brigantine": (42, 13, 2, "sg", 6, False),
    "brig":       (46, 14, 2, "ss", 8, False),
    "fluyt":      (50, 17, 3, "ssl", 3, False),
    "frigate":    (58, 17, 3, "ssl", 11, True),
    "galleon":    (64, 21, 3, "ssl", 10, True),
    "man_of_war": (70, 23, 3, "sss", 13, True),
}


def top_ship(type_id, sail_state="full", damaged=False):
    L, B, masts, rig, guns, gilt = TOP[type_id]
    rng = random.Random(sum(map(ord, type_id)) + len(sail_state))
    w = int(B * 3.6) + 6
    w += w % 2
    h = L + 18
    cx = w // 2
    y0 = 10
    hull = Image.new("RGBA", (w, h), CLEAR)
    sails = Image.new("RGBA", (w, h), CLEAR)
    hp = hull.load()
    sp = sails.load()

    def hw(t):  # half-beam along the length: a pointed bow, full amidships, a flat transom
        if t < 0.38:
            return B / 2 * (t / 0.38) ** 0.6
        return B / 2 * (1 - 0.22 * ((t - 0.38) / 0.62) ** 2)

    inside = set()
    for y in range(y0, y0 + L + 1):
        t = (y - y0) / L
        half = hw(t)
        for x in range(w):
            if abs(x - cx + 0.5) <= half:
                inside.add((x, y))
    for x, y in inside:  # a drop shadow on the water first
        if 0 <= x + 2 < w and y + 3 < h and (x + 2, y + 3) not in inside:
            hp[x + 2, y + 3] = (0, 0, 0, 70)
    qd = y0 + int(L * 0.78)  # the quarterdeck break
    for x, y in inside:
        t = (y - y0) / L
        edge = not all((x + dx, y + dy) in inside for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)])
        rail = not all((x + dx, y + dy) in inside for dx in (-2, -1, 0, 1, 2) for dy in (-1, 0, 1))
        if edge:
            c = W_DD
        elif rail:
            c = W_H if x < cx else W_D  # the light from the upper left
        else:
            c = dith(DECK_L, DECK_M, abs(x - cx) / (B / 2), x, y)
            if (x - cx) % 3 == 0:  # deck planks run fore and aft
                c = mix(c, W_M, 0.45)
            if y >= qd:
                c = mix(c, W_M, 0.25)
            if y == qd:
                c = W_D
        hp[x, y] = c
    for k, ty in enumerate(range(y0 + int(L * 0.3), y0 + int(L * 0.72), max(5, L // 7))):  # hatches with gratings
        for dx in range(-2, 2):
            for dy in range(3):
                if (cx + dx, ty + dy) in inside:
                    hp[cx + dx, ty + dy] = (70, 46, 28, 255) if (dx + dy) % 2 else (46, 30, 18, 255)
    for g in range(guns):  # guns run out on both sides
        t = 0.22 + 0.62 * g / max(1, guns - 1)
        y = y0 + int(t * L)
        half = int(hw(t))
        for side in (-1, 1):
            x = cx + side * (half - 1) - (1 if side > 0 else 0)
            if (x, y) in inside:
                hp[x, y] = IRON
            xo = cx + side * (half + 1) - (1 if side > 0 else 0)
            if 0 <= xo < w:
                hp[xo, y] = IRON
    if gilt:
        for x in range(cx - int(hw(1.0)) + 1, cx + int(hw(1.0))):
            hp[x, y0 + L - 1] = GILT
    for k in range(9):  # the bowsprit
        hp[cx, y0 - 1 - k] = W_D if k < 6 else W_M
    fr = {1: [0.42], 2: [0.33, 0.6], 3: [0.26, 0.48, 0.7]}[masts]
    mys = [y0 + int(L * f) for f in fr]
    for my in mys:
        for dx, dy, c in [(0, 0, W_D), (-1, 0, W_M), (0, -1, W_L), (-1, -1, W_H)]:
            hp[cx + dx, my + dy] = c
    if damaged:
        holes(hull, rng, 3 + L // 15, 1.6, burn=(26, 16, 10, 255))

    if sail_state != "none":
        span_k = {"full": 1.0, "half": 0.75, "torn": 1.0, "furled": 0.85}[sail_state]
        depth_k = {"full": 1.0, "half": 0.6, "torn": 1.0, "furled": 0.15}[sail_state]
        for k, my in enumerate(mys):
            kind = rig[k] if k < len(rig) else rig[-1]
            if kind == "s":
                span = int(B * (0.95 + 0.25 * (masts - k) / masts) * span_k) + 2
                depth = max(2, int(B * 0.3 * depth_k))
                th = 2 if sail_state == "furled" else max(3, int(B * 0.28 * depth_k) + 2)
                for x in range(cx - span, cx + span):
                    u = (x - cx + 0.5) / span
                    yb = my - int(depth * (1 - u * u))  # bellied forward by the wind astern
                    for d in range(th):
                        y = yb - d
                        v = d / max(1, th - 1)
                        c = dith(S_SH, S_L, v, x, y) if v < 0.7 else S_H
                        if u > 0.3:
                            c = mix(c, S_SH, 0.25 * (u - 0.3))
                        sp[x, y] = c
                    sp[x, yb] = W_DD  # the yard along the after edge
            elif kind == "g" or kind == "l":
                length = int(L * (0.42 if kind == "g" else 0.22) * (0.95 if sail_state != "furled" else 0.9))
                bulge = B * (0.55 if kind == "g" else 0.35) * depth_k
                for y in range(my, my + length):
                    u = (y - my) / length
                    width = int(bulge * math.sin(math.pi * u) * (1 - 0.35 * u))
                    for x in range(cx, cx + max(1, width) + 1):
                        v = (x - cx) / max(1, width)
                        sp[x, y] = dith(S_H, S_SH, v, x, y)
                    sp[cx, y] = W_DD  # the boom
        if rig[0] in "g" and sail_state != "furled":  # a jib from the bowsprit
            for y in range(y0 - 7, mys[0] - 2):
                u = (y - (y0 - 7)) / max(1, mys[0] - 2 - (y0 - 7))
                width = int(B * 0.45 * math.sin(math.pi * min(1.0, u * 0.9 + 0.1)) * depth_k)
                for x in range(cx + 1, cx + 1 + width):
                    sp[x, y] = dith(S_L, S_SH, (x - cx) / max(1, width), x, y)
        if sail_state == "torn":
            holes(sails, rng, 3 + L // 12, 2.0, burn=(90, 72, 50, 255))
        outline_mask(sp, w, h, S_D, lambda x, y: True)
    return hull, sails


def make_ships():
    for t in SIDE:
        out = A / "ships_side" / t
        hull, sails, layout = side_ship(t)
        save(hull, out / "hull.png")
        save(side_ship(t, damaged=True)[0], out / "hull_damaged.png")
        save(sails, out / "sails.png")
        save(side_ship(t, torn=True)[1], out / "sails_torn.png")
        (out / "layout.json").write_text(json.dumps(layout))
    for t in TOP:  # the map's ships replace the engraved ones at the same paths
        out = A / "ships" / t
        hull, _ = top_ship(t, "none")
        save(hull, out / "hull.png")
        save(top_ship(t, "none", damaged=True)[0], out / "hull_damaged.png")
        for state in ("furled", "half", "full", "torn"):
            save(top_ship(t, state)[1], out / f"sails_{state}.png")


# ---- backdrop props -------------------------------------------------------------------------

def make_props():
    out = A / "battle"
    rng = random.Random(7)
    # a distant island: a green hump with a sandy shore and a couple of palms
    W, H = 160, 48
    im = Image.new("RGBA", (W, H), CLEAR)
    d = ImageDraw.Draw(im)
    pts = [(0, H - 6)]
    for x in range(0, W + 1, 4):
        t = x / W
        pts.append((x, int(H - 8 - 30 * math.sin(math.pi * t) ** 1.5 - rng.randint(0, 3))))
    pts.append((W, H - 6))
    d.polygon(pts, fill=(52, 96, 70, 255))
    for x, y in pts[1:-1:2]:  # light from the upper left
        d.point((x, y + 1), fill=(96, 150, 96, 255))
    d.rectangle([0, H - 7, W, H - 4], fill=(226, 206, 150, 255))
    for px in (40, 52, 118):
        top = H - 26 - rng.randint(0, 6)
        d.line([px, H - 7, px + 2, top], fill=(90, 62, 36, 255))
        for dx, dy in [(-5, 2), (5, 2), (-3, -1), (4, -1), (0, -2)]:
            d.line([px + 2, top, px + 2 + dx, top + dy], fill=(40, 110, 60, 255))
    save(up(im, 1), out / "island.png")
    # clouds: soft lumps in three tones
    for n in range(2):
        W, H = 64, 24
        im = Image.new("RGBA", (W, H), CLEAR)
        d = ImageDraw.Draw(im)
        for _ in range(7):
            cx, cy, r = rng.randint(10, W - 10), rng.randint(10, 16), rng.randint(5, 10)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(236, 232, 240, 255))
        for _ in range(4):
            cx, cy, r = rng.randint(12, W - 12), rng.randint(15, 18), rng.randint(4, 7)
            d.ellipse([cx - r, cy - r // 2, cx + r, cy + r // 2], fill=(196, 200, 222, 255))
        save(im, out / f"cloud{n + 1}.png")
    # a rock in the shallows
    im = Image.new("RGBA", (24, 14), CLEAR)
    d = ImageDraw.Draw(im)
    d.polygon([(1, 13), (6, 4), (12, 1), (18, 5), (23, 13)], fill=(80, 78, 84, 255), outline=(36, 34, 40, 255))
    d.line([7, 5, 12, 2], fill=(140, 138, 146, 255))
    save(im, out / "rock.png")


# ---- the world map: land texture and port towns ---------------------------------------------------

def make_map():
    out = A / "map"
    rng = random.Random(11)
    W = 96  # a seamless tile of grass and jungle, lit from the upper left
    tile = Image.new("RGBA", (W, W))
    px = tile.load()
    G = [(52, 92, 50, 255), (66, 112, 58, 255), (82, 132, 66, 255), (104, 150, 76, 255)]
    for y in range(W):
        for x in range(W):
            n = (math.sin(x * 0.21) + math.sin(y * 0.17) + math.sin((x + y) * 0.11)) / 3.0
            px[x, y] = dith(G[1], G[2], 0.5 + n * 0.5, x, y)
    for _ in range(40):  # jungle clumps: dark crowns with a lit edge, wrapping round the tile edges
        cx, cy, r = rng.randrange(W), rng.randrange(W), rng.randint(3, 6)
        for dy in range(-r - 1, r + 2):
            for dx in range(-r - 1, r + 2):
                d = math.hypot(dx, dy)
                x, y = (cx + dx) % W, (cy + dy) % W
                if d <= r:
                    px[x, y] = G[3] if (dx + dy) < -r * 0.6 else (G[0] if (dx + dy) > r * 0.5 else G[1])
    for _ in range(140):  # grass flecks
        x, y = rng.randrange(W), rng.randrange(W)
        px[x, y] = G[3]
    save(tile, out / "land_tile.png")
    # a port town: walls, a fort, red roofs and a church tower; windows lit (they glow at night)
    T = Image.new("RGBA", (28, 22), CLEAR)
    d = ImageDraw.Draw(T)
    WALL, WALL_D, ROOF, ROOF_D, STONE = (226, 210, 170, 255), (170, 150, 110, 255), (182, 70, 48, 255), (122, 44, 32, 255), (150, 146, 140, 255)
    d.rectangle([1, 15, 26, 20], fill=STONE, outline=BLACK)  # the harbour wall
    for x in range(2, 26, 3):
        d.point((x, 15), fill=(190, 186, 178, 255))
    houses = [(3, 9, 7), (9, 7, 6), (15, 10, 5), (20, 8, 6)]
    for hx, hy, hw in houses:
        d.rectangle([hx, hy + 3, hx + hw - 1, 15], fill=WALL, outline=BLACK)
        d.polygon([(hx - 1, hy + 3), (hx + hw // 2, hy - 1), (hx + hw, hy + 3)], fill=ROOF, outline=BLACK)
        d.line([hx + hw // 2, hy, hx + hw - 1, hy + 3], fill=ROOF_D)
        d.point((hx + 2, hy + 6), fill=GLASS)
        d.line([hx + hw - 1, hy + 4, hx + hw - 1, 14], fill=WALL_D)
    d.rectangle([12, 1, 14, 9], fill=WALL, outline=BLACK)  # the church tower
    d.point((13, 4), fill=GLASS)
    d.point((13, 0), fill=BLACK)
    save(T, out / "town.png")


if __name__ == "__main__":
    make_ui()
    make_icons()
    make_ships()
    make_props()
    make_map()
