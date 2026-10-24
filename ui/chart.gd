class_name Chart
extends Control
## A chart of weekly numbers from Stats, drawn in _draw() like PriceSpark. Three sizes:
##   full  - axis ticks at round numbers, a legend for two or more series, the current value at each line's end;
##   mini  - one panel of a row of small multiples (one nation, one town): its name and value inside, no legend;
##   spark - a bare trend line for a stat tile.
## History events are gold ticks, wars red bands. Hover a week for its values and what happened.
## Colours: one series wears the gold accent with a faint wash under it; two or three wear series_1-3 (validated
## for colour-blind readers on viz_surface). More than three belong in small multiples, not one chart.
## bars: the first series as columns, in its colour; give it "signed": true for green above zero and red below
## (gold that rose or fell: the status colours, used only where they mean good and bad).

const FONT_SIZE := 16
const SERIES := ["series_1", "series_2", "series_3"]

var days: Array = []     # the game day of each week
var series: Array = []   # [{name, values, color?}]
var bars := false
var mode := "full"       # full, mini or spark
var title := ""          # mini: drawn inside the panel
var fixed := {}          # {lo, hi}: a shared scale, so a row of small multiples compares fairly
var marks: Array = []    # [{at, text}]: history events
var bands: Array = []    # [{from, to, text}]: wars
var notes: Array = []    # per week: lines for the tooltip (what the captain did)
var _hover := -1


static func make(week_days: Array, lines: Array, height := 190.0) -> Chart:
	var c := Chart.new()
	c.days = week_days
	c.series = lines
	for i in lines.size():  # one series: the accent; two or three: the validated slots, in order
		if not lines[i].has("color"):
			lines[i].color = Style.c("header") if lines.size() == 1 else Style.c(SERIES[mini(i, SERIES.size() - 1)])
	c.custom_minimum_size = Vector2(0, height)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.tooltip_text = " "  # anything, so Godot asks _get_tooltip
	c.mouse_exited.connect(func():
		c._hover = -1
		c.queue_redraw())
	return c


## A small-multiples panel: one series, its name and current value inside.
static func make_mini(week_days: Array, name: String, values: Array) -> Chart:
	var c := make(week_days, [{"name": name, "values": values}], 96.0)
	c.mode = "mini"
	c.title = name
	return c


