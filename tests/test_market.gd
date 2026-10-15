extends GutTest

var port_royal: Dictionary = Data.table("ports").port_royal  # large; produces sugar, wants cloth


func _price(port: Dictionary, good: String, buying := true) -> float:
	return Market.unit_price(port, good, Market.normal_stock(port, good, []), buying)


func test_produced_goods_are_cheap_and_wanted_goods_dear():
	assert_lt(_price(port_royal, "sugar"), Data.table("goods").sugar.base_price)
	assert_gt(_price(port_royal, "cloth"), Data.table("goods").cloth.base_price)


func test_buy_price_above_sell_price():
	assert_gt(_price(port_royal, "rum", true), _price(port_royal, "rum", false))


func test_big_trades_move_the_price_against_you():
	var stock := Market.normal_stock(port_royal, "sugar", [])
	assert_gt(float(Market.quote(port_royal, "sugar", stock, 50, true)), Market.unit_price(port_royal, "sugar", stock, true) * 50)
	assert_lt(float(Market.quote(port_royal, "sugar", stock, 50, false)), Market.unit_price(port_royal, "sugar", stock, false) * 50)


func test_small_ports_saturate_faster_than_large():
	var small: Dictionary = Data.table("ports").portobelo
	var s_small := Market.normal_stock(small, "rum", [])
	var s_large := Market.normal_stock(port_royal, "rum", [])
	var drop_small := Market.unit_price(small, "rum", s_small + 20, false) / Market.unit_price(small, "rum", s_small, false)
	var drop_large := Market.unit_price(port_royal, "rum", s_large + 20, false) / Market.unit_price(port_royal, "rum", s_large, false)
	assert_lt(drop_small, drop_large)


func test_light_goods_move_the_market_less():
	assert_eq(Market.max_buy("food", 11.0), 100)
	assert_eq(Market.max_buy("sugar", 11.0), 10)


func test_stock_drifts_back_to_normal():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ps := {"stock": {"sugar": 20.0}, "mods": []}
	for i in 120:
		Market.daily_update(port_royal, ps, rng)
	var normal := Market.normal_stock(port_royal, "sugar", [])
	assert_almost_eq(ps.stock.sugar, normal, normal * 0.35)


func test_shortage_lowers_normal_stock_and_expires():
	var mods := [{"good": "cloth", "mult": 0.35, "days_left": 2, "reason": "Shortage"}]
	assert_lt(Market.normal_stock(port_royal, "cloth", mods), Market.normal_stock(port_royal, "cloth", []))
	var ps := {"stock": {"cloth": 30.0}, "mods": mods}
	var rng := RandomNumberGenerator.new()
	Market.daily_update(port_royal, ps, rng)
	Market.daily_update(port_royal, ps, rng)
	assert_eq(ps.mods.size(), 0)


func test_seizure_risk_only_for_contraband_and_grows_with_quantity():
	var laws := {"contraband": ["cloth"], "vigilance": 0.6}
	assert_eq(Market.seizure_chance(laws, "sugar", 50), 0.0)
	assert_gt(Market.seizure_chance(laws, "cloth", 50), Market.seizure_chance(laws, "cloth", 10))
	assert_lt(Market.seizure_chance(laws, "cloth", 50), 1.0)


func test_breakdown_explains_the_price():
	var ps := {"stock": {"cloth": 10.0}, "mods": [{"good": "cloth", "mult": 0.35, "days_left": 9, "reason": "Shortage"}]}
	var text := Market.breakdown(port_royal, "cloth", ps, {"contraband": ["cloth"], "vigilance": 0.5})
	assert_string_contains(text, "Shortage")
	assert_string_contains(text, "in demand here")
	assert_string_contains(text, "CONTRABAND")
