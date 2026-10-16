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
	for d in 20:
		Ports.daily()
	assert_lt(Ports.state.port_royal.sailors, Ports.port("port_royal").sailors * 0.8, "and the waterfront empties")


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