## A headline number: label, value, this week's change (green when it moved the good way) and a trend line.
static func tile(label: String, values: Array, up_is_good := true, tip := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Style.c("viz_surface")
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(box)
	UIKit.label(box, label, "", Style.c("dim"))
	var row := UIKit.row(box)
	var now: float = values[-1] if not values.is_empty() else 0.0
	var big := UIKit.label(row, _short(now, true))
	big.add_theme_font_size_override("font_size", 30)
	if values.size() >= 2:
		var d: float = values[-1] - values[-2]
		if absf(d) >= 0.5:
			var good := (d > 0) == up_is_good
			var dl := UIKit.label(row, "%s%s this week" % ["+" if d > 0 else "-", _short(absf(d), true)], "", Style.c("good") if good else Style.c("bad"))
			dl.size_flags_vertical = Control.SIZE_SHRINK_END
		var spark := make([], [{"name": label, "values": values.slice(maxi(0, values.size() - 26)), "color": Style.c("dim")}], 26.0)
		spark.days = range(spark.series[0].values.size())
		spark.mode = "spark"
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(spark)
	return p


func _pad() -> Dictionary:  # left, top, right, bottom
	match mode:
		"spark": return {"l": 2.0, "t": 4.0, "r": 6.0, "b": 4.0}
		"mini": return {"l": 8.0, "t": 30.0, "r": 10.0, "b": 8.0}
	return {"l": 50.0, "t": 30.0 if series.size() > 1 else 14.0, "r": 56.0, "b": 24.0}


func _plot() -> Rect2:
	var p := _pad()
	return Rect2(p.l, p.t, size.x - p.l - p.r, size.y - p.t - p.b)


func _x(i: int) -> float:
	var r := _plot()
	return r.position.x + r.size.x * i / float(maxi(1, days.size() - 1))


## The value range, widened to round numbers, and the step between ticks.
func _range() -> Dictionary:
	var lo := INF
	var hi := -INF
	for sr in series:
		for v in sr.values:
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if not fixed.is_empty():
		lo = fixed.lo
		hi = fixed.hi
	if bars or lo >= 0.0 and lo < hi * 0.4:
		lo = minf(lo, 0.0)  # bars, and lines that come near zero, start from zero
	if mode == "spark":
		return {"lo": lo, "hi": hi if hi > lo else lo + 1.0, "step": 0.0}
	var step := _nice((hi - lo) / 3.0)
	return {"lo": floorf(lo / step) * step, "hi": maxf(ceilf(hi / step) * step, floorf(lo / step) * step + step), "step": step}


static func _nice(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var mag := pow(10.0, floorf(log(raw) / log(10.0)))
	for f in [1.0, 2.0, 5.0, 10.0]:
		if raw <= f * mag:
			return maxf(f * mag, 1.0)
	return 10.0 * mag


func _y(v: float, span: Dictionary) -> float:
	var r := _plot()
	return r.end.y - (v - span.lo) / (span.hi - span.lo) * r.size.y


func _draw() -> void:
	var font := Style.font("body")
	var ink := Style.c("ink_soft")
	var muted := Style.c("dim")
	var r := _plot()
	if mode != "spark":
		var sb := StyleBoxFlat.new()
		sb.bg_color = Style.c("viz_surface")
		sb.set_corner_radius_all(4)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
	if mode == "mini":
		draw_string(font, Vector2(8, 20), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.65 - 12, FONT_SIZE - 2, ink)
	if days.size() < 2:
		if mode != "spark":
			draw_string(font, r.position + Vector2(0, r.size.y / 2 + 6), "Fills in week by week.", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, muted)
		return
	var span := _range()
	if mode != "spark":
		for b in bands:
			draw_rect(Rect2(_x(b.from), r.position.y, maxf(2.0, _x(b.to) - _x(b.from)), r.size.y), Color(Style.c("bad"), 0.08))
	if mode == "full":
		var v: float = span.lo
		while v <= span.hi + 0.001:  # hairline rules at round numbers
			var y := _y(v, span)
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Style.c("viz_grid"), 1.0)
			draw_string(font, Vector2(4, y + 5), _short(v), HORIZONTAL_ALIGNMENT_RIGHT, _pad().l - 10, FONT_SIZE - 2, muted)
			v += span.step
		var year := -1
		var last_x := -INF
		for i in days.size():  # each new year along the bottom, unless it would crowd the last one
			var y: int = Clock.date_of(days[i]).year
			if y != year and _x(i) - last_x > 48.0:
				draw_string(font, Vector2(_x(i), size.y - 5), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, muted)
				last_x = _x(i)
			year = y
	if span.lo < 0.0 and mode != "spark":
		draw_line(Vector2(r.position.x, _y(0, span)), Vector2(r.end.x, _y(0, span)), Color(Style.c("ink"), 0.35), 1.0)
	if mode == "full":
		for m in marks:
			draw_line(Vector2(_x(m.at), r.position.y), Vector2(_x(m.at), r.end.y), Color(Style.c("header"), 0.35), 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(_x(m.at) - 4, r.position.y - 6), Vector2(_x(m.at) + 4, r.position.y - 6),
				Vector2(_x(m.at), r.position.y)]), Style.c("header"))
	for si in series.size():
		var sr: Dictionary = series[si]
		if bars and si == 0:
			_bars(sr, span)
			continue
		var pts := PackedVector2Array()
		for i in sr.values.size():
			pts.append(Vector2(_x(i), _y(sr.values[i], span)))
		if series.size() == 1 and is_zero_approx(span.lo) and mode != "spark":  # a faint wash under a lone line from zero
			var area := pts.duplicate()
			area.append(Vector2(pts[-1].x, r.end.y))
			area.append(Vector2(pts[0].x, r.end.y))
			draw_colored_polygon(area, Color(sr.color, 0.10))
		draw_polyline(pts, sr.color, 1.5 if mode == "spark" else 2.0, true)
		if mode == "spark":
			draw_circle(pts[-1], 2.5, Style.c("header"))
	if mode == "full":
		_end_labels(span, font)
		if series.size() > 1:
			var lx := r.position.x  # the legend: a short line-key beside each name, the text in ink
			for sr in series:
				draw_line(Vector2(lx, 14), Vector2(lx + 14, 14), sr.color, 3.0)
				draw_string(font, Vector2(lx + 20, 19), sr.name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, ink)
				lx += 34 + font.get_string_size(sr.name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2).x
	elif mode == "mini":
		var now: float = series[0].values[-1]
		draw_string(font, Vector2(size.x * 0.65 - 8, 20), _short(now), HORIZONTAL_ALIGNMENT_RIGHT, size.x * 0.35, FONT_SIZE, Style.c("ink"))
	if _hover >= 0 and mode != "spark":
		draw_line(Vector2(_x(_hover), r.position.y), Vector2(_x(_hover), r.end.y), Color(Style.c("ink"), 0.5), 1.0)
		for si in range(1 if bars else 0, series.size()):
			_dot(Vector2(_x(_hover), _y(series[si].values[_hover], span)), series[si].color)


