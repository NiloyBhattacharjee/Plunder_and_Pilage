"""Build the Caribbean map from Natural Earth (public domain) data.

Outputs:
  data/map/coastline.json  land + shallow polygons in map pixels (for drawing)
  data/map/terrain.png     coarse mask, 1 px per cell: 0 deep, 128 shallow, 192 reef, 255 land (for logic)

Usage: tools/.venv/Scripts/python tools/build_map.py
Needs tools/cache/ne_10m_land.geojson, ne_10m_minor_islands.geojson, ne_10m_bathymetry_K_200.geojson, ne_10m_reefs.geojson
from https://github.com/nvkelso/natural-earth-vector/tree/master/geojson
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw
import numpy as np
from shapely import set_precision, transform
from shapely.geometry import Point, Polygon, box, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / "cache"
OUT = ROOT / "data" / "map"

# Map window and projection. Equirectangular, x scaled by cos(LAT_REF) so shapes look right.
LON_MIN, LON_MAX, LAT_MIN, LAT_MAX = -98.0, -57.5, 7.0, 31.0
LAT_REF = 19.0
PX_PER_DEG = 100.0          # 100 px = 1 degree of latitude = 60 nautical miles
CELL_PX = 4                 # terrain mask resolution
SIMPLIFY_DEG = 0.01         # ~1 km; keeps small Lesser Antilles islands recognisable
MIN_AREA_DEG2 = 0.0004      # drop specks smaller than ~2x2 km
REEF_WIDTH_DEG = 0.03       # reefs are lines in Natural Earth; widen them to ~3 km bands
X_SCALE = math.cos(math.radians(LAT_REF)) * PX_PER_DEG


def to_px(lon, lat):
    return ((lon - LON_MIN) * X_SCALE, (LAT_MAX - lat) * PX_PER_DEG)


def load(name, window):
    data = json.loads((CACHE / f"{name}.geojson").read_text(encoding="utf-8"))
    geoms = [shape(f["geometry"]) for f in data["features"]]
    return unary_union([g.intersection(window) for g in geoms if g.intersects(window)])


def polygons(geom):
    """Exterior rings in map pixels, valid on a 0.1 px grid (Godot can't triangulate self-intersecting rings).
    Holes are dropped: land holes are lakes, shallow holes are islands drawn on top."""
    px = set_precision(transform(geom, lambda c: np.column_stack(to_px(c[:, 0], c[:, 1]))).buffer(0), 0.1)
    out = []
    for p in getattr(px, "geoms", [px]):
        if p.geom_type != "Polygon" or p.area < MIN_AREA_DEG2 * X_SCALE * PX_PER_DEG:
            continue
        p = Polygon(p.exterior)
        if not p.is_valid:  # dropping holes can expose a ring that touches itself
            continue
        out.append([round(c, 1) for x, y in list(p.exterior.coords)[:-1] for c in (x, y)])
    return out


def main():
    window = box(LON_MIN, LAT_MIN, LON_MAX, LAT_MAX)
    land = unary_union([load("ne_10m_land", window), load("ne_10m_minor_islands", window)])
    deep = load("ne_10m_bathymetry_K_200", window)
    shallow = window.difference(deep).difference(land)
    land = land.simplify(SIMPLIFY_DEG)
    shallow = shallow.simplify(SIMPLIFY_DEG)
    reefs = load("ne_10m_reefs", window).buffer(REEF_WIDTH_DEG).difference(land).simplify(SIMPLIFY_DEG)

    w, h = to_px(LON_MAX, LAT_MIN)
    OUT.mkdir(parents=True, exist_ok=True)
    land_px, shallow_px, reef_px = polygons(land), polygons(shallow), polygons(reefs)
    (OUT / "coastline.json").write_text(json.dumps({
        "source": "Natural Earth 1:10m (public domain), built by tools/build_map.py",
        "projection": {"lon_min": LON_MIN, "lat_max": LAT_MAX, "lat_ref": LAT_REF, "px_per_deg": PX_PER_DEG},
        "size": [round(w), round(h)],
        "cell_px": CELL_PX,
        "land": land_px,
        "shallow": shallow_px,
        "reefs": reef_px,
    }, separators=(",", ":")))

    # Rasterise at cell resolution. Shallow first, then reefs, land on top.
    cw, ch = math.ceil(w / CELL_PX), math.ceil(h / CELL_PX)
    img = Image.new("L", (cw, ch), 0)
    draw = ImageDraw.Draw(img)
    for value, polys in ((128, shallow_px), (192, reef_px), (255, land_px)):
        for flat in polys:
            pts = [(flat[i] / CELL_PX, flat[i + 1] / CELL_PX) for i in range(0, len(flat), 2)]
            if len(pts) >= 3:
                draw.polygon(pts, fill=value)
    img.save(OUT / "terrain.png")

    print(f"map {round(w)}x{round(h)} px, mask {cw}x{ch}, "
          f"{len(land_px)} land polys ({sum(len(p) for p in land_px) // 2} pts), "
          f"{len(shallow_px)} shallow polys ({sum(len(p) for p in shallow_px) // 2} pts), {len(reef_px)} reef polys")

    # Sanity check: every port must have sea within ~10 nm, or the game can't find an anchorage.
    ports = json.loads((ROOT / "data" / "ports.json").read_text(encoding="utf-8"))
    for pid, p in ports.items():
        d = land.boundary.distance(Point(p["lon"], p["lat"])) if land.contains(Point(p["lon"], p["lat"])) else 0
        status = "ok" if d < 0.15 else "TOO FAR INLAND"
        print(f"  {pid:16} {status} ({d * 60:.1f} nm from water)")


if __name__ == "__main__":
    main()
