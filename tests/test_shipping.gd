extends GutTest

var world


func before_each():
	world = load("res://scenes/world_map.tscn").instantiate()
	add_child_autofree(world)
	await get_tree().process_frame  # the world opens the start port deferred; close it once it's open
	world.port_screen.close()
	world.shipping.npcs = []
	world.shipping.rng.seed = 12


func after_each():
	Clock.day = 0.0
	Ports.reset()


## A voyage at sea with a route the map can draw.
func voyage() -> Dictionary:
	for v in Economy.voyages():
		if not world.shipping._route(v.origin, v.dest).is_empty():
			return v
	return {}


## A merchant at sea, drawn from the economy's voyages.
func merchant() -> Dictionary:
	var v := voyage()
	var path: PackedVector2Array = world.shipping._route(v.origin, v.dest)
	var at: Array = world.shipping._along(world.anchorages[v.origin], path, 0.5)
	return world.shipping.spawn_voyage(v, at[0], at[1])


func test_merchants_are_the_economys_voyages():
	assert_false(Economy.voyages().is_empty(), "the warmed-up economy has ships at sea")
	var v := voyage()
	var path: PackedVector2Array = world.shipping._route(v.origin, v.dest)
	var at: Array = world.shipping._along(world.anchorages[v.origin], path, Economy.progress(v))
	world.shipping._mirror(at[0])
	var n: Dictionary = world.shipping.npcs.filter(func(x): return x.get("voyage", "") == v.id)[0]
	assert_eq(n.enemy.cargo, {v.good: v.qty}, "she carries the voyage's cargo")
	var before: float = Economy.stock(v.dest, v.good)
	world.shipping._arrive(n)
	assert_eq(Economy.stock(v.dest, v.good), before, "the cargo lands on the economy's schedule, not twice")
	world.shipping.npcs = []
	world.shipping._mirror(Vector2(-99999, -99999))
	assert_eq(world.shipping.npcs.size(), 0, "nothing drawn far from anyone")


func test_patrols_and_pirates_spawn_with_goals():
	var navy: Dictionary = world.shipping.spawn("navy", "spain")
	var pirate: Dictionary = world.shipping.spawn("pirate", "pirates")
	assert_false(navy.route.is_empty())
	assert_eq(pirate.enemy.faction, "pirates")


func test_daily_fills_the_seas():
	for i in 10:
		world.shipping.daily()
	assert_gt(world.shipping.count("navy"), 0)
	assert_gt(world.shipping.count("pirate"), 0)


func test_pirates_take_merchants_they_meet():
	var m := merchant()
	var p: Dictionary = world.shipping.spawn("pirate", "pirates")
	p.pos = m.pos
	world.shipping._meetings()
	assert_false(m in world.shipping.npcs)
	assert_false(p.enemy.cargo.is_empty())
	assert_false(Economy.voyages().any(func(v): return v.id == m.voyage), "the voyage never arrives")
	assert_gt(Economy.model.traffic.route_risk(m.origin, m.dest), 0.0, "and the route remembers")


func test_deep_keels_cannot_follow_into_shallows():
	var s: Dictionary = world.ship.state
	s.career.pirate = true
	s.reputation.notoriety = 50
	var hunter: Dictionary = world.shipping.spawn("hunter", "spain")
	# put the player in shallow water with the hunter just outside it
	var g: TerrainGrid = world.terrain
	var shallow: Vector2 = Vector2.ZERO
	for c in g._shallow_cells:
		var p := (Vector2(c) + Vector2(0.5, 0.5)) * g.cell_px
		var deep := p + Vector2(0, 12)
		if g.at(deep) == TerrainGrid.DEEP:
			shallow = p
			hunter.pos = deep
			break
	assert_ne(shallow, Vector2.ZERO)
	hunter.enemy.type = "frigate"
	hunter.hostile = true
	var start: Vector2 = hunter.pos
	for i in 20:
		world.shipping.move(hunter, 0.05, shallow, s)
	assert_ne(g.at(hunter.pos), TerrainGrid.SHALLOW, "the frigate stops at the edge of the shallows")


func test_contact_signal_when_close():
	var m := merchant()
	world.ship.anchored_at = ""
	world.ship.position = m.pos
	watch_signals(world.shipping)
	world.shipping.contact.disconnect(world._on_contact)
	world.shipping._contacts(world.ship)
	assert_signal_emitted(world.shipping, "contact")


func test_shipping_survives_save_and_load():
	merchant()
	for i in 5:
		world.shipping.daily()
	var count: int = world.shipping.npcs.size()
	var first_pos: Vector2 = world.shipping.npcs[0].pos
	assert_eq(SaveGame.save_game(world, "user://ship_test.json"), OK)
	world.shipping.npcs = []
	assert_eq(SaveGame.load_game(world, "user://ship_test.json"), OK)
	assert_eq(world.shipping.npcs.size(), count)
	assert_eq(world.shipping.npcs[0].pos, first_pos)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ship_test.json"))
