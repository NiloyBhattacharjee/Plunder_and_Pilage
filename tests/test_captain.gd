extends GutTest
## The captain's own life: the night they took the ship, their nature, their focus, and choices that show what they ask of you.

var s: Dictionary
var stats: Dictionary


func before_each():
	Clock.day = 0.0
	Events.reset()
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	stats = ShipStats.effective(s.type, s.upgrades)


func after_each():
	Clock.day = 0.0
	Events.reset()


func ctx(port := "") -> Dictionary:
	return {"s": s, "stats": stats, "port": port, "storm": false}


func test_every_background_has_a_night_that_starts_its_story():
	for id in Data.table("backgrounds"):
		var night: String = Data.table("backgrounds")[id].get("night", "")
		assert_true(Events.events.has(night), "%s has a night" % id)
		for ch in Events.events[night].choices:
			var outs: Array = ch.get("outcomes", []) + ch.get("fail_outcomes", [])
			assert_true(outs.has("event night_captain 0 5"), "%s: on to the old captain" % ch.text)
			var story: Array = outs.filter(func(o): return o.begins_with("event ") and Events.events[o.split(" ")[1]].has("story"))
			assert_false(story.is_empty(), "%s: someone will come looking" % ch.text)
	for f in Data.table("focus"):
		if not f.begins_with("_"):
			for p in Data.table("focus")[f].perks:
				assert_true(Data.table("perks").has(p), p)


func test_the_night_plays_through_and_shapes_the_captain():
	s = NewGame.build({"nationality": "english", "background": "ex_navy", "focus": "blade", "night": true}).state
	stats = ShipStats.effective(s.type, s.upgrades)
	assert_eq(s.night, "night_navy")
	assert_eq(ShipStats.captain(s).focus, "blade")
	ShipStats.captain(s).traits = ["former_navy"]  # nothing rolled that calm would clash with
	var inst := Events.materialize(Events.instance_of(s.night, ctx("port_royal")), ctx("port_royal"))
	var seen := []
	while not inst.is_empty():
		seen.append(inst.id)
		var ev: Dictionary = Events.events[inst.id]
		var pick: int = ev.choices.size() - 1 if inst.id == "night_captain" else 0  # the crew vote
		Events.view(inst, ctx("port_royal"))
		Events.resolve(inst, pick, ctx("port_royal"))
		inst = Events.take_chain("night_", ctx("port_royal"))
		if not inst.is_empty():
			inst = Events.materialize(inst, ctx("port_royal"))
	assert_eq(seen, ["night_navy", "night_captain", "night_dawn"])
	assert_true("calm" in ShipStats.captain(s).traits, "the old captain's fate made you who you are")
	var warrant: Array = Events.queue.filter(func(q): return q.id == "warrant_posted")
	assert_eq(warrant.size(), 1, "the lieutenant is coming")
	assert_true(People.chars.has(str(warrant[0].vars.hunter)), "the same lieutenant you met that night")


func test_going_against_your_nature_wears_it_away():
	var cap := ShipStats.captain(s)
	cap.traits = ["merciful"]
	assert_eq(Nature.tag(cap, {"cruel": 2}), "[Against: Merciful] ")
	assert_eq(Nature.tag(cap, {"cruel": -1}), "[Merciful] ")
	for i in int(Data.rules.nature.strain) - 1:
		Nature.chose(cap, {"cruel": 2})
	assert_true("merciful" in cap.traits, "not yet")
	var news := Nature.chose(cap, {"cruel": 2})
	assert_false("merciful" in cap.traits)
	assert_true(news.any(func(n): return "no longer" in n))


func test_leaning_one_way_becomes_a_trait():
	var cap := ShipStats.captain(s)
	cap.traits = []
	for i in int(Data.rules.nature.drift):
		Nature.chose(cap, {"bold": 1})
	assert_true("brave" in cap.traits)
	cap.traits = ["cowardly"]
	for i in int(Data.rules.nature.drift):
		Nature.chose(cap, {"bold": 1})
	assert_false("brave" in cap.traits, "not while the opposite holds")


func test_choices_wear_their_requirements():
	var cap := ShipStats.captain(s)
	var ch := {"text": "x", "conditions": ["captain.swordplay >= 12", "captain_trait.devout", "gold >= 10"]}
	assert_eq(Events.tags(ch, ctx(), {}), "[Swordplay 12] [Devout] ")
	cap.skills.swordplay = 20
	var t := Events.tags({"text": "x", "check": {"who": "captain", "skill": "swordplay", "dc": 5}}, ctx(), {})
	assert_string_starts_with(t, "[Swordplay ")
	assert_string_ends_with(t, "%] ")


func test_a_focus_teaches_its_perks_in_order():
	var cap := ShipStats.captain(s)
	cap.focus = "blade"
	cap.perks = []
	var ranks: Array = Data.rules.growth.focus.ranks
	var before := People.value(cap, "swordplay")
	Growth.focus_gain(cap, float(ranks[0]))
	assert_true(Growth.has_perk(cap, "hardened"))
	assert_false(Growth.has_perk(cap, "dread_name"))
	assert_eq(People.value(cap, "swordplay"), mini(20, before + 2), "a perk's effects count like a trait's")
	Growth.focus_gain(cap, float(ranks[1]))
	assert_true(Growth.has_perk(cap, "dread_name"))
	assert_eq(Growth.check_bonus(cap, "intimidation"), 3)
	cap.focus = "purse"
	Growth.focus_gain(cap, 1.0)
	assert_eq(cap.focus_xp.blade, float(ranks[0] + ranks[1]), "another focus keeps what the first learned")
	cap.perk_picks = 1
	assert_false(Growth.perks_open(cap).any(func(p): return Data.table("perks")[p].has("focus")), "focus perks aren't chosen at a level-up")


func test_focus_perks_reach_the_world():
	var cap := ShipStats.captain(s)
	var spread := ShipStats.spread_mult(s)
	var wages := ShipStats.daily_cost(s, stats)
	var bribe := AtSea.bribe_cost(s, "spain")
	cap.perks = ["haggler", "paymaster", "open_palm"]
	assert_lt(ShipStats.spread_mult(s), spread)
	assert_lt(ShipStats.daily_cost(s, stats), wages)
	assert_lt(AtSea.bribe_cost(s, "spain"), bribe)
	assert_lt(Politics.bribe_cost(s), int(Data.table("politics").council.bribe))
