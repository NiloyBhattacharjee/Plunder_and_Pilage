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
			b.play_round(b.ai_orders(0))
		assert_ne(b.result, "", "battle %d never ended" % k)
		assert_between(b.sides[0].morale, 0.0, 100.0)
		if b.result in ["enemy_struck", "enemy_sunk"]:
			taken += 1
	assert_gt(taken, 10)
