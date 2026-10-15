extends GutTest

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	rng.seed = 5
	Clock.day = 0.0
	Ports.reset()
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state  # resets Factions to 1680 too


func after_each():
	Clock.day = 0.0
	Factions.reset()


func test_history_drives_war_and_peace():
	assert_true(Factions.at_war("france", "spain"), "no peace beyond the line in 1680")
	assert_false(Factions.at_war("england", "spain"))
	assert_true(Factions.at_war("england", "pirates"))
	Clock.day = 365.0 * 10  # 1690: the Nine Years' War
	Factions.apply_history(true)
	assert_false(Factions.at_war("france", "spain") and not Factions.at_war("england", "france"))
	assert_true(Factions.at_war("england", "france"))
	assert_true(Factions.at_war("spain", "france"))


func test_kings_pardon_opens_and_closes():
	Clock.day = (Time.get_unix_time_from_datetime_string("1718-01-01") - Time.get_unix_time_from_datetime_string("1680-01-01")) / 86400.0
	Factions.apply_history(true)
	assert_true("england" in Factions.pardons)
	Clock.day += 300
	Factions.apply_history(true)
	assert_false("england" in Factions.pardons)


func test_marque_needs_standing_and_a_war():
	assert_ne(Career.marque_problem(s, "england"), "", "England is at peace in 1680")
	s.relations.france = 20
	assert_eq(Career.marque_problem(s, "france"), "")
	s.relations.france = 0
	assert_ne(Career.marque_problem(s, "france"), "")


func test_lawful_raid_versus_piracy():
	s.relations.france = 20
	Career.grant_marque(s, "france")
	var spanish := Encounters.generate("spain", rng, "merchant")
	Career.on_attack(s, spanish)
	assert_true(spanish.legal)
	assert_false(s.career.pirate)
	assert_gt(s.relations.france, 20)
	var dutch := Encounters.generate("dutch", rng, "merchant")
	Career.on_attack(s, dutch)
	assert_false(dutch.legal)
	assert_true(s.career.pirate)
	assert_eq(s.career.marque, "", "abusing the commission costs you it")
	assert_gt(s.reputation.notoriety, 0)


func test_hunting_pirates_is_always_lawful():
	var before: int = s.relations.spain
	var pirate := Encounters.generate("pirates", rng, "pirate")
	Career.on_attack(s, pirate)
	assert_true(pirate.legal)
	assert_false(s.career.pirate)
	assert_gt(s.relations.spain, before)


func test_prizes_owe_the_crown_and_earn_rank():
	s.relations.france = 20
	Career.grant_marque(s, "france")
	var msgs := Career.record_prize(s, 2000.0)
	assert_almost_eq(s.career.crown_debt, 2000.0 * Data.rules.career.crown_cut, 0.01)
	assert_eq(s.career.rank, 1)
	assert_true(msgs.any(func(m): return "makes you" in m))
	s.gold = 10000.0
	Career.pay_crown(s)
	assert_eq(s.career.crown_debt, 0.0)


func test_peace_voids_the_letter():
	s.relations.france = 20
	Career.grant_marque(s, "france")
	Clock.day = 365.0 * 5  # 1685: after the Truce of Ratisbon
	Factions.apply_history(true)
	assert_ne(Career.check_peace(s), "")
	assert_eq(s.career.marque, "")


func test_pardon_forgives_but_others_remember():
	s.career.pirate = true
	s.reputation.notoriety = 20
	s.relations.england = -30
	s.relations.spain = -40
	s.gold = 10000.0
	assert_eq(Career.pardon_problem(s, "england"), "")
	Career.pardon(s, "england")
	assert_false(s.career.pirate)
	assert_eq(s.relations.england, 0)
	assert_eq(s.relations.spain, -40)
	assert_lt(s.reputation.notoriety, 20)


func test_wanted_pirates_find_lawful_ports_closed_but_havens_open():
	s.career.pirate = true
	s.reputation.notoriety = 40
	assert_false(Career.port_access(s, "havana").open)
	assert_true(Career.port_access(s, "nassau").open)
	assert_true(Career.port_access(s, "tortuga").open, "Tortuga has a fence and asks no questions")


func test_false_colours_and_standing_prices():
	s.flag = "spain"
	assert_true(Career.false_colours(s))
	assert_true(Career.flag_fools_port(s, "port_royal"))
	s.flag = "black"
	assert_false(Career.flag_fools_port(s, "port_royal"))
	s.relations.england = 50
	assert_lt(Career.price_mult(s, "port_royal"), 1.0)
	s.relations.england = -50
	assert_gt(Career.price_mult(s, "port_royal"), 1.0)


func test_navies_judge_you_by_your_colours():
	var spanish_navy := Encounters.generate("spain", rng, "navy")
	s.flag = "england"
	assert_false(Career.npc_hostile(s, spanish_navy, rng))
	s.flag = "france"  # France is at war with Spain in 1680
	assert_true(Career.npc_hostile(s, spanish_navy, rng))
	s.flag = "black"
	assert_true(Career.npc_hostile(s, spanish_navy, rng))
