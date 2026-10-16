class_name PriceSpark
extends Control
## A tiny price-history line: weekly price multipliers, oldest on the left, with the base price as a faint rule
## and today's price as a dot. Hover for the range.

var values: Array = []


static func make(history: Array, now: float) -> PriceSpark:
	var p := PriceSpark.new()
	p.values = history + [now]
	p.custom_minimum_size = Vector2(72, 22)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	if p.values.size() > 1:
		p.tooltip_text = "The last %d weeks: from x%.2f to x%.2f of the base price (the faint line). Today x%.2f." % [
			p.values.size() - 1, p.values.min(), p.values.max(), now]
	else:
		p.tooltip_text = "No price history yet."
	return p


func _draw() -> void:
	if values.size() < 2:
		return
	var lo: float = minf(values.min(), 1.0)
	var hi: float = maxf(values.max(), 1.0)
	var span := maxf(hi - lo, 0.05)
	var h := size.y - 4.0
	var y_of := func(v: float) -> float: return 2.0 + h - (v - lo) / span * h
	draw_line(Vector2(0, y_of.call(1.0)), Vector2(size.x, y_of.call(1.0)), Color(Style.c("dim"), 0.4), 1.0)
	var pts := PackedVector2Array()
	for i in values.size():
		pts.append(Vector2(i * (size.x - 3.0) / (values.size() - 1), y_of.call(values[i])))
	draw_polyline(pts, Style.c("header"), 1.0)
	draw_circle(pts[pts.size() - 1], 2.0, Style.c("ink"))
