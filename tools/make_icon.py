"""The app icon and the itch.io cover, from the game's own art (our own, CC0). Run from the project root:

    python tools/make_icon.py

icon.png (256, the window icon), icon.ico (the exe, several sizes): a brig under the black flag on a night sea.
build/itch_cover.png (630x500, itch.io's cover size): the map screenshot with the title on it.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHIP = ROOT / "assets" / "ships_side" / "brig"
NIGHT = [(14, 20, 44), (22, 34, 70), (34, 52, 98)]
SEA = [(16, 40, 78), (28, 66, 112), (70, 120, 160)]


def icon():
    lay = json.loads((SHIP / "layout.json").read_text())
    hull = Image.alpha_composite(Image.open(SHIP / "hull.png"), Image.open(SHIP / "sails.png"))
    ship = Image.new("RGBA", (hull.width, hull.height + 40))  # headroom for the flag over the masthead
    ship.alpha_composite(hull, (0, 40))
    fx, fy = lay["flag"]
    flag = Image.open(ROOT / "assets" / "flags" / "black.png").resize((52, 34), Image.NEAREST)
    ship.alpha_composite(flag, (fx, fy + 40 - 34))
    ship = ship.crop(ship.getbbox())

    S = 64  # drawn at 64 px, scaled up whole so it stays pixel art
    im = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):  # night sky in bands, then the sea
        band = NIGHT[min(2, y * 3 // 44)] if y < 44 else SEA[0 if y > 52 else 1]
        d.line([(0, y), (S, y)], fill=band + (255,))
    for x in range(0, S, 7):  # a glint on each swell
        d.point((x + (3 if x % 2 else 0), 47 + x % 3), fill=SEA[2] + (255,))
    for x, y in [(8, 6), (20, 12), (50, 5), (58, 16), (36, 4)]:
        d.point((x, y), fill=(220, 224, 200, 255))
    w = 46
    small = ship.resize((w, round(ship.height * w / ship.width)), Image.LANCZOS)
    a = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)  # hard pixel edges
    small.putalpha(a)
    im.alpha_composite(small, ((S - w) // 2, 50 - small.height))
    mask = Image.new("L", (S, S), 0)  # rounded corners, in whole pixels
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=8, fill=255)
    im.putalpha(mask)
    big = im.resize((256, 256), Image.NEAREST)
    big.save(ROOT / "icon.png")
    big.save(ROOT / "icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote icon.png, icon.ico")


def cover():
    shot = Image.open(ROOT / "docs" / "screenshots" / "map.png").convert("RGB")
    W, H = 630, 500
    crop = shot.crop((937, 120, 1920, 900)).resize((W, H), Image.LANCZOS)  # Jamaica and Hispaniola, under the top bar and above the message log
    d = ImageDraw.Draw(crop, "RGBA")
    d.rectangle([0, 0, W, 120], fill=(10, 16, 34, 200))
    font = ImageFont.truetype(str(ROOT / "assets" / "ui" / "fonts" / "PixelifySans.ttf"), 54)
    sub = ImageFont.truetype(str(ROOT / "assets" / "ui" / "fonts" / "IMFellEnglish-Italic.ttf"), 24)
    for text, f, y, col in [("Plunder and Pillage", font, 18, (244, 232, 196)), ("The Caribbean, 1680", sub, 82, (200, 210, 230))]:
        tw = d.textlength(text, font=f)
        d.text(((W - tw) / 2, y), text, font=f, fill=col)
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    crop.save(out / "itch_cover.png")
    print("wrote build/itch_cover.png")


icon()
cover()
