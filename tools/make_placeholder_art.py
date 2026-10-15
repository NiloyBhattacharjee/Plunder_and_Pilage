"""Generate placeholder art in the sea-chart style: ships (hull, damage, sail states), flags, portrait parts,
goods icons and a paper panel texture. All of it is our own work (CC0).

Real art replaces these files one by one; game code only knows the paths in data/*.json.
Usage: tools/.venv/Scripts/python tools/make_placeholder_art.py
"""
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "assets"
INK = (59, 42, 26, 255)
CREAM = (243, 234, 210, 255)
FONT = str(A / "ui" / "fonts" / "IMFellEnglish-Regular.ttf")


def engrave(img, spacing=4, cross=False, stipple=False, shadow_from=0.5, alpha=150):
    """Engraver's shading: hatch lines (or stipple dots) over the shadow side of whatever is drawn in `img`.
    Light comes from the upper left, so the shadow is everything right of `shadow_from` across the part's width."""
    a = img.split()[3]
    box = a.getbbox()
    if not box:
        return img
    w, h = img.size
    shade = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(shade)
    x0 = box[0] + (box[2] - box[0]) * shadow_from
    sd.polygon([(x0, box[1]), (box[2], box[1]), (box[2], box[3]), (x0 - (box[3] - box[1]) * 0.25, box[3])], fill=255)
    lines = Image.new("L", (w, h), 0)
    ld = ImageDraw.Draw(lines)
    if stipple:
        rnd = random.Random(w * 7 + h)
        for _ in range(int(w * h / (spacing * spacing))):
            ld.point((rnd.randrange(w), rnd.randrange(h)), fill=255)
    else:
        for k in range(-h, w + h, spacing):
            ld.line([(k, 0), (k + h, h)], fill=255, width=1)
            if cross:
                ld.line([(k + h, 0), (k, h)], fill=255, width=1)
    from PIL import ImageChops
    mask = ImageChops.multiply(ImageChops.multiply(lines, shade), a)
    mask = mask.point(lambda v: v * alpha // 255)
    ink = Image.new("RGBA", (w, h), INK)
    out = img.copy()
    out.paste(ink, (0, 0), mask)
    return out


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# ---------------------------------------------------------------- ships
SHIPS = {  # length at 2x, width factor, rig per mast (s = square, f = fore-and-aft)
    "sloop": (96, 0.32, "f", 8), "schooner": (104, 0.30, "ff", 6), "brigantine": (120, 0.32, "sf", 14),
    "brig": (128, 0.33, "ss", 18), "fluyt": (140, 0.36, "sss", 6), "frigate": (160, 0.32, "sss", 32),
    "galleon": (176, 0.38, "sss", 40), "man_of_war": (200, 0.36, "sss", 70),
}


def hull_outline(cx, cy, L, W):
    pts_r, pts_l = [], []
    for i in range(41):
        t = i / 40
        if t < 0.35:
            f = math.sin(math.pi / 2 * t / 0.35) ** 0.8
        else:
            f = 1.0 - 0.28 * ((t - 0.35) / 0.65) ** 1.6
        y = cy - L / 2 + t * L
        pts_r.append((cx + W / 2 * f, y))
        pts_l.append((cx - W / 2 * f, y))
    return pts_r + pts_l[::-1]


def draw_hull(L, wf, guns, damaged):
    W = L * wf
    size = (int(W * 2.8), int(L * 1.15))
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = size[0] / 2, size[1] / 2
    d.polygon(hull_outline(cx, cy, L, W), fill=(196, 160, 112, 255), outline=INK)
    d.line(hull_outline(cx, cy, L, W) + [hull_outline(cx, cy, L, W)[0]], fill=INK, width=3)
    d.polygon(hull_outline(cx, cy + L * 0.02, L * 0.86, W * 0.72), fill=(222, 196, 150, 255))
    for k in range(-2, 3):  # deck planks
        x = cx + k * W * 0.12
        d.line([(x, cy - L * 0.3), (x, cy + L * 0.4)], fill=(120, 92, 60, 255), width=1)
    ports = min(guns // 2, 16)
    for i in range(ports):  # gun ports along each side
        y = cy - L * 0.25 + (i + 0.5) * (L * 0.62 / max(ports, 1))
        for side in (-1, 1):
            x = cx + side * W * 0.43
            d.rectangle([x - 2, y - 2, x + 2, y + 2], fill=INK)
    if damaged:
        rnd = random.Random(L)
        for _ in range(6):
            x = cx + rnd.uniform(-W * 0.35, W * 0.35)
            y = cy + rnd.uniform(-L * 0.35, L * 0.4)
            r = rnd.uniform(4, 9)
            d.ellipse([x - r, y - r * 0.7, x + r, y + r * 0.7], fill=(40, 28, 18, 170))
        for _ in range(4):
            x = cx + rnd.uniform(-W * 0.3, W * 0.3)
            y = cy + rnd.uniform(-L * 0.3, L * 0.3)
            d.line([(x, y), (x + rnd.uniform(-10, 10), y + rnd.uniform(6, 16)), (x + rnd.uniform(-12, 12), y + rnd.uniform(14, 26))], fill=INK, width=2)
    return engrave(img, spacing=3 if damaged else 4, cross=damaged, shadow_from=0.55)


def mast_positions(L, n, cy):
    fr = {1: [0.42], 2: [0.33, 0.6], 3: [0.28, 0.5, 0.72]}[n]
    return [cy - L / 2 + f * L for f in fr]


def draw_sails(L, wf, rig, state):
    W = L * wf
    size = (int(W * 2.8), int(L * 1.15))
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = size[0] / 2, size[1] / 2
    rnd = random.Random(L + len(state))
    for kind, y in zip(rig, mast_positions(L, len(rig), cy)):
        if kind == "s":
            span = {"full": W * 1.25, "half": W * 0.85, "torn": W * 1.25, "furled": W * 1.05}[state]
            depth = {"full": L * 0.075, "half": L * 0.05, "torn": L * 0.07, "furled": 3}[state]
            if state == "furled":
                d.rounded_rectangle([cx - span, y - 3, cx + span, y + 3], radius=3, fill=CREAM, outline=INK, width=2)
            else:
                pts = [(cx - span, y + depth * 0.3)]
                for i in range(21):
                    t = i / 20
                    pts.append((cx - span + 2 * span * t, y - depth * math.sin(math.pi * t) + depth * 0.3))
                pts.append((cx + span, y + depth * 0.3))
                d.polygon(pts, fill=CREAM, outline=INK)
                d.line(pts + [pts[0]], fill=INK, width=2)
                d.line([(cx - span, y + depth * 0.3), (cx + span, y + depth * 0.3)], fill=INK, width=3)  # yard
        else:  # fore-and-aft: a long lens of canvas from the mast toward the stern
            length = {"full": L * 0.42, "half": L * 0.3, "torn": L * 0.42, "furled": L * 0.38}[state]
            width = {"full": W * 0.42, "half": W * 0.26, "torn": W * 0.42, "furled": 4}[state]
            if state == "furled":
                d.rounded_rectangle([cx - 3, y, cx + 3, y + length], radius=3, fill=CREAM, outline=INK, width=2)
            else:
                pts = [(cx, y)]
                for i in range(1, 20):
                    t = i / 20
                    pts.append((cx + width * math.sin(math.pi * t) * (1 - 0.3 * t), y + length * t))
                pts.append((cx, y + length))
                d.polygon(pts, fill=CREAM, outline=INK)
                d.line(pts, fill=INK, width=2)
                d.line([(cx, y), (cx, y + length)], fill=INK, width=3)  # boom
        d.ellipse([cx - 3, y - 3, cx + 3, y + 3], fill=INK)  # mast
    if rig[0] == "f":  # jib at the bow
        top = cy - L / 2
        jib = {"full": W * 0.35, "half": W * 0.2, "torn": W * 0.35, "furled": 0}[state]
        if jib:
            d.polygon([(cx, top + 2), (cx + jib, top + L * 0.25), (cx, top + L * 0.3)], fill=CREAM, outline=INK)
    if state == "torn":
        for _ in range(7):
            x = cx + rnd.uniform(-W * 1.1, W * 1.1)
            y = cy + rnd.uniform(-L * 0.35, L * 0.35)
            r = rnd.uniform(3, 7)
            d.polygon([(x + r * math.cos(a) * rnd.uniform(0.5, 1.2), y + r * math.sin(a) * rnd.uniform(0.5, 1.2))
                       for a in [k * math.pi / 3 for k in range(6)]], fill=(0, 0, 0, 0))
    return engrave(img, spacing=3, stipple=True, shadow_from=0.6, alpha=170)


def make_ships():
    for t, (L, wf, rig, guns) in SHIPS.items():
        folder = A / "ships" / t
        save(draw_hull(L, wf, guns, False), folder / "hull.png")
        save(draw_hull(L, wf, guns, True), folder / "hull_damaged.png")
        for state in ("furled", "half", "full", "torn"):
            save(draw_sails(L, wf, rig, state), folder / f"sails_{state}.png")


# ---------------------------------------------------------------- flags
def make_flags():
    flags = {}
    W, H = 40, 26
    def base(color):
        img = Image.new("RGBA", (W, H), color)
        return img, ImageDraw.Draw(img)
    specs = {}
    img, d = base((245, 242, 232, 255)); d.rectangle([17, 0, 23, H], fill=(190, 30, 35, 255)); d.rectangle([0, 10, W, 16], fill=(190, 30, 35, 255)); specs["england"] = ("St George's cross", img)
    img, d = base((245, 242, 232, 255)); d.line([(2, 2), (W - 2, H - 2)], fill=(185, 30, 30, 255), width=5); d.line([(2, H - 2), (W - 2, 2)], fill=(185, 30, 30, 255), width=5); specs["spain"] = ("Cross of Burgundy", img)
    img, d = base((248, 248, 244, 255))
    for x, y in ((10, 8), (28, 8), (19, 18)):
        d.polygon([(x, y - 4), (x + 3, y), (x, y + 4), (x - 3, y)], fill=(200, 160, 40, 255))
    specs["france"] = ("Royal white with lilies", img)
    img, d = base((0, 0, 0, 0)); d.rectangle([0, 0, W, 8], fill=(230, 120, 30, 255)); d.rectangle([0, 9, W, 17], fill=(248, 248, 244, 255)); d.rectangle([0, 18, W, H], fill=(30, 70, 150, 255)); specs["dutch"] = ("Prince's flag", img)
    img, d = base((20, 18, 16, 255)); d.ellipse([15, 4, 25, 13], fill=(240, 236, 225, 255)); d.rectangle([17, 12, 23, 15], fill=(240, 236, 225, 255))
    d.ellipse([17, 7, 19, 9], fill=(20, 18, 16, 255)); d.ellipse([21, 7, 23, 9], fill=(20, 18, 16, 255))
    d.line([(11, 16), (29, 23)], fill=(240, 236, 225, 255), width=2); d.line([(11, 23), (29, 16)], fill=(240, 236, 225, 255), width=2); specs["black"] = ("The black flag", img)
    img, d = base((170, 25, 25, 255)); specs["red"] = ("The red flag: no quarter", img)
    img, d = base((245, 242, 232, 255)); specs["white"] = ("Plain white", img)
    for fid, (name, img) in specs.items():
        ImageDraw.Draw(img).rectangle([0, 0, W - 1, H - 1], outline=INK, width=1)
        save(img, A / "flags" / f"{fid}.png")
        flags[fid] = {"name": name, "path": f"res://assets/flags/{fid}.png"}
    return flags


# ---------------------------------------------------------------- portraits
S = 128


def layer():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def make_portraits():
    parts = {}
    def add(layer_name, pid, img, tags=("any",)):
        path = A / "portraits" / layer_name / f"{pid}.png"
        save(img, path)
        parts.setdefault(layer_name, []).append({"id": pid, "path": f"res://assets/portraits/{layer_name}/{pid}.png", "tags": list(tags)})

    for pid, col in (("parchment", (234, 217, 176)), ("sea", (176, 196, 186)), ("tavern", (150, 112, 78)), ("crimson", (122, 46, 36))):
        img, d = layer()
        d.rectangle([0, 0, S, S], fill=col + (255,))
        for r in range(90, 30, -6):  # darker towards the corners, like an engraved oval frame
            shade = tuple(max(0, int(c * (0.78 + 0.22 * (r - 30) / 60) ** -0.0)) for c in col)
        rnd = random.Random(len(pid))
        for _ in range(400):  # light paper speckle
            x, y = rnd.randrange(S), rnd.randrange(S)
            d.point((x, y), fill=tuple(max(0, c - 18) for c in col) + (255,))
        frame = Image.new("RGBA", (S, S), (0, 0, 0, 0))  # an engraved oval frame: cross-hatching outside the oval
        fd = ImageDraw.Draw(frame)
        fd.rectangle([0, 0, S, S], fill=col + (255,))
        fd.ellipse([8, 4, S - 8, S + 30], fill=(0, 0, 0, 0))
        frame = engrave(frame, spacing=3, cross=True, shadow_from=0.0, alpha=110)
        img.alpha_composite(frame)
        d = ImageDraw.Draw(img)
        d.ellipse([8, 4, S - 8, S + 30], outline=INK, width=2)
        d.rectangle([0, 0, S - 1, S - 1], outline=INK, width=3)
        add("background", pid, img)

    def body(pid, coat, tags, trim=None, collar=None, stripes=None):
        img, d = layer()
        d.pieslice([10, 92, 118, 200], 180, 360, fill=coat, outline=INK, width=2)
        if stripes:
            for y in range(98, S, 7):
                d.line([(22, y), (106, y)], fill=stripes, width=3)
        if collar:
            d.polygon([(52, 94), (64, 116), (76, 94)], fill=collar, outline=INK)
        if trim:
            d.line([(44, 96), (56, S)], fill=trim, width=3)
            d.line([(84, 96), (72, S)], fill=trim, width=3)
            for y in (108, 118):
                d.ellipse([60, y, 66, y + 6], fill=trim)
        add("body", pid, engrave(img, spacing=3, shadow_from=0.55, alpha=170), tags)
    body("sailor_shirt", (226, 214, 186, 255), ["crew"], collar=(200, 186, 156, 255))
    body("striped_shirt", (238, 236, 228, 255), ["crew", "pirate"], stripes=(52, 80, 130, 255))
    body("pirate_coat", (176, 84, 70, 255), ["pirate", "captain"], trim=(212, 170, 60, 255), collar=(240, 236, 225, 255))
    body("navy_coat", (92, 108, 150, 255), ["navy", "officer", "captain"], trim=(212, 170, 60, 255), collar=(240, 236, 225, 255))
    body("merchant_coat", (160, 128, 92, 255), ["merchant", "captain", "official"], collar=(245, 243, 236, 255))
    body("governor_coat", (128, 96, 140, 255), ["governor", "official"], trim=(220, 190, 90, 255), collar=(250, 250, 250, 255))
    body("priest_robe", (70, 62, 58, 255), ["priest"], collar=(250, 250, 250, 255))

    def head(pid, box):
        img, d = layer()
        d.rectangle([52, 78, 76, 100], fill=(232, 232, 232, 255), outline=INK)  # neck
        d.ellipse([box[0] - 6, 50, box[0] + 4, 66], fill=(236, 236, 236, 255), outline=INK)  # ears
        d.ellipse([box[2] - 4, 50, box[2] + 6, 66], fill=(236, 236, 236, 255), outline=INK)
        d.ellipse(box, fill=(246, 246, 246, 255), outline=INK, width=2)
        add("head", pid, engrave(img, spacing=3, stipple=True, shadow_from=0.6, alpha=120))
    head("oval", [40, 24, 88, 86])
    head("round", [36, 28, 92, 86])
    head("long", [42, 20, 86, 90])

    img, d = layer()
    for y in (40, 45):
        d.arc([50, y - 6, 78, y + 4], 200, 340, fill=(90, 70, 50, 110), width=1)
    d.line([(46, 70), (52, 76)], fill=(90, 70, 50, 140), width=1); d.line([(82, 70), (76, 76)], fill=(90, 70, 50, 140), width=1)
    d.line([(52, 38), (76, 38)], fill=(90, 70, 50, 140), width=1); d.line([(54, 34), (74, 34)], fill=(90, 70, 50, 120), width=1)
    add("wrinkles", "aged", img)

    for pid, draw in (
        ("dots", lambda d: [d.ellipse([x - 3, 50, x + 3, 56], fill=INK) for x in (54, 74)]),
        ("almond", lambda d: [d.chord([x - 6, 49, x + 6, 57], 0, 360, fill=(250, 250, 250, 255), outline=INK) or d.ellipse([x - 2, 51, x + 2, 55], fill=INK) for x in (54, 74)]),
        ("heavy", lambda d: [d.line([(x - 6, 50), (x + 6, 50)], fill=INK, width=3) or d.ellipse([x - 2, 52, x + 2, 56], fill=INK) for x in (54, 74)]),
        ("squint", lambda d: [d.line([(x - 6, 53), (x + 6, 53)], fill=INK, width=2) for x in (54, 74)]),
    ):
        img, d = layer(); draw(d)
        for x in (54, 74):
            d.line([(x - 7, 45), (x + 6, 44)], fill=INK, width=2)  # brows
        add("eyes", pid, img)

    for pid, pts in (("straight", [(64, 54), (62, 66), (67, 67)]), ("hooked", [(63, 52), (59, 64), (66, 67)]), ("broad", [(64, 55), (59, 66), (69, 66)])):
        img, d = layer(); d.line(pts, fill=INK, width=2); add("nose", pid, img)

    for pid, fn in (("line", lambda d: d.line([(56, 74), (72, 74)], fill=INK, width=2)),
                    ("smile", lambda d: d.arc([54, 66, 74, 78], 20, 160, fill=INK, width=2)),
                    ("frown", lambda d: d.arc([54, 72, 74, 84], 200, 340, fill=INK, width=2)),
                    ("open", lambda d: d.ellipse([58, 70, 70, 78], fill=(90, 30, 30, 255), outline=INK))):
        img, d = layer(); fn(d); add("mouth", pid, img)

    W_ = (245, 245, 245, 255)
    for pid, fn in (
        ("short", lambda d: d.chord([38, 18, 90, 60], 180, 360, fill=W_, outline=INK)),
        ("long", lambda d: (d.chord([36, 16, 92, 62], 180, 360, fill=W_, outline=INK), d.rectangle([34, 40, 44, 96], fill=W_, outline=INK), d.rectangle([84, 40, 94, 96], fill=W_, outline=INK))),
        ("queue", lambda d: (d.chord([38, 18, 90, 58], 180, 360, fill=W_, outline=INK), d.rectangle([88, 46, 96, 84], fill=W_, outline=INK), d.rectangle([87, 60, 97, 64], fill=(20, 20, 20, 255)))),
        ("bald", lambda d: (d.chord([36, 40, 46, 64], 90, 270, fill=W_, outline=INK), d.chord([82, 40, 92, 64], 270, 90, fill=W_, outline=INK))),
        ("curly", lambda d: [d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=W_, outline=INK) for x, y in ((44, 34), (54, 24), (66, 21), (78, 25), (86, 36), (40, 46), (88, 48))]),
        ("receding", lambda d: d.chord([38, 22, 90, 50], 200, 340, fill=W_, outline=INK)),
    ):
        img, d = layer(); fn(d); add("hair", pid, engrave(img, spacing=2, shadow_from=0.0, alpha=110))

    for pid, fn in (
        ("stubble", lambda d: [d.point((x, y), fill=(200, 200, 200, 255)) for x in range(46, 84, 3) for y in range(68, 86, 3) if (x - 64) ** 2 / 400 + (y - 72) ** 2 / 250 < 1.2]),
        ("moustache", lambda d: d.polygon([(52, 70), (64, 66), (76, 70), (72, 72), (64, 69), (56, 72)], fill=W_, outline=INK)),
        ("full_beard", lambda d: d.chord([42, 52, 86, 98], 0, 180, fill=W_, outline=INK)),
        ("goatee", lambda d: d.polygon([(58, 78), (70, 78), (66, 92), (62, 92)], fill=W_, outline=INK)),
    ):
        img, d = layer(); fn(d); add("facial_hair", pid, engrave(img, spacing=2, shadow_from=0.0, alpha=110))

    def hat(pid, fn, tags):
        img, d = layer(); fn(d); add("hat", pid, engrave(img, spacing=3, shadow_from=0.5, alpha=150), tags)
    hat("tricorne", lambda d: (d.polygon([(26, 30), (64, 6), (102, 30), (64, 22)], fill=(26, 24, 24, 255), outline=INK), d.line([(30, 29), (64, 22), (98, 29)], fill=(212, 170, 60, 255), width=2)), ["captain", "navy", "officer", "pirate"])
    hat("bandana", lambda d: (d.chord([38, 16, 90, 52], 180, 360, fill=(170, 30, 30, 255), outline=INK), d.polygon([(88, 34), (100, 44), (92, 48)], fill=(170, 30, 30, 255), outline=INK)), ["pirate", "crew"])
    hat("bicorne", lambda d: d.chord([22, 4, 106, 40], 180, 360, fill=(26, 24, 30, 255), outline=INK), ["navy", "officer"])
    hat("wig", lambda d: [d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=(250, 250, 245, 255), outline=INK) for x, y in ((40, 30), (50, 20), (64, 16), (78, 20), (88, 30), (34, 46), (94, 46), (34, 62), (94, 62), (36, 78), (92, 78))], ["governor", "official"])
    hat("straw", lambda d: (d.ellipse([18, 22, 110, 40], fill=(214, 186, 120, 255), outline=INK), d.chord([42, 6, 86, 40], 180, 360, fill=(222, 196, 132, 255), outline=INK)), ["crew", "merchant"])
    hat("knit_cap", lambda d: d.chord([38, 10, 90, 54], 180, 360, fill=(60, 80, 120, 255), outline=INK), ["crew"])

    img, d = layer(); d.ellipse([86, 62, 94, 72], outline=(212, 170, 60, 255), width=2); add("accessory", "earring", img, ["pirate", "crew", "captain"])
    img, d = layer(); d.line([(36, 44), (92, 46)], fill=INK, width=2); d.ellipse([46, 46, 62, 60], fill=(18, 18, 18, 255)); add("eyepatch", "patch", img)
    img, d = layer(); d.line([(70, 46), (80, 70)], fill=(140, 60, 50, 230), width=2); [d.line([(71 + i * 2, 50 + i * 5), (76 + i * 2, 49 + i * 5)], fill=(140, 60, 50, 200)) for i in range(4)]; add("scar", "cheek", img)
    img, d = layer(); d.arc([12, 100, 34, 124], 200, 90, fill=(170, 170, 175, 255), width=4); d.rectangle([20, 118, 30, S], fill=(110, 80, 50, 255), outline=INK); add("hook", "hook", img)
    img, d = layer(); d.line([(64, 104), (64, 118)], fill=(40, 60, 110, 220), width=2); d.arc([56, 108, 72, 122], 20, 160, fill=(40, 60, 110, 220), width=2); d.line([(59, 107), (69, 107)], fill=(40, 60, 110, 220), width=2); add("tattoo", "anchor", img, ["pirate", "crew"])

    data = {
        "_comment": "Layered portraits. Parts are picked from each character's portrait seed, filtered by tags (role, background, traits). Swap art by replacing files; add parts by adding entries.",
        "size": S,
        "layers": ["background", "body", "head", "wrinkles", "eyes", "nose", "mouth", "scar", "facial_hair", "hair", "hat", "eyepatch", "accessory", "tattoo", "hook"],
        "none_chance": {"facial_hair": 0.45, "hat": 0.35, "accessory": 0.75, "tattoo": 0.85, "scar": 0.94},
        "story_layers": {"wrinkles": "age", "eyepatch": "one_eyed", "scar": "scarred", "hook": "hook_hand"},
        "modulate": {"head": "skin", "hair": "hair", "facial_hair": "hair"},
        "skin_tones": {
            "default": ["#f1cfaa", "#e6b991", "#d9a679", "#c99367"],
            "spanish": ["#e6b991", "#d9a679", "#c99367", "#b98256"],
            "portuguese": ["#e0b086", "#cf9a6c", "#b98256"],
            "afro_caribbean": ["#8d5a3b", "#7a4b2f", "#6a3f27", "#a46a45"]
        },
        "hair_colors": {
            "default": ["#2b1d14", "#4a2f1d", "#6b4a2b", "#a87a3d", "#1a1410", "#8a3d1e"],
            "afro_caribbean": ["#1a1410", "#2b1d14"],
            "spanish": ["#1a1410", "#2b1d14", "#4a2f1d"]
        },
        "grey": "#a8a49c", "grey_from_age": 42, "grey_full_age": 65, "wrinkles_from_age": 50,
        "parts": parts,
    }
    (ROOT / "data" / "portraits.json").write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


