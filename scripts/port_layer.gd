extends Node2D
## Draws port markers and names. Kept apart from the chart so it can redraw cheaply on zoom:
## marker and text size are divided by the zoom so names stay readable at any scale.
## In a trade map mode (`trade_good` set) each label also shows the last known buy/sell price and its age.


var port_positions := {}  # port id -> map position, filled by world_map
var ship_state := {}
var trade_good := "":
	set(g):
		trade_good = g
		queue_redraw()
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
		var label: String = port.name
		if trade_good == "@standing" and not ship_state.is_empty():
			var acc := Career.port_access(ship_state, id)
			label += "  %+d%s" % [ship_state.relations.get(port.faction, 0), "" if acc.open else ", CLOSED"]
		elif trade_good != "":
			var k: Dictionary = Ports.known.get(id, {}).get(trade_good, {})
			label += "  ?" if k.is_empty() else "  buy %s / sell %s (%dd%s)" % [
				Market.fmt(k.buy), Market.fmt(k.sell), int(Clock.day) - int(k.day), ", rumour" if k.get("source", "") == "rumour" else ""]
		draw_circle(pos, 6.0 * s, Color(Data.table("factions")[port.faction].color))
		draw_circle(pos, 6.0 * s, Style.c("ink"), false, 1.5 * s)
		draw_string_outline(ThemeDB.fallback_font, text_pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), int(4 * s), Style.c("parchment_light"))
		draw_string(ThemeDB.fallback_font, text_pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), Style.c("ink"))
