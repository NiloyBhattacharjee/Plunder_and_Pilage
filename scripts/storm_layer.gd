extends Node2D
## Draws storms as translucent circles over the chart, redrawn every frame as they drift.

const COLORS := {"squall": Color(0.3, 0.3, 0.4, 0.25), "hurricane": Color(0.5, 0.1, 0.2, 0.3)}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for s in Weather.storms:
		var c: Color = COLORS.get(s.kind, Color(0, 0, 0, 0.25))
		draw_circle(s.pos, s.radius, c)
		draw_circle(s.pos, s.radius, Color(c, 0.8), false, 2.0)
		draw_string(ThemeDB.fallback_font, s.pos - Vector2(40, 0), Data.rules.storms[s.kind].name,
			HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(c, 1.0))
