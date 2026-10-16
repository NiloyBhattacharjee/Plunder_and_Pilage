extends GutTest

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	rng.seed = 9
	Ports.reset()
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func test_generated_enemy_is_complete():
	for f in ["spain", "england", "pirates"]:
		var e := Encounters.generate(f, rng)
		assert_true(Data.table("ships").has(e.type))
		assert_gt(e.crew, 0)
		assert_true(e.has("captain"))
		if f == "pirates":
			assert_eq(e.kind, "pirate")


func test_pirates_are_hostile_merchants_are_not():
	assert_true(Career.npc_hostile(s, Encounters.generate("spain", rng, "pirate"), rng))
	assert_false(Career.npc_hostile(s, Encounters.generate("spain", rng, "merchant"), rng))
	var navy := Encounters.generate("spain", rng, "navy")
	assert_false(Career.npc_hostile(s, navy, rng))
	s.relations.spain = -50
	assert_true(Career.npc_hostile(s, navy, rng))


func test_attacking_costs_standing():
	var e := Encounters.generate("spain", rng, "merchant")
	var before: int = s.relations.spain
	Career.on_attack(s, e)
	assert_lt(s.relations.spain, before)
	assert_gt(s.reputation.notoriety, 0)


func test_casualties_kill_real_crew_and_surgeon_saves_some():
	var before: int = s.crew.size()
	var after := {"hull": 50.0, "sails": 30.0, "masts": 1, "guns_working": 6, "casualties": 20.0}
	s.officers.surgeon = s.crew[0]
	People.person(s.crew[0]).skills.medicine = 20
	People.person(s.crew[0]).traits = []
	Encounters.apply_battle(s, after, rng)
	assert_lt(s.crew.size(), before)
	assert_gt(s.crew.size(), before - 20, "a good surgeon saves lives")
	assert_eq(s.guns_lost, 2)
	assert_eq(s.hull, 50.0)


func test_taken_cargo_is_stolen_and_sells_cheap_without_a_fence():
	var e := Encounters.generate("spain", rng, "merchant")
	e.cargo = {"cocoa": 20}
	s.cargo = {}
	assert_eq(Encounters.take_cargo(s, e, "cocoa", 100, 60.0), 20)
	assert_eq(s.stolen.cocoa, 20)
	var clean := s.duplicate(true)
	clean.stolen = {}
	var r_legal := Ports.sell("port_royal", "cocoa", 20, s)
	Ports.reset()
	var r_clean := Ports.sell("port_royal", "cocoa", 20, clean)
	assert_lt(float(r_legal.value), r_clean.value * 0.6)
	assert_false(s.stolen.has("cocoa"))


func test_fence_pays_nearly_full_price():
	assert_eq(Ports.fence_mult("nassau"), Data.rules.fence.fence_mult)
	assert_gt(Ports.fence_mult("nassau"), Ports.fence_mult("havana") * 1.5, "far better than an honest market")


func test_eating_stolen_food_clears_the_mark():
	s.cargo = {"food": 10.0}
	s.stolen = {"food": 10.0}
	Ports.remove_cargo(s, "food", 4.0)
	assert_eq(s.stolen.food, 6.0)


func test_prisoner_fate_shapes_reputation_and_crew_feelings():
	var c := People.person(s.crew[0])
	c.traits = ["bloodthirsty"]
	var before: int = s.reputation.honour
	Encounters.prisoner_fate(s, "adrift")
	assert_gt(s.reputation.honour, before)
	assert_lt(c.relations.get(s.captain, 0), 0, "a bloodthirsty hand resents mercy")
	var react := Encounters.fate_reaction(s, "kill")
	assert_gte(react.pleased, 1)


func test_prize_takes_a_prize_crew_and_can_be_sold():
	var e := Encounters.generate("spain", rng, "merchant")
	var before: int = s.crew.size()
	var need := Encounters.prize_crew_needed(e)
	assert_eq(Encounters.take_prize(s, e, need), "")
	assert_eq(s.crew.size(), before - need)
	assert_eq(s.prizes.size(), 1)
	var gold: float = s.gold
	Ports.sell_prize("port_royal", 0, s)
	assert_gt(s.gold, gold)
	assert_eq(s.crew.size(), before)


func test_hostage_ransomed_only_in_their_nations_port():
	var e := Encounters.generate("spain", rng, "merchant")
	Encounters.take_hostage(s, e)
	assert_false(Ports.ransom("port_royal", s, 0).ok)
	var gold: float = s.gold
	assert_true(Ports.ransom("havana", s, 0).ok)
	assert_gt(s.gold, gold)
	assert_eq(s.hostages.size(), 0)


func test_surrender_strips_cargo_but_keeps_provisions():
	s.cargo = {"food": 50.0, "sugar": 20}
	s.gold = 100.0
	Encounters.surrender_losses(s)
	assert_false(s.cargo.has("sugar"))
	assert_eq(s.cargo.food, 50.0)
	assert_eq(s.gold, 50.0)


func test_recruited_prisoners_become_crew():
	var e := Encounters.generate("spain", rng, "pirate")
	var before: int = s.crew.size()
	var n := Encounters.recruit_prisoners(s, e, 20, 75, rng)
	assert_gt(n, 0)
	assert_eq(s.crew.size(), before + n)
