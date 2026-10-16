extends Node2D
## Ships of the living world. Merchants are the economy's voyages (scripts/economy/traffic.gd), drawn when they
## pass near you: real cargo bound for a real market, so taking one starves that port and frightens that route. Navies patrol their coasts, pirates lurk on the
## trade routes (sometimes under false colours) and take merchants, hunters come for notorious pirates.
## Each NPC carries the same encounter data the battle scene uses. Only ships within sight are drawn.

signal contact(npc: Dictionary)
signal news(text: String)
signal alert(text: String)   # a hostile ship has started bearing down on you: worth pausing for

const SPRITE := preload("res://scenes/ship_sprite.tscn")

var npcs: Array = []   # {id, kind, enemy, pos, heading, route, origin, dest, flag, age, cooldown, hostile}
var next_id := 1
var terrain: TerrainGrid
var world: Node        # the world map: anchorages, the player's ship, busy()
var rng := RandomNumberGenerator.new()
var _routes := {}
var _sprites := {}
var _since_mirror := 1.0


func setup(t: TerrainGrid, w: Node) -> void:
	terrain = t
	world = w
	rng.randomize()
	Clock.ticked.connect(_tick)
	Clock.day_passed.connect(func(_d): daily())


static func cfg() -> Dictionary:
	return Data.rules.shipping


func nm(n: float) -> float:
	return n * Geo.px_per_nm()


# ---- movement --------------------------------------------------------------

func _tick(dd: float) -> void:
	if world == null:
		return
	var player: Node2D = world.ship
	_since_mirror += dd
	if _since_mirror >= 0.25:
		_since_mirror = 0.0
		_mirror(player.position)
	for n in npcs.duplicate():
		move(n, dd, player.position, player.state)
	_contacts(player)
	_update_sprites(player.position)


## One NPC's movement: follow its route, or chase/flee the player when it has reason to.
func move(n: Dictionary, dd: float, player_pos: Vector2, s: Dictionary) -> void:
	var e: Dictionary = n.enemy
	var st := ShipStats.effective(e.type, e.upgrades)
	var dist: float = n.pos.distance_to(player_pos)
	var target: Vector2
	var free_course := false  # off its route: deep keels won't follow into shallows
	if dist > nm(cfg().sight_nm):
		n.hostile = null  # out of sight: they'll judge you afresh next time
	elif n.hostile == null and n.kind != "merchant":
		n.hostile = Career.npc_hostile(s, e, rng)
	var was_chasing: bool = n.get("chasing", false)
	n.chasing = false
	if n.kind != "merchant" and n.hostile == true and dist < nm(cfg().chase_nm) and s.hull > 0:
		target = player_pos
		free_course = true
		n.chasing = true
		if not was_chasing:
			alert.emit("The %s is bearing down on you from the %s!" % [n.enemy.name, Geo.compass_name(Geo.bearing(n.pos - player_pos))])
	elif n.kind == "merchant" and dist < nm(cfg().sight_nm) and wary(n, s):
		target = n.pos + (n.pos - player_pos).normalized() * 200.0
		free_course = true
	elif not n.route.is_empty():
		target = n.route[0]
	else:
		_new_goal(n)
		return
	var heading := Geo.bearing(target - n.pos)
	var wind := Weather.wind_at(n.pos)
	var knots: float = st.speed_knots * Sailing.best_course(st.polar, Geo.angle_between(heading, wind.dir)).factor * wind.strength * cfg().npc_speed_factor
	var next: Vector2 = n.pos.move_toward(target, Geo.knots_to_px_per_day(knots) * dd)
	var ground := terrain.at(next)
	var deep: bool = Data.rules.draught[st.draught].route_cost > 1.0
	if ground == TerrainGrid.LAND or (free_course and deep and ground >= TerrainGrid.SHALLOW):
		return  # can't go there: a sloop that runs into the shallows leaves a frigate behind
	n.pos = next
	n.heading = heading
	if not free_course and not n.route.is_empty() and n.pos.distance_to(n.route[0]) < 1.0:
		n.route.remove_at(0)
		if n.route.is_empty():
			_arrive(n)


