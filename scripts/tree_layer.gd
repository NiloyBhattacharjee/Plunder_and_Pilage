class_name TreeLayer
extends Node2D
## Trees standing on the world map's land: palms along the coasts, jungle inland, pines up high, none on bare rock
## (the height bands the land shader paints). Placed once on a jittered grid, each drawn upright (Geo.UPRIGHT),
## lifted as far as its hill rises in the tilted view (Geo.HILL), back to front. Drawn once; Godot caches it.
## Sprites: assets/map/trees.png (tools/make_map_trees.py), one row of CELL cells, the foot at the bottom middle.

const SHEET := preload("res://assets/map/trees.png")
const CELL := Vector2(12, 14)
const BROADLEAF := [0, 1, 2]
const PALMS := [3, 4]
const PINES := [5, 6]
const SPACING := 6.0  # map pixels between trees in the thickest jungle

var _trees: Array = []


func _ready() -> void:
	_trees = place()


## Every tree: {foot (on the flat map), lift (map pixels it rises with its hill), cell}, north to south.
static func place() -> Array:
	var height: Image = load("res://assets/map/height.png").get_image()
	var mask: Image = load("res://data/map/terrain.png").get_image()
	var size := Vector2(Data.map.size[0], Data.map.size[1])
	var cell_px := float(Data.map.cell_px)
	var cot := sqrt(1.0 - Geo.TILT * Geo.TILT) / Geo.TILT
	var clearings := FastNoiseLite.new()
	clearings.seed = 7
	clearings.frequency = 0.02
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var trees := []
	for gy in int(size.y / SPACING):
		for gx in int(size.x / SPACING):
			var foot := (Vector2(gx, gy) + Vector2(rng.randf(), rng.randf())) * SPACING
			var roll := rng.randf()
			var cell_at := Vector2i((foot / cell_px).floor())  # the cell TerrainGrid sees; the height map shares its grid
			if mask.get_pixelv(cell_at).r8 <= 224:  # land only
				continue
			var h := height.get_pixelv(cell_at).r
			var woods := smoothstep(0.12, 0.28, h) * (1.0 - smoothstep(0.8, 0.88, h))
			var thick := woods * (0.45 + 0.55 * (clearings.get_noise_2dv(foot) * 0.5 + 0.5))
			var cell: int
			if h < 0.1 and roll < 0.18:
				cell = PALMS[rng.randi() % PALMS.size()]
			elif roll < thick * 0.9 or (h < 0.14 and roll < 0.04):
				cell = PINES[rng.randi() % PINES.size()] if rng.randf() < (h - 0.55) * 4.0 else BROADLEAF[rng.randi() % BROADLEAF.size()]
			else:
				continue
			trees.append({"foot": foot, "lift": h * Geo.HILL * cot, "cell": cell})
	return trees


func _draw() -> void:
	var art: float = Data.table("palette").map_pixel
	var size := CELL * art * Geo.UPRIGHT
	for t in _trees:
		var at: Vector2 = ((t.foot - Vector2(0.0, t.lift)) / art).floor() * art  # on the art-pixel grid
		draw_texture_rect_region(SHEET, Rect2(at - Vector2(size.x / 2.0, size.y), size), Rect2(Vector2(t.cell * CELL.x, 0.0), CELL))
