extends Node2D
## Draws the static chart: sea, shallows, land and coastlines. Drawn once; Godot caches it.
## Colours are placeholders for a parchment sea chart. Swap them (or the whole node) for real art later.

const SEA := Color("#c9d6c8")
const SHALLOW := Color("#dfe6d3")
const LAND := Color("#e8d6a8")
const INK := Color("#4a3a26")


func _draw() -> void:
	var size := Vector2(Data.map.size[0], Data.map.size[1])
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	for flat in Data.map.shallow:
		draw_colored_polygon(_points(flat), SHALLOW)
	for flat in Data.map.land:
		var pts := _points(flat)
		draw_colored_polygon(pts, LAND)
		pts.append(pts[0])
		draw_polyline(pts, INK, 1.0, true)
	draw_rect(Rect2(Vector2.ZERO, size), INK, false, 3.0)


static func _points(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		pts.append(Vector2(flat[i], flat[i + 1]))
	return pts
