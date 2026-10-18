extends GutTest

var rng := RandomNumberGenerator.new()


func battle(kind: String, mode := "attack", seed := 1) -> DiceCombat:
	rng.seed = seed
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	var enemy := Encounters.generate("spain", rng, kind)
	enemy.party = DiceCombat.npc_party(enemy, rng)
	var b := DiceCombat.new()
	b.rng.seed = seed
	b.setup(DiceCombat.make_side(Encounters.player_side(s)), DiceCombat.make_side(enemy), mode, 1.0)
	return b


func test_modifiers_and_odds():
	assert_eq(Dice.mod(10), 0)
	assert_eq(Dice.mod(9), -1)
	assert_eq(Dice.mod(20), 5)
	assert_eq(Dice.mod(0), -5)
	assert_eq(Dice.chance(0, 11), 0.5)
	assert_eq(Dice.chance(-30, 50), 0.05, "a natural 20 always succeeds")
	assert_eq(Dice.chance(30, 0), 0.95, "a natural 1 always fails")
	assert_gt(Dice.contest_chance(0, 0), 0.5, "ties go to the one acting")
	assert_lt(Dice.contest_chance(-5, 5), 0.2)


func test_checks_keep_their_breakdown():
	var c := Dice.check(rng, "Test", [["Skill", 3], ["Gauge", 2]], 12)
	assert_eq(c.total, c.roll + 5)
	assert_eq(c.success, c.roll == 20 or (c.roll != 1 and c.total >= 12))
	assert_string_contains(Dice.describe(c), "Gauge +2")


func test_actions_depend_on_the_range_band():
	var b := battle("pirate")
	b.band = 0
	assert_true(b.available(0, "boatswain").has("flee"))
	assert_false(b.available(0, "boatswain").has("grapple"))
	assert_false(b.available(0, "master_gunner").has("grape"), "grape can't reach at long range")
	assert_true(b.available(0, "master_gunner").has("round"))
	b.band = 2
	assert_true(b.available(0, "boatswain").has("grapple"))
	b.band = 3
	assert_true(b.available(0, "quartermaster").has("push"))
	assert_false(b.available(0, "master_gunner").has("chain"))
	assert_false(b.available(1, "captain").has("strike"), "the enemy strikes through morale, not orders")


func test_grappling_brings_hand_to_hand():
	var b := battle("merchant")
	b.band = 3
	b.sides[1].party.erase("boatswain")  # nobody to cut the grapples
	b.next_queue = b.next_queue.filter(func(q): return q.side != 1 or q.post != "boatswain")
	var before: float = b.sides[0].casualties + b.sides[1].casualties
	b.play_round({"quartermaster": "push"})
	assert_true(b.entries.any(func(e): return e.text.begins_with("Hand to hand")))
	assert_gt(b.sides[0].casualties + b.sides[1].casualties, before)


func test_striking_ends_the_fight():
	var b := battle("navy")
	b.play_round({"captain": "strike"})
	assert_eq(b.result, "player_struck")


func test_fights_end_and_merchants_usually_fall():
	var taken := 0
	for k in 20:
		var b := battle("merchant", "attack", k + 1)
		while b.result == "" and b.round_no < 40:
			if b.turn().is_empty():
				break
			b.act_ai()  # your officers choose turn by turn, as you would
		assert_ne(b.result, "", "battle %d never ended" % k)
		assert_between(b.sides[0].morale, 0.0, 100.0)
		if b.result in ["enemy_struck", "enemy_sunk"]:
			taken += 1
	assert_gt(taken, 10)


func test_every_officer_gets_a_turn_in_order():
	var b := battle("navy")
	var t := b.turn()
	assert_eq(b.round_no, 1)
	var officers := func(q: Array) -> int: return q.filter(func(x): return not x.post.begins_with("@")).size()
	assert_eq(officers.call(b.queue), b.sides[0].party.size() + b.sides[1].party.size())
	assert_eq(officers.call(b.next_queue), officers.call(b.queue), "next round's order is known ahead")
	assert_has([0, 1], t.side)


