extends GutTest

var sim: CombatSim


func _side(type: String, crew: int, behaviour := "warship") -> Dictionary:
	var st := ShipStats.effective(type, [])
	return {"name": type, "type": type, "upgrades": [], "hull": float(st.hull), "sails": float(st.sails), "crew": crew,
		"gunnery": 10, "swordplay": 8, "captain_swordplay": 10, "morale": 70.0, "carpentry": 5, "behaviour": behaviour}


func before_each():
	sim = CombatSim.new()
	sim.rng.seed = 11
	sim.setup(CombatSim.make_ship(_side("brig", 120, "player")), CombatSim.make_ship(_side("brig", 120)), 0.0, 1.0, "attack")


func _place(dist: float, enemy_bearing: float, my_heading: float) -> void:
	var me: Dictionary = sim.ships[0]
	me.pos = Vector2.ZERO
	me.heading = my_heading
	sim.ships[1].pos = Geo.from_bearing(enemy_bearing) * dist


func test_broadside_bears_only_off_the_beam():
	_place(200, 90, 0)   # heading north, enemy due east: starboard beam
	assert_eq(CombatSim.bearing_side(sim.ships[0], sim.ships[1].pos), "starboard")
	_place(200, 270, 0)
	assert_eq(CombatSim.bearing_side(sim.ships[0], sim.ships[1].pos), "port")
	_place(200, 0, 0)    # dead ahead: no guns bear
	assert_eq(CombatSim.bearing_side(sim.ships[0], sim.ships[1].pos), "")


func test_accuracy_falls_with_range():
	var near := sim.hit_chance(sim.ships[0], sim.ships[1], 50)
	var far := sim.hit_chance(sim.ships[0], sim.ships[1], CombatSim.gun_range(sim.ships[0]) * 0.95)
	assert_gt(near, far * 2.0)


func test_shot_outside_arc_misses_and_reload_blocks_second_shot():
	_place(150, 0, 0)
	var hull: float = sim.ships[1].hull
	assert_true(sim.fire(sim.ships[0], "starboard"))
	assert_eq(sim.ships[1].hull, hull, "enemy is dead ahead, nothing bears")
	assert_false(sim.fire(sim.ships[0], "starboard"), "still reloading")


func test_ammo_does_what_it_says():
	var t := CombatSim.make_ship(_side("brig", 120))
	var hull: float = t.hull
	var sails: float = t.sails
	sim.apply_hits(t, 10, 9, "chain")
	assert_gt(sails - t.sails, (hull - t.hull) * 3.0, "chain shreds sails, not hull")
	var t2 := CombatSim.make_ship(_side("brig", 120))
	sim.apply_hits(t2, 10, 9, "grape")
	assert_gt(t2.casualties, 15.0, "grape kills crew")
	assert_lt(t2.morale, 70.0)


func test_switching_ammo_forces_reload():
	var me: Dictionary = sim.ships[0]
	sim.set_ammo(me, "grape")
	assert_gt(me.reload.port, 0.0)
	assert_gt(me.reload.starboard, 0.0)


func test_short_crew_mans_fewer_guns():
	var me: Dictionary = sim.ships[0]
	var full := CombatSim.manned_guns(me)
	me.crew = 12.0
	assert_lt(CombatSim.manned_guns(me), full)
	assert_gt(CombatSim.reload_time(me), CombatSim.reload_time(sim.ships[1]))


func test_full_sail_is_faster_but_slows_reloading():
	var me: Dictionary = sim.ships[0]
	me.heading = 120.0  # broad reach in a north wind
	me.sail_setting = 1
	var battle := sim.target_speed(me)
	var reload_battle := CombatSim.reload_time(me)
	me.sail_setting = 2
	assert_gt(sim.target_speed(me), battle)
	assert_gt(CombatSim.reload_time(me), reload_battle)


