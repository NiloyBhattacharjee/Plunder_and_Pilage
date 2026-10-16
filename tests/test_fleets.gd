extends GutTest
## The treasure fleets and convoys, smuggling, the Navigation Acts, fences and treasure.

var m: EconomyModel


func before_each():
	m = EconomyModel.new()
	m.setup(Data.table("goods"), Data.table("ports"), Data.table("economy").duplicate(true), 5)
	m.warm_up(120, 1)


func run_until(fleet: String, status: String, year: int) -> void:
	for d in 800:
		var month := (d / 30) % 12 + 1
		m.step(month, year + d / 360)
		if m.fleets.state[fleet].status == status:
			return


func test_the_fair_floods_the_market_and_the_fleet_takes_the_silver():
	m.cfg.fleets.galeones.delay_days = [5, 5]
	run_until("galeones", "due", 1680)
	var cloth := m.mult("cartagena", "cloth")
	run_until("galeones", "fair", 1680)
	assert_lt(m.mult("cartagena", "cloth"), cloth * 0.8, "European goods flood in")
	var silver: float = m.stock.cartagena.silver
	run_until("galeones", "waiting", 1680)
	assert_lt(m.stock.cartagena.silver, silver * 0.5, "and the silver goes home")
	var events := m.fleets.take_events()
	assert_true(events.any(func(e): return e.kind == "sailed" and e.treasure > 0.0))


func test_after_1700_the_fleets_sometimes_dont_come():
	m.cfg.fleets.flota.skip_chance = 1.0
	m.fleets.state.flota.year = 0
	for d in 40:
		m.step(9, 1705)
	assert_eq(m.fleets.state.flota.status, "waiting")
	assert_true(m.fleets.take_events().any(func(e): return e.kind == "skipped"))


func test_the_sugar_convoy_buys_up_sugar():
	m.cfg.fleets.english_convoy.delay_days = [5, 5]
	run_until("english_convoy", "fair", 1690)
	assert_gt(m.fleets.use_mult("bridgetown", "sugar"), 1.0)
	assert_eq(m.fleets.use_mult("havana", "sugar"), 1.0, "only in the convoy's own ports")


func test_smugglers_carry_only_forbidden_goods_into_spain():
	assert_true(m.traffic.allowed("dutch", "cartagena"), "the Dutch smuggle")
	assert_false(m.traffic.allowed("france", "cartagena"))
	for d in 200:
		m.step(5)
	var runs: Array = m.traffic.voyages.filter(func(v): return v.get("smuggler", false))
	for v in runs:
		assert_has(m.ports[v.dest].laws.contraband, v.good)


func test_enumerated_goods_stay_with_their_nations_ships():
	for d in 200:
		m.step(3)
	for v in m.traffic.voyages:
		if v.faction != m.ports[v.origin].faction:
			assert_false(v.good in m.ports[v.origin].laws.get("enumerated", []), "%s loaded %s at %s" % [v.faction, v.good, v.origin])


func test_loading_enumerated_goods_under_foreign_colours_is_smuggling():
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "merchant_son"}).state
	s.gold = 100000.0
	s.flag = "dutch"
	Ports.state.bridgetown.laws.vigilance = 1000.0
	var res := Ports.buy("bridgetown", "sugar", 40, s, 1000.0)
	assert_false(res.ok)
	assert_string_contains(res.text, "English ships")
	s.flag = Data.table("factions").england.flag
	assert_true(Ports.buy("bridgetown", "sugar", 40, s, 1000.0).ok, "under English colours it's lawful")
	Ports.reset()


func test_fences_have_limited_coin_and_pay_more_as_they_trust_you():
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "merchant_son"}).state
	var first := Ports.fence_mult("nassau", s)
	s.fence_trust = {"nassau": 5000.0}
	assert_gt(Ports.fence_mult("nassau", s), first)
	s.cargo.silver = 200.0
	s.stolen = {"silver": 200.0}
	Ports.state.nassau.fence_cash = 1000.0
	var res := Ports.sell("nassau", "silver", 200, s)
	assert_lt(s.cargo.get("silver", 0.0) , 200.0)
	assert_gt(s.cargo.get("silver", 0.0), 0.0, "the fence ran out of coin before the silver ran out")
	assert_string_contains(res.text, "no more coin")
	Ports.reset()


func test_treasure_has_few_honest_buyers():
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "merchant_son"}).state
	s.cargo.silver = 10.0
	var res := Ports.sell("port_royal", "silver", 10, s)
	assert_string_contains(res.text, "went cheap")
	Ports.reset()
