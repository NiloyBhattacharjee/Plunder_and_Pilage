class_name Finds
extends Node2D
## Things floating at sea that you can sail to: casks, a boat adrift, a wreck on a reef, whales, turtles, a bottle,
## smoke from a sandbar. Each is an event (data/events/*.json with a "find" key) waiting where it was seen; sail
## up to it and it happens. They drift off after a few days, so a long passage has reasons to turn aside.
## Storms leave wreckage in their wake, and other ships' battles leave it where they fought.

signal reached(inst: Dictionary)
signal news(text: String)

var finds: Array = []   # {id: event id, vars, kind, pos, until, seen}
var terrain: TerrainGrid
var world: Node
var rng := RandomNumberGenerator.new()


static func cfg() -> Dictionary:
	return Data.rules.finds


func setup(t: TerrainGrid, w: Node) -> void:
	terrain = t
	world = w
	rng.randomize()
	z_index = 1
	Clock.day_passed.connect(func(_d): daily())
	Clock.ticked.connect(func(_dd): _tick())


func daily() -> void:
	finds = finds.filter(func(f): return f.until > Clock.day)
	var ship: Node2D = world.ship
	if ship.anchored_at == "" and finds.size() < int(cfg().max) and rng.randf() < float(cfg().daily_chance):
		var inst := Events.pick_find(world._event_ctx(), finds.map(func(f): return f.id))
		if not inst.is_empty():
			spawn(inst, ship.position)
	for s in Weather.storms:  # a storm that has done damage leaves some behind
		if Data.rules.storms[s.kind].hull_damage_per_day > 0 and rng.randf() < float(cfg().storm_wreck_chance):
			var inst := Events.instance_of(["flotsam_cask", "abandoned_ship"][rng.randi() % 2], world._event_ctx())
			if not inst.is_empty():
				spawn(inst, s.pos, 0.0)


## Puts a find on the map somewhere around `near` (more often than not out of sight, to be spotted as you sail).
## `spread` scales the distance; 0 puts it right there. Returns the find, or {} if there was no water for it.
func spawn(inst: Dictionary, near: Vector2, spread := 1.0) -> Dictionary:
	var ev: Dictionary = Events.events[inst.id]
	var pos := _place(near, ev.get("find_near", "sea"), spread)
	if pos == Vector2.INF:
		return {}
	var d: Array = cfg().days
	var f := {"id": inst.id, "vars": inst.vars, "kind": ev.find, "pos": pos, "until": Clock.day + rng.randf_range(d[0], d[1]), "seen": false}
	finds.append(f)
	queue_redraw()
	return f


func _place(near: Vector2, where: String, spread: float) -> Vector2:
	var r: Array = cfg().spawn_nm
	for attempt in 40:
		var p := near + Geo.from_bearing(rng.randf() * 360.0) * rng.randf_range(r[0], r[1]) * spread * Geo.px_per_nm()
		var t := terrain.at(p)
		if (where == "reef" and (t == TerrainGrid.SHALLOW or t == TerrainGrid.REEF)) or (where != "reef" and t == TerrainGrid.DEEP):
			return p
	return Vector2.INF


## Spotting finds as they come within sight (fog and night shorten it), and reaching them.
func _tick() -> void:
	var ship: Node2D = world.ship
	if world.busy() or ship.anchored_at != "" or ship.state.hull <= 0:
		return
	var sight: float = Data.rules.shipping.sight_nm * Geo.px_per_nm() * Weather.visibility(ship.position)
	for f in finds:
		var d: float = f.pos.distance_to(ship.position)
		if not f.seen and d < sight:
			f.seen = true
			news.emit("Lookout: %s, to the %s. (Sail to it to see.)" % [cfg().kinds[f.kind].spotted, Geo.compass_name(Geo.bearing(f.pos - ship.position))])
		if d < float(cfg().reach_nm) * Geo.px_per_nm():
			finds.erase(f)
			queue_redraw()
			reached.emit({"id": f.id, "vars": f.vars})
			return


func _process(_delta: float) -> void:
	if not finds.is_empty():
		queue_redraw()


# ---- drawing: small pixel marks, bobbing, with a ring that pulses so they catch the eye ----

