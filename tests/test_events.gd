extends GutTest

var s: Dictionary
var stats: Dictionary


func before_each():
	Clock.day = 0.0
	Events.reset()
	Events.rng.seed = 3
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	stats = ShipStats.effective(s.type, s.upgrades)


func after_each():
	Clock.day = 0.0
	Factions.reset()


func ctx(port := "") -> Dictionary:
	return {"s": s, "stats": stats, "port": port, "storm": false}


## A crew with every trait somewhere aboard, a full hold, and something for every kind of event to bite on.
func rich_state(kind: String) -> void:
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	stats = ShipStats.effective(s.type, s.upgrades)
	var traits: Array = Data.table("traits").keys().filter(func(t): return "crew" in Data.table("traits")[t].pools)
	for i in traits.size():
		var c := People.generate({})
		c.traits = [traits[i]]
		c.relations[s.captain] = -20 if i % 2 == 0 else 20
		s.crew.append(People.add(c))
	var free: Array = s.crew.filter(func(id): return not id in s.officers.values())
	for post in Data.rules.officer_roles:  # every post filled, so officer events can always bind
		if not s.officers.has(post):
			s.officers[post] = free.pop_back()
	for id in s.officers.values():
		People.person(id).stats.intimidation = 12
	s.unrest = {"leader": s.crew[0], "support": [s.crew[0]], "stage": 2, "known": true}
	var enemy := Politics.official("havana", "governor")  # someone who hates you, and someone you owe
	People.person(enemy).relations[s.captain] = -60
	Politics.add_favours(Politics.official("port_royal", "merchant"), s, -1)
	Politics.council_members()
	s.council_member = true
	var r := Bonds.roster()  # an ally, a rival, and a captain who likes you
	s.bonds = {r[0]: {"type": "alliance", "level": 3, "since": "", "strain": 0, "history": []},
		r[1]: {"type": "rivalry", "level": 2, "since": "", "strain": 0, "history": []}}
	People.person(r[2]).relations[s.captain] = 40
	People.person(r[1]).relations[s.captain] = -30
	Bases.reset()  # a base with a bit of everything, and a manager who doesn't like you
	Bases.discovered = ["vieques"]
	s.gold = 5000.0
	Bases.claim(s, "vieques")
	var base: Dictionary = Bases.bases.vieques
	base.buildings = ["dock", "plantation"]
	base.loyalty = 30.0
	base.visibility = 40.0
	base.garrison = 10
	base.manager = s.crew[5]
	People.person(base.manager).relations[s.captain] = -40
	for i in 30:  # and a town you hold, heavily taxed, loyal enough, thinly garrisoned
		s.crew.append(People.add(People.generate({})))
	Bases.hold_town(s, "maracaibo", 15)
	Bases.bases.maracaibo.taxes = "heavy"
	Bases.bases.maracaibo.loyalty = 60.0
	base.manager = s.crew[5]  # the garrison came off the crew: make sure the manager is still someone
	People.person(base.manager).relations[s.captain] = -40
	People.person(s.crew[6]).traits = ["greedy"]
	s.relations.spain = -30
	s.bounty = {"spain": 2000.0}
	s.gold = 2000.0
	var trait_holder: String = s.officers.values()[0]
	People.person(trait_holder).traits = ["ambitious"]
	s.secrets = []
	s.gold = 2000.0
	s.cargo.rum = 20.0
	s.cargo.gunpowder = 20.0
	s.cargo.naval_stores = 5.0
	s.cargo.silver = 5.0
	var wants := ["debt", "family", "home", "vow"]
	for i in wants.size():  # someone whose want comes due in port, at Port Royal
		People.person(s.crew[10 + i]).want = {"id": wants[i], "port": "port_royal", "due": 9999.0, "status": "open"}
	s.stolen = {"silver": 5.0}
	s.wages_owed = 50.0
	s.reputation = {"honour": 10, "fear": 30, "notoriety": 40}
	match kind:
		"pirate":
			s.career.pirate = true
			s.relations.pirates = 30
		"privateer":
			Factions.wars = [["england", "spain"]]
			s.career.marque = "england"
			s.relations.england = 30


func test_all_events_are_valid():
	assert_eq(Events.errors.size(), 0, "\n".join(Events.errors))
	assert_gt(Events.events.size(), 20)


