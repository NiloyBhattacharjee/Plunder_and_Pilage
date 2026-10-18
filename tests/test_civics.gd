extends GutTest

var s: Dictionary
var stats: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 3
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	stats = ShipStats.effective(s.type, s.upgrades)
	s.gold = 5000.0
	for i in 80:
		s.crew.append(People.add(People.generate({})))


func after_each():
	Clock.day = 0.0


func test_every_slot_has_its_default_and_options():
	for slot in Civics.table()._slots:
		var d: String = Civics.table()._slots[slot].default
		assert_eq(Civics.table()[d].slot, slot, "%s's default is one of its options" % slot)
		assert_false(Civics.table()[d].has("bonus"), "a default costs nothing")
		assert_gt(Civics.options(slot).size(), 1, "%s is a choice" % slot)
	for id in Civics.table():
		if not id.begins_with("_"):
			for k in Civics.table()[id].get("bonus", {}):
				assert_true(Civics.EFFECTS.has(k), "%s.%s is described" % [id, k])


func test_articles_change_the_crew_and_wait_a_month():
	var calm: float = Crew.morale(s, stats).value
	var cost := ShipStats.daily_cost(s, stats)
	assert_string_contains(Civics.adopt(s, stats, s, "maimed_fund", rng), "maimed")
	assert_eq(Civics.chosen(s, "maimed"), "maimed_fund", "a navy captain just decides")
	assert_gt(Crew.morale(s, stats).value, calm)
	assert_gt(ShipStats.daily_cost(s, stats), cost, "and pays for it")
	assert_ne(Civics.problem(s, "own_risk"), "", "not again this month")
	Clock.day = 31.0
	assert_eq(Civics.problem(s, "own_risk"), "")


func test_a_harsh_article_imposed_is_resented():
	Civics.adopt(s, stats, s, "the_lash", rng)
	assert_true(s.morale_mods.any(func(m): return m.id == "articles_imposed"))
	assert_lt(Civics.bonus(s, "unrest"), 0.0, "and ringleaders find fewer listeners")


func test_town_laws_move_order_loyalty_and_the_harbour():
	Sieges.hold(s, "maracaibo")
	var b: Dictionary = Bases.bases.maracaibo
	var order: float = PortLife.situation("maracaibo").order
	var tax := Bases.tax_income("maracaibo")
	Civics.adopt(s, stats, b, "martial_law", rng, "maracaibo")
	assert_gt(PortLife.situation("maracaibo").order, order, "quiet streets")
	assert_lt(Bases.tax_income("maracaibo"), tax, "and trade suffers")
	var pirates: int = s.relations.pirates
	Civics.adopt(s, stats, b, "closed_to_pirates", rng, "maracaibo")
	assert_lt(Ports.state.maracaibo.laws.pirates, 0.0, "the Brethren are turned away")
	assert_lt(s.relations.pirates, pirates, "and they take it badly")
	assert_eq(Civics.chosen(b, "rule"), "martial_law", "each slot holds its own choice")
