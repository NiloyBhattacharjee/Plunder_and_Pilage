extends GutTest
## The Maroons: hidden landings learnt from people, trade, raids on the estates and the militia, alliances, betrayal.

var s: Dictionary
const LANDING := "manchioneal"


func before_each():
	Clock.day = 0.0
	Maroons.rng.seed = 4
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func after_each():
	Clock.day = 0.0
	Maroons.reset()
	Events.flags.erase("freed_aboard")


func ctx(base := "", port := "") -> Dictionary:
	return {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": port, "storm": false, "base": base}


func test_a_people_not_a_nation_and_a_landing_not_a_cove():
	assert_false("maroons" in Career.nations(), "no wars, commissions or ships")
	assert_true(s.relations.has("maroons"))
	assert_false(LANDING in Bases.hidden(), "never spotted by sailing past")
	assert_string_contains(Bases.claim_problem(s, LANDING), "isn't yours")
	assert_eq(Bonds.kind("f:maroons"), "maroons")
	assert_eq(Bonds.enemies_of("f:maroons").size(), Maroons.colonies().size())


func test_people_tell_you_where_they_trade():
	var res := {}
	Events._apply("maroons reveal port_royal", ctx(), {}, res)
	assert_true(LANDING in Bases.discovered)
	assert_gt(float(Events.value("maroons", ctx("", "port_royal"))), 0.0, "known, above the port you're in")
	assert_gt(float(Events.value("maroons", ctx(LANDING))), 0.0, "anchored at the landing")


func test_trading_powder_arms_them_and_pays_in_hides_and_food():
	s.cargo.gunpowder = 20
	var o: Dictionary = Maroons.offers(s, LANDING).filter(func(x): return x.good == "gunpowder")[0]
	assert_gt(o.hides, 0)
	Maroons.trade(s, LANDING, o)
	assert_eq(int(s.cargo.gunpowder), 20 - int(o.qty))
	assert_gt(int(s.cargo.hides), 0)
	assert_gt(Maroons.bands[LANDING].armed, 0.0)
	assert_gt(s.relations.maroons, 0)
	s.relations.maroons = -50
	assert_ne(Maroons.trade_problem(s, LANDING), "", "no trade with a ship they don't trust")


func test_strong_bands_raid_the_estates_and_the_militia_comes():
	Maroons.bands[LANDING].strength = 100.0
	Maroons.bands[LANDING].armed = 40.0
	var raided := false
	for i in 24:
		Maroons.monthly()
		raided = raided or Economy.mods("port_royal").any(func(x): return x.reason == "Maroon raids on the estates")
	assert_true(raided, "the planters' crops fall")
	assert_lt(Maroons.bands[LANDING].strength, 100.0 + 24 * 0.6, "the militia went in at least once")


func test_selling_their_paths_burns_their_town_and_your_crew_remember():
	var before: int = People.person(s.crew[0]).relations.get(s.captain, 0)
	Maroons.betray(s, LANDING)
	assert_eq(s.relations.maroons, -100)
	assert_lt(People.person(s.crew[0]).relations.get(s.captain, 0), before)
	Maroons.monthly()
	assert_true(Maroons.burned(LANDING), "the militia had a guide")
	assert_string_contains(Maroons.trade_problem(s, LANDING), "burned")


func test_allies_raid_with_you_and_the_sworn_fight_beside_you():
	assert_ne(Maroons.raid_problem(s, LANDING), "")
	s.bonds = {"f:maroons": {"type": "alliance", "level": 4, "since": "", "strain": 0, "history": []}}
	assert_eq(Maroons.raid_problem(s, LANDING), "")
	var gold: float = s.gold
	Maroons.raid(s, LANDING)
	assert_gt(s.gold, gold)
	assert_ne(Maroons.raid_problem(s, LANDING), "", "not again so soon")
	assert_ne(Maroons.sworn_near(s, "port_royal"), "")
	assert_eq(Maroons.sworn_near(s, "havana"), "")


func test_people_you_carried_go_up_to_the_hills():
	Events.flags["freed_aboard"] = -1
	var strength: float = Maroons.bands[LANDING].strength
	Maroons.land_freed(s, LANDING)
	assert_false(Events.flags.has("freed_aboard"))
	assert_gt(Maroons.bands[LANDING].strength, strength)


func test_bands_survive_save_and_load():
	Maroons.bands[LANDING].strength = 77.0
	Maroons.bands[LANDING].burned = 12
	var d: Dictionary = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(Maroons.save_state()))))
	Maroons.reset()
	Maroons.load_state(d)
	assert_eq(Maroons.bands[LANDING].strength, 77.0)
	assert_eq(Maroons.bands[LANDING].burned, 12)
