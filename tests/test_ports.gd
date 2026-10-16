extends GutTest

var s: Dictionary


func before_each():
	Ports.reset()
	Ports.rng.seed = 7
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	s.gold = 1000.0
	s.cargo = {"food": 100.0}


func test_buy_respects_hold_space():
	s.gold = 5000.0  # plenty, so the hold is what stops it
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


func test_haggling_narrows_the_spread():
	assert_lt(Ports.price("port_royal", "rum", true, 0.5), Ports.price("port_royal", "rum", true, 1.0))
	assert_gt(Ports.price("port_royal", "rum", false, 0.5), Ports.price("port_royal", "rum", false, 1.0))


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


func test_hire_creates_people_up_to_berths():
	var before: int = s.crew.size()
	var r := Ports.hire("port_royal", 100, s, 75)
	assert_true(r.ok)
	assert_eq(ShipStats.headcount(s), 75)
	assert_true(People.chars.has(s.crew[-1]), "each hand is a real character")
	assert_almost_eq(s.gold, 1000.0 - (75 - 1 - before) * Data.rules.tavern.hire_cost, 0.01)


func test_dismiss_never_removes_officers():
	var officers: Array = s.officers.values()
	Ports.dismiss("port_royal", s.crew.size(), s)
	for id in officers:
		assert_true(id in s.crew)


func test_buy_ship_moves_crew_and_drops_upgrades():
	s.gold = 20000.0
	s.upgrades = ["racing_rig"]
	var crew_before: Array = s.crew.duplicate()
	var r := Ports.buy_ship("port_royal", "brig", s)
	assert_true(r.ok)
	assert_eq(s.type, "brig")
	assert_eq(s.upgrades, [])
	assert_eq(s.crew, crew_before)
	assert_eq(s.hull, float(Data.table("ships").brig.hull))


func test_cannot_buy_ship_too_small_for_crew():
	s.gold = 20000.0
	s.crew.resize(0)
	for i in 60:
		s.crew.append(People.add(People.generate()))
	assert_false(Ports.buy_ship("bridgetown", "schooner", s).ok)


func test_rumour_teaches_a_price_elsewhere():
	var text := Ports.rumour("port_royal", 100)
	assert_ne(text, "")
	assert_eq(Ports.known.size(), 1)
	assert_false(Ports.known.has("port_royal"))


func test_market_events_on_purpose():
	var news := Ports.start_market_event("bridgetown", "glut")
	assert_string_contains(news, "Bridgetown")
	assert_false(Economy.mods("bridgetown").is_empty())