## Merchants run from anyone flying colours that threaten them.
func wary(n: Dictionary, s: Dictionary) -> bool:
	var shown := Career.flag_faction(s.get("flag", "white"))
	return shown == "pirates" or Factions.at_war(shown, n.enemy.faction)


func _contacts(player: Node2D) -> void:
	if world.busy() or player.anchored_at != "" or player.state.hull <= 0:
		return
	for n in npcs:
		if n.cooldown <= Clock.day and n.pos.distance_to(player.position) < nm(cfg().contact_nm):
			n.cooldown = Clock.day + cfg().contact_cooldown_days
			contact.emit(n)
			return


func _arrive(n: Dictionary) -> void:
	if n.kind == "merchant":
		if not n.has("voyage"):  # a contract's ship; a voyage's cargo reaches the market on the economy's schedule
			for g in n.enemy.cargo:
				Economy.add(n.dest, g, n.enemy.cargo[g])
		remove(n)
	else:
		_new_goal(n)


func _new_goal(n: Dictionary) -> void:
	var goal: Vector2
	if n.has("captain_id") and Bonds.level(world.ship.state, n.captain_id) <= -3 and rng.randf() < 0.7:
		n.route = terrain.find_path(n.pos, world.ship.position)  # a blood feud: they come looking for you
		if not n.route.is_empty():
			return
	if n.has("home"):  # a contract target keeps to the waters she was reported in
		var r: float = nm(Data.rules.contracts.lurk_nm)
		goal = terrain.nearest_sea(world.anchorages[n.home] + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)))
		n.route = terrain.find_path(n.pos, goal)
		if n.route.is_empty():
			n.route = PackedVector2Array([goal])
		return
	match n.kind:
		"navy":
			var own := _ports_of(n.enemy.faction)
			var a: Vector2 = world.anchorages[own[rng.randi() % own.size()]]
			goal = terrain.nearest_sea(a + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90)))
		"hunter":
			goal = world.ship.position if rng.randf() < 0.6 else world.anchorages[Ports.state.keys()[rng.randi() % Ports.state.size()]]
		_:  # pirates lurk somewhere along a trade route
			var ids: Array = Ports.state.keys()
			var a: Vector2 = world.anchorages[ids[rng.randi() % ids.size()]]
			var b: Vector2 = world.anchorages[ids[rng.randi() % ids.size()]]
			goal = terrain.nearest_sea(a.lerp(b, rng.randf_range(0.3, 0.7)))
	n.route = terrain.find_path(n.pos, goal)
	if n.route.is_empty():
		n.route = PackedVector2Array([terrain.nearest_sea(n.pos + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60)))])


# ---- the daily round: spawning, ageing, ships meeting ships ----------------

func daily() -> void:
	for n in npcs.duplicate():
		n.age += 1
		if n.age > cfg().max_age_days and not n.has("contract") and not n.has("captain_id"):  # contract targets and named captains stay
			remove(n)
	if count("pirate") < cfg().pirates:
		spawn("pirate", "pirates")
	for f in Career.nations():
		if not _ports_of(f).is_empty() and npcs.filter(func(n): return n.kind == "navy" and n.enemy.faction == f).size() < cfg().navy_per_faction:
			spawn("navy", f)
	var s: Dictionary = world.ship.state
	if Career.wanted(s) and count("hunter") < cfg().hunters_max and rng.randf() < cfg().hunter_spawn_chance:
		var worst: String = Career.nations().reduce(func(a, b): return a if s.relations[a] < s.relations[b] else b)
		var h := spawn("hunter", worst)
		_say(h, "Word in the taverns: a %s pirate hunter, the %s, has sailed to bring you in." % [Data.table("factions")[worst].adjective, h.enemy.name], true)
	_meetings()


