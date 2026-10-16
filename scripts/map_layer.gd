extends Node2D
## The chart itself: land, inked coastlines with period water-lining, reef outlines, a lat/long grid,
## sea lettering (data/map_labels.json) and a compass rose. Drawn once; Godot caches it.
## The sea underneath and the paper on top are shaders (sea_layer.gd); colours come from data/palette.json.

const WATERLINES := [4.0, 9.0, 15.0]   # offsets in map pixels, period-chart style
const GRID_DEGREES := 5


func _draw() -> void:
	var ink := Style.c("chart_ink")
	var size := Vector2(Data.map.size[0], Data.map.size[1])
	var land_polys: Array[PackedVector2Array] = []
	for flat in Data.map.land:
		land_polys.append(_points(flat))

	for i in WATERLINES.size():  # concentric lines round every coast; land drawn over them hides the inner half
		var a: float = 0.32 - i * 0.09
		for pts in land_polys:
			for ring in Geometry2D.offset_polygon(pts, WATERLINES[i]):
				_ring(ring, Color(ink, a), 1.0)
	for pts in land_polys:
		draw_colored_polygon(pts, Style.c("chart_paper"))
	for pts in land_polys:
		_ring(pts, ink, 1.6)
	for flat in Data.map.get("reefs", []):
		var pts := _points(flat)
		for i in pts.size():
			draw_dashed_line(pts[i], pts[(i + 1) % pts.size()], Color(ink, 0.6), 1.0, 3.0)

	_grid(size, ink)
	_labels()
	_compass(Geo.latlon_to_px(27.6, -63.2), 105.0, ink)
	draw_rect(Rect2(Vector2.ZERO, size), ink, false, 4.0)
	draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 20)), Color(ink, 0.6), false, 1.5)


func _grid(size: Vector2, ink: Color) -> void:
	var p: Dictionary = Data.map.projection
	var font := Style.font("italic")
	var lon := ceili(p.lon_min / GRID_DEGREES) * GRID_DEGREES
	while true:
		var x := Geo.latlon_to_px(0, lon).x
		if x > size.x:
			break
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(ink, 0.16), 1.0)
		draw_string(font, Vector2(x + 4, 30), "%d° W" % absi(lon), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.7))
		lon += GRID_DEGREES
	var lat := floori(p.lat_max / GRID_DEGREES) * GRID_DEGREES
	while true:
		var y := Geo.latlon_to_px(lat, p.lon_min).y
		if y > size.y:
			break
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(ink, 0.16), 1.0)
		draw_string(font, Vector2(16, y - 4), "%d° N" % lat, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.7))
		lat -= GRID_DEGREES


func _labels() -> void:
	for id in Data.table("map_labels"):
		if id.begins_with("_"):
			continue
		var l: Dictionary = Data.table("map_labels")[id]
		var font := Style.font("italic" if l.italic else "title")
		var pos := Geo.latlon_to_px(l.lat, l.lon)
		var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(l.size)).x
		draw_string(font, pos - Vector2(w / 2.0, 0), l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(l.size), Color(Style.c("chart_ink"), 0.45))


func _compass(c: Vector2, r: float, ink: Color) -> void:
	var paper := Style.c("chart_paper_light")
	draw_circle(c, r * 1.08, Color(ink, 0.5), false, 1.0)
	draw_circle(c, r * 0.98, Color(ink, 0.5), false, 1.0)
	for i in 32:  # rhumb lines radiating across the chart, as on a portolan
		draw_line(c, c + Geo.from_bearing(i * 11.25) * r * 9.0, Color(ink, 0.05), 1.0)
	for i in 16:
		var length := r if i % 4 == 0 else (r * 0.72 if i % 2 == 0 else r * 0.5)
		var width := r * (0.13 if i % 4 == 0 else 0.09)
		var dir := Geo.from_bearing(i * 22.5)
		var side := Vector2(-dir.y, dir.x) * width
		var tip := c + dir * length
		draw_colored_polygon(PackedVector2Array([c, c + side, tip]), ink if i % 2 == 0 else paper)
		draw_colored_polygon(PackedVector2Array([c, tip, c - side]), paper if i % 2 == 0 else ink)
		_ring(PackedVector2Array([c + side, tip, c - side]), ink, 1.0)
	draw_circle(c, r * 0.08, ink)
	draw_string(Style.font("title"), c + Vector2(-10, -r - 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)


func _ring(pts: PackedVector2Array, color: Color, width: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, color, width, true)


static func _points(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		pts.append(Vector2(flat[i], flat[i + 1]))
	return pts
