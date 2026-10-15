class_name UIKit
## Small helpers for building UI rows in code. Every label can carry a tooltip (the Paradox-style breakdowns).

const HEADER := Color(0.8, 0.75, 0.6)
const BAD := Color("#c0392b")
const GOOD := Color("#2e8b57")
const DIM := Color(0.75, 0.75, 0.75)


static func label(parent: Node, text: String, tip := "", color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS  # labels ignore the mouse by default, so no tooltip
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func grid(parent: Node, columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 16)
	parent.add_child(g)
	return g


static func row(parent: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	parent.add_child(h)
	return h


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Pauses the clock while a screen is open; returns what to call on close.
static func pause_clock() -> void:
	if Clock.speed_index > 0:
		Clock.toggle_pause()


static func resume_clock() -> void:
	if Clock.speed_index == 0:
		Clock.toggle_pause()