func _meetings() -> void:
	for p in npcs.filter(func(n): return n.kind == "pirate"):
		for m in npcs.filter(func(n): return n.kind == "merchant" and not n.has("contract") and not n.has("captain_id")):
			if p.pos.distance_to(m.pos) < nm(cfg().contact_nm) * 2.0:
				for g in m.enemy.cargo:
					p.enemy.cargo[g] = p.enemy.cargo.get(g, 0) + m.enemy.cargo[g]
				_say(m, "Pirates took the %s merchantman %s; her cargo never reached %s." % [
					Data.table("factions")[m.enemy.faction].adjective, m.enemy.name, Ports.port(m.dest).name])
				if m.has("voyage"):
					Economy.lose_voyage(m.voyage, "pirates")
				remove(m)
	for v in npcs.filter(func(n): return n.kind == "navy" or n.kind == "hunter"):
		for p in npcs.filter(func(n): return n.kind == "pirate" and not n.has("contract") and not n.has("captain_id")):
			if v.pos.distance_to(p.pos) < nm(cfg().contact_nm) * 2.0:
				_say(p, "The %s navy ran down the pirate %s." % [Data.table("factions")[v.enemy.faction].adjective, p.enemy.name])
				remove(p)


func _say(n: Dictionary, text: String, always := false) -> void:
	if always or world.ship.position.distance_to(n.pos) < nm(cfg().sight_nm) * 2.0:
		news.emit(text)


## A merchant voyage from the economy (Economy.voyages()), drawn as a ship where she is along her route right now.
## Her cargo is the voyage's. She's the same voyage: take her and the cargo never reaches port.
func spawn_voyage(v: Dictionary, pos: Vector2, rest: PackedVector2Array) -> Dictionary:
	var f: String = v.faction
	var e := Encounters.generate(f, rng, "merchant")
	e.cargo = {v.good: v.qty}
	var n := _add("merchant", e, pos, Data.table("factions")[f].flag)
	n.voyage = v.id
	n.origin = v.origin
	n.dest = v.dest
	n.route = rest
	return n


## Ships at sea near you (or a watchtower) are drawn from the voyages; ones far out of sight are let go
## (the voyage sails on, unseen). Checked a few times a day.
func _mirror(player_pos: Vector2) -> void:
	var near := nm(cfg().sight_nm) * 1.5
	var eyes: Array = [player_pos] + Bases.watch_points()
	var drawn := {}
	for n in npcs.duplicate():
		if not n.has("voyage"):
			continue
		if eyes.all(func(p): return n.pos.distance_to(p) > near * 2.0):
			remove(n)
		else:
			drawn[n.voyage] = true
	for v in Economy.voyages():
		if drawn.has(v.id) or not world.anchorages.has(v.origin) or not world.anchorages.has(v.dest):
			continue
		var path := _route(v.origin, v.dest)
		if path.is_empty():
			continue
		var at := _along(world.anchorages[v.origin], path, Economy.progress(v))
		if eyes.any(func(p): return at[0].distance_to(p) < near):
			spawn_voyage(v, at[0], at[1])


## The point a fraction f of the way along a route, and the rest of the route from there: [Vector2, PackedVector2Array].
static func _along(start: Vector2, path: PackedVector2Array, f: float) -> Array:
	var total := 0.0
	var prev := start
	for p in path:
		total += prev.distance_to(p)
		prev = p
	var left := total * f
	prev = start
	for i in path.size():
		var seg := prev.distance_to(path[i])
		if left <= seg:
			return [prev.move_toward(path[i], left), path.slice(i)]
		left -= seg
		prev = path[i]
	return [prev, PackedVector2Array()]


func spawn(kind: String, f: String) -> Dictionary:
	var e := Encounters.generate(f, rng, kind)
	var flag: String = Data.table("factions")[f].flag
	if kind == "pirate" and rng.randf() < Data.rules.flags.npc_false_flag_chance:
		var nat: Array = Career.nations()
		flag = Data.table("factions")[nat[rng.randi() % nat.size()]].flag  # honest-looking colours
	var homes := _ports_of(f) if f != "pirates" else Ports.state.keys().filter(func(id): return Ports.port(id).get("fence", false))
	var n := _add(kind, e, world.anchorages[homes[rng.randi() % homes.size()]], flag)
	_new_goal(n)
	return n


