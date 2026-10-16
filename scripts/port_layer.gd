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
	var red := Color(Style.c("bad"), 0.8)
	for id in Bases.discovered:  # coves you've found: an anchor, or your own flag
		var cp := Bases.cove_pos(id)
		var mine := Bases.bases.has(id)
		var col: Color = Style.c("wax") if mine else Style.c("chart_ink")
		draw_circle(cp, 5.0 * s, Style.c("chart_paper_light"))
		draw_arc(cp, 5.0 * s, 0.0, TAU, 16, col, 1.5 * s)
		draw_line(cp + Vector2(0, -3.5) * s, cp + Vector2(0, 3.5) * s, col, 1.5 * s)  # an anchor, roughly
		draw_line(cp + Vector2(-2.5, -1.5) * s, cp + Vector2(2.5, -1.5) * s, col, 1.5 * s)
		var label: String = Bases.cove(id).name + (" (your base)" if mine else "")
		if mine and not Bases.bases[id].raid.is_empty() and Bases.bases[id].raid.warned:
			label += " - RAID COMING"
		draw_string_outline(Style.font("pixel"), cp + Vector2(8, 5) * s, label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), int(4 * s), Style.c("chart_paper_light"))
		draw_string(Style.font("pixel"), cp + Vector2(8, 5) * s, label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), col)
	if trade_good == "@routes":
		_draw_routes(s)
	for h in Contracts.hints():  # where your contracts send you, inked on the chart
		var at: Vector2
		if h.has("radius"):
			draw_arc(h.pos, h.radius, 0.0, TAU, 64, red, 2.0 * s)
			at = h.pos + Vector2(-h.radius, -h.radius - 6.0 * s)
		else:
			draw_dashed_line(h.from, h.to, red, 2.0 * s, 10.0 * s)
			at = h.from.lerp(h.to, 0.5)
		draw_string(Style.font("italic"), at, h.label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), red)
	for id in port_positions:
		var port: Dictionary = Data.table("ports")[id]
		var pos: Vector2 = port_positions[id]
		var off: Array = port.get("label_offset", [9, 5])  # optional, for ports too close together
		var text_pos := pos + Vector2(off[0], off[1]) * s
		var label: String = port.name
		if trade_good == "@standing" and not ship_state.is_empty():
			var acc := Career.port_access(ship_state, id)
			label += "  %+d%s" % [ship_state.relations.get(port.faction, 0), "" if acc.open else ", CLOSED"]
		elif trade_good != "" and not trade_good.begins_with("@"):
			var k: Dictionary = Ports.known.get(id, {}).get(trade_good, {})
			label += "  ?" if k.is_empty() else "  buy %s / sell %s (%dd%s)" % [
				Market.fmt(k.buy), Market.fmt(k.sell), int(Clock.day) - int(k.day), ", rumour" if k.get("source", "") == "rumour" else ""]
		draw_circle(pos, 6.0 * s, Color(Data.table("factions")[port.faction].color))
		draw_circle(pos, 6.0 * s, Style.c("chart_ink"), false, 1.5 * s)
		draw_string_outline(Style.font("pixel"), text_pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), int(4 * s), Style.c("chart_paper_light"))
		draw_string(Style.font("pixel"), text_pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), Style.c("chart_ink"))


## Trade routes map mode: a line for each route merchants have used lately, thicker the busier, redder the riskier.
func _draw_routes(s: float) -> void:
	var tr: Traffic = Economy.model.traffic
	var pairs := {}  # "a|b" (sorted) -> [recent, risk]
	for key in tr.routes:
		var a: String = key.get_slice(">", 0)
		var b: String = key.get_slice(">", 1)
		var k: String = a + "|" + b if a < b else b + "|" + a
		var cur: Array = pairs.get(k, [0.0, 0.0])
		pairs[k] = [cur[0] + tr.routes[key].recent, maxf(cur[1], tr.risk.get(key, 0.0))]
	var font := Style.font("pixel")
	for k in pairs:
		var busy: float = pairs[k][0]
		if busy < 0.5:
			continue
		var a: String = k.get_slice("|", 0)
		var b: String = k.get_slice("|", 1)
		if not port_positions.has(a) or not port_positions.has(b):
			continue
		var r: float = pairs[k][1]
		var col := Color(Style.c("chart_ink"), 0.7).lerp(Style.c("bad"), clampf(r * 2.0, 0.0, 1.0))
		draw_line(port_positions[a], port_positions[b], col, clampf(busy * 0.6, 1.5, 9.0) * s)
		if r >= Data.table("economy").traffic.raid_reason_risk:
			draw_string(font, port_positions[a].lerp(port_positions[b], 0.5), "raiders", HORIZONTAL_ALIGNMENT_CENTER, -1, int(14 * s), Style.c("bad"))
