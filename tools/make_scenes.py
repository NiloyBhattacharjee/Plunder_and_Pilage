"""Painted scenes for the port screen and the dialogs (our own, CC0). Run from the project root:

    python tools/make_scenes.py

Each scene is a folder, assets/scenes/<key>/:
  back.png    the sky and the far hills (or the whole picture, for a scene drawn at one hour)
  front.png   the town, the water and the ships, clear where the sky shows; it shifts more than the back with
              the mouse on the port screen, for depth
  lights.png  lit windows and lanterns, shown from dusk (a scene with lights is tinted by the hour in game)
800x450, shown at x2 behind the port screen and at x1 above a dialog's text, cropped to the middle (about
x 110-690, y 130-320), so keep the subject in that band. port_<id> for every port, drawn from its tags and
nation; the rest are the scenes data/scenes.json points events and endings to. Replace any file with hand-made
art at the same path: back.png alone is enough.
"""
import json
import math
import random

from PIL import Image, ImageDraw

from make_pixel_art import A, BLACK, CLEAR, ROOT, dith, mix, save

W, H = 800, 450
OUT = A / "scenes"
GLOW = (255, 200, 110, 255)
HALO = (255, 170, 80, 90)

SKIES = {  # top, middle, horizon
    "day": [(58, 104, 176), (118, 168, 220), (214, 228, 230)],
    "dusk": [(40, 38, 90), (172, 90, 106), (250, 178, 104)],
    "night": [(6, 8, 26), (18, 26, 58), (46, 58, 92)],
    "storm": [(30, 34, 42), (60, 66, 76), (106, 112, 118)],
    "fire": [(26, 14, 22), (112, 36, 30), (232, 118, 56)],
}

# Walls (lit, shade), roofs (lit, shade), by nation: Spanish whitewash and tile, English brick and slate,
# French plaster and slate, Dutch orange brick with stepped gables, the Brethren's planks and thatch.
STYLES = {
    "spain": {"wall": (234, 224, 198), "wall_d": (186, 172, 146), "roof": (190, 86, 54), "roof_d": (128, 52, 34), "roof_kind": "low"},
    "england": {"wall": (168, 86, 66), "wall_d": (116, 56, 46), "roof": (84, 90, 106), "roof_d": (54, 58, 72), "roof_kind": "steep"},
    "france": {"wall": (226, 210, 174), "wall_d": (176, 160, 128), "roof": (92, 100, 124), "roof_d": (60, 64, 84), "roof_kind": "steep"},
    "dutch": {"wall": (192, 106, 64), "wall_d": (136, 70, 44), "roof": (122, 48, 40), "roof_d": (80, 30, 28), "roof_kind": "gable"},
    "pirates": {"wall": (138, 100, 64), "wall_d": (94, 66, 42), "roof": (190, 164, 98), "roof_d": (138, 116, 66), "roof_kind": "thatch"},
}
STONE, STONE_D, STONE_HI = (152, 148, 140, 255), (102, 98, 94, 255), (196, 192, 182, 255)
JUNGLE = [(30, 70, 46), (44, 92, 56), (66, 120, 66), (98, 150, 80)]


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def new(opaque=True):
    return Image.new("RGBA", (W, H), (0, 0, 0, 255) if opaque else CLEAR)


# ---- sky, sea, land ---------------------------------------------------------------------------------

def gradient(px, y0, y1, stops):
    """A vertical gradient through the stops, in four bands per step, dithered where the bands meet."""
    n = len(stops) - 1
    for y in range(max(0, y0), min(H, y1)):
        t = (y - y0) / max(1, y1 - y0 - 1) * n
        i = min(int(t), n - 1)
        f = (t - i) * 4
        a = rgba(mix(stops[i], stops[i + 1], math.floor(f) / 4))
        b = rgba(mix(stops[i], stops[i + 1], min(1.0, (math.floor(f) + 1) / 4)))
        for x in range(W):
            px[x, y] = dith(a, b, f - math.floor(f), x, y)


def disc(px, cx, cy, r, col, glow, glow_r):
    for y in range(max(0, cy - glow_r), min(H, cy + glow_r + 1)):
        for x in range(max(0, cx - glow_r), min(W, cx + glow_r + 1)):
            d = math.hypot(x - cx, y - cy)
            if d <= r:
                px[x, y] = rgba(col)
            elif d <= glow_r:
                px[x, y] = dith(px[x, y], mix(px[x, y], rgba(glow), 0.45), (1 - (d - r) / (glow_r - r)) * 0.9, x, y)


def stars(px, rng, y1, n=160):
    for _ in range(n):
        x, y = rng.randrange(W), rng.randrange(y1)
        px[x, y] = (230, 230, 255, 255) if rng.random() < 0.3 else (150, 156, 196, 255)


