"""HD pixel-art portrait parts, Octopath-style with a pirate flavour (our own, CC0). Run from the project root:

    python tools/make_pixel_portraits.py

Writes assets/portraits/<layer>/<id>.png (96x96, drawn pixel by pixel) and updates data/portraits.json.
Skin (head) and hair (hair, facial_hair) are drawn in grey ramps: the game tints them by the character's skin and
hair colour (Portraits.layers). Everything else is drawn in its own colours. Light comes from the upper left.
Add a part: write a function below, add it to PARTS with its tags, run this again.
"""
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "assets"
S = 96
CLEAR = (0, 0, 0, 0)
OUT = (34, 22, 20, 255)          # outline for coloured parts
GREY = [96, 146, 184, 212, 232, 246, 255]   # tint ramp: deep shadow .. highlight (multiplied by skin or hair colour)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
LIGHT = (-0.55, -0.75)


def canvas():
    im = Image.new("RGBA", (S, S), CLEAR)
    return im, im.load()


def g(v, a=255):
    return (v, v, v, a)


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(4))


def dith(a, b, t, x, y):
    return b if t * 16 > BAYER[y % 4][x % 4] + 0.5 else a


def band(a, b, t, n=7):
    """Clean colour bands (no dither): the HD-2D way with skies and walls."""
    t = round(max(0.0, min(1.0, t)) * (n - 1)) / (n - 1)
    return mix(a, b, t)


def ramp_at(ramp, t, x, y):
    """t 0 (dark) .. 1 (light) over a list of colours, dithered between neighbours."""
    t = max(0.0, min(0.999, t)) * (len(ramp) - 1)
    i = int(t)
    f = t - i
    if 0.42 < f < 0.58:  # a thin seam of dither only where two bands meet; clean bands elsewhere
        return dith(ramp[i], ramp[min(i + 1, len(ramp) - 1)], f, x, y)
    return ramp[min(i + (1 if f >= 0.5 else 0), len(ramp) - 1)]


