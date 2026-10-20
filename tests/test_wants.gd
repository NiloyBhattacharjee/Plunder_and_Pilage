extends GutTest
## Wants and assets: what your people want, and what only they have.

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 7
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	for id in s.crew:  # no one aboard knows anyone yet, unless a test says so
		People.person(id).asset = {}


func after_each():
	Clock.day = 0.0


## A hand aboard with this want (and no asset unless given).
func hand(want: String, traits := [], asset := {}) -> Dictionary:
	var c := People.generate({})
	c.traits = traits
	c.asset = asset
	People.add(c)
	s.crew.append(c.id)
	Wants.ensure(c, rng)
	c.want.id = want
	c.want.port = "port_royal"
	return c


func test_officers_start_with_a_story():
	for id in s.officers.values():
		assert_true(People.person(id).has("want"), "every officer wants something")
	var c := People.generate({})
	c.traits = ["family_man"]
	Wants.ensure(c, rng)
	assert_eq(c.want.id, "family", "and it grows out of who they are")
	assert_string_contains(People.describe(c), "Wants:")


func test_help_them_and_they_are_yours():
	var c := hand("family")
	var ctx := {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "port_royal", "storm": false}
	var inst := Events.instance_of("want_family", ctx)
	assert_false(inst.is_empty(), "their family's town brings it up")
	assert_eq(inst.vars.who, c.id)
	ctx.port = "havana"
	assert_true(Events.instance_of("want_family", ctx).is_empty(), "but not anywhere else")
	Events.apply_outcome("want %s done" % c.id, ctx)
	assert_eq(c.want.status, "done")
	assert_true("loyal" in c.traits)
	assert_gt(c.relations.get(s.captain, 0), 0)


func test_let_it_lapse_and_they_remember():
	var c := hand("home")
	Clock.day = c.want.due + 1.0
	Wants.daily(s, rng)
	assert_eq(c.want.status, "ignored")
	assert_lt(c.relations.get(s.captain, 0), 0)
	var a := hand("own_ship")
	a.want.status = "open"
	Clock.day = a.want.due + 1.0
	Wants.daily(s, rng)
	assert_false(a.id in s.crew, "an ambitious one goes to find a ship elsewhere")


func test_battles_and_commands_fulfil_wants():
	var c := hand("glory")
	Wants.on_battle(s, {"kind": "merchant"}, "enemy_struck")
	assert_eq(c.want.status, "open", "a merchant is no warship")
	Wants.on_battle(s, {"kind": "navy"}, "enemy_struck")
	assert_eq(c.want.status, "done")
	var b := hand("own_ship")
	s.prizes.append(Fleet.ensure({"type": "sloop", "name": "Dream", "faction": "spain", "hull": 60.0, "sails": 40.0}))
	assert_string_contains(Fleet.appoint(s, s.prizes.size() - 1, b.id), "won't forget")
	assert_eq(b.want.status, "done")


func test_what_they_know_goes_with_them():
	assert_eq(Wants.customs_mult(s, "havana"), 1.0)
	var c := hand("home", [], {"id": "customs", "port": "havana", "used": false})
	assert_lt(Wants.customs_mult(s, "havana"), 1.0, "kin in the customs house")
	var price := Career.price_mult(s, "havana")
	c.asset = {"id": "price", "port": "havana", "used": false}
	assert_lt(Career.price_mult(s, "havana"), price, "an old friend in trade")
	Crew.remove_hand(s, c.id)
	assert_eq(Career.price_mult(s, "havana"), price, "gone with them")
	var p := hand("home", [], {"id": "cove", "cove": "roatan", "used": false})
	Bases.discovered.erase("roatan")
	assert_string_contains(Wants.show_cove(p), "Roatán" if Bases.cove("roatan").name == "Roatán" else Bases.cove("roatan").name)
	assert_true("roatan" in Bases.discovered)
	assert_eq(Wants.show_cove(p), "", "once")


func test_they_speak_up_and_remember():
	assert_eq(Voices.infer(["kill {x}", "fear +3", "gold -300"]), {"cruel": 3, "greedy": -1})
	var c := hand("home", ["bloodthirsty"])
	var opts := [{"text": "Put them to the sword", "voice": {"cruel": 2}}, {"text": "Let them go", "voice": {"cruel": -1}}]
	var said := Voices.dress(s, "", opts)
	var mine: Array = said.voices.filter(func(v): return v.id == c.id)
	assert_eq(mine.size(), 1, "a bloodthirsty hand has something to say")
	assert_eq(mine[0].index, 0)
	assert_string_contains(said.text, c.name)
	var before: int = c.relations.get(s.captain, 0)
	Voices.heard(s, said.voices, 1)
	assert_lt(c.relations.get(s.captain, 0), before, "overruled, and they remember")


