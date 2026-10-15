extends Control
## Compass rose: blue arrow shows where the wind blows TO, brown needle shows the ship's heading.

var wind_dir := 0.0
var heading := 0.0


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 4.0
	var ink := Style.c("ink")
	draw_circle(c, r, Style.c("parchment_light"))
	draw_circle(c, r, ink, false, 1.5)
	for i in 16:  # a little compass rose
		var len := r * (0.95 if i % 4 == 0 else (0.7 if i % 2 == 0 else 0.5))
		draw_line(c, c + Geo.from_bearing(i * 22.5) * len, Color(ink, 0.35), 1.0)
	draw_string(Style.font("title"), c + Vector2(-5, -r + 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	draw_line(c, c + Geo.from_bearing(heading) * r * 0.8, Style.c("player_ship"), 3.0)
	# Wind arrow: from the upwind side, across the centre, pointing downwind.
	var to := Geo.from_bearing(wind_dir + 180.0)
	var tip := c + to * r * 0.85
	draw_line(c - to * r * 0.85, tip, Color("#2f5fb3"), 2.0)
	draw_colored_polygon(PackedVector2Array([tip, tip - to.rotated(0.4) * 10, tip - to.rotated(-0.4) * 10]), Color("#2f5fb3"))

