extends GutTest
## The trade economy: the price formula, stock moving with trades and with the days, shocks, and repeatability.

var m: EconomyModel


func before_each():
	m = EconomyModel.new()
	m.setup(Data.table("goods"), Data.table("ports"), Data.table("economy"), 7)


func warm() -> void:
	m.warm_up(240, 1)


func test_price_follows_stock_against_normal():
	var n: float = m.params.port_royal.sugar.normal
	assert_almost_eq(m.mult_at("port_royal", "sugar", n), 1.0, 0.001, "normal stock, base price")
	assert_almost_eq(m.mult_at("port_royal", "sugar", n / 4.0), pow(4.0, 0.5), 0.001, "luxury elasticity")
	assert_almost_eq(m.mult_at("port_royal", "food", m.params.port_royal.food.normal / 4.0), pow(4.0, 0.8), 0.01, "necessities react harder")
	assert_eq(m.mult_at("port_royal", "sugar", 0.0), 4.0, "clamped, never infinite")
	assert_eq(m.mult_at("port_royal", "sugar", n * 1000.0), 0.25, "and never free")


func test_buying_costs_more_than_selling_and_small_ports_spread_wider():
	assert_gt(m.price("port_royal", "rum", true), m.price("port_royal", "rum", false))
	var wide := m.price("nassau", "rum", true) / m.price("nassau", "rum", false)
	var narrow := m.price("port_royal", "rum", true) / m.price("port_royal", "rum", false)
	assert_gt(wide, narrow)
	assert_gt(m.price("havana", "rum", true, 1.0, 0.08), m.price("havana", "rum", true), "duty on top")


func test_big_sales_get_worse_prices():
	var small := m.quote("basseterre", "sugar", 10, false) / 10.0
	var big := m.quote("basseterre", "sugar", 200, false) / 200.0
	assert_lt(big, small * 0.9, "200 sugar sells for noticeably less each than 10")
	var before := m.mult("basseterre", "sugar")
	m.add("basseterre", "sugar", 200)
	assert_lt(m.mult("basseterre", "sugar"), before)


func test_ports_have_characters():
	warm()
	assert_lt(m.mult("bridgetown", "sugar"), 0.95, "sugar is cheap where it grows")
	assert_gt(m.mult("cartagena", "cloth"), 1.5, "European goods are dear where foreigners can't trade")
	assert_lt(m.mult("willemstad", "cloth"), m.mult("port_royal", "cloth"), "the Dutch free port undercuts everyone")
	assert_gt(m.mult("bridgetown", "food"), m.mult("santo_domingo", "food"), "plantations must buy their food")


func test_sugar_is_cheapest_after_the_harvest():
	warm()
	var lows := []
	var highs := []
	for month in range(1, 13):
		for d in 30:
			m.step(month)
		if month in [4, 5]:
			lows.append(m.mult("bridgetown", "sugar"))
		elif month in [10, 11]:
			highs.append(m.mult("bridgetown", "sugar"))
	assert_lt(lows.max(), highs.min(), "spring, after the harvest, is cheaper than autumn")


func test_a_glut_fades_back():
	warm()
	var before := m.mult("port_royal", "wine")
	m.add("port_royal", "wine", m.params.port_royal.wine.normal * 2.0)
	assert_lt(m.mult("port_royal", "wine"), before * 0.7)
	for d in 90:
		m.step(1)
	assert_almost_eq(m.mult("port_royal", "wine"), before, before * 0.12, "three months on, the market has absorbed it")


func test_shocks_change_production_and_expire():
	warm()
	m.add_mod("bridgetown", {"good": "sugar", "stock": 0.5, "make": 0.2, "days": 10, "reason": "Hurricane"})
	if m.level("bridgetown", "sugar") != "normal":
		assert_eq(m.reason("bridgetown", "sugar", 9), "Hurricane", "the shock is the reason given")
	for d in 11:
		m.step(6)
	assert_true(m.mods.bridgetown.is_empty())


func test_same_seed_same_economy():
	var other := EconomyModel.new()
	other.setup(Data.table("goods"), Data.table("ports"), Data.table("economy"), 7)
	for d in 100:
		m.step(3)
		other.step(3)
	assert_eq(m.stock, other.stock)


func test_player_trades_move_the_market():
	Ports.reset()
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "merchant_son"}).state
	s.gold = 100000.0
	var before := Economy.mult("port_royal", "rum")
	Ports.buy("port_royal", "rum", 40, s, 1000.0)
	assert_gt(Economy.mult("port_royal", "rum"), before)
	var res := Ports.sell("port_royal", "rum", 40, s)
	assert_true(res.ok)
	assert_eq(s.ledger.size(), 2)
	assert_lt(s.ledger[1].profit, 0, "selling straight back loses the spread and the duty")
