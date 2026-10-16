extends GutTest
## Market events: random shocks, the effect handlers story events use, and the historical timeline.

var s: Dictionary


func before_each():
	Clock.day = 0.0
	s = NewGame.build({"nationality": "english", "background": "merchant_son"}).state
	EconomyEffects.player = s
	Economy.news = []


func after_each():
	Clock.day = 0.0
	Events.flags = {}


func test_every_effect_the_johnson_events_use_is_handled_or_knowingly_skipped():
	# the effect types listed in docs/economic_events.md (tools/economic_events.py's MARKET and WORLD sets)
	for t in ["market_shock", "open_market", "port_closed_days", "port_damage", "trade_profit_multiplier", "unlock_trade_with",
			"unlock_fence", "fence_trust", "fence_dependence", "launder_prize", "prize_unsellable_here", "sell_items",
			"buy_provisions", "rep_with_smugglers", "treat_ships_from", "faction_port_hostility", "burn_ships_in_road",
			"bombard_port", "repair_discount", "free_supplies", "merchant_resistance_multiplier", "war", "world_state",
			"pirate_spawn_rate_multiplier", "letter_of_marque", "revoke_letter_of_marque", "start_land_raid"]:
		assert_true(EconomyEffects.known(t) or t in EconomyEffects.SKIPPED, t)


func test_unknown_effects_are_skipped():
	assert_eq(EconomyEffects.apply({"type": "summon_kraken"}, {"s": s}), "")


func test_the_1722_hurricane_drives_up_naval_stores():
	var before := Economy.mult("port_royal", "naval_stores")
	EconomyEffects.apply({"type": "market_shock", "port": "port_royal", "goods": ["naval_stores", "provisions"], "price_multiplier": 1.8, "days": 90}, {"s": s})
	assert_almost_eq(Economy.mult("port_royal", "naval_stores"), minf(4.0, before * 1.8), 0.05)
	assert_gt(Economy.mult("port_royal", "food"), 1.0, "provisions is an alias for food")


func test_a_shock_fades():
	var before := Economy.mult("bridgetown", "cloth")
	Economy.model.apply_effect("bridgetown", {"type": "stock", "goods": "all", "mult": 0.4})
	assert_gt(Economy.mult("bridgetown", "cloth"), before * 1.3)
	for d in 120:
		Economy.model.step(2)
	assert_almost_eq(Economy.mult("bridgetown", "cloth"), before, before * 0.25, "four months on, trade has restored supply")


func test_random_shocks_strike_in_season():
	var m := EconomyModel.new()
	var cfg: Dictionary = Data.table("economy").duplicate(true)
	cfg.shock_chance_per_day = 1.0
	m.setup(Data.table("goods"), Data.table("ports"), cfg, 9)
	for d in 60:
		m.step(3)  # March: no hurricanes
	var seen: Array = m.shocks.take_events().map(func(e): return e.shock)
	assert_gt(seen.size(), 30)
	assert_false("hurricane" in seen, "hurricanes keep to their season")
	for e in m.shocks.events:
		assert_ne(e.news, "")


func test_an_open_market_pays_for_smuggled_goods():
	s.cargo.cloth = 20.0
	EconomyEffects.apply({"type": "open_market", "kind": "smuggling", "price_bonus": 25}, {"s": s, "port": "havana"})
	Ports.state.havana.laws.vigilance = 1000.0
	var res := Ports.sell("havana", "cloth", 20, s)
	assert_true(res.ok, "no customs at a smugglers' night")
	assert_string_contains(res.text, "interlopers")


func test_closed_ports_free_supplies_and_discounts():
	EconomyEffects.apply({"type": "port_closed_days", "port": "current", "days": 60}, {"s": s, "port": "bridgetown"})
	assert_false(Career.port_access(s, "bridgetown").open)
	EconomyEffects.apply({"type": "free_supplies", "days": 30}, {"s": s, "port": "port_royal"})
	var gold: float = s.gold
	Ports.buy("port_royal", "food", 50, s, 1000.0)
	assert_eq(s.gold, gold, "the town gives what you need")
	EconomyEffects.apply({"type": "repair_discount", "percent": 50, "days": 30}, {"s": s})
	assert_eq(EconomyEffects.active(s, "repair_discount").percent, 50.0)
	Clock.day = 40.0
	assert_null(EconomyEffects.active(s, "repair_discount"), "and it runs out")


func test_fences_from_events():
	EconomyEffects.apply({"type": "unlock_fence", "npc": "old_crackers"}, {"s": s, "port": "bridgetown"})
	assert_true(Ports.is_fence("bridgetown", s))
	var before := Ports.fence_mult("nassau", s)
	EconomyEffects.apply({"type": "fence_trust", "amount": -30}, {"s": s, "port": "nassau"})
	assert_lte(Ports.fence_mult("nassau", s), before)
	EconomyEffects.apply({"type": "fence_dependence", "amount": 5}, {"s": s, "port": "nassau"})
	assert_lt(Ports.fence_mult("nassau", s), before)


func test_world_drivers():
	EconomyEffects.apply({"type": "pirate_spawn_rate_multiplier", "value": 2.0, "days": 1500}, {"s": s})
	assert_eq(Economy.model.world_mult("pirates"), 2.0)
	EconomyEffects.apply({"type": "war", "between": ["england", "spain"], "until": "1680-03-01"}, {"s": s})
	assert_true(Factions.at_war("england", "spain"))
	Clock.day = 70.0
	Factions.apply_history(true)
	assert_false(Factions.at_war("england", "spain"), "the war ends on its date")
	EconomyEffects.apply({"type": "world_state", "key": "post_war_unemployment", "value": true, "days": 100}, {"s": s})
	assert_true(Events.flags.has("post_war_unemployment"))


func test_the_player_can_change_history():
	Events.flags["rogers_stopped"] = -1.0
	Factions.applied.erase("woodes_rogers")
	var ev: Dictionary = Data.table("history").woodes_rogers
	var saved: String = ev.date
	ev.date = "1680-01-01"
	Factions.apply_history(true)
	assert_true(Ports.is_fence("nassau", s), "Rogers never came: Nassau keeps its fences")
	Events.flags.erase("rogers_stopped")
	Factions.applied.erase("woodes_rogers")
	Factions.apply_history(true)
	assert_false(Ports.is_fence("nassau", s), "otherwise he cleans the place up")
	ev.date = saved
	Ports.reset()