# ---------------------------------------------------------------- goods icons and UI
GOOD_COLORS = {
    "food": (150, 110, 60), "water": (80, 130, 170), "sugar": (230, 225, 210), "rum": (150, 80, 30), "molasses": (90, 50, 20),
    "tobacco": (120, 90, 40), "cotton": (240, 240, 235), "indigo": (50, 60, 140), "cocoa": (100, 60, 40), "hides": (170, 120, 80),
    "logwood": (140, 40, 50), "silver": (190, 195, 200), "gold": (220, 180, 50), "cloth": (180, 60, 60), "gunpowder": (60, 60, 60),
    "weapons": (120, 120, 130), "tools": (110, 100, 90), "wine": (110, 20, 50),
}


def make_icons():
    font = ImageFont.truetype(FONT, 26)
    goods = json.loads((ROOT / "data" / "goods.json").read_text(encoding="utf-8"))
    for gid, g in goods.items():
        img = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        base = GOOD_COLORS.get(gid, (160, 140, 110))
        col = tuple(int(c * 0.6 + 234 * 0.4) for c in base) + (255,)  # faded towards paper: a wash, not paint
        d.ellipse([3, 3, 45, 45], fill=col, outline=INK, width=2)
        light = sum(col[:3]) > 450
        d.text((24, 25), g["name"][0], font=font, fill=INK if light else CREAM, anchor="mm")
        save(engrave(img, spacing=3, shadow_from=0.6, alpha=90), A / "icons" / "goods" / f"{gid}.png")


