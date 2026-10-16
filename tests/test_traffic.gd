extends GutTest
## Merchant traffic: route choice, cargo moving only on arrival, losses and route risk, wars, and news.

var m: EconomyModel


func before_each():
	m = EconomyModel.new()
	m.setup(Data.table("goods"), Data.table("ports"), Data.table("economy").duplicate(true), 3)  # a copy, so tests can turn knobs
	m.warm_up(120, 1)


func test_merchants_sail_for_a_profit():
	assert_false(m.traffic.voyages.is_empty())
	var dearer := 0
	for v in m.traffic.voyages:
		assert_true(m.traffic.allowed(v.faction, v.dest), "%s may trade at %s" % [v.faction, v.dest])
		if m.mult(v.dest, v.good) > m.mult(v.origin, v.good):
			dearer += 1
	assert_gt(dearer, m.traffic.voyages.size() * 0.7, "most cargoes are bound where they're dearer")


func test_cargo_leaves_on_sailing_and_lands_on_arrival():
	var tr := m.traffic
	var v: Dictionary = tr.voyages[0]
	var before: float = m.stock[v.dest][v.good]
	tr._arrive(v, m.day)
	assert_almost_eq(m.stock[v.dest][v.good], before + v.qty, 0.01)
	assert_false(v in tr.voyages)


func test_a_lost_voyage_never_arrives_and_frightens_the_route():
	var tr := m.traffic
	var v: Dictionary = tr.voyages[0]
	var before: float = m.stock[v.dest][v.good]
	tr.lose(v, "player", m.day)
	assert_false(v in tr.voyages)
	assert_eq(m.stock[v.dest][v.good], before)
	assert_almost_eq(tr.route_risk(v.origin, v.dest), Data.table("economy").traffic.loss_risk.player, 0.001)
	m.cfg.traffic.pirate_loss_per_day = 0.0  # no fresh losses while we watch
	m.cfg.traffic.storm_loss_per_day = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for d in 60:
		tr.step(m.day, 3)
	assert_lt(tr.route_risk(v.origin, v.dest), Data.table("economy").traffic.loss_risk.player * 0.6, "fear fades")


func test_risky_routes_see_fewer_ships():
	var calm := EconomyModel.new()
	calm.setup(Data.table("goods"), Data.table("ports"), Data.table("economy"), 3)
	calm.warm_up(120, 1)
	var key := "port_royal>nassau"
	var c0: int = calm.traffic.routes.get(key, {}).get("sailings", 0)
	var r0: int = m.traffic.routes.get(key, {}).get("sailings", 0)
	for d in 120:
		m.traffic.risk[key] = 0.9  # a raider working the route all season
		m.step(3)
		calm.step(3)
	var raided: int = m.traffic.routes.get(key, {}).get("sailings", 0) - r0
	var quiet: int = calm.traffic.routes.get(key, {}).get("sailings", 0) - c0
	assert_lt(raided, quiet, "merchants avoid it")


func test_no_trade_with_the_enemy():
	m.traffic.wars = [["england", "france"]]
	assert_false(m.traffic.allowed("england", "saint_pierre"))
	assert_true(m.traffic.allowed("england", "willemstad"))
	assert_false(m.traffic.allowed("england", "havana"), "Spain admits only its own")
	assert_true(m.traffic.allowed("dutch", "nassau"), "the Dutch trade with anyone")


func test_news_travels_with_ships():
	var tr := m.traffic
	var v: Dictionary = tr.voyages[0]
	var o: String = v.origin
	tr.board[v.dest][o] = {"day": -999, "m": {}}
	tr._arrive(v, m.day)
	assert_eq(tr.board[v.dest][o].day, v.depart, "the destination now knows the origin's prices as of her sailing")


func test_same_seed_same_traffic():
	var other := EconomyModel.new()
	other.setup(Data.table("goods"), Data.table("ports"), Data.table("economy"), 3)
	other.warm_up(120, 1)
	assert_eq(other.traffic.voyages.size(), m.traffic.voyages.size())
	assert_eq(other.stock, m.stock)
