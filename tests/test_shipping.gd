extends GutTest

var world


func before_each():
	world = load("res://scenes/world_map.tscn").instantiate()
	add_child_autofree(world)
	world.port_screen.close()
	world.shipping.npcs = []
	world.shipping.rng.seed = 12


func after_each():
	Clock.day = 0.0
	Ports.reset()


func test_merchants_carry_goods_from_producers_to_buyers():
	var n: Dictionary = {}
	for i in 20:
		n = world.shipping.spawn_merchant()
		if not n.is_empty():
			break
	assert_false(n.is_empty())
	var g: String = n.enemy.cargo.keys()[0]
	assert_true(g in Ports.port(n.origin).produces)
	assert_true(g in Ports.port(n.dest).wants)
	assert_false(n.route.is_empty())
	var before: float = Ports.state[n.dest].stock[g]
	world.shipping._arrive(n)
	assert_gt(Ports.state[n.dest].stock[g], before, "the cargo reaches the market")
	assert_eq(world.shipping.npcs.size(), 0)


func test_patrols_and_pirates_spawn_with_goals():
	var navy: Dictionary = world.shipping.spawn("navy", "spain")
	var pirate: Dictionary = world.shipping.spawn("pirate", "pirates")
	assert_false(navy.route.is_empty())
	assert_eq(pirate.enemy.faction, "pirates")


func test_daily_fills_the_seas():
	for i in 10:
		world.shipping.daily()
	assert_gt(world.shipping.count("merchant"), 5)
	assert_gt(world.shipping.count("navy"), 0)


func test_pirates_take_merchants_they_meet():
	var m: Dictionary = world.shipping.spawn_merchant()
	while m.is_empty():
		m = world.shipping.spawn_merchant()
	var p: Dictionary = world.shipping.spawn("pirate", "pirates")
	p.pos = m.pos
	world.shipping._meetings()
	assert_false(m in world.shipping.npcs)
	assert_false(p.enemy.cargo.is_empty())


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
	var m: Dictionary = world.shipping.spawn_merchant()
	while m.is_empty():
		m = world.shipping.spawn_merchant()
	world.ship.anchored_at = ""
	world.ship.position = m.pos
	watch_signals(world.shipping)
	world.shipping.contact.disconnect(world._on_contact)
	world.shipping._contacts(world.ship)
	assert_signal_emitted(world.shipping, "contact")


func test_shipping_survives_save_and_load():
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