def make_fx():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r in range(15, 0, -1):  # soft round puff for smoke, splashes and splinters (tinted in code)
        d.ellipse([16 - r, 16 - r, 16 + r, 16 + r], fill=(255, 255, 255, int(255 * (1 - r / 16) ** 0.6)))
    save(img, A / "fx" / "puff.png")


def make_panel():
    rnd = random.Random(7)
    img = Image.new("RGBA", (96, 96), (234, 217, 176, 255))
    px = img.load()
    for y in range(96):
        for x in range(96):
            n = rnd.randint(-10, 10)
            r, g, b, a = px[x, y]
            px[x, y] = (r + n, g + n, b + int(n * 0.8), 255)
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    d = ImageDraw.Draw(img)
    d.rectangle([1, 1, 94, 94], outline=INK, width=2)
    d.rectangle([5, 5, 90, 90], outline=(59, 42, 26, 120), width=1)
    save(img, A / "ui" / "panel.png")


if __name__ == "__main__":
    make_ships()
    flags = make_flags()
    (ROOT / "data" / "flags.json").write_text("{\n" + ",\n".join(f'  "{k}": ' + json.dumps(v, ensure_ascii=False) for k, v in flags.items()) + "\n}\n", encoding="utf-8")
    make_portraits()
    make_icons()
    make_fx()
    make_panel()
    n = sum(1 for _ in A.rglob("*.png"))
    print(f"wrote {n} png files")
