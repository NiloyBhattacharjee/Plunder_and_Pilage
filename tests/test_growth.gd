extends GutTest


func person() -> Dictionary:
	var c := People.generate({})
	People.add(c)
	return c


func test_experience_brings_levels_points_and_perks():
	var c := person()
	for i in 200:
		People.gain_xp(c, "gunnery", 1.0)
	assert_gt(Growth.level(c), 3)
	assert_eq(int(c.points), Growth.level(c) - 1, "a point a level")
	assert_eq(int(c.perk_picks), Growth.level(c) / 3, "a perk every third level")
	var before: int = c.skills.navigation
	Growth.raise(c, "navigation")
	assert_eq(c.skills.navigation, before + 1)


func test_perks_need_skill():
	var c := person()
	c.skills.gunnery = 5
	c.perk_picks = 1
	assert_false("steady_hand" in Growth.perks_open(c))
	assert_true("quick_study" in Growth.perks_open(c), "some perks need nothing")
	c.skills.gunnery = 12
	Growth.take_perk(c, "steady_hand")
	assert_true(Growth.has_perk(c, "steady_hand"))
	assert_eq(int(c.perk_picks), 0)


func test_hands_spend_their_own_points():
	var c := person()
	c.points = 2
	var best := ""
	for k in People.SKILLS:
		if best == "" or c.skills[k] > c.skills[best]:
			best = k
	var was: int = c.skills[best]
	Growth.auto_spend(c)
	assert_eq(c.skills[best], mini(20, was + 2))


func test_point_buy_captain():
	var b := {"stats": {"authority": 3}, "skills": {"gunnery": 4}, "traits": ["brave"], "flaw": "drunkard", "portrait": {"seed": 1, "pick": {"hat": ""}}}
	assert_eq(NewGame.build_points(b).stats, Data.rules.growth.build.stat_points - 3)
	assert_eq(NewGame.build_points(b).skills, Data.rules.growth.build.skill_points + Data.rules.growth.build.flaw_points - 4)
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "ex_navy", "build": b}).state
	var cap := People.person(s.captain)
	var bg: Dictionary = Data.table("backgrounds").ex_navy
	assert_eq(cap.stats.authority, NewGame.build_value(bg, b, "authority"))
	assert_has(cap.traits, "brave")
	assert_has(cap.traits, "drunkard")
	assert_false(Portraits.layers(cap, ["captain"]).any(func(l): return l.layer == "hat"), "chose no hat")


func test_perks_work_in_battle():
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	People.person(s.captain).perks = ["reserves"]
	var enemy := Encounters.generate("spain", rng, "merchant")
	enemy.party = DiceCombat.npc_party(enemy, rng)
	var b := DiceCombat.new()
	b.setup(DiceCombat.make_side(Encounters.player_side(s)), DiceCombat.make_side(enemy), "attack", 1.0)
	assert_eq(b.sides[0].party.captain.bp, Data.rules.dice_combat.boost.start + 2)
