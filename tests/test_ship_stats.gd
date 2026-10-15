extends GutTest

var s: Dictionary


func before_each():
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func test_upgrades_apply_set_add_mult():
	var base := ShipStats.effective("brig", [])
	var up := ShipStats.effective("brig", ["reinforced_hull", "swivel_guns", "cannons_12"])
	assert_eq(up.hull, int(round(base.hull * 1.3)))
	assert_lt(up.speed_knots, base.speed_knots * 0.95)
	assert_eq(up.swivels, 6)
	assert_eq(up.crew_min, base.crew_min + 4)
	assert_eq(up.gun_weight, 12)


func test_expanded_hold_trades_guns_for_cargo():
	var base := ShipStats.effective("brigantine", [])
	var up := ShipStats.effective("brigantine", ["expanded_hold"])
	assert_gt(up.cargo, base.cargo)
	assert_lt(up.guns, base.guns)


func test_breakdown_names_each_upgrade():
	var text := ShipStats.breakdown("sloop", ["racing_rig", "copper_sheathing"], "speed_knots")
	assert_string_contains(text, "Racing rig")
	assert_string_contains(text, "Copper sheathing")


func test_cannon_upgrades_replace_each_other_and_respect_hull_limits():
	s.type = "brig"
	ShipStats.install(s, "cannons_12")
	ShipStats.install(s, "cannons_6")
	assert_eq(s.upgrades, ["cannons_6"])
	assert_ne(ShipStats.cannot_install(s, "cannons_24", 2), "", "a brig can't carry 24-pounders")
	assert_ne(ShipStats.cannot_install(s, "copper_sheathing", 1), "", "copper needs a large shipyard")


func test_condition_slows_a_worn_fouled_shorthanded_ship():
	var stats := ShipStats.effective(s.type, s.upgrades)
	var fresh: float = ShipStats.condition(s, stats).mult
	s.fouling = 0.5
	s.sails = stats.sails * 0.5
	s.crew = s.crew.slice(0, 5)
	var worn: float = ShipStats.condition(s, stats).mult
	assert_lt(worn, fresh * 0.6)
	assert_string_contains(ShipStats.condition(s, stats).text, "Short-handed")


func test_navigator_cuts_grounding_risk():
	var stats := ShipStats.effective("galleon", [])
	s.officers.erase("navigator")
	People.person(s.captain).skills.navigation = 0
	var without := ShipStats.grounding_risk(s, stats)
	var nav := People.generate()
	nav.skills.navigation = 18
	nav.traits = []
	s.crew.append(People.add(nav))
	s.officers.navigator = nav.id
	assert_lt(ShipStats.grounding_risk(s, stats), without * 0.5)
	assert_eq(ShipStats.grounding_risk(s, ShipStats.effective("sloop", [])), 0.0, "sloops float over shallows")


func test_officers_cost_more_than_hands():
	var stats := ShipStats.effective(s.type, [])
	s.officers = {}
	var no_officers := ShipStats.daily_cost(s, stats)
	NewGame.auto_appoint(s, 0)
	assert_gt(ShipStats.daily_cost(s, stats), no_officers)


func test_trade_in_falls_with_damage():
	var full := ShipStats.trade_in_value(s)
	s.hull = 10.0
	assert_lt(ShipStats.trade_in_value(s), full)


func test_deep_draught_routes_avoid_shallows():
	var g := TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	# Nassau to Havana: a sloop cuts across the Bahama Banks; a galleon goes round.
	var a := g.nearest_sea(Geo.latlon_to_px(25.078, -77.339))
	var b := g.nearest_sea(Geo.latlon_to_px(23.136, -82.359))
	var shallow_route := g.find_path(a, b)
	g.set_shallow_cost(Data.rules.draught.deep.route_cost)
	var deep_route := g.find_path(a, b)
	assert_false(deep_route.is_empty())
	assert_lt(_shallow_samples(g, a, deep_route), _shallow_samples(g, a, shallow_route))


func _shallow_samples(g: TerrainGrid, start: Vector2, path: PackedVector2Array) -> int:
	var shallow := 0
	var prev := start
	for p in path:
		var steps := int(prev.distance_to(p) / 4.0) + 1
		for k in steps:
			if g.at(prev.lerp(p, float(k) / steps)) == TerrainGrid.SHALLOW:
				shallow += 1
		prev = p
	return shallow