func test_weak_points_break_a_ship():
	var b := battle("merchant")
	b.turn()
	var t: Dictionary = b.sides[1]
	assert_has(t.weak, "nerve", "merchant crews scare easily")
	assert_true(t.known.is_empty(), "you have to find her weak points")
	for k in t.shields_max:
		b._hit_weak(1, "nerve")
	assert_has(t.known, "nerve")
	assert_true(b.is_broken(1))
	t.morale = 100.0
	var sides_acting := []
	while true:  # her turns this round are passed over
		var who := b.turn()
		if b.round_no != 1:
			break
		sides_acting.append(who.side)
		b.act("")
	assert_false(1 in sides_acting)
	assert_true(b.is_broken(1), "and next round's too")
	b.end_round()
	b.begin_round()
	assert_false(b.is_broken(1))
	assert_eq(t.shields, t.shields_max, "shields come back")


func test_boost_points_bank_and_spend():
	var b := battle("pirate")
	var who := b.turn()
	var m: Dictionary = b.sides[who.side].party[who.post]
	assert_eq(m.bp, 2, "one to start and one for the round")
	b.act("", 2)
	assert_eq(m.bp, 0)
	assert_true(m.boosted)
	b.end_round()
	b.begin_round()
	assert_eq(m.bp, 0, "no point the round after a boost")
	b.end_round()
	b.begin_round()
	assert_eq(m.bp, 1)
	assert_gt(b.odds(0, "captain", "rally", 3), b.odds(0, "captain", "rally", 0))


func test_melee_allies_and_fire_take_turns():
	var b := battle("merchant")
	b.turn()
	var posts: Array = b.next_queue.map(func(q): return q.post)  # next round's, untouched: specials at the front of this one may already be passed over
	assert_has(posts, "@melee")
	assert_has(posts, "@damage")
	assert_false(b.special_applies({"side": -1, "post": "@melee"}), "no melee unless grappled")
	b.sides[1].fire = 1
	assert_true(b.special_applies({"side": 1, "post": "@damage"}))
	var hull: float = b.sides[1].hull
	b._run_special({"side": 1, "post": "@damage"})
	assert_lt(b.sides[1].hull, hull)


func test_intelligence_reveals_weak_points():
	rng.seed = 3
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	var enemy := Encounters.generate("spain", rng, "merchant")
	enemy.party = DiceCombat.npc_party(enemy, rng)
	enemy.captain_id = "cap_x"
	Encounters.add_intel(s, "cap_x", ["all"], "a captured log")
	var side := Encounters.player_side(s)
	side.intel = Encounters.intel_on(s, enemy)
	var b := DiceCombat.new()
	b.setup(DiceCombat.make_side(side), DiceCombat.make_side(enemy), "attack", 1.0)
	assert_eq(b.sides[1].known, b.sides[1].weak)
	Encounters.remember(s, {"captain_id": "cap_y", "type": "fluyt"}, ["chain", "nerve"])
	assert_eq(Encounters.intel_on(s, {"captain_id": "z", "type": "fluyt"}), ["chain"], "a class's rig is known; a crew's nerve isn't")


func with_conditions(kind: String, ids: Array, mode := "attack", seed := 1) -> DiceCombat:
	rng.seed = seed
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	var enemy := Encounters.generate("spain", rng, kind)
	enemy.party = DiceCombat.npc_party(enemy, rng)
	var side := Encounters.player_side(s)
	side.conditions = ids.map(func(id): return Encounters._condition(id))
	var b := DiceCombat.new()
	b.rng.seed = seed
	b.setup(DiceCombat.make_side(side), DiceCombat.make_side(enemy), mode, 1.0)
	return b


func test_conditions_change_the_odds():
	var clear := battle("navy")
	var fog := with_conditions("navy", ["fog"])
	assert_eq(fog.band, clear.band + 1, "in fog you sight each other late and close")
	fog.band = 0
	clear.band = 0
	assert_lt(fog.odds(0, "master_gunner", "round"), clear.odds(0, "master_gunner", "round"), "firing at a shadow")
	assert_gt(fog.odds(0, "boatswain", "flee"), clear.odds(0, "boatswain", "flee"), "a ship can lose herself in fog")
	var calm := with_conditions("navy", ["calm"])
	calm.band = 0
	assert_lt(calm.odds(0, "boatswain", "flee"), clear.odds(0, "boatswain", "flee"), "nobody runs in a dead calm")