## Every choice of every event, for an honest captain, a pirate and a privateer, at sea and in port.
## Conditions are skipped (they're tested elsewhere): this only proves the outcomes all work.
func test_every_choice_of_every_event_resolves():
	var seen := {}
	for kind in ["honest", "pirate", "privateer"]:
		for port in ["", "port_royal", "nassau"]:
			for id in Events.events:
				var ev: Dictionary = Events.events[id]
				if not Events._fits(ev, "port" if port != "" else "sea") and not (port == "" and Events._fits(ev, "find")):
					continue
				for i in ev.choices.size():
					rich_state(kind)
					if port != "" and PortLife.captain_here(port) == "":  # a named captain in the tavern, for the events about them
						PortLife.start(port, "captains_drinking", Events.rng)
					var c := ctx(port)
					var vars := {}
					var ok := true
					for name in ev.get("roles", {}):
						var v = Events._bind(ev.roles[name], c, vars)
						if v == null:
							ok = false
							break
						vars[name] = v
					if not ok:
						continue
					var inst := Events._materialize({"id": id, "vars": vars}, c)
					var v := Events.view(inst, c)
					assert_eq(v.options.size(), ev.choices.size())
					assert_false(v.text.contains("{"), "%s: unfilled text: %s" % [id, v.text])
					var res := Events.resolve(inst, i, c)
					assert_true(res.has("effects"))
					seen[id] = true
	var missed := Events.events.keys().filter(func(id): return not seen.has(id))
	assert_eq(missed, [], "events whose roles never bound in any test state")


func test_validator_catches_mistakes():
	Events.events["_bad"] = {"id": "_bad", "title": "T", "text": "Hello {nobody}", "roles": {"x": {"from": "nowhere"}},
		"choices": [{"text": "a", "conditions": ["gold >= wages_owed", "moon == full"],
			"outcomes": ["gold", "fly away", "event no_such_event", "cargo unobtainium 5", "trait captain winged"]}]}
	var errs := "
".join(Events.validate())
	Events.events.erase("_bad")
	for want in ["unknown {nobody}", "unknown source", "compares a number", "unknown condition key 'moon'", "wrong number of arguments",
			"unknown outcome 'fly away'", "unknown event 'no_such_event'", "unknown good", "unknown trait"]:
		assert_string_contains(errs, want)


func test_conditions_gate_events():
	s.cargo.water = 1000.0
	var inst := Events._instance(Events.events.rain_squall_water, ctx(), {})
	assert_true(inst.is_empty(), "no rain event with full water casks")
	s.cargo.water = 0.0
	assert_false(Events._instance(Events.events.rain_squall_water, ctx(), {}).is_empty())


func test_greyed_out_choices_say_why():
	rich_state("honest")
	var inst := Events._materialize(Events._instance(Events.events.drifting_longboat, ctx(), {}), ctx())
	var v := Events.view(inst, ctx())
	var ransom: Dictionary = v.options[2]
	assert_true(ransom.disabled, "only pirates hold castaways for ransom")
	assert_string_contains(ransom.tooltip, "Requires")


func test_chains_wait_for_their_moment():
	var inst := Events._instance(Events.events.message_in_bottle, ctx(), {})
	var target: String = inst.vars.port
	Events.resolve(inst, 0, ctx())
	assert_eq(Events.queue.size(), 1)
	var other: String = "nassau" if target != "nassau" else "port_royal"
	Events.rng.seed = 1
	var elsewhere := Events.pick("port", ctx(other))
	assert_ne(elsewhere.get("id", ""), "treasure_twin_palms")
	var there := Events.pick("port", ctx(target))
	assert_eq(there.id, "treasure_twin_palms")
	assert_eq(there.vars.port, target)


func test_once_and_cooldown():
	var ev: Dictionary = Events.events.waterspout
	assert_true(Events._eligible(ev, "sea"))
	Events.fired.waterspout = Clock.day
	assert_false(Events._eligible(ev, "sea"))
	Clock.day += Data.rules.events.cooldown_days + 1
	assert_true(Events._eligible(ev, "sea"))


func test_events_survive_save_and_load():
	Events.flags.met_morgan = -1.0
	Events.queue.append({"id": "whale", "at": 5.0, "until": 50.0, "vars": {}})
	var d := Events.save_state()
	Events.reset()
	Events.load_state(JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(d)))))
	assert_true(Events.flags.has("met_morgan"))
	assert_eq(Events.queue[0].id, "whale")