func test_events_hear_them_too():
	var debtor := hand("debt")
	var honest := hand("home", ["honest"])
	for id in s.crew:  # the rest keep their counsel
		if id != honest.id:
			People.person(id).traits = []
	var ctx := {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "port_royal", "storm": false}
	var inst := Events.instance_of("want_debt", ctx)
	var v := Events.view(inst, ctx)
	assert_true(inst.voices.any(func(x): return x.id == honest.id and not x["for"]), "the honest one speaks against handing them over")
	assert_false(inst.voices.any(func(x): return x.id == debtor.id), "not the one it's about")
	assert_string_contains(v.text, honest.name)
	var before: int = honest.relations.get(s.captain, 0)
	Events.resolve(inst, 3, ctx)
	assert_lt(honest.relations.get(s.captain, 0), before)
	assert_false(debtor.id in s.crew)


func test_partings_cost_something():
	var a := hand("home")
	var b := hand("home")
	b.relations[a.id] = 60
	var regard := PortLife.regard(a.home)
	var before: int = b.relations.get(s.captain, 0)
	Wants.part(s, a.id, "hanged")
	assert_false(a.id in s.crew)
	assert_lt(b.relations.get(s.captain, 0), before, "their friend won't forgive it")
	assert_lt(PortLife.regard(a.home), regard, "and their home town hears of it")
	var p: Dictionary = Wants.table()._parting.dismissed
	var chance: float = p.rival
	p.rival = 1.0
	var r := hand("home")
	r.relations[s.captain] = -10
	Wants.part(s, r.id, "dismissed")
	p.rival = chance
	assert_true(r.id in Bonds.captains, "back with a ship of their own")
	assert_eq(Wants.knows_you({"captain_id": r.id}), r.name, "and they know yours")


func test_a_friend_finishes_what_they_started():
	var a := hand("vow")
	var b := hand("home")
	b.want.status = "done"
	b.relations[a.id] = 60
	assert_string_contains(Crew.mourn(s, a.id), b.name)
	assert_eq(b.want.id, "vow")
	assert_eq(b.want.sworn, a.name)
	var c := hand("home")
	var d := hand("home")
	d.want.status = "done"
	d.relations[c.id] = 60
	var killer: String = Bonds.roster()[0]
	Crew.mourn(s, c.id, killer)
	assert_eq(d.want.id, "revenge")
	assert_eq(d.want.target, killer, "revenge on the captain who did it")


# ---- a captain's own want ---------------------------------------------------------------

func ctx() -> Dictionary:
	return {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "", "storm": false}


func test_titles_die_with_the_captain_and_the_new_one_chases_their_own_want():
	Ambitions.take(s, "scourge")
	Ambitions.ensure(s).titles.append("fortune")
	var c := hand("home")
	Crew.make_captain(s, c.id, "elected")
	var cap := Ambitions.ensure(s)
	assert_eq(cap.titles, [], "the old captain's titles went with them")
	assert_eq(s.captains[-1].titles, ["the Rich"], "the log keeps them")
	assert_eq(cap.ambition.id, "own_home", "not the old captain's ambition: their own")
	assert_string_contains(Ambitions.summary(s, ctx()), Ports.port("port_royal").name)
	assert_false("own_home" in Ambitions.offered(s, ctx()), "never offered, only brought aboard")
	assert_eq(Wants.captain_arrives(s, "havana"), "", "only in its port")
	assert_ne(Wants.captain_arrives(s, "port_royal"), "")
	assert_eq(Ambitions.check(s, ctx()).title, "the Wanderer")


func test_a_captains_debt_costs_what_it_costs():
	var c := hand("debt")
	Crew.make_captain(s, c.id, "elected")
	s.gold = 100
	assert_string_contains(Wants.captain_arrives(s, "port_royal"), "300")
	assert_true(Wants.open(ShipStats.captain(s)), "can't pay, still owed")
	s.gold = 400
	Wants.captain_arrives(s, "port_royal")
	assert_eq(s.gold, 100)
	assert_eq(Ambitions.check(s, ctx()).title, "the Square")


func test_a_captains_revenge_is_settled_in_battle():
	var foe := People.add(People.generate({}))
	var c := hand("revenge")
	c.want.target = foe
	Crew.make_captain(s, c.id, "elected")
	assert_string_contains(Ambitions.summary(s, ctx()), People.person(foe).name)
	Wants.on_battle(s, {"captain_id": foe}, "enemy_struck")
	assert_eq(Ambitions.check(s, ctx()).title, "the Avenger")


func test_one_who_wanted_a_ship_has_one():
	var c := hand("own_ship")
	Crew.make_captain(s, c.id, "elected")
	assert_eq(ShipStats.captain(s).want.status, "done")
	assert_true(ShipStats.captain(s).ambition.is_empty(), "free to choose what next")


func test_old_saves_move_ambition_and_titles_onto_the_captain():
	var cap := ShipStats.captain(s)
	cap.erase("ambition")
	cap.erase("titles")
	s.ambition = {"id": "fortune", "start": 0.0, "day": 0.0}
	s.titles = ["scourge"]
	Ambitions.ensure(s)
	assert_false(s.has("titles"))
	assert_eq(cap.titles, ["scourge"])
	assert_eq(cap.ambition.id, "fortune")
