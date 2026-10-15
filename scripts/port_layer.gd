extends Node2D
## Draws port markers and names. Kept apart from the chart so it can redraw cheaply on zoom:
## marker and text size are divided by the zoom so names stay readable at any scale.

const INK := Color("#4a3a26")

var port_positions := {}  # port id -> map position, filled by world_map
var zoom := 1.0:
	set(z):
		zoom = z
		queue_redraw()


func _draw() -> void:
	var s := 1.0 / zoom
	for id in port_positions:
		var port: Dictionary = Data.table("ports")[id]
		var pos: Vector2 = port_positions[id]
		var off: Array = port.get("label_offset", [9, 5])  # optional, for ports too close together
		var text_pos := pos + Vector2(off[0], off[1]) * s
		draw_circle(pos, 6.0 * s, Color(Data.table("factions")[port.faction].color))
		draw_circle(pos, 6.0 * s, INK, false, 1.5 * s)
		draw_string_outline(ThemeDB.fallback_font, text_pos, port.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), int(4 * s), Color("#f3ecd8"))
		draw_string(ThemeDB.fallback_font, text_pos, port.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), INK)