## Columns, at most 24px, with a 2px gap of the surface between neighbours.
func _bars(sr: Dictionary, span: Dictionary) -> void:
	var values: Array = sr.values
	var r := _plot()
	var slot := r.size.x / maxf(1.0, values.size() - 1)
	var w := clampf(slot - 2.0, 1.0, 24.0)
	for i in values.size():
		var top := _y(maxf(values[i], 0.0), span)
		var bottom := _y(minf(values[i], 0.0), span)
		var color: Color = (Style.c("good") if values[i] >= 0 else Style.c("bad")) if sr.get("signed", false) else sr.color
		draw_rect(Rect2(_x(i) - w / 2, top, w, maxf(1.0, bottom - top)), color)


## A marker: the series colour inside a 2px ring of the surface, so it stands clear of the lines it sits on.
func _dot(at: Vector2, color: Color) -> void:
	draw_circle(at, 6.0, Style.c("viz_surface"))
	draw_circle(at, 4.0, color)


## The value at the end of each line, in ink beside an end-dot; a label that would sit on another is left to the legend.
func _end_labels(span: Dictionary, font: Font) -> void:
	var r := _plot()
	var taken := []
	for si in range(1 if bars else 0, series.size()):
		var v: float = series[si].values[-1]
		var at := Vector2(r.end.x, _y(v, span))
		_dot(at, series[si].color)
		if taken.any(func(y): return absf(y - at.y) < 15.0):
			continue
		taken.append(at.y)
		draw_string(font, at + Vector2(9, 5), _short(v), HORIZONTAL_ALIGNMENT_LEFT, _pad().r - 10, FONT_SIZE - 2, Style.c("ink"))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and days.size() >= 2 and mode != "spark":
		var i := clampi(roundi((e.position.x - _plot().position.x) / _plot().size.x * (days.size() - 1)), 0, days.size() - 1)
		if i != _hover:
			_hover = i
			queue_redraw()


func _get_tooltip(_at: Vector2) -> String:
	if _hover < 0 or _hover >= days.size() or mode == "spark":
		return ""
	var t := Clock.date_of(days[_hover])
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var lines := PackedStringArray(["Week of %d %s %d" % [t.day, months[t.month - 1], t.year]])
	for sr in series:
		lines.append("%s: %s" % [sr.name, _short(sr.values[_hover], true)])
	for b in bands:
		if _hover >= b.from and _hover <= b.to:
			lines.append(b.text)
	for m in marks:
		if m.at == _hover:
			lines.append(m.text)
	if _hover < notes.size():
		for n in notes[_hover]:
			lines.append("  " + n)
	return "\n".join(lines)


## 1,284 / 12.9K: compact from ten thousand up (from a thousand on the axis, where space is short).
static func _short(v: float, long := false) -> String:
	var a := absf(v)
	var sgn := "-" if v < 0 else ""
	if a >= 10000.0 or (a >= 1000.0 and not long):
		return sgn + ("%.1fK" % (a / 1000.0)).replace(".0K", "K")
	if a >= 1000.0:
		return sgn + "%d,%03d" % [int(a) / 1000, int(a) % 1000]
	return "%d" % roundi(v) if a >= 10.0 or is_equal_approx(v, roundf(v)) else "%.1f" % v
