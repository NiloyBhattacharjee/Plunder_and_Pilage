extends GutTest
## Taking towns: the siege, the assault, and what comes after (sack, ransom, hold, and the expeditions to retake it).

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 7
	Bases.rng.seed = 7
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	s.gold = 5000.0
	for i in 80:
		s.crew.append(People.add(People.generate({})))


func after_each():
	Clock.day = 0.0


func siege(id := "maracaibo") -> Dictionary:
	return Sieges.begin(s, id, rng).g


func test_defences_follow_the_town():
	var small := Sieges.defences("basseterre")
	var big := Sieges.defences("cartagena")
	assert_gt(big.garrison, small.garrison * 3, "a large garrison town")
	assert_gt(big.fort, small.fort)
	assert_lt(Sieges.defences("tortuga").garrison, Sieges.cfg().size.small.garrison, "a pirate haven keeps fewer soldiers")


func test_capitals_need_a_squadron():
	assert_string_contains(Sieges.problem(s, "havana"), "squadron")
	assert_eq(Sieges.problem(s, "maracaibo"), "")


func test_laying_siege_is_an_act_of_war():
	var before: int = s.relations.get("spain", 0)
	siege()
	assert_lt(s.relations.spain, before)
	assert_true(s.career.pirate, "no commission against Spain: it's piracy")


func test_the_odds_answer_to_men_fort_and_scouting():
	var g := siege()
	var odds := func(men, side): return Dice.sum_parts(Sieges.assault_parts(s, g, men, side))
	assert_gt(odds.call(80, 1), odds.call(20, 1), "more men")
	var harbour: int = odds.call(50, 0)
	g.fort = 0.0
	assert_gt(odds.call(50, 0), harbour, "a silenced fort")
	assert_eq(odds.call(50, g.weak) - odds.call(50, (g.weak + 1) % 3), int(Sieges.cfg().weak_bonus), "the weak side")


func test_starving_and_relief():
	var g := siege()
	g.supplies = 2.0
	g.relief = Clock.day + 100
	var men: int = g.garrison
	var r := Sieges.pass_days(g, 3)
	assert_true(g.starving)
	assert_lt(g.garrison, men)
	assert_false(r.relief)
	g.relief = Clock.day + 1
	assert_true(Sieges.pass_days(g, 5).relief, "the relief squadron interrupts the blockade")


func test_bombarding_silences_the_fort_and_costs_hull():
	var g := siege()
	var stats := {"guns": 200}
	var hull: float = s.hull
	for i in 10:
		Sieges.bombard(s, stats, g, rng)
	assert_lt(g.fort, 100.0)
	assert_lt(s.hull, hull)


func test_an_assault_costs_men():
	var g := siege()
	var crew: int = s.crew.size()
	Sieges.assault(s, g, 50, 1, rng)
	assert_lt(s.crew.size(), crew)


func test_a_sack_pays_and_is_remembered():
	var gold: float = s.gold
	var text := Sieges.sack(s, "maracaibo")
	assert_gt(s.gold, gold)
	assert_lt(s.relations.spain, -30)
	assert_lt(s.reputation.honour, 0)
	assert_lt(Bonds.level(s, Politics.official("maracaibo", "governor")), 0, "the governor never forgets")
	assert_string_contains(text, "sack")


func test_a_ransom_pays_less_and_hurts_less():
	assert_lt(Sieges.ransom_gold("maracaibo"), Sieges.sack_gold("maracaibo"))
	Sieges.ransom(s, "maracaibo")
	assert_gt(s.relations.spain, -30)


func test_a_held_town_is_a_base_that_pays_and_is_fought_over():
	Sieges.hold(s, "maracaibo")
	var b: Dictionary = Bases.bases.maracaibo
	assert_true(b.has("town"))
	assert_eq(b.garrison, Sieges.garrison_needed("maracaibo"))
	assert_true(Bases.has(b, "battery"))
	assert_true(Career.port_access(s, "maracaibo").open, "your own harbour")
	assert_eq(b.raid.kind, "expedition")
	assert_eq(Bases.cove("maracaibo").name, "Maracaibo")
	var gold: float = b.gold
	b.raid.day = 1000.0
	Bases.daily(s, "")
	assert_gt(b.gold, gold, "taxes")
	b.raid.day = 0.0
	b.garrison = 1
	Bases.daily(s, "")
	assert_false(Bases.bases.has("maracaibo"), "the expedition takes it back")


