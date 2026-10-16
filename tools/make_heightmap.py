"""Heights for the world map's land, so the terrain shader can light hills and mountains (assets/map/height.png).

    python tools/make_heightmap.py

Height grows with distance inland (a multi-scale blur of the land mask in data/map/terrain.png), and rough ridges
of noise are added to the interior, so big islands (Cuba, Hispaniola, Jamaica) get mountains and small cays stay
flat. Not real elevation data: a stylised relief. Same size as the terrain mask; 0 = sea level, 255 = the peaks.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
mask = Image.open(ROOT / "data" / "map" / "terrain.png").convert("L")
land = (np.asarray(mask, dtype=np.float32) >= 240).astype(np.float32)
img = Image.fromarray((land * 255).astype(np.uint8))

inland = np.zeros_like(land)
for r, w in [(2, 0.25), (5, 0.35), (12, 0.4)]:  # how much of the land around is land, at growing distances
    inland += np.asarray(img.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0 * w

rng = np.random.default_rng(4)
h, w = land.shape
noise = np.zeros_like(land)
for scale, amp in [(64, 0.5), (24, 0.3), (9, 0.2)]:  # value noise, a few octaves: the ridges
    small = rng.random((h // scale + 2, w // scale + 2)).astype(np.float32)
    big = np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    noise += big * amp
ridges = 1.0 - np.abs(noise * 2.0 - 1.0)  # sharp crests

height = land * inland ** 1.4 * (0.3 + 0.7 * ridges)
height = np.clip(height / np.percentile(height[land > 0], 99.5), 0.0, 1.0)  # the highest peaks just reach the top
out = Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))
out.save(ROOT / "assets" / "map" / "height.png")
print("wrote assets/map/height.png", out.size, "max", int(np.asarray(out).max()))