def outline(px, color, inside=lambda c: c[3] > 0):
    edge = []
    for y in range(S):
        for x in range(S):
            if px[x, y][3] == 0 and any(0 <= x + dx < S and 0 <= y + dy < S and inside(px[x + dx, y + dy])
                                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge.append((x, y))
    for p in edge:
        px[p] = color


def shaded_blob(px, inside, ramp, cx, cy, rx, ry, bias=0.0, soft=1.0):
    """Fill every pixel where inside(x, y), lit like a rounded surface centred on cx, cy."""
    for y in range(S):
        for x in range(S):
            if inside(x, y):
                nx, ny = (x - cx) / max(rx, 1), (y - cy) / max(ry, 1)
                lit = 0.5 - (nx * LIGHT[0] + ny * LIGHT[1]) * 0.5 * soft + bias
                lit -= max(0.0, nx * nx + ny * ny - 0.6) * 0.35  # turning away at the edges
                px[x, y] = ramp_at(ramp, lit, x, y)


def ramp_of(base, n=5, lo=0.45, hi=1.35):
    """A colour ramp from a base colour: darker shades up to a lighter highlight."""
    out = []
    for i in range(n):
        f = lo + (hi - lo) * i / (n - 1)
        out.append(tuple(max(0, min(255, int(c * f))) for c in base[:3]) + (255,))
    return out


TINT = [g(v) for v in GREY]


# ---- backgrounds ----------------------------------------------------------------------------------

def bg_sea():
    im, px = canvas()
    for y in range(S):
        for x in range(S):
            if y < 58:  # sky: deep at the top, warm at the horizon
                t = y / 58
                px[x, y] = band((58, 98, 160, 255), (240, 196, 140, 255), t ** 1.6, 9)
            else:
                t = (y - 58) / 38
                c = band((40, 112, 150, 255), (16, 58, 96, 255), t, 5)
                if (x + y * 3) % 23 == 0 and y < 80:
                    c = (210, 232, 240, 255)  # glints
                px[x, y] = c
    d = ImageDraw.Draw(im)
    d.ellipse([66, 40, 80, 54], fill=(255, 226, 160, 255))  # the sun low on the water
    d.line([12, 58, 30, 58], fill=(30, 40, 50, 255))  # a distant ship
    d.line([20, 49, 20, 58], fill=(30, 40, 50, 255))
    d.polygon([(20, 50), (26, 56), (20, 56)], fill=(236, 230, 214, 255))
    for x in range(0, S, 7):
        d.point((x + 3, 22 + (x * 5) % 9), fill=(250, 250, 255, 180))  # a gull or two
    return im


def bg_tavern():
    im, px = canvas()
    for y in range(S):
        for x in range(S):
            plank = (x // 12) % 2
            base = (92, 58, 34, 255) if plank else (104, 66, 38, 255)
            glow = max(0.0, 1.0 - math.hypot(x - 78, y - 20) / 60)  # lantern light
            c = mix(base, (220, 150, 70, 255), glow * 0.6)
            if x % 12 == 0:
                c = (58, 36, 22, 255)
            px[x, y] = band(c, mix(c, (0, 0, 0, 255), 0.25), y / S, 5)
    d = ImageDraw.Draw(im)
    d.rectangle([74, 12, 82, 26], fill=(60, 44, 30, 255))
    d.rectangle([75, 15, 81, 24], fill=(255, 212, 120, 255))  # the lantern
    d.rectangle([4, 30, 26, 32], fill=(70, 44, 26, 255))  # a shelf of bottles
    for i, col in enumerate([(60, 110, 60), (120, 40, 30), (70, 70, 120)]):
        d.rectangle([7 + i * 6, 22, 10 + i * 6, 30], fill=col + (255,))
    return im


def bg_crimson():
    im, px = canvas()
    for y in range(S):
        for x in range(S):
            fold = (math.sin(x * 0.42) + 1) / 2  # velvet folds
            px[x, y] = band((70, 16, 20, 255), (176, 56, 50, 255), fold * 0.8 + 0.1 - y / S * 0.25, 5)
    d = ImageDraw.Draw(im)
    d.line([0, 4, S, 4], fill=(212, 170, 80, 255), width=2)  # a gilt rod
    return im


def bg_parchment():
    im, px = canvas()
    rng = random.Random(3)
    for y in range(S):
        for x in range(S):
            px[x, y] = band((226, 206, 160, 255), (200, 176, 128, 255), (abs(x - 48) + abs(y - 48)) / 96, 4)
    d = ImageDraw.Draw(im)
    pts = [(2 + i * 4, 14 + int(4 * math.sin(i * 0.9)) - i) for i in range(7)]
    d.line(pts, fill=(120, 90, 60, 255))  # a coastline on a chart, up in the corner
    d.ellipse([76, 6, 90, 20], outline=(150, 112, 74, 255))  # and a compass rose
    d.line([83, 4, 83, 22], fill=(150, 112, 74, 255))
    d.line([74, 13, 92, 13], fill=(150, 112, 74, 255))
    for i in range(0, S, 16):
        d.line([i, 0, i, S], fill=(190, 166, 120, 255))
    for _ in range(6):
        x, y = rng.randrange(S), rng.randrange(S)
        d.point((x, y), fill=(160, 120, 80, 255))
    return im


def bg_deck():
    im, px = canvas()
    for y in range(S):
        for x in range(S):
            if y < 64:
                px[x, y] = band((120, 168, 210, 255), (206, 224, 232, 255), y / 64, 7)
            else:
                plank = ((y - 64) // 5) % 2
                px[x, y] = (128, 86, 50, 255) if plank else (112, 74, 42, 255)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 60, S, 64], fill=(86, 54, 30, 255))  # the rail
    d.line([70, 0, 70, 60], fill=(70, 46, 28, 255), width=3)  # a mast and its shrouds
    for k in range(5):
        d.line([70, 6, 80 + k * 4, 60], fill=(50, 40, 34, 255))
    for yy in range(14, 58, 6):
        d.line([72, yy, 70 + 10 + int((yy - 6) / 54 * 16), yy], fill=(60, 48, 40, 255))
    return im


# ---- the body: clothes --------------------------------------------------------------------------

SHOULDERS = [(4, 96), (10, 80), (28, 71), (68, 71), (86, 80), (92, 96)]


def _poly_mask(points):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    mp = m.load()
    return lambda x, y: mp[x, y] > 0


def body(base, collar=None, shirt=(236, 230, 214), trim=None, buttons=None, stripes=None, lapels=True, sash=None, jabot=False, vest=False):
    im, px = canvas()
    ramp = ramp_of(base)
    inside = _poly_mask(SHOULDERS)
    shaded_blob(px, inside, ramp, 40, 72, 50, 30, soft=0.8)
    d = ImageDraw.Draw(im)
    if stripes:
        for y in range(72, S):
            if (y // 3) % 2 == 0:
                for x in range(S):
                    if inside(x, y):
                        px[x, y] = mix(px[x, y], stripes + (255,), 0.75)
    # the shirt at the open neck
    d.polygon([(38, 71), (58, 71), (52, 90), (44, 90)], fill=shirt + (255,))
    d.line([(47, 72), (48, 80)], fill=mix(shirt + (255,), OUT, 0.35))  # the shirt's opening
    if jabot:  # lace at the throat
        for k in range(4):
            d.ellipse([44 + k % 2, 72 + k * 4, 52 - k % 2, 77 + k * 4], fill=(250, 248, 240, 255), outline=(200, 196, 186, 255))
    if vest:  # a leather vest over the shirt, and a baldric across it
        d.polygon([(28, 71), (40, 71), (46, 96), (20, 96)], fill=(96, 62, 36, 255))
        d.polygon([(56, 71), (68, 71), (76, 96), (50, 96)], fill=(80, 50, 28, 255))
        d.line([(30, 74), (64, 96)], fill=(60, 40, 22, 255), width=4)
        d.line([(30, 73), (64, 95)], fill=(130, 90, 50, 255), width=1)
        d.rectangle([44, 84, 48, 88], fill=(212, 176, 90, 255))  # the buckle
    elif lapels:
        d.polygon([(30, 71), (40, 71), (46, 92), (38, 86)], fill=ramp[3])
        d.polygon([(66, 71), (56, 71), (50, 92), (58, 86)], fill=ramp[1])
    if trim:  # gold or white edging down the front
        d.line([(40, 72), (46, 94)], fill=trim + (255,))
        d.line([(56, 72), (50, 94)], fill=trim + (255,))
    if buttons:
        for k in range(3):
            d.rectangle([37 - k, 80 + k * 5, 38 - k, 81 + k * 5], fill=buttons + (255,))
            d.rectangle([58 + k, 80 + k * 5, 59 + k, 81 + k * 5], fill=buttons + (255,))
    if collar:
        d.polygon([(26, 72), (38, 70), (36, 76)], fill=collar + (255,))
        d.polygon([(70, 72), (58, 70), (60, 76)], fill=collar + (255,))
    if sash:
        d.rectangle([14, 92, 82, 95], fill=sash + (255,))
    outline(px, OUT)
    return im


# ---- the head -------------------------------------------------------------------------------------

def head(rx, ry, jaw):
    """Face, ears and neck in the tint ramp."""
    im, px = canvas()
    cx, cy = 48, 44

    def face(x, y):
        dy = (y - cy) / ry
        w = rx * (1 - jaw * max(0.0, dy) ** 2)
        return dy * dy * (rx / w) ** 2 * 0 + ((x - cx) / w) ** 2 + dy ** 2 <= 1.0 if w > 0 else False

    neck = lambda x, y: 41 <= x <= 55 and cy + ry * 0.55 <= y <= 74
    shaded_blob(px, neck, TINT, 46, 60, 12, 16, bias=-0.15)
    for ex in (cx - rx - 1, cx + rx + 1):  # ears
        ear = lambda x, y, ex=ex: ((x - ex) / 3.2) ** 2 + ((y - 46) / 5.0) ** 2 <= 1
        shaded_blob(px, ear, TINT, ex, 46, 4, 6, bias=-0.05)
    shaded_blob(px, face, TINT, cx - 3, cy - 4, rx, ry, bias=0.05)
    for y in range(int(cy + ry - 3), int(cy + ry + 2)):  # the shadow under the jaw on the neck
        for x in range(41, 56):
            if px[x, y][3] > 0 and not face(x, y):
                px[x, y] = g(GREY[1])
    outline(px, g(48))
    return im


def wrinkles():
    im, px = canvas()
    d = ImageDraw.Draw(im)
    for y in (31, 34):
        d.line([42, y, 54, y], fill=(0, 0, 0, 60))
    for side in (-1, 1):
        x = 48 + side * 12
        d.line([x, 41, x + side * 2, 43], fill=(0, 0, 0, 70))
        d.line([48 + side * 7, 52, 48 + side * 9, 57], fill=(0, 0, 0, 60))
    return im


# ---- features -------------------------------------------------------------------------------------

BROW = (66, 46, 34, 255)
IRIS = (70, 50, 34, 255)
WHITE = (244, 240, 232, 255)


def eyes(kind):
    im, px = canvas()
    d = ImageDraw.Draw(im)
    for ex in (41, 55):
        lid = (36, 24, 20, 255)
        if kind == "squint":
            d.line([ex - 4, 43, ex + 3, 42], fill=lid)
            d.line([ex - 3, 44, ex + 2, 44], fill=(0, 0, 0, 50))
            d.line([ex - 4, 38, ex + 4, 39], fill=BROW, width=2)
            continue
        top = 40 if kind != "heavy" else 41
        d.ellipse([ex - 4, top, ex + 3, 45], fill=WHITE)              # the white of the eye
        d.rectangle([ex - 1, top + 1, ex + 1, 44], fill=IRIS)        # the iris
        d.point((ex - 1, top + 1), fill=(255, 255, 255, 255))        # a glint
        d.line([ex - 4, top, ex + 3, top - 1 if kind == "almond" else top], fill=lid)  # the upper lid
        if kind == "heavy":
            d.line([ex - 4, top - 1, ex + 3, top - 1], fill=(0, 0, 0, 80))
        d.point((ex - 5, top + 2), fill=(0, 0, 0, 60))
        d.line([ex - 5, 36 if kind != "dots" else 37, ex + 3, 35 if kind == "almond" else 36], fill=BROW, width=2)  # the brow
    return im


def nose(kind):
    im, px = canvas()
    d = ImageDraw.Draw(im)
    shade = (0, 0, 0, 70)
    hi = (255, 255, 255, 70)
    if kind == "straight":
        d.line([49, 44, 50, 50], fill=shade)
        d.point((47, 46), fill=hi)
    elif kind == "hooked":
        d.line([49, 43, 51, 47], fill=shade)
        d.line([51, 47, 50, 50], fill=shade)
        d.point((47, 45), fill=hi)
    else:  # broad
        d.line([50, 44, 51, 49], fill=shade)
        d.rectangle([45, 50, 52, 51], fill=shade)
        d.point((47, 47), fill=hi)
    d.point((46, 51), fill=(0, 0, 0, 110))  # nostrils
    d.point((51, 51), fill=(0, 0, 0, 110))
    return im


LIP = (140, 70, 60, 255)
LIP_D = (90, 40, 36, 255)


def mouth(kind):
    im, px = canvas()
    d = ImageDraw.Draw(im)
    if kind == "line":
        d.line([44, 56, 52, 56], fill=LIP_D)
        d.line([45, 57, 51, 57], fill=(0, 0, 0, 40))
    elif kind == "smile":
        d.line([43, 55, 45, 57], fill=LIP_D)
        d.line([45, 57, 51, 57], fill=LIP_D)
        d.line([51, 57, 53, 55], fill=LIP_D)
        d.point((54, 54), fill=(0, 0, 0, 50))
    elif kind == "frown":
        d.line([43, 57, 45, 55], fill=LIP_D)
        d.line([45, 55, 51, 55], fill=LIP_D)
        d.line([51, 55, 53, 57], fill=LIP_D)
    else:  # open: a laugh, or a curse
        d.ellipse([44, 54, 52, 59], fill=(60, 24, 22, 255), outline=LIP_D)
        d.line([45, 55, 51, 55], fill=(236, 226, 196, 255))  # teeth
        d.point((49, 55), fill=(212, 176, 80, 255))  # a gold tooth
    return im


def scar():
    im, px = canvas()
    d = ImageDraw.Draw(im)
    d.line([56, 44, 62, 55], fill=(178, 92, 86, 255))
    for k in range(3):
        y = 46 + k * 3
        x = 57 + k * 2
        d.line([x - 1, y + 1, x + 1, y - 1], fill=(120, 56, 52, 255))  # stitches
    return im


def eyepatch():
    im, px = canvas()
    d = ImageDraw.Draw(im)
    d.line([32, 34, 64, 46], fill=(30, 22, 20, 255), width=1)  # the strap
    d.ellipse([51, 38, 60, 46], fill=(26, 20, 18, 255), outline=(10, 8, 8, 255))
    d.point((53, 40), fill=(90, 80, 74, 255))
    return im


def hook():
    im, px = canvas()
    d = ImageDraw.Draw(im)
    d.rectangle([72, 84, 82, 96], fill=(80, 54, 34, 255), outline=OUT)  # the cuff
    d.arc([70, 64, 86, 82], 180, 450, fill=(200, 204, 212, 255), width=2)  # the hook
    d.line([78, 82, 78, 84], fill=(200, 204, 212, 255), width=2)
    d.point((71, 72), fill=(250, 250, 255, 255))
    return im


def tattoo():
    im, px = canvas()
    d = ImageDraw.Draw(im)
    c = (48, 70, 120, 220)  # an anchor inked low on the neck
    d.line([48, 66, 48, 71], fill=c)
    d.line([46, 67, 50, 67], fill=c)
    d.arc([45, 68, 51, 73], 0, 180, fill=c)
    return im


def earring():
    im, px = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse([29, 50, 33, 55], outline=(226, 184, 80, 255))
    d.point((30, 51), fill=(255, 236, 170, 255))
    return im


# ---- hair (tinted) -----------------------------------------------------------------------------------

def hair(kind):
    im, px = canvas()
    rng = random.Random(len(kind) * 7)
    cx, cy = 48, 40
    if kind == "bald":
        ring = lambda x, y: (abs(x - 48) > 13 and 38 <= y <= 50 and ((x - 48) / 18) ** 2 + ((y - 44) / 12) ** 2 <= 1)
        shaded_blob(px, ring, TINT, 44, 40, 18, 12)
    else:
        top = {"short": 0.95, "long": 1.0, "queue": 0.98, "curly": 1.12, "receding": 0.9}[kind]

        def cap(x, y):
            inside = ((x - cx) / (18 * top)) ** 2 + ((y - cy + 3) / (16 * top)) ** 2 <= 1 and y <= 40
            if kind == "receding":
                inside = inside and not (abs(x - 48) < 7 and y > 26)
            side = 30 <= y <= 44 and (31 <= x <= 34 or 62 <= x <= 65)  # sideburns
            return inside or side

        def long_hair(x, y):
            return cap(x, y) or (kind == "long" and ((26 <= x <= 33 or 63 <= x <= 70) and 34 <= y <= 74))

        shaded_blob(px, long_hair, TINT, 42, 30, 20, 22, bias=0.05)
        if kind == "curly":  # a ragged edge of curls
            for a in range(0, 360, 18):
                r = 18 * top
                x = int(cx + math.cos(math.radians(a)) * r)
                y = int(cy - 3 + math.sin(math.radians(a)) * r * 0.9)
                if y <= 42:
                    for dx in range(-2, 3):
                        for dy in range(-2, 3):
                            if dx * dx + dy * dy <= 4 and 0 <= x + dx < S and 0 <= y + dy < S:
                                px[x + dx, y + dy] = ramp_at(TINT, 0.5 - (dx + dy) * 0.12, x + dx, y + dy)
        if kind == "queue":  # tied back: the tail shows behind the neck
            for y in range(52, 70):
                for x in range(60, 65):
                    px[x, y] = ramp_at(TINT, 0.35, x, y)
            d = ImageDraw.Draw(im)
            d.rectangle([59, 52, 65, 54], fill=g(GREY[1]))  # the ribbon
        for _ in range(26):  # strands catching the light
            x = rng.randint(32, 64)
            y = rng.randint(24, 38)
            if px[x, y][3] > 0:
                px[x, y] = g(GREY[6])
                if px[x + 1, y + 1][3] > 0:
                    px[x + 1, y + 1] = g(GREY[5])
        # a fringe over the forehead
        for x in range(36, 60):
            y = 30 + int(2 * math.sin(x * 0.9))
            if kind != "receding" and px[x, y][3] > 0:
                for k in range(3):
                    if y + k < S:
                        px[x, y + k] = ramp_at(TINT, 0.45 - k * 0.1, x, y + k)
    outline(px, g(40))
    return im


def facial_hair(kind):
    im, px = canvas()
    if kind == "stubble":
        for y in range(48, 64):
            for x in range(34, 63):
                dx, dy = (x - 48) / 14, (y - 46) / 18
                if dx * dx + dy * dy <= 1 and y > 50 and BAYER[y % 4][x % 4] < 6 and not (44 <= x <= 52 and 54 <= y <= 58):
                    px[x, y] = g(GREY[1], 150)
        return im
    if kind == "moustache":
        shape = lambda x, y: 52 <= y <= 55 and abs(x - 48) <= 7 - (y - 52) * 0.5 and not (y == 52 and abs(x - 48) < 2)
    elif kind == "goatee":
        shape = lambda x, y: (52 <= y <= 54 and abs(x - 48) <= 6) or (58 <= y <= 65 and abs(x - 48) <= 4 - (y - 58) * 0.4)
    else:  # full beard: jaw and chin, the mouth left clear
        def shape(x, y):
            dx, dy = (x - 48) / 16, (y - 47) / 19
            return dx * dx + dy * dy <= 1 and y >= 49 and not (43 <= x <= 53 and 54 <= y <= 58) and not (abs(x - 48) < 3 and y < 53)
    shaded_blob(px, shape, TINT, 46, 56, 14, 10, bias=-0.05)
    outline(px, g(40))
    return im


# ---- hats (their own colours) ---------------------------------------------------------------------------

def hat(kind):
    im, px = canvas()
    d = ImageDraw.Draw(im)
    if kind in ("tricorne", "feathered_tricorne"):
        felt = ramp_of((48, 40, 38))
        crown = lambda x, y: ((x - 48) / 15) ** 2 + ((y - 24) / 11) ** 2 <= 1 and y <= 28
        shaded_blob(px, crown, felt, 44, 20, 15, 11)
        d.polygon([(18, 30), (48, 22), (78, 30), (66, 36), (48, 30), (30, 36)], fill=felt[1])  # the turned-up brim
        d.line([(18, 30), (48, 22), (78, 30)], fill=felt[3])
        d.line([(30, 36), (48, 30), (66, 36)], fill=(212, 176, 90, 255))  # gold lace
        if kind == "feathered_tricorne":  # a plume, white with a red tip, sweeping back
            for k in range(14):
                x = 56 + k
                y = 20 - int(6 * math.sin(k / 13 * math.pi))
                d.line([x, y, x + 1, y + 3], fill=(240, 236, 228, 255))
            d.line([69, 18, 72, 22], fill=(190, 40, 36, 255), width=2)
    elif kind == "bicorne":
        felt = ramp_of((34, 36, 54))
        d.polygon([(16, 32), (34, 18), (62, 18), (80, 32), (48, 30)], fill=felt[1])
        d.line([(16, 32), (34, 18), (62, 18), (80, 32)], fill=felt[3])
        d.line([(18, 31), (78, 31)], fill=(212, 176, 90, 255))
        d.ellipse([44, 22, 52, 28], fill=(200, 40, 40, 255), outline=(240, 220, 160, 255))  # the cockade
    elif kind == "bandana":
        red = ramp_of((176, 40, 36))
        wrap = lambda x, y: ((x - 48) / 18) ** 2 + ((y - 34) / 14) ** 2 <= 1 and y <= 36
        shaded_blob(px, wrap, red, 44, 28, 18, 14)
        for x in range(32, 66, 5):  # white spots
            for y in range(24, 36, 5):
                if px[x, y][3] > 0:
                    px[x, y] = (240, 232, 220, 255)
        d.polygon([(64, 32), (74, 40), (70, 44), (64, 38)], fill=red[2])  # the knot and its tails
        d.polygon([(68, 40), (76, 50), (72, 50)], fill=red[1])
    elif kind == "wig":
        white = [(150, 150, 156, 255), (190, 190, 196, 255), (220, 220, 226, 255), (240, 240, 244, 255), (252, 252, 255, 255)]
        def curls(x, y):
            return (((x - 48) / 20) ** 2 + ((y - 34) / 18) ** 2 <= 1 and y <= 38) or ((24 <= x <= 33 or 63 <= x <= 72) and 34 <= y <= 66)
        shaded_blob(px, curls, white, 44, 30, 22, 26)
        for y in range(36, 66, 5):  # rows of rolled curls at the sides
            for x0 in (24, 63):
                d.line([x0, y, x0 + 9, y], fill=(170, 170, 176, 255))
    elif kind == "straw":
        straw = ramp_of((208, 176, 104))
        d.ellipse([12, 26, 84, 38], fill=straw[2], outline=straw[0])
        crown = lambda x, y: ((x - 48) / 13) ** 2 + ((y - 26) / 10) ** 2 <= 1 and y <= 31
        shaded_blob(px, crown, straw, 44, 22, 13, 10)
        d.line([35, 30, 61, 30], fill=(120, 60, 40, 255), width=2)  # the band
        for x in range(16, 82, 3):
            d.point((x, 32), fill=straw[1])
    else:  # knit cap
        wool = ramp_of((60, 90, 140))
        cap = lambda x, y: ((x - 48) / 17) ** 2 + ((y - 32) / 15) ** 2 <= 1 and y <= 35
        shaded_blob(px, cap, wool, 44, 26, 17, 15)
        d.rectangle([31, 32, 65, 36], fill=wool[1])  # the rolled brim
        for x in range(31, 66, 2):
            d.point((x, 34), fill=wool[3])
    outline(px, OUT)
    return im


# ---- assembling --------------------------------------------------------------------------------

PARTS = {
    "background": [("parchment", bg_parchment, ["any"]), ("sea", bg_sea, ["any"]), ("tavern", bg_tavern, ["any"]),
                   ("crimson", bg_crimson, ["any"]), ("deck", bg_deck, ["pirate", "crew", "captain"])],
    "body": [("sailor_shirt", lambda: body((222, 214, 196), lapels=False, shirt=(240, 234, 220), sash=(150, 40, 36)), ["crew"]),
             ("striped_shirt", lambda: body((236, 232, 224), lapels=False, stripes=(50, 70, 120), shirt=(240, 236, 228)), ["crew", "pirate"]),
             ("pirate_coat", lambda: body((140, 36, 34), trim=(212, 176, 90), buttons=(232, 196, 104), sash=(40, 30, 60)), ["pirate", "captain"]),
             ("navy_coat", lambda: body((36, 50, 92), collar=(236, 232, 224), trim=(236, 232, 224), buttons=(222, 184, 90)), ["navy", "officer", "captain"]),
             ("merchant_coat", lambda: body((104, 74, 46), buttons=(200, 170, 110)), ["merchant", "captain", "official"]),
             ("governor_coat", lambda: body((52, 92, 70), trim=(220, 186, 96), buttons=(230, 196, 104), jabot=True), ["governor", "official"]),
             ("priest_robe", lambda: body((32, 30, 34), lapels=False, shirt=(240, 240, 240)), ["priest"]),
             ("buccaneer_vest", lambda: body((236, 228, 210), lapels=False, vest=True, sash=(170, 40, 36)), ["pirate", "crew", "captain"])],
    "head": [("oval", lambda: head(15, 19, 0.35), ["any"]), ("round", lambda: head(16, 17, 0.2), ["any"]), ("long", lambda: head(14, 21, 0.45), ["any"])],
    "wrinkles": [("aged", wrinkles, ["any"])],
    "eyes": [(k, (lambda k=k: eyes(k)), ["any"]) for k in ("dots", "almond", "heavy", "squint")],
    "nose": [(k, (lambda k=k: nose(k)), ["any"]) for k in ("straight", "hooked", "broad")],
    "mouth": [(k, (lambda k=k: mouth(k)), ["any"]) for k in ("line", "smile", "frown", "open")],
    "scar": [("cheek", scar, ["any"])],
    "facial_hair": [(k, (lambda k=k: facial_hair(k)), ["any"]) for k in ("stubble", "moustache", "full_beard", "goatee")],
    "hair": [(k, (lambda k=k: hair(k)), ["any"]) for k in ("short", "long", "queue", "bald", "curly", "receding")],
    "hat": [("tricorne", lambda: hat("tricorne"), ["captain", "navy", "officer", "pirate"]),
            ("feathered_tricorne", lambda: hat("feathered_tricorne"), ["captain", "pirate"]),
            ("bandana", lambda: hat("bandana"), ["pirate", "crew"]),
            ("bicorne", lambda: hat("bicorne"), ["navy", "officer"]),
            ("wig", lambda: hat("wig"), ["governor", "official"]),
            ("straw", lambda: hat("straw"), ["crew", "merchant"]),
            ("knit_cap", lambda: hat("knit_cap"), ["crew"])],
    "eyepatch": [("patch", eyepatch, ["any"])],
    "accessory": [("earring", earring, ["pirate", "crew", "captain"])],
    "tattoo": [("anchor", tattoo, ["pirate", "crew"])],
    "hook": [("hook", hook, ["any"])],
}


def main():
    path = ROOT / "data" / "portraits.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    data["size"] = S
    parts = {}
    for layer, items in PARTS.items():
        parts[layer] = []
        for pid, fn, tags in items:
            out = A / "portraits" / layer / f"{pid}.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            fn().save(out)
            parts[layer].append({"id": pid, "path": f"res://assets/portraits/{layer}/{pid}.png", "tags": tags})
    data["parts"] = parts
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", sum(len(v) for v in parts.values()), "portrait parts")


if __name__ == "__main__":
    main()
