extends GutTest
## Wars of the moment: tension, incidents, war, towns changing hands, and the peace.

var s: Dictionary


func before_each():
	Clock.day = 0.0
	Factions.rng.seed = 5
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	Factions.wars = []
	Factions.timed = []


func after_each():
	Clock.day = 0.0
	Data.rules.diplomacy.capture_chance = 0.06
	Data.rules.diplomacy.return_on_peace = 0.5
	Ports.reset()
	Factions.reset()


func test_incidents_bring_war_closer_and_war_comes():
	var before: float = Factions.tension["england|spain"]
	Factions.incident("england", "spain", 10)
	assert_eq(Factions.tension["england|spain"], minf(100.0, before + 10))
	Factions.incident("pirates", "spain", 50)  # nothing between a nation and the Brethren
	Factions.tension["england|spain"] = 100.0
	Factions.monthly()
	assert_true(Factions.at_war("england", "spain"))
	assert_string_contains(Factions.war_summary(), "England and Spain")


func test_a_privateers_raids_set_nations_against_each_other():
	s.career.marque = "england"
	Factions.declare("england", "spain", "")
	var before: float = Factions.tension["england|spain"]
	Career.on_attack(s, Encounters.generate("spain", RandomNumberGenerator.new(), "merchant"))
	assert_gt(Factions.tension["england|spain"], before)


func test_towns_change_hands_in_a_war_and_maybe_back_at_the_peace():
	Data.rules.diplomacy.capture_chance = 1.0
	Data.rules.diplomacy.return_on_peace = 1.0
	Factions.declare("england", "spain", "")
	Factions._campaign(["england", "spain"])
	assert_false(Factions.taken.is_empty())
	var t: Dictionary = Factions.taken.filter(func(x): return x.by == "england")[0]
	assert_eq(Ports.port(t.port).faction, "england", "the flag over the fort")
	assert_true(Ports.state[t.port].laws.has("enumerated"), "English laws now")
	var saved := Ports.save_state()
	Ports.reset()
	assert_eq(Ports.port(t.port).faction, "spain", "a new game starts from the map as it was")
	Ports.load_state(JSON.parse_string(JSON.stringify(saved)))
	assert_eq(Ports.port(t.port).faction, "england", "and a saved game keeps who holds what")
	Factions._make_peace(["england", "spain"])
	assert_eq(Ports.port(t.port).faction, "spain", "handed back by the treaty")
	assert_false(Factions.at_war("england", "spain"))
