extends GutTest

var s: Dictionary


func before_each():
	Ports.reset()
	Ports.rng.seed = 7
	s = {"crew": 40, "gold": 1000.0, "wages_owed": 0.0, "cargo": {"food": 100.0}, "cargo_cost": {}}


func test_buy_respects_hold_space():
	var r := Ports.buy("port_royal", "sugar", 1000, s, 60.0)
	assert_true(r.ok)
	assert_almost_eq(Market.cargo_used(s.cargo), 60.0, 1.0, "10 tons of food plus 50 of sugar")
	assert_gt(s.gold, 0.0)


func test_buy_respects_gold():
	s.gold = 50.0
	Ports.buy("port_royal", "cloth", 100, s, 200.0)
	assert_gte(s.gold, 0.0)
	assert_lt(s.cargo.get("cloth", 0), 2)


func test_buying_raises_the_local_price():
	var before := Ports.price("port_royal", "sugar", true)
	Ports.buy("port_royal", "sugar", 30, s, 200.0)
	assert_gt(Ports.price("port_royal", "sugar", true), before)


func test_sell_pays_and_tracks_cost_basis():
	Ports.buy("port_royal", "sugar", 20, s, 200.0)
	var paid: float = s.cargo_cost.sugar
	var gold_before: float = s.gold
	var r := Ports.sell("st_eustatius", "sugar", 10, s)
	assert_true(r.ok)
	assert_gt(s.gold, gold_before)
	assert_eq(s.cargo.sugar, 10.0)
	assert_almost_eq(s.cargo_cost.sugar, paid / 2.0, 0.01)


func test_contraband_can_be_seized():
	Ports.state.cartagena.laws.vigilance = 1000.0  # makes seizure certain
	s.cargo["cloth"] = 30.0
	var gold_before: float = s.gold
	var r := Ports.sell("cartagena", "cloth", 10, s)
	assert_false(r.ok)
	assert_false(s.cargo.has("cloth"), "all of it is confiscated")
	assert_lt(s.gold, gold_before, "plus a fine")


func test_hire_limited_by_berths():
	var r := Ports.hire("port_royal", 100, s, 75)
	assert_true(r.ok)
	assert_eq(s.crew, 75)
	assert_almost_eq(s.gold, 1000.0 - 35 * Data.rules.tavern.hire_cost, 0.01)


func test_rumour_teaches_a_price_elsewhere():
	var text := Ports.rumour("port_royal", 100)
	assert_ne(text, "")
	assert_eq(Ports.known.size(), 1)
	assert_false(Ports.known.has("port_royal"))


func test_market_events_happen_over_a_year():
	for i in 365:
		Ports.daily()
	assert_true(Ports.state.values().any(func(ps): return not ps.mods.is_empty()))