func test_finds_wait_on_the_map_not_in_the_daily_roll():
	assert_false(Events._eligible(Events.events.whale, "sea"), "whales are found, not rolled")
	assert_true(Events._eligible(Events.events.whale, "find"))
	assert_false(Events._eligible(Events.events.waterspout, "find"))
	var inst := Events.pick_find(ctx(""))
	assert_true(Events.events[inst.id].has("find"))
	assert_true(Events.pick_find(ctx(""), Events.events.keys()).is_empty(), "never one already out there")


func test_a_story_runs_from_hook_to_ending():
	Events.flags["sacked_havana"] = -1.0
	s.gold = 1000.0
	var hook := Events._materialize(Events._instance(Events.events.brother_knife, ctx("havana"), {}), ctx("havana"))
	assert_false(hook.is_empty())
	assert_string_contains(Events.view(hook, ctx("havana")).title, "A Brother's Knife")
	Events.resolve(hook, 2, ctx("havana"))  # the purse, thrown back
	assert_true(Events.is_open("brother"))
	assert_false(Events._eligible(Events.events.brother_knife, "port"), "a story is told once")
	Clock.day += 16
	var bills := Events.pick("port", ctx("port_royal"))
	assert_eq(bills.id, "brother_handbills")
	Events.resolve(bills, 1, ctx("port_royal"))  # meet at dawn
	assert_true(Events.pick("port", ctx("port_royal")).get("id", "") != "brother_dawn", "only on the beach below the town")
	var dawn := Events.pick("port", ctx("havana"))
	assert_eq(dawn.id, "brother_dawn")
	var res := Events.resolve(dawn, 2, ctx("havana"))
	assert_false(Events.is_open("brother"))
	assert_eq(Events.stories.brother.ending, "murdered")
	assert_eq(Events.stories.brother.entries.size(), 4, "three acts and the ending")
	assert_true(res.effects.any(func(e): return e.contains("Settled with grape")))


func test_a_battle_decides_the_next_act():
	var inst := Events._materialize(Events._instance(Events.events.brother_hunter, ctx(), {"town": "havana"}), ctx())
	var res := Events.resolve(inst, 0, ctx())
	assert_false(res.fight.is_empty())
	assert_true(People.chars.has(inst.vars.avenger), "kept for the next act while the battle is fought")
	Events.after_battle(false)
	assert_eq(Events.queue[-1].id, "brother_avenged")
	assert_true(Events.after_fight.is_empty())


func test_stories_go_cold_and_have_a_limit():
	var inst := Events._materialize(Events._instance(Events.events.pardon_hunt, ctx(), {}), ctx())
	Events.stories.pardon = {"act": 2, "began": "", "entries": [], "ended": -1.0, "ending": ""}
	Events.queue.append({"id": "pardon_hunt", "at": 0.0, "until": 5.0, "vars": inst.vars})
	Clock.day = 10.0
	Events.pick("sea", ctx())
	assert_eq(Events.stories.pardon.ending, "cold", "the trail ran out")
	for sid in ["brother", "silver", "castaway"]:
		Events.stories[sid] = {"act": 1, "began": "", "entries": [], "ended": -1.0, "ending": ""}
	assert_false(Events._story_ok(Events.events.want_debt), "no new story while three are open")
	assert_false(Events._story_ok(Events.events.dying_pirate), "nor its hook again while it runs")
	Events.end_story("silver", "found")
	assert_true(Events._story_ok(Events.events.want_debt), "room for one more")
	assert_false(Events._story_ok(Events.events.dying_pirate), "but never the same story twice")
	assert_false(Events._story_ok(Events.events.pardon_old_friends), "one that went cold was told")
	Events.stories.debt = {"act": 3, "began": "", "entries": [], "ended": 1.0, "ending": "paid"}
	assert_true(Events._story_ok(Events.events.want_debt), "the debt story can be told again")


func test_validator_catches_a_story_left_hanging():
	Events.events["_bad"] = {"id": "_bad", "title": "T", "text": "x", "story": "brother", "act": 9,
		"choices": [{"text": "a", "outcomes": ["gold +1"]}, {"text": "b", "outcomes": ["ending brother nope"]}]}
	var errs := "\n".join(Events.validate())
	Events.events.erase("_bad")
	for want in ["has no act 9", "leaves the story hanging", "unknown ending"]:
		assert_string_contains(errs, want)