func test_dusk_turns_to_night_and_fog_can_lift():
	var b := with_conditions("merchant", ["dusk", "fog"])
	b.conditions[1].ends = 1.0
	for r in 5:  # just the turning of the rounds, so nobody wins first
		b.begin_round()
	assert_true(b.has_condition("night"), "dusk becomes night after four rounds")
	assert_false(b.has_condition("fog"), "the fog lifted")


func test_dawn_catches_the_side_attacked():
	var b := with_conditions("merchant", ["dawn"], "attack")
	var calm := battle("merchant", "attack")
	assert_eq(b.gauge, 0, "the attacker has the gauge")
	assert_lt(b.sides[1].morale, calm.sides[1].morale)


func test_a_fort_fires_on_the_side_it_is_against():
	var b := with_conditions("navy", [])
	var f := Encounters._condition("fort", "Havana")
	f.merge({"port_name": "Havana", "guns": 24, "gunnery": 20, "gun_weight": 24, "side": 1}, true)
	b.conditions = [f]
	b.next_queue = b._roll_order()
	assert_true(b.next_queue.any(func(q): return q.post == "@fort"))
	var fired := false
	for r in 4:
		b.band = 1  # in range of the fort, not grappled
		b.result = ""
		b.play_round({})
		fired = fired or b.entries.any(func(e): return e.text.begins_with("The fort at Havana"))
	assert_true(fired, "the fort takes its turns")
	b.result = ""
	b.band = 1
	assert_eq(b.ai_orders(1).get("boatswain", ""), "open", "she wants out from under the guns")


func test_forts_take_sides():
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	var spanish := Encounters.generate("spain", rng, "merchant")
	assert_eq(Encounters.fort_target(s, spanish, "attack", "havana"), 0, "attack a Spaniard under Havana's walls and the fort fires on you")
	var pirate := Encounters.generate("pirates", rng, "pirate")
	assert_eq(Encounters.fort_target(s, pirate, "defend", "port_royal"), 1, "Port Royal's fort guards you from a pirate")


func test_captains_fight_to_their_temper():
	var b := battle("navy")
	b.sides[1].temper = "timid"
	b.sides[1].hull = b.sides[1].hull_start * 0.5
	b.band = 1
	assert_eq(b.ai_orders(1).get("boatswain", ""), "open", "a timid captain breaks off when it goes badly")
	b.sides[1].temper = "bold"
	assert_ne(b.ai_orders(1).get("boatswain", ""), "open", "a bold one comes on")
	assert_eq(DiceCombat.temperament({"traits": ["hot_headed"]}), "bold")
	assert_eq(DiceCombat.temperament({"traits": ["calm"]}), "steady")
	assert_eq(DiceCombat.temperament({"traits": []}), "")


func test_the_carpenter_can_get_guns_back_and_the_surgeon_chooses_who_to_save():
	var b := battle("navy", "attack", 4)
	var e: Dictionary = b.sides[1]
	e.party.carpenter.skills.carpentry = 20
	e.party.surgeon.skills.medicine = 20
	e.guns_working = int(e.stats.guns) - 6
	for i in 5:
		b._act(1, "carpenter", "remount")
	assert_gt(e.guns_working, int(e.stats.guns) - 6, "guns back on their carriages")
	e.party.captain.wounded = true
	e.captain_wounded = true
	for i in 5:
		b._act(1, "surgeon", "officers")
	assert_false(e.captain_wounded, "the captain first")
	e.casualties = 40.0
	var morale: float = e.morale
	for i in 3:
		b._act(1, "surgeon", "saw")
	assert_lt(e.casualties, 40.0)
	assert_lt(e.morale, morale + 1, "the crew hear the saw")


func test_quarter_is_worth_more_from_an_honourable_captain():
	var b := battle("navy", "attack", 9)
	b.band = 2  # within hail
	b.sides[0].party.captain.stats.charisma = 20
	b.sides[0].honour = 0
	var low := []
	var high := []
	for k in 2:
		b.sides[0].honour = 0 if k == 0 else 50
		for i in 20:
			b.sides[1].morale = 80.0
			b._act(0, "captain", "quarter")
			(low if k == 0 else high).append(80.0 - b.sides[1].morale)
	assert_gt(high.reduce(func(a, x): return a + x, 0.0), low.reduce(func(a, x): return a + x, 0.0))