func test_losing_a_mast_slows_the_ship():
	var me: Dictionary = sim.ships[0]
	me.heading = 120.0
	var before := sim.target_speed(me)
	me.masts -= 1
	assert_almost_eq(sim.target_speed(me), before / 2.0, 0.01)


func test_battered_merchant_strikes():
	var m := CombatSim.make_ship(_side("fluyt", 40, "merchant"))
	sim.ships[1] = m
	_place(150, 90, 0)
	m.morale = 20.0
	sim.step(0.1)
	assert_eq(sim.result, "enemy_struck")


func test_sinking_and_separation_end_the_fight():
	sim.ships[1].hull = 0.0
	sim.step(0.1)
	assert_eq(sim.result, "enemy_sunk")
	var sim2 := CombatSim.new()
	sim2.setup(CombatSim.make_ship(_side("sloop", 50, "player")), CombatSim.make_ship(_side("brig", 100)), 0.0, 1.0, "attack")
	sim2.ships[1].pos = Vector2(5000, 0)
	sim2.step(0.1)
	assert_eq(sim2.result, "separated")


func test_broken_crew_strikes_on_its_own():
	sim.ships[0].morale = -1.0
	sim.step(0.1)
	assert_eq(sim.result, "player_struck")


func test_boarding_needs_close_and_slow():
	_place(300, 90, 0)
	assert_false(sim.can_board())
	_place(40, 90, 0)
	sim.ships[0].speed = 10.0
	sim.ships[1].speed = 10.0
	sim.ships[1].heading = 0.0
	assert_true(sim.board(0))
	assert_eq(sim.result, "boarding")


func test_enemy_ai_turns_to_bring_guns_to_bear_and_fires():
	_place(220, 0, 0)  # enemy north of us
	sim.ships[1].heading = 180.0  # pointing at us: no broadside
	for i in 200:
		sim.step(0.05)
		if sim.ships[0].hull < sim.ships[0].hull_start:
			break
	assert_lt(sim.ships[0].hull, sim.ships[0].hull_start, "the AI manoeuvred and hit us")


func test_merchant_ai_runs():
	var m := CombatSim.make_ship(_side("fluyt", 40, "merchant"))
	m.morale = 100.0
	sim.ships[1] = m
	_place(500, 90, 0)
	sim.ships[0].sail_setting = 0
	var start := sim.distance()
	for i in 100:
		sim.step(0.1)
	assert_gt(sim.distance(), start)


func test_boarding_strong_side_wins():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var me := {"crew": 100.0, "swordplay": 10.0, "captain_swordplay": 10, "morale": 70.0}
	var them := {"crew": 40.0, "swordplay": 6.0, "captain_swordplay": 8, "morale": 50.0}
	var result := ""
	for i in 20:
		result = Boarding.fight_round(me, them, "push", "hold", rng).result
		if result != "":
			break
	assert_eq(result, "won")


func test_holding_costs_fewer_men_than_pushing():
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var a := {"crew": 80.0, "swordplay": 8.0, "captain_swordplay": 8, "morale": 60.0}
	var b := {"crew": 80.0, "swordplay": 8.0, "captain_swordplay": 8, "morale": 60.0}
	var push: float = Boarding.fight_round(a.duplicate(), b.duplicate(), "push", "push", rng).player_loss
	rng.seed = 2
	var hold: float = Boarding.fight_round(a.duplicate(), b.duplicate(), "hold", "push", rng).player_loss
	assert_lt(hold, push)


func test_captain_duel_swings_morale():
	var rng := RandomNumberGenerator.new()
	var me := {"crew": 50.0, "swordplay": 8.0, "captain_swordplay": 20, "morale": 60.0}
	var them := {"crew": 50.0, "swordplay": 8.0, "captain_swordplay": 0, "morale": 60.0}
	rng.seed = 1
	Boarding.fight_round(me, them, "captain", "hold", rng)
	assert_true(them.get("captain_down", false))
	assert_lt(them.morale, 30.0)
