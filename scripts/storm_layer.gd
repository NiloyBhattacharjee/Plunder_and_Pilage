extends Node2D
## Draws storms as translucent circles over the chart, redrawn every frame as they drift.

const COLORS := {"squall": Color(0.3, 0.3, 0.4, 0.25), "hurricane": Color(0.5, 0.1, 0.2, 0.3),
	"calm": Color(0.85, 0.8, 0.55, 0.25), "norther": Color(0.3, 0.45, 0.65, 0.22)}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for s in Weather.storms:
		var c: Color = COLORS.get(s.kind, Color(0, 0, 0, 0.25))
		draw_circle(s.pos, s.radius, c)
		draw_circle(s.pos, s.radius, Color(c, 0.8), false, 2.0)
		draw_string(Style.font("italic"), s.pos - Vector2(60, 0), Data.rules.storms[s.kind].name,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(c, 1.0))
		if Data.rules.storms[s.kind].hull_damage_per_day > 0:
			_rain(s, c)


# Inky rain strokes, re-scattered a few times a second.
func _rain(s: Dictionary, c: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec() / 120) + int(s.pos.x)
	for i in int(s.radius / 2.5):
		var a := rng.randf() * TAU
		var p: Vector2 = s.pos + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * s.radius
		draw_line(p, p + Vector2(-3, 9), Color(Style.c("ink"), 0.25), 1.0)