func test_leading_the_council_hands_you_nassau():
	s.reputation.notoriety = 100
	Politics.council_members()
	for i in 20:
		if Politics.council_leader == "player":
			break
		Politics.challenge(s)
	assert_eq(Politics.council_leader, "player")
	assert_true(Bases.bases.has("nassau"))
	assert_eq(Bases.bases.nassau.town.from, "england")


func test_a_held_town_is_yours_to_run():
	var gov := Politics.official("maracaibo", "governor")
	Sieges.hold(s, "maracaibo")
	assert_eq(Economy.duty("maracaibo", "sugar"), 0.0, "no duty in your own town")
	assert_true(Ports.state.maracaibo.laws.contraband.is_empty(), "your laws")
	assert_eq(People.person(gov).role, "former_governor")
	assert_lt(Bonds.level(s, gov), 0, "the governor you turned out remembers")
	assert_eq(Politics.official("maracaibo", "governor"), "", "nobody governs until you appoint a manager")
	var who: String = s.crew[0]
	Bases.appoint(s, "maracaibo", who)
	assert_eq(Politics.official("maracaibo", "governor"), who)
	Politics.monthly()
	assert_true(Ports.state.maracaibo.laws.contraband.is_empty(), "the old interest groups don't rewrite your laws")
	Bases.lose("maracaibo")
	assert_false(Ports.state.maracaibo.laws.contraband.is_empty(), "the old laws come back with the old flag")
	assert_ne(Politics.official("maracaibo", "governor"), who, "and a new governor")


func test_taxes_trade_gold_for_goodwill():
	Sieges.hold(s, "maracaibo")
	var b: Dictionary = Bases.bases.maracaibo
	var fair := Bases.tax_income("maracaibo")
	var calm: float = Bases.loyalty_parts("maracaibo").reduce(func(a, p): return a + p[1], 0.0)
	Bases.set_taxes("maracaibo", "heavy")
	assert_gt(Bases.tax_income("maracaibo"), fair)
	assert_lt(Bases.loyalty_parts("maracaibo").reduce(func(a, p): return a + p[1], 0.0), calm)
	b.loyalty = 0.0
	b.garrison = 1
	for i in 30:
		if not Bases.bases.has("maracaibo"):
			break
		Bases.rebellion(s, "maracaibo")
	assert_false(Bases.bases.has("maracaibo"), "a town that hates you rises and throws you out")


func test_expeditions_grow_and_can_be_caught_at_sea():
	Sieges.hold(s, "maracaibo")
	var first := Bases.expedition_strength("maracaibo")
	var text := Bases.expedition_beaten("maracaibo")
	assert_string_contains(text, "broken at sea")
	assert_gt(Bases.expedition_strength("maracaibo"), first)
	assert_gt(Bases.bases.maracaibo.raid.day, Clock.day)


func test_a_lifted_siege_is_remembered():
	var g := siege()
	g.fort = 10.0
	Sieges.remember(s, g)
	Clock.advance(5)
	var back := Sieges.resume(s, "maracaibo", rng)
	assert_false(back.is_empty())
	assert_almost_eq(back.g.fort, 10.0 + 5 * Sieges.cfg().fort_repair_per_day, 0.01, "patched, not rebuilt")
	Sieges.ransom(s, "maracaibo")
	assert_true(Sieges.resume(s, "maracaibo", rng).is_empty(), "a town taken is a siege over")


func test_consorts_land_and_bleed_too():
	var cap := People.add(People.generate({}))
	var p := Fleet.ensure({"type": "brig", "name": "Consort", "faction": "", "hull": 100.0, "sails": 100.0, "captain": cap})
	for i in 40:
		p.crew.append(People.add(People.generate({})))
	s.prizes = [p]
	assert_true(Fleet.is_consort(p))
	assert_eq(Sieges.landing(s), s.crew.size() - 10 + 40 - int(Sieges.cfg().ship_keepers))
	Sieges.casualties(s, Sieges.landing(s), 30, rng)
	assert_lt(p.crew.size(), 40, "her men died ashore too")
