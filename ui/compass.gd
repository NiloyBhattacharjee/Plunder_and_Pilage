extends Control
## Compass rose: blue arrow shows where the wind blows TO, brown needle shows the ship's heading.

var wind_dir := 0.0
var heading := 0.0


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 4.0
	draw_circle(c, r, Color(0.95, 0.9, 0.78))
	draw_circle(c, r, Color("#4a3a26"), false, 1.5)
	draw_string(ThemeDB.fallback_font, c + Vector2(-5, -r + 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#4a3a26"))
	draw_line(c, c + Geo.from_bearing(heading) * r * 0.8, Color("#7a4a1e"), 3.0)
	# Wind arrow: from the upwind side, across the centre, pointing downwind.
	var to := Geo.from_bearing(wind_dir + 180.0)
	var tip := c + to * r * 0.85
	draw_line(c - to * r * 0.85, tip, Color("#2f5fb3"), 2.0)
	draw_colored_polygon(PackedVector2Array([tip, tip - to.rotated(0.4) * 10, tip - to.rotated(-0.4) * 10]), Color("#2f5fb3"))