## A named captain from the roster (Bonds), in their own ship, haunting their home waters.
func spawn_captain(id: String) -> Dictionary:
	var c := People.person(id)
	var kind := "pirate" if c.faction == "pirates" else "hunter"
	var e := Encounters.generate(c.faction, rng, kind, c.ship_type)
	e.name = c.ship
	e.captain = c.duplicate(true)
	e.captain_id = id
	e.label = "the %s, %s's ship" % [c.ship, c.name]
	var flag: String = Data.table("factions")[c.faction].flag
	var n := _add(kind, e, world.anchorages[c.haunt], flag)
	n.captain_id = id
	n.home = c.haunt
	_new_goal(n)
	return n


## A named ship for a contract. Merchants sail origin to dest; the others lurk near origin.
func spawn_target(kind: String, e: Dictionary, origin: String, dest: String) -> Dictionary:
	var n := _add(kind, e, world.anchorages[origin], Data.table("factions")[e.faction].flag)
	n.contract = e.contract
	if dest != "":
		n.origin = origin
		n.dest = dest
		n.route = _route(origin, dest)
	else:
		n.home = origin
		_new_goal(n)
	return n


func _add(kind: String, e: Dictionary, pos: Vector2, flag: String) -> Dictionary:
	var n := {"id": "n%d" % next_id, "kind": kind, "enemy": e, "pos": pos, "heading": 0.0, "route": PackedVector2Array(),
		"origin": "", "dest": "", "flag": flag, "age": 0, "cooldown": 0.0, "hostile": null}
	next_id += 1
	npcs.append(n)
	return n


func _route(a: String, b: String) -> PackedVector2Array:
	var key := a + ">" + b
	if not _routes.has(key):
		_routes[key] = terrain.find_path(world.anchorages[a], world.anchorages[b])
	return _routes[key].duplicate()


func remove(n: Dictionary) -> void:
	npcs.erase(n)
	if _sprites.has(n.id):
		_sprites[n.id].queue_free()
		_sprites.erase(n.id)


func count(kind: String) -> int:
	return npcs.filter(func(n): return n.kind == kind).size()


func npc_at(pos: Vector2, radius: float) -> Dictionary:
	for n in npcs:
		if n.pos.distance_to(pos) < radius and _sprites.has(n.id):
			return n
	return {}


func find(id: String) -> Dictionary:
	for n in npcs:
		if n.id == id:
			return n
	return {}


func _ports_of(f: String) -> Array:
	return Ports.state.keys().filter(func(id): return Ports.port(id).faction == f)


# ---- drawing: sprites for ships within sight -------------------------------

func _update_sprites(player_pos: Vector2) -> void:
	var sight := nm(cfg().sight_nm)
	for n in npcs:
		var visible: bool = n.pos.distance_to(player_pos) < sight or Bases.watch_points().any(func(w): return n.pos.distance_to(w) < sight)  # watchtowers see too
		if visible and not _sprites.has(n.id):
			var shown := Career.flag_faction(n.flag)
			var adj: String = Data.table("factions")[shown].adjective if shown != "" and shown != "pirates" else ""
			news.emit("Sail ho: %s %s to the %s." % ["a pirate" if shown == "pirates" else (("an " if adj.left(1).to_lower() in "aeiou" else "a ") + adj if adj != "" else "an unmarked"),
				Data.table("ships")[n.enemy.type].name.to_lower(), Geo.compass_name(Geo.bearing(n.pos - player_pos))])
			var sp: Node2D = SPRITE.instantiate()
			add_child(sp)
			sp.setup(n.enemy.type, n.flag)
			sp.scale = Vector2.ONE * 0.74
			_sprites[n.id] = sp
		elif not visible and _sprites.has(n.id):
			_sprites[n.id].queue_free()
			_sprites.erase(n.id)
		if visible:
			var sp: Node2D = _sprites[n.id]
			sp.position = n.pos
			sp.rotation = deg_to_rad(n.heading)
			sp.set_state(1.0, 1.0, 2)
	queue_redraw()


func _draw() -> void:
	var font := Style.font("italic")
	for n in npcs:
		if _sprites.has(n.id):
			draw_string(font, n.pos + Vector2(-60, -18), n.enemy.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(Style.c("chart_ink"), 0.8))


# ---- saving ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {"npcs": npcs, "next_id": next_id}


func load_state(d: Dictionary) -> void:
	for id in _sprites:
		_sprites[id].queue_free()
	_sprites = {}
	npcs = d.npcs
	next_id = d.next_id
