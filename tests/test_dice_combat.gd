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
