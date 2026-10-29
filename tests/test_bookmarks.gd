extends GutTest


func after_each():
	Clock.day = 0.0
	Economy.piracy_start = {}
	NewGame.build({"nationality": "english", "background": "ex_navy"})


func test_a_later_bookmark_opens_on_its_day_with_history_caught_up():
	var s: Dictionary = NewGame.build({"nationality": "english", "background": "ex_navy", "bookmark": "republic"}).state
	assert_eq(Clock.date_string(), "1 November 1715")
	assert_eq(People.person(Bonds.real.hornigold).faction, "pirates", "the pardon is two years off")
	assert_true(People.person(Bonds.real.hornigold).id in Bonds.roster())
	assert_false(Bonds.real.has("blackbeard"))
	assert_false(People.person(Bonds.real.grammont).alive, "lost at sea in 1686")
	assert_true(Events.flags.has("fate_grammont"))
	assert_true(Factions.wars.is_empty(), "Utrecht made the peace")
	assert_true(Events.flags.has("post_war_unemployment"), "Utrecht's slump still runs")
	assert_gt(Economy.model.brethren.men(), 600)
	assert_true(s.bonds.is_empty())


func test_catch_up_keeps_only_whats_left():
	Clock.day = Clock.day_of("1716-01-01")
	var left := Factions.catch_up([{"type": "world_state", "key": "a", "days": 1500}, {"type": "world_state", "key": "b", "days": 30},
		{"type": "port_damage", "port": "port_royal"}, {"type": "fair_access", "faction": "england"}], "1713-04-11")
	assert_eq(left.size(), 2)
	assert_lt(int(left[0].days), 1500)
	assert_eq(left[1].type, "fair_access")
