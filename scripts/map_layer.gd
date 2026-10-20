extends Node2D
## The world map's land, HD-2D style: beaches, then the land lit as relief by assets/map/land.gdshader (hills
## and mountains from assets/map/height.png), coastlines, and the sea's names (data/map_labels.json).
## Drawn once; Godot caches it (only the lettering redraws, on zoom). The sea underneath and the clouds on top are shaders (sea_layer.gd).

var zoom := 1.0:  # set by world_map; the sea's names are re-rasterised at screen size so they stay sharp
	set(z):
		zoom = z
		queue_redraw()


func _ready() -> void:
	var land := _Land.new()  # the land itself, drawn behind this node's lettering through the relief shader
	land.show_behind_parent = true
	land.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/map/land.gdshader")
	mat.set_shader_parameter("height_map", load("res://assets/map/height.png"))
	mat.set_shader_parameter("detail", load("res://assets/map/land_tile.png"))
	mat.set_shader_parameter("map_size", Vector2(Data.map.size[0], Data.map.size[1]))
	mat.set_shader_parameter("art_px", float(Data.table("palette").map_pixel))
	mat.set_shader_parameter("tilt", Geo.TILT)
	land.material = mat
	add_child(land)


func _draw() -> void:
	var size := Vector2(Data.map.size[0], Data.map.size[1])
	_labels()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0e1224"), false, 6.0)
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Style.c("header"), false, 2.0)


## The land polygons for the relief shader, which colours them by height: a beach ring just outside each coast
## (sea level, so it comes out sand), the land, and the coastline (drawn dark, which the shader keeps dark).
class _Land extends Node2D:
	func _draw() -> void:
		var polys: Array[PackedVector2Array] = []
		for flat in Data.map.land:
			var pts := PackedVector2Array()
			for i in range(0, flat.size(), 2):
				pts.append(Vector2(flat[i], flat[i + 1]))
			polys.append(pts)
		for pts in polys:
			for ring in Geometry2D.offset_polygon(pts, 2.5):
				if not Geometry2D.triangulate_polygon(ring).is_empty():  # skip holes and slivers that won't triangulate
					draw_colored_polygon(ring, Color.WHITE)
		for pts in polys:
			draw_colored_polygon(pts, Color.WHITE)
		for pts in polys:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, Color.BLACK, 1.2)


func _labels() -> void:
	for id in Data.table("map_labels"):
		if id.begins_with("_"):
			continue
		var l: Dictionary = Data.table("map_labels")[id]
		var font := Style.font("pixel")
		var pos := Geo.latlon_to_px(l.lat, l.lon)
		var px := roundi(float(l.size) * zoom)  # world size -> screen pixels, drawn back down under a 1/zoom transform
		var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_set_transform(pos, 0.0, Geo.UPRIGHT / zoom)
		draw_string_outline(font, Vector2(-w / 2.0, 0), l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, roundi(5 * zoom), Color(0.04, 0.1, 0.2, 0.5))
		draw_string(font, Vector2(-w / 2.0, 0), l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.9, 0.95, 1.0, 0.55))
	draw_set_transform(Vector2.ZERO)


func _ring(pts: PackedVector2Array, color: Color, width: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, color, width, true)


static func _points(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		pts.append(Vector2(flat[i], flat[i + 1]))
	return pts