func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in finds:
		if not f.seen:
			continue
		var p: Vector2 = (f.pos + Vector2(0, sin(t * 2.0 + f.pos.x) * 0.8)).round()
		var pulse := fposmod(t * 0.6 + f.pos.y * 0.01, 1.0)
		draw_arc(p, 8.0 + pulse * 12.0, 0.0, TAU, 24, Color(1.0, 0.95, 0.7, 0.7 * (1.0 - pulse)), 1.5)
		draw_set_transform(p, 0.0, Geo.UPRIGHT * 1.6)
		_icon(f.kind, Vector2.ZERO, t)
		draw_set_transform(Vector2.ZERO)


func _icon(kind: String, p: Vector2, t: float) -> void:
	var ink := Color("#1c1a24")
	match kind:
		"cask":
			for k in 3:
				var c := p + Vector2(k * 4 - 4, (k % 2) * 2)
				draw_rect(Rect2(c - Vector2(1.5, 2), Vector2(3, 4)), Color("#8a5a2e"))
				draw_rect(Rect2(c - Vector2(1.5, 0.5), Vector2(3, 1)), ink)
		"boat":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -1), p + Vector2(5, -1), p + Vector2(3, 2), p + Vector2(-3, 2)]), Color("#7a4e28"))
			draw_rect(Rect2(p + Vector2(-1, -4), Vector2(1, 3)), Color("#e8e0c8"))
		"wreck", "wreckage":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 0), p + Vector2(5, -2), p + Vector2(6, 2), p + Vector2(-5, 3)]), Color("#4a3424"))
			draw_line(p + Vector2(-1, 0), p + Vector2(3, -8), ink, 1.0)
			if kind == "wreckage":  # still smoking
				for k in 3:
					var a := fposmod(t * 0.5 + k / 3.0, 1.0)
					draw_circle(p + Vector2(2 + a * 4, -6 - a * 10), 1.5 + a * 2.5, Color(0.35, 0.33, 0.32, 0.5 * (1.0 - a)))
		"whale":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(-2, -3), p + Vector2(5, -2), p + Vector2(7, 0), p + Vector2(0, 2)]), Color("#3e4a5a"))
			if fposmod(t, 3.0) < 1.0:  # blowing
				draw_line(p + Vector2(-2, -3), p + Vector2(-3, -8), Color(1, 1, 1, 0.8), 1.0)
				draw_line(p + Vector2(-2, -3), p + Vector2(-1, -8), Color(1, 1, 1, 0.8), 1.0)
		"bottle":
			draw_rect(Rect2(p - Vector2(1.5, 3), Vector2(3, 5)), Color("#3f8a5a"))
			draw_rect(Rect2(p - Vector2(0.5, 5), Vector2(1, 2)), Color("#c8b48a"))
		"castaway":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 2), p + Vector2(-3, -1), p + Vector2(4, -1), p + Vector2(8, 2)]), Color("#e6d29a"))
			draw_rect(Rect2(p + Vector2(0, -6), Vector2(1, 5)), ink)
			for k in 3:
				var a := fposmod(t * 0.4 + k / 3.0, 1.0)
				draw_circle(p + Vector2(1 + a * 3, -8 - a * 10), 1.0 + a * 2.0, Color(0.85, 0.85, 0.85, 0.5 * (1.0 - a)))
		"fish":
			for k in 5:
				var a := t * 3.0 + k * 1.7
				draw_rect(Rect2(p + Vector2(cos(a) * 5, sin(a * 1.3) * 3), Vector2(2, 1)), Color("#d8e4ee"))
		"turtle":
			for k in 3:
				var c := p + Vector2(k * 5 - 5, (k % 2) * 3 - 1)
				draw_circle(c, 2.0, Color("#4a6a3a"))
				draw_circle(c + Vector2(2.2, 0), 0.8, Color("#4a6a3a"))
		"satchel":
			draw_rect(Rect2(p - Vector2(3, 2), Vector2(6, 4)), Color("#9a8a6a"))
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("#a3261b"))
		_:
			draw_circle(p, 2.5, Color.WHITE)


func save_state() -> Dictionary:
	return {"finds": finds}


func load_state(d: Dictionary) -> void:
	finds = d.get("finds", [])
	queue_redraw()
