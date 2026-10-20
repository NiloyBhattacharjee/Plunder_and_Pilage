extends GutTest
## Ambitions: take one up, chase it, earn a title (and sometimes an edge).

var s: Dictionary


func before_each():
	Clock.day = 0.0
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func ctx() -> Dictionary:
	return {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "", "storm": false}


func test_offers_follow_your_situation():
	var ids := Ambitions.offered(s, ctx())
	assert_true("scourge" in ids)
	assert_false("pardon" in ids, "nothing to be pardoned for")
	assert_false("corsair" in ids, "no letter of marque")
	s.career.marque = "england"
	assert_true("corsair" in Ambitions.offered(s, ctx()))


func test_tallies_count_from_when_you_take_it_up():
	Ambitions.tally(s, "ships_taken", 3)
	Ambitions.take(s, "scourge")
	assert_eq(Ambitions.progress(s, ctx()), [0.0, 5.0], "earlier prizes don't count")
	Ambitions.tally(s, "ships_taken", 4)
	assert_true(Ambitions.check(s, ctx()).is_empty())
	Ambitions.tally(s, "ships_taken")
	var fear: float = s.reputation.fear
	var won := Ambitions.check(s, ctx())
	assert_eq(won.title, "Scourge of the Main")
	assert_gt(s.reputation.fear, fear, "the rewards apply")
	assert_true(ShipStats.captain(s).ambition.is_empty())
	assert_eq(Ambitions.bonus(s, "enemy_morale"), -5.0, "a lasting edge")
	assert_false("scourge" in Ambitions.offered(s, ctx()), "achieved once")


func test_values_read_your_situation():
	Ambitions.take(s, "fortune")
	s.gold = 4000
	assert_eq(Ambitions.progress(s, ctx())[0], 4000.0)
	assert_string_contains(Ambitions.summary(s, ctx()), "4.0k/10.0k")
	s.gold = 12000
	assert_eq(Ambitions.check(s, ctx()).title, "the Rich")
	assert_eq(Ambitions.title(s), "the Rich")


func test_giving_up_disappoints_the_crew():
	Ambitions.take(s, "haven")
	var id: String = s.crew[0]
	var before: int = People.person(id).relations.get(s.captain, 0)
	Ambitions.abandon(s, ctx())
	assert_true(ShipStats.captain(s).ambition.is_empty())
	assert_lt(People.person(id).relations.get(s.captain, 0), before)


func test_every_ambition_is_well_formed():
	for id in Ambitions.table():
		if id.begins_with("_"):
			continue
		var a: Dictionary = Ambitions.table()[id]
		assert_true(a.has("tally") != a.has("value"), "%s: a tally or a value" % id)
		for o in a.get("rewards", []):
			var w: PackedStringArray = o.split(" ", false)
			assert_true(Events.VERBS.has(w[0]) and w.size() - 1 >= Events.VERBS[w[0]][0] and w.size() - 1 <= Events.VERBS[w[0]][1], "%s: %s" % [id, o])
		for c in a.get("requires", []):
			assert_eq(Events._check_cond(c, id, false), PackedStringArray(), "%s: %s" % [id, c])