def cloud(d, rng, cx, cy, w, tones):
    """Soft lumps in three tones, lit from the upper left: shade, body, lit tops."""
    lumps = [(cx + rng.randint(-w // 2, w // 2), cy + rng.randint(-w // 12, w // 14), rng.randint(w // 8, w // 4)) for _ in range(7)]
    for x, y, r in lumps:
        d.ellipse([x - r + 3, y - r // 2 + 3, x + r + 3, y + r // 2 + 3], fill=rgba(tones[0]))
    for x, y, r in lumps:
        d.ellipse([x - r, y - r // 2, x + r, y + r // 2], fill=rgba(tones[1]))
    for x, y, r in lumps:
        d.ellipse([x - r + 2, y - r // 2, x + r - 5, y - r // 2 + max(2, r // 4)], fill=rgba(tones[2]))


def clouds(im, rng, n, y0, y1, tones):
    d = ImageDraw.Draw(im)
    for _ in range(n):
        cloud(d, rng, rng.randint(-20, W + 20), rng.randint(y0, y1), rng.randint(70, 150), tones)


def ridge(px, rng, base, amp, col, lit, shade, x0=0, x1=W, speckle=None, bottom=None):
    """A line of hills from x0 to x1 standing on `base`: lit where they face the upper left, dithered into shade on
    the far slopes, with tree crowns if `speckle` is given. Returns the top of the land in each column."""
    ph = [rng.uniform(0, 6.28) for _ in range(4)]
    freq = rng.uniform(0.008, 0.014)
    tops = {}
    for x in range(max(0, x0), min(W, x1)):
        t = (x - x0) / max(1, x1 - x0)
        env = math.sin(math.pi * t) ** 0.6 if (x0 > 0 or x1 < W) else 1.0
        h = amp * env * (0.62 + 0.24 * math.sin(x * freq + ph[0]) + 0.12 * math.sin(x * freq * 3.1 + ph[1]) + 0.04 * math.sin(x * 0.11 + ph[2]))
        tops[x] = int(base - h)
    for x, top in tops.items():
        slope = top - tops.get(x - 2, top)
        for y in range(max(0, top), min(H, bottom or base)):
            k = y - top
            c = rgba(col)
            if slope < 0 and k < 3:
                c = rgba(lit)
            elif slope > 0 and k < 10:
                c = dith(rgba(col), rgba(shade), 0.7 - k * 0.06, x, y)
            px[x, y] = c
    if speckle:
        for _ in range(int((x1 - x0) * amp / 40)):
            x = rng.randrange(max(0, x0), min(W, x1))
            if x not in tops:
                continue
            y = rng.randint(tops[x] + 2, max(tops[x] + 3, base - 2))
            r = rng.randint(2, 4)
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if dx * dx + dy * dy <= r * r and 0 <= x + dx < W and 0 <= y + dy < H and y + dy >= tops.get(x + dx, H):
                        px[x + dx, y + dy] = rgba(speckle[2] if dx + dy < -r * 0.5 else (speckle[0] if dx + dy > r * 0.4 else speckle[1]))
    return tops


def sea(px, rng, y0, y1, stops, hl, waves=900):
    gradient(px, y0, y1, stops)
    for _ in range(waves):  # crests: short near the horizon, longer close by, with a dark trough under the near ones
        y = rng.randint(y0 + 2, y1 - 2)
        t = (y - y0) / max(1, y1 - y0)
        n = int(2 + t * t * 18)
        x = rng.randint(-n, W)
        for i in range(n):
            if 0 <= x + i < W:
                px[x + i, y] = rgba(hl)
                if t > 0.35 and y + 1 < H:
                    px[x + i, y + 1] = rgba(mix(px[x + i, y + 1][:3], (0, 0, 0), 0.25))


def glint(px, rng, cx, y0, y1, col, spread=40):
    """The sun's or moon's road on the water: bright dashes, narrow at the horizon, wide close by."""
    for _ in range(int((y1 - y0) * 2.2)):
        y = rng.randint(y0, y1 - 1)
        t = (y - y0) / max(1, y1 - y0)
        half = 4 + t * spread
        x = int(cx + rng.uniform(-half, half))
        for i in range(int(2 + t * 6)):
            if 0 <= x + i < W:
                px[x + i, y] = rgba(col)


def reflect(px, water_y, depth, water):
    """Mirror what stands on the quay into the harbour, broken by the ripples and sunk into the water's colour."""
    for y in range(water_y + 1, min(H, water_y + depth)):
        src = 2 * water_y - y
        k = (y - water_y) / depth
        wob = int(round(math.sin(y * 0.9) * 2))
        for x in range(W):
            if (x + y) % 2 and k > 0.5:
                continue
            s = px[min(W - 1, max(0, x + wob)), src]
            if s[3] == 0:
                continue
            px[x, y] = rgba(mix(s[:3], water, 0.55 + k * 0.4))


# ---- buildings ----------------------------------------------------------------------------------------

def windows(d, lights, rng, x0, y0, x1, y1, step=6, lit=0.45):
    for wy in range(y0, y1, step + 2):
        for wx in range(x0, x1, step):
            d.rectangle([wx, wy, wx + 1, wy + 2], fill=(34, 30, 44, 255))
            if lights is not None and rng.random() < lit:
                lights.rectangle([wx - 1, wy - 1, wx + 2, wy + 3], fill=HALO)
                lights.rectangle([wx, wy, wx + 1, wy + 2], fill=GLOW)


def house(d, lights, rng, x, base, w, h, st):
    wall, wall_d, roof, roof_d = rgba(st["wall"]), rgba(st["wall_d"]), rgba(st["roof"]), rgba(st["roof_d"])
    top = base - h
    d.rectangle([x, top, x + w - 1, base], fill=wall, outline=BLACK)
    d.line([x + w - 2, top + 1, x + w - 2, base - 1], fill=wall_d)  # the shaded side, away from the light
    kind = st["roof_kind"]
    if kind == "low":
        d.polygon([(x - 2, top), (x + 3, top - 5), (x + w - 4, top - 5), (x + w + 1, top)], fill=roof, outline=BLACK)
        d.line([x + 3, top - 4, x + w - 4, top - 4], fill=rgba(mix(st["roof"], (255, 230, 200), 0.3)))
    elif kind == "gable":  # a stepped Dutch gable facing the water
        for k in range(3):
            d.rectangle([x + k * 2, top - 3 - k * 3, x + w - 1 - k * 2, top - k * 3], fill=wall, outline=BLACK)
        d.rectangle([x + w // 2 - 1, top - 13, x + w // 2, top - 9], fill=wall, outline=BLACK)
    else:
        peak = 9 if kind == "steep" else 7
        d.polygon([(x - 2, top + 1), (x + w // 2, top - peak), (x + w + 1, top + 1)], fill=roof, outline=BLACK)
        d.line([x + w // 2, top - peak + 1, x + w, top], fill=roof_d)
        if kind == "thatch":
            for k in range(x, x + w, 3):
                d.point((k, top - 1), fill=roof_d)
    windows(d, lights, rng, x + 2, top + 3, x + w - 3, base - 5, step=5 if w < 14 else 6)
    d.rectangle([x + w // 2 - 1, base - 4, x + w // 2 + 1, base], fill=(60, 40, 30, 255))


def tower(d, lights, x, base, w, h, st, dome=False):
    wall = rgba(st["wall"] if st["roof_kind"] != "thatch" else STYLES["spain"]["wall"])
    d.rectangle([x, base - h, x + w - 1, base], fill=wall, outline=BLACK)
    d.line([x + w - 2, base - h + 1, x + w - 2, base - 1], fill=rgba(st["wall_d"]))
    d.rectangle([x + w // 2 - 2, base - h + 4, x + w // 2 + 1, base - h + 9], fill=(30, 26, 36, 255))  # the belfry
    if lights is not None:
        lights.rectangle([x + w // 2 - 1, base - h + 6, x + w // 2, base - h + 8], fill=GLOW)
    if dome:
        d.ellipse([x - 2, base - h - w // 2 - 3, x + w + 1, base - h + w // 2 - 2], fill=rgba(st["roof"]), outline=BLACK)
        d.rectangle([x + 2, base - h - 1, x + w - 3, base - h + 2], fill=wall)
        d.line([x + w // 2, base - h - w // 2 - 8, x + w // 2, base - h - w // 2 - 3], fill=BLACK)
    else:
        d.polygon([(x - 1, base - h), (x + w // 2, base - h - w - 4), (x + w, base - h)], fill=rgba(st["roof"]), outline=BLACK)
    d.line([x + w // 2, base - h - w - 9, x + w // 2, base - h - w - 4], fill=BLACK)
    d.line([x + w // 2 - 2, base - h - w - 7, x + w // 2 + 2, base - h - w - 7], fill=BLACK)


def flag(im, faction, x, y, k=0.5):
    fid = json.loads((ROOT / "data" / "factions.json").read_text(encoding="utf-8"))[faction]["flag"]
    f = Image.open(A / "flags" / f"{fid}.png").convert("RGBA")
    f = f.resize((max(1, int(f.width * k)), max(1, int(f.height * k))), Image.NEAREST)
    ImageDraw.Draw(im).line([x, y, x, y + f.height + 12], fill=BLACK, width=1)
    im.paste(f, (x + 1, y), f)


def fort(im, d, lights, x, base, w, h, faction):
    """A bastion: battered stone walls, a parapet with embrasures, and the flag over it."""
    d.polygon([(x, base), (x + 6, base - h), (x + w - 6, base - h), (x + w, base)], fill=STONE, outline=BLACK)
    d.line([x + 7, base - h + 1, x + w - 7, base - h + 1], fill=STONE_HI)
    d.line([x + 1, base - 1, x + 6, base - h + 1], fill=STONE_HI)
    for k in range(x + 4, x + w - 4, 7):  # courses of stone
        d.line([k, base - h // 2, k + 4, base - h // 2], fill=STONE_D)
    for k in range(x + 8, x + w - 10, 10):
        d.rectangle([k, base - h - 4, k + 6, base - h], fill=STONE, outline=BLACK)
        d.rectangle([k + 7, base - h + 4, k + 9, base - h + 6], fill=(20, 18, 22, 255))  # a gun port
    if lights is not None:
        for k in range(x + 12, x + w - 12, 22):
            lights.rectangle([k - 1, base - h - 3, k + 1, base - h - 1], fill=GLOW)
    flag(im, faction, x + w // 2, base - h - 30)


def windmill(d, x, base):
    d.polygon([(x, base), (x + 3, base - 26), (x + 11, base - 26), (x + 14, base)], fill=rgba(STYLES["spain"]["wall"]), outline=BLACK)
    d.polygon([(x + 2, base - 26), (x + 7, base - 32), (x + 12, base - 26)], fill=rgba(STYLES["spain"]["roof"]), outline=BLACK)
    cx, cy = x + 7, base - 27
    for a in (0.6, 0.6 + math.pi / 2, 0.6 + math.pi, 0.6 + 3 * math.pi / 2):
        ex, ey = cx + math.cos(a) * 20, cy + math.sin(a) * 20
        d.line([cx, cy, ex, ey], fill=(70, 50, 36, 255), width=1)
        d.line([cx + math.cos(a) * 6 + math.cos(a + 1.57) * 3, cy + math.sin(a) * 6 + math.sin(a + 1.57) * 3,
                ex + math.cos(a + 1.57) * 3, ey + math.sin(a + 1.57) * 3], fill=(226, 214, 186, 255))


def palm(d, x, base, h, rng):
    lean = rng.choice([-1, 1]) * rng.randint(2, 7)
    pts = [(x + lean * (k / 8) ** 2, base - h * k / 8) for k in range(9)]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        d.line([ax, ay, bx, by], fill=(98, 68, 40, 255), width=2)
    tx, ty = pts[-1]
    for a, l in [(-2.8, 14), (-2.3, 16), (-1.6, 10), (-0.9, 16), (-0.35, 14), (2.6, 9), (0.5, 9)]:
        ex, ey = tx + math.cos(a) * l, ty + math.sin(a) * l * 0.6 + l * 0.35
        d.line([tx, ty, (tx + ex) / 2, min(ty, ey) - 2], fill=(40, 104, 54, 255), width=2)
        d.line([(tx + ex) / 2, min(ty, ey) - 2, ex, ey], fill=(40, 104, 54, 255), width=2)
        d.line([tx, ty - 1, (tx + ex) / 2, min(ty, ey) - 3], fill=(86, 150, 76, 255))


def awnings(d, x0, x1, base, rng):
    for x in range(x0, x1, 16):
        col = rng.choice([(196, 60, 48), (230, 196, 96), (60, 110, 170), (230, 226, 210)])
        d.rectangle([x, base - 10, x + 1, base], fill=(70, 50, 36, 255))
        d.rectangle([x + 11, base - 10, x + 12, base], fill=(70, 50, 36, 255))
        d.polygon([(x - 2, base - 9), (x + 2, base - 14), (x + 11, base - 14), (x + 15, base - 9)], fill=rgba(col), outline=BLACK)
        for k in range(x + 1, x + 13, 3):
            d.point((k, base - 2), fill=rgba(rng.choice([(120, 80, 40), (200, 170, 60), (90, 140, 60)])))


def flames(d, lights, rng, x, y, w):
    """A roof on fire: tongues of flame in three tones."""
    for k in range(w // 2):
        fx = x + rng.randint(0, w)
        fh = rng.randint(5, 16)
        d.polygon([(fx - 3, y), (fx, y - fh), (fx + 3, y)], fill=(236, 110, 40, 255))
        d.polygon([(fx - 1, y), (fx, y - fh * 0.6), (fx + 1, y)], fill=(255, 220, 110, 255))
        if lights is not None:
            lights.ellipse([fx - 6, y - fh - 4, fx + 6, y + 2], fill=(255, 140, 50, 60))


def smoke(d, rng, x, y, height, col=(40, 36, 40)):
    for k in range(int(height / 6)):
        r = 4 + k * 1.1
        cx, cy = x + k * 2.2 + rng.randint(-3, 3), y - k * 6
        d.ellipse([cx - r, cy - r * 0.8, cx + r, cy + r * 0.8], fill=rgba(mix(col, (110, 100, 100), k / max(1, height / 6) * 0.6)))


def town(im, d, lights, rng, x0, x1, base, st, back_row=True):
    """Houses along the shore: a hazier back row, then the front row on the quay. Returns the gaps for landmarks."""
    if back_row:
        x = x0 + rng.randint(0, 8)
        while x < x1 - 10:
            w = rng.randint(12, 22)
            house(d, lights, rng, x, base - 14, w, rng.randint(18, 32), st)
            x += w + rng.randint(0, 4)
    x = x0
    while x < x1 - 12:
        w = rng.randint(14, 28)
        house(d, lights, rng, x, base, w, rng.randint(20, 38), st)
        x += w + rng.randint(1, 3)


# ---- ships ------------------------------------------------------------------------------------------

def ship(im, kind, x, water, scale=1.0, flip=False, sails=True, torn=False, tilt=0, lights=None):
    """A battle sprite standing in the water at x, cut at its waterline, with a line of foam along it."""
    sd = A / "ships_side" / kind
    lay = json.loads((sd / "layout.json").read_text())
    img = Image.open(sd / "hull.png").convert("RGBA")
    if sails:
        img.alpha_composite(Image.open(sd / ("sails_torn.png" if torn else "sails.png")).convert("RGBA"))
    img = img.crop((0, 0, img.width, lay["waterline"] + 1))
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    if scale != 1.0:
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.NEAREST)
    if tilt:
        img = img.rotate(tilt, Image.NEAREST, expand=True)
    left, top = int(x - img.width / 2), int(water - img.height)
    im.paste(img, (left, top), img)
    d = ImageDraw.Draw(im)
    hw = int(lay["size"][0] * scale * 0.42)
    for k in range(-hw, hw, 3):
        d.point((x + k, water), fill=(226, 236, 240, 255))
    if lights is not None:
        lx = x + (hw - 4 if flip else -hw + 4)
        lights.ellipse([lx - 4, water - 18, lx + 4, water - 10], fill=HALO)
        lights.rectangle([lx - 1, water - 15, lx + 1, water - 13], fill=GLOW)


# ---- the ports --------------------------------------------------------------------------------------

def port_scene(pid, p):
    rng = random.Random(pid)
    tags = p["tags"]
    st = STYLES.get(p["faction"], STYLES["spain"])
    if "pirate_haven" in tags:
        st = STYLES["pirates"]
    quay = 304

    back = new()
    bp = back.load()
    gradient(bp, 0, quay, SKIES["day"])
    clouds(back, rng, rng.randint(3, 6), 30, 150, [(176, 186, 210), (236, 236, 244), (255, 255, 255)])
    haze = SKIES["day"][2]
    ridge(bp, rng, 290, rng.randint(70, 130), mix((70, 110, 96), haze, 0.55), mix((120, 150, 120), haze, 0.5), mix((50, 80, 80), haze, 0.55), bottom=quay)

    front = new(False)
    fp = front.load()
    d = ImageDraw.Draw(front)
    lights_im = new(False)
    li = ImageDraw.Draw(lights_im)
    green = JUNGLE if "pirate_haven" not in tags else [(36, 82, 52), (52, 104, 60), (76, 132, 70), (110, 160, 86)]
    hx0 = rng.choice([-60, 200, 380])
    ridge(fp, rng, quay - 6, rng.randint(40, 70), green[1], green[3], green[0], x0=hx0, x1=hx0 + rng.randint(420, 620), speckle=green)
    if "plantation" in tags:  # cane fields in rows up the hill, and a mill
        fx = rng.randint(80, 520)
        for row in range(6):
            y = quay - 22 - row * 5
            d.line([fx + row * 6, y, fx + 200 - row * 8, y], fill=rgba((172, 176, 86)), width=2)
            d.line([fx + row * 6, y + 2, fx + 200 - row * 8, y + 2], fill=rgba((120, 130, 60)))
        windmill(d, fx + 210, quay - 18)
    d.rectangle([0, quay - 8, W, quay], fill=rgba((196, 176, 132)))  # the shore the town stands on

    span = max(180, min(640, int(p["population"] / 14)))
    x0 = rng.randint(max(20, 400 - span // 2 - 60), max(20, 400 - span // 2 + 40))
    x1 = min(W - 20, x0 + span)
    if "pirate_haven" in tags:
        for k in range(rng.randint(4, 7)):
            palm(d, rng.randint(20, W - 20), quay - 6, rng.randint(30, 48), rng)
        town(front, d, li, rng, x0, x1, quay - 2, st, back_row=False)
        for k in range(3):  # cook fires
            smoke(d, rng, rng.randint(x0, x1), quay - 26, 60, (120, 116, 112))
    else:
        town(front, d, li, rng, x0, x1, quay - 2, st)
    if "capital" in tags or "fair_town" in tags or p["population"] >= 3000:
        tower(d, li, (x0 + x1) // 2 + rng.randint(-60, 60), quay - 2, 14, 66, st, dome=p["faction"] == "spain")
    elif "pirate_haven" not in tags:
        tower(d, li, rng.randint(x0 + 10, max(x0 + 11, x1 - 20)), quay - 2, 10, 44, st)
    if "capital" in tags:  # the governor's palace: long and arcaded
        px0 = max(10, x0 - 10 + rng.randint(0, 40))
        d.rectangle([px0, quay - 30, px0 + 70, quay - 2], fill=rgba(STYLES["spain"]["wall"] if p["faction"] == "spain" else st["wall"]), outline=BLACK)
        for k in range(px0 + 4, px0 + 66, 8):
            d.arc([k, quay - 16, k + 6, quay - 4], 180, 360, fill=BLACK)
        windows(d, li, rng, px0 + 4, quay - 26, px0 + 66, quay - 18, step=8, lit=0.7)
        d.polygon([(px0 - 2, quay - 30), (px0 + 6, quay - 36), (px0 + 64, quay - 36), (px0 + 72, quay - 30)], fill=rgba(st["roof"]), outline=BLACK)
    if "garrison" in tags or "capital" in tags:
        side = rng.choice([0, 1])
        fw = 120 if "garrison" in tags else 90
        fort(front, d, li, 20 if side == 0 else W - 20 - fw, quay - 2, fw, 46 if "garrison" in tags else 34, p["faction"])
    elif "pirate_haven" in tags:
        flag(front, "pirates", x1 - 30, quay - 70, 0.6)
    else:  # a small battery by the water
        fort(front, d, li, rng.choice([30, W - 110]), quay - 2, 80, 24, p["faction"])
    if "free_port" in tags or "fair_town" in tags:  # warehouses on the quay
        for k in range(3):
            wx = rng.randint(x0, max(x0 + 1, x1 - 40))
            d.rectangle([wx, quay - 18, wx + 40, quay - 2], fill=rgba(st["wall_d"]), outline=BLACK)
            d.rectangle([wx + 16, quay - 12, wx + 24, quay - 2], fill=(50, 36, 26, 255))
            d.polygon([(wx - 2, quay - 18), (wx + 20, quay - 26), (wx + 42, quay - 18)], fill=rgba(st["roof"]), outline=BLACK)
    if "fair_town" in tags:
        awnings(d, rng.randint(60, 200), rng.randint(320, 460), quay - 2, rng)

    water = (34, 92, 112)
    d.rectangle([0, quay - 2, W, quay + 3], fill=STONE, outline=None)  # the quay wall
    d.line([0, quay - 2, W, quay - 2], fill=STONE_HI)
    d.line([0, quay + 3, W, quay + 3], fill=BLACK)
    gradient(fp, quay + 4, H, [(64, 132, 140), water, (16, 52, 82)])
    reflect(fp, quay + 3, 46, water)
    sea_rng = random.Random(pid + "sea")
    for _ in range(500):
        y = sea_rng.randint(quay + 6, H - 2)
        n = int(2 + (y - quay) / 10)
        x = sea_rng.randint(-n, W)
        for i in range(n):
            if 0 <= x + i < W:
                fp[x + i, y] = (150, 200, 206, 255)
    if rng.random() < 0.6:  # a pier
        px0 = rng.randint(200, 560)
        d.rectangle([px0, quay + 3, px0 + 8, quay + 40], fill=(122, 88, 56, 255), outline=BLACK)
        for k in range(quay + 8, quay + 44, 9):
            d.rectangle([px0 - 1, k, px0 + 9, k + 1], fill=(80, 56, 36, 255))

    kinds = {"free_port": ["fluyt", "fluyt", "brig", "schooner"], "fair_town": ["galleon", "galleon", "fluyt", "sloop"],
             "pirate_haven": ["sloop", "brigantine", "schooner"], "garrison": ["frigate", "brig"], "capital": ["frigate", "galleon", "brig"]}
    pool = next((kinds[t] for t in tags if t in kinds), ["sloop", "schooner"])
    count = 4 if ("free_port" in tags or "fair_town" in tags) else (3 if "capital" in tags else 2)
    xs = sorted(rng.sample(range(80, 720, 40), count))
    for i, sx in enumerate(xs):
        ship(front, pool[i % len(pool)], sx, quay + 34 + (i % 2) * 14, 0.5, flip=rng.random() < 0.5, sails=False, lights=li)
    if rng.random() < 0.7:  # a ship close by, half out of frame
        ship(front, rng.choice(pool), rng.choice([40, W - 40]), H - 6, 1.0, flip=rng.random() < 0.5, sails=False, lights=li)

    folder = OUT / f"port_{pid}"
    save(back, folder / "back.png")
    save(front, folder / "front.png")
    save(lights_im, folder / "lights.png")


# ---- the other scenes: one hour each, all on back.png -------------------------------------------------

def scene_sea(key, sky, rng, at_night=False):
    im = new()
    px = im.load()
    horizon = 236
    gradient(px, 0, horizon, SKIES[sky])
    if sky == "storm":  # grey: no sun, low cloud, a sullen swell
        clouds(im, rng, 6, 30, 160, [(60, 64, 72), (96, 100, 108), (130, 134, 140)])
        sea(px, rng, horizon, H, [(96, 106, 112), (54, 68, 78), (26, 34, 44)], (150, 160, 166), waves=700)
        return im
    if at_night:
        stars(px, rng, horizon - 30)
        disc(px, 600, 70, 14, (236, 236, 214), (120, 130, 170), 46)
        clouds(im, rng, 3, 40, 160, [(14, 18, 40), (34, 40, 70), (70, 76, 110)])
    else:
        disc(px, 620, 64, 18, (255, 246, 210), (255, 240, 200), 60)
        clouds(im, rng, 5, 40, 170, [(176, 186, 210), (236, 236, 244), (255, 255, 255)])
    ridge(px, rng, horizon, 24, mix((70, 110, 96), SKIES[sky][2], 0.6), mix((120, 150, 120), SKIES[sky][2], 0.5),
          mix((50, 80, 80), SKIES[sky][2], 0.6), x0=40, x1=260)
    if at_night:
        sea(px, rng, horizon, H, [(30, 40, 70), (10, 18, 40), (4, 8, 22)], (70, 86, 130), waves=700)
        glint(px, rng, 600, horizon, H, (210, 214, 200), 60)
    else:
        sea(px, rng, horizon, H, [(120, 170, 196), (44, 104, 150), (20, 54, 98)], (196, 224, 236))
        glint(px, rng, 620, horizon, H, (255, 248, 220), 40)
    return im


def make_scenes():
    out = {}
    rng = random.Random(3)

    im = scene_sea("sea_day", "day", rng)
    ship(im, "brig", 380, 312, flip=False)
    out["sea_day"] = im

    im = scene_sea("sea_night", "night", rng, at_night=True)
    d = ImageDraw.Draw(im)
    ship(im, "brigantine", 360, 312, flip=True, lights=d)
    out["sea_night"] = im

    im = scene_sea("sail_ho", "day", rng)
    ship(im, "frigate", 520, 262, 0.5, flip=True)
    ship(im, "sloop", 260, 330, flip=False)
    out["sail_ho"] = im

    im = scene_sea("fight", "day", rng)
    d = ImageDraw.Draw(im)
    ship(im, "galleon", 560, 270, 0.5, flip=True)
    ship(im, "brig", 260, 318, flip=False)
    for k in range(5):  # broadsides and their smoke
        smoke(d, rng, 330 + k * 14, 290, 40, (220, 214, 206))
        smoke(d, rng, 520 + k * 9, 256, 30, (220, 214, 206))
    for fx, fy in [(350, 288), (380, 286), (530, 254)]:
        d.ellipse([fx - 5, fy - 3, fx + 5, fy + 3], fill=(255, 220, 110, 255))
    out["fight"] = im

    # the storm: a low black sky, a bolt, steep seas and a ship heeled over with her sails in rags
    im = new()
    px = im.load()
    gradient(px, 0, 250, SKIES["storm"])
    clouds(im, rng, 9, 20, 200, [(20, 22, 28), (44, 48, 56), (74, 80, 90)])
    d = ImageDraw.Draw(im)
    x, y = 520, 40
    while y < 240:
        nx, ny = x + rng.randint(-14, 14), y + rng.randint(12, 26)
        d.line([x, y, nx, ny], fill=(240, 240, 255, 255), width=2)
        x, y = nx, ny
    sea(px, rng, 250, H, [(70, 82, 90), (34, 48, 58), (14, 22, 30)], (200, 214, 220), waves=1600)
    ship(im, "schooner", 360, 330, tilt=-12, torn=True)
    for _ in range(900):  # rain
        rx, ry = rng.randrange(W), rng.randrange(H - 10)
        d.line([rx, ry, rx - 3, ry + 8], fill=(170, 180, 196, 255))
    out["storm"] = im

    # a hidden cove: clear shallows over sand, a beach, palms, jungle hills, a sloop at anchor
    im = new()
    px = im.load()
    gradient(px, 0, 250, SKIES["day"])
    clouds(im, rng, 4, 40, 150, [(176, 186, 210), (236, 236, 244), (255, 255, 255)])
    ridge(px, rng, 270, 120, JUNGLE[1], JUNGLE[3], JUNGLE[0], x0=-80, x1=420, speckle=JUNGLE)
    ridge(px, rng, 270, 90, JUNGLE[1], JUNGLE[3], JUNGLE[0], x0=380, x1=880, speckle=JUNGLE)
    gradient(px, 270, H, [(110, 206, 196), (52, 160, 176), (30, 100, 140)])
    d = ImageDraw.Draw(im)
    d.pieslice([120, 240, 680, 320], 0, 180, fill=(232, 214, 160, 255))
    d.arc([120, 240, 680, 320], 0, 180, fill=(250, 244, 220, 255))
    for k in range(7):
        palm(d, rng.randint(140, 660), 284, rng.randint(34, 60), rng)
    ship(im, "sloop", 520, 318, flip=True, sails=False)
    out["cove"] = im

    # a town burning: a red night, smoke in columns, flames on the roofs
    im = new()
    px = im.load()
    gradient(px, 0, 300, SKIES["fire"])
    d = ImageDraw.Draw(im)
    ridge(px, rng, 300, 70, (40, 26, 30), (70, 40, 36), (24, 16, 20))
    town(im, d, None, rng, 120, 680, 298, STYLES["spain"])
    tower(d, None, 390, 298, 12, 46, STYLES["spain"], dome=True)
    for k in range(8):
        smoke(d, rng, rng.randint(120, 680), 270, rng.randint(90, 180), (36, 28, 30))
    for k in range(9):
        flames(d, None, rng, rng.randint(120, 640), 282 + rng.randint(-8, 8), 30)
    gradient(px, 302, H, [(120, 60, 40), (40, 24, 30), (14, 10, 18)])
    reflect(px, 301, 50, (60, 30, 30))
    ship(im, "brig", 200, 330, flip=False, sails=False)
    out["sack"] = im

    # the gallows on a bare hill against the last of the light
    im = new()
    px = im.load()
    gradient(px, 0, 330, SKIES["dusk"])
    disc(px, 300, 290, 34, (255, 210, 130), (255, 170, 100), 90)
    sea(px, rng, 300, H, [(200, 130, 100), (80, 50, 70), (24, 20, 36)], (255, 200, 140), waves=300)
    d = ImageDraw.Draw(im)
    tops = ridge(px, rng, H, 190, (24, 18, 26), (44, 30, 36), (14, 10, 18), x0=330, x1=900)
    gx = 540
    gy = tops[gx] + 4
    d.rectangle([gx, gy - 70, gx + 3, gy], fill=(10, 8, 12, 255))
    d.rectangle([gx, gy - 70, gx + 46, gy - 67], fill=(10, 8, 12, 255))
    d.line([gx + 3, gy - 56, gx + 16, gy - 67], fill=(10, 8, 12, 255), width=2)
    d.line([gx + 38, gy - 67, gx + 38, gy - 44], fill=(10, 8, 12, 255))
    d.ellipse([gx + 34, gy - 46, gx + 42, gy - 38], outline=(10, 8, 12, 255))
    out["gallows"] = im

    # retirement: a fine house above the bay at sundown
    im = new()
    px = im.load()
    gradient(px, 0, 250, SKIES["dusk"])
    clouds(im, rng, 4, 40, 150, [(150, 84, 110), (236, 160, 130), (255, 214, 170)])
    disc(px, 560, 236, 26, (255, 220, 150), (255, 180, 110), 80)
    sea(px, rng, 250, H, [(220, 150, 110), (110, 70, 90), (30, 26, 50)], (255, 200, 140), waves=500)
    glint(px, rng, 560, 250, H, (255, 220, 150), 50)
    d = ImageDraw.Draw(im)
    tops = ridge(px, rng, H, 300, JUNGLE[1], JUNGLE[3], JUNGLE[0], x0=-40, x1=500, speckle=JUNGLE)
    house(d, d, rng, 200, tops[235] + 8, 70, 36, STYLES["spain"])
    for k in (170, 300, 350):
        palm(d, k, tops[k] + 4, 50, rng)
    ship(im, "schooner", 560, 300, 0.5, sails=False)
    out["retire"] = im

    # lost at sea: wreckage on a grey swell
    im = scene_sea("lost", "storm", rng)
    d = ImageDraw.Draw(im)
    d.line([300, 290, 420, 270], fill=(96, 70, 46, 255), width=5)  # a broken mast with a rag of sail
    d.polygon([(380, 274), (400, 250), (420, 270)], fill=(200, 196, 180, 255), outline=BLACK)
    for _ in range(14):
        x, y = rng.randint(200, 600), rng.randint(250, 320)
        d.rectangle([x, y, x + rng.randint(6, 18), y + 2], fill=(90, 66, 44, 255))
    for k in range(3):  # gulls
        x, y = rng.randint(200, 600), rng.randint(140, 220)
        d.line([x - 6, y, x, y + 3, x + 6, y], fill=(30, 30, 34, 255))
    out["lost"] = im

    for key, img in out.items():
        save(img, OUT / key / "back.png")


if __name__ == "__main__":
    ports = json.loads((ROOT / "data" / "ports.json").read_text(encoding="utf-8"))
    for pid, p in ports.items():
        if not pid.startswith("_"):
            port_scene(pid, p)
    make_scenes()
