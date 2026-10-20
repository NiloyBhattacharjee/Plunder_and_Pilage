extends GutTest

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 4
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	s.gold = 20000.0
	for i in 40:
		s.crew.append(People.add(People.generate({})))
	s.prizes.append(Fleet.ensure({"type": "brigantine", "name": "Prize", "faction": "spain", "hull": 160.0, "sails": 80.0}))


func spare() -> String:
	return s.crew.filter(func(id): return not id in s.officers.values())[0]


func test_a_prize_becomes_a_consort():
	var p: Dictionary = s.prizes[0]
	assert_false(Fleet.is_consort(p))
	Fleet.transfer(s, 0, Fleet.fight_need(p))
	assert_false(Fleet.is_consort(p), "hands but no captain")
	var cap := spare()
	Fleet.appoint(s, 0, cap)
	assert_false(cap in s.crew)
	assert_true(Fleet.is_consort(p))
	assert_eq(Fleet.allies(s).size(), 1)
	p.fights = false
	assert_eq(Fleet.allies(s).size(), 0, "kept out of the fight")


func test_the_squadron_eats_and_draws_pay():
	var before := ShipStats.headcount(s)
	var cost := ShipStats.daily_cost(s, ShipStats.effective(s.type, s.upgrades))
	Fleet.transfer(s, 0, 10)
	assert_eq(ShipStats.headcount(s), before, "moving hands doesn't change mouths")
	Fleet.appoint(s, 0, spare())
	assert_gt(ShipStats.daily_cost(s, ShipStats.effective(s.type, s.upgrades)), cost, "a consort costs upkeep and a captain's pay")


func test_a_consort_that_draws_too_much_fire_sinks():
	Fleet.transfer(s, 0, 30)
	Fleet.appoint(s, 0, spare())
	var a: Array = Fleet.allies(s)
	a[0].hull_lost = 999.0
	var msgs := Fleet.after_battle(s, a)
	assert_true(s.prizes.is_empty())
	assert_string_contains(msgs[0], "goes down")


func test_shifting_the_flag_keeps_both_ships():
	var old_type: String = s.type
	Fleet.shift_flag(s, 0)
	assert_eq(s.type, "brigantine")
	assert_eq(s.prizes[0].type, old_type)


func test_slots_limit_upgrades():
	s.upgrades = []
	ShipStats.install(s, "copper_sheathing")
	assert_string_contains(ShipStats.cannot_install(s, "reinforced_hull", 2), "slot", "a sloop has one hull slot")
	ShipStats.remove(s, "copper_sheathing")
	assert_eq(ShipStats.cannot_install(s, "reinforced_hull", 2), "")


func test_looks_have_effects():
	assert_eq(ShipStats.look_effect(s, "enemy_morale"), 0.0)
	s.look = {"sails": "black", "figurehead": "skull"}
	assert_eq(ShipStats.look_effect(s, "enemy_morale"), -9.0)
	assert_gt(ShipStats.look_effect(s, "no_false_colours"), 0.0)


func test_a_bitter_captain_sails_off_with_her():
	Fleet.transfer(s, 0, 30)
	var cap := spare()
	Fleet.appoint(s, 0, cap)
	People.person(cap).relations[s.captain] = -80
	var msgs := []
	for i in 2000:
		msgs = Fleet.daily(s, rng)
		if not msgs.is_empty():
			break
	assert_true(s.prizes.is_empty())
	assert_lt(Bonds.level(s, cap), 0, "and becomes a rival")


func test_ships_are_built_at_a_base():
	Bases.discovered.append("roatan")
	Bases.claim(s, "roatan")
	var b: Dictionary = Bases.bases.roatan
	b.gold = 5000.0  # paid and quiet: no rebellion or raid takes the yard before she's launched
	Bases.rng.seed = 4
	assert_string_contains(Bases.keel_problem(s, "roatan", "sloop"), "shipyard")
	b.buildings = ["dock", "careening_yard", "shipyard"]
	assert_string_contains(Bases.keel_problem(s, "roatan", "frigate"), "warehouse")
	Bases.lay_keel(s, "roatan", "sloop", "Hope")
	for i in 60:
		Bases.daily(s, "")
	assert_eq(b.prizes.size(), 1)
	assert_eq(b.prizes[0].name, "Hope")
