extends GutTest
## Port life: the town's situation comes from the economy, politics and war, and happenings grow out of it.

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	Ports.reset()
	Factions.reset()
	rng.seed = 5
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func after_each():
	Clock.day = 0.0
	Factions.reset()


func test_hunger_follows_the_price_of_food():
	var before: float = PortLife.situation("port_royal").hunger
	Economy.model.stock["port_royal"].food *= 0.1  # the warehouses empty
	var t := PortLife.situation("port_royal")
	assert_gt(t.hunger, before + 30.0)
	assert_lt(t.order, 100.0)
	assert_string_contains(PortLife.describe("port_royal"), "hungry")


func test_happenings_need_their_town():
	Economy.model.stock["port_royal"].food *= 0.05
	assert_true(PortLife.can_start("port_royal", "bread_riot", s), "a hungry town can riot")
	assert_false(PortLife.can_start("port_royal", "festival", s), "and doesn't hold feasts")
	assert_false(PortLife.can_start("nassau", "hanging", s), "pirates don't hang pirates")
	var at_war := Factions.enemies_of("england").is_empty()
	assert_eq(PortLife.can_start("port_royal", "press_gang", s), not at_war, "press gangs only in wartime")


func test_happenings_change_the_port():
	var cost := Ports.hire_cost("port_royal")
	PortLife.start("port_royal", "press_gang", rng)
	assert_true(PortLife.is_on("port_royal", "press_gang"))
	assert_gt(Ports.hire_cost("port_royal"), cost, "seamen are dear while the press is out")
	for d in 4:  # (it lasts at least five days)
		Ports.daily()
	assert_lt(Ports.state.port_royal.sailors, float(Ports.port("port_royal").sailors), "and the waterfront empties")


func test_happenings_end_and_rest():
	var h := PortLife.start("havana", "festival", rng)
	Clock.day = h.until + 0.1
	PortLife.daily(rng, s)
	assert_false(PortLife.is_on("havana", "festival"))
	assert_true(Ports.state.havana.life.ended.has("festival"), "a cooldown before the next one")


func test_events_read_the_town():
	var ctx := {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "port_royal", "storm": false}
	assert_false(Events.test("life.festival", ctx, {}))
	PortLife.start("port_royal", "festival", rng)
	assert_true(Events.test("life.festival", ctx, {}))
	assert_true(Events.test("town.wealth >= 0", ctx, {}))


func test_the_ball_needs_a_good_name():
	var h := PortLife.start("port_royal", "governors_ball", rng)
	var stats := ShipStats.effective(s.type, s.upgrades)
	s.relations.england = 20
	assert_eq(PortLife.action("port_royal", h, s, stats).problem, "", "invited")
	s.reputation.honour = -5
	assert_ne(PortLife.action("port_royal", h, s, stats).problem, "", "not with that reputation")


func test_a_captain_drinks_in_the_tavern():
	var h := PortLife.start("tortuga", "captains_drinking", rng)
	assert_true(h.has("captain"))
	assert_eq(PortLife.captain_here("tortuga"), h.captain)
	assert_string_contains(PortLife.text_of("tortuga", h), People.person(h.captain).name)


func ctx_at(id: String) -> Dictionary:
	return {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": id, "storm": false}


func test_feeding_a_hungry_town_ends_its_riot():
	var normal: float = Economy.model.params["port_royal"].food.normal
	Economy.model.stock["port_royal"].food = normal * 0.45
	var hunger: float = PortLife.situation("port_royal").hunger
	assert_gt(hunger, 40.0, "a hungry town")
	PortLife.start("port_royal", "bread_riot", rng)
	s.cargo.food = normal
	Events.apply_outcome("supply food %d" % int(normal * 0.6), ctx_at("port_royal"))
	assert_lt(PortLife.situation("port_royal").hunger, hunger, "food in the market brings the price down")
	PortLife.settle("port_royal", s)
	assert_false(PortLife.is_on("port_royal", "bread_riot"), "fed, the riot dies down")


func test_what_you_do_fades():
	var order: float = PortLife.situation("havana").order
	Events.apply_outcome("town order +20", ctx_at("havana"))
	assert_almost_eq(PortLife.situation("havana").order, minf(100.0, order + 20.0), 0.01)
	for d in 30:
		PortLife.daily(rng, s)
	assert_almost_eq(PortLife.situation("havana").order, order, 0.01, "a month later it's forgotten")


func test_happenings_vary_their_events():
	var h := PortLife.start("port_royal", "festival", rng)
	var first: String = PortLife.action("port_royal", h, s, ShipStats.effective(s.type, s.upgrades)).event
	Events.fired[first] = Clock.day
	var second: String = PortLife.action("port_royal", h, s, ShipStats.effective(s.type, s.upgrades)).event
	assert_ne(first, second, "not the same one twice running")


func test_new_happenings_need_their_town():
	assert_false(PortLife.can_start("havana", "revolt", s), "no plantations to rise")
	assert_true(PortLife.situation("bridgetown").plantation)
	assert_true(PortLife.situation("havana").contraband)
	assert_false(PortLife.situation("port_royal").contraband)
	assert_false(PortLife.can_start("port_royal", "smugglers", s), "nothing forbidden to smuggle")
