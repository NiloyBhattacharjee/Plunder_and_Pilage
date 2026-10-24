extends GutTest
## The pirates as a population: war and peace, prizes and volunteers, the navy, havens, pardons.

var m: EconomyModel
var b: Brethren


func before_each():
	m = EconomyModel.new()
	m.setup(Data.table("goods"), Data.table("ports"), Data.table("economy").duplicate(true), 3)
	b = m.brethren


func weeks(n: int, month := 3, year := 1716) -> void:
	for i in n * 7:
		m.step(month, year)


func test_a_long_war_takes_seamen_in_and_the_peace_throws_them_out():
	m.traffic.wars = [["england", "spain"]]
	weeks(200, 3, 1705)
	assert_gt(b.service, 3000.0, "a long war has the seamen in service")
	var idle_at_war := b.idle
	m.traffic.wars = []
	weeks(60, 3, 1714)
	assert_gt(b.idle, idle_at_war + 1000.0, "paid off at the peace")


func test_a_short_war_barely_dents_them():
	m.traffic.wars = [["england", "spain"]]
	weeks(10, 3, 1719)
	assert_lt(b.mobilised(), 0.1)


func test_a_prize_feeds_the_company_working_that_route_and_angers_her_nation():
	b.companies = []
	b._form(60, ["nassau"], "florida_straits", false)
	var co: Dictionary = b.companies[0]
	b.on_loss({"origin": "havana", "dest": "veracruz", "faction": "spain"}, "pirates")
	assert_eq(co.prizes, 1)
	assert_gt(co.men, 60, "her sailors sign on")
	assert_gt(b.pressure.spain, 0.0)
	assert_gt(b.heat.florida_straits, 0.0, "the navy will know where to look")


func test_threat_levels_off():
	b.companies = []
	b._form(100, [], "spanish_main", false)
	var one := b.threat("cartagena", "portobelo")
	b.companies[0].men = 10000
	var many := b.threat("cartagena", "portobelo")
	assert_gt(many, one)
	assert_lte(many, 1.0)
	assert_eq(b.threat("havana", "veracruz"), 0.0, "nobody cruising there")


func test_nassau_closes_when_rogers_comes():
	assert_true("nassau" in b.havens(1716))
	m.apply_effect("nassau", {"type": "haven_closed"})
	assert_false("nassau" in b.havens(1716))
	assert_false("tortuga" in b.havens(1716), "Tortuga's buccaneer days are over")


func test_a_company_ends_and_the_tally_remembers():
	b.companies = []
	b._form(100, [], "windward_passage", false)
	b.lose(b.companies[0].id, "navy")
	assert_true(b.companies.is_empty())
	assert_eq(b.tally.hanged, int(100 * float(b.cfg().hanged_share)))
	assert_false(b.take_events().is_empty(), "the news goes round")


func test_saved_and_loaded():
	weeks(20)
	var other := EconomyModel.new()
	other.setup(Data.table("goods"), Data.table("ports"), m.cfg, 3)
	other.load_state(JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(m.save_state())))))
	assert_eq(other.brethren.men(), b.men())
	assert_eq(other.brethren.companies.size(), b.companies.size())
