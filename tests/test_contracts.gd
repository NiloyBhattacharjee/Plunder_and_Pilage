extends GutTest

const PATH := "user://saves/test_contracts.json"
var world
var s: Dictionary


func before_each():
	world = load("res://scenes/world_map.tscn").instantiate()
	add_child_autofree(world)
	await get_tree().process_frame
	world.port_screen.close()
	world.shipping.npcs = []
	s = world.ship.state
	Contracts.rng.seed = 5
	Factions.wars = [["england", "spain"]]


func after_each():
	Clock.day = 0.0
	Ports.reset()
	Factions.reset()


func gov(port := "port_royal") -> String:
	return Contracts.employer(port, "governor")


func job(tid: String, emp: String) -> Dictionary:
	var c := Contracts.make(tid, emp, s)
	c.lied = false
	c.trap = false
	return c


func test_employers_are_characters_and_brokers_keep_to_havens():
	assert_eq(Contracts.employer("nassau", "governor"), "", "the Brethren have no governor to hire you")
	assert_ne(Contracts.employer("nassau", "broker"), "")
	assert_eq(Contracts.employer("port_royal", "broker"), "")
	assert_eq(People.person(gov()).name, Ports.port("port_royal").governor)
	assert_eq(gov(), gov(), "the same governor every visit")
	assert_false(Contracts.offers_at("port_royal", s).is_empty())


func test_privateer_jobs_need_a_letter_of_marque():
	var c := job("raid_shipping", gov())
	assert_eq(c.target, "spain")
	assert_string_contains(Contracts.problem(c, s), "letter of marque")
	s.career.marque = "england"
	assert_eq(Contracts.problem(c, s), "")
	s.career.pirate = true
	assert_string_contains(Contracts.problem(c, s), "pirate")


func test_trust_unlocks_bigger_jobs():
	s.career.marque = "england"
	assert_eq(job("capture_ship", gov()).tier, 0)
	People.person(gov()).relations[s.captain] = 40
	assert_eq(job("capture_ship", gov()).tier, 1, "the best jobs aren't for neutrals")
	s.bonds = {gov(): {"type": "alliance", "level": 2, "since": "", "strain": 0, "history": []}}
	var big := job("capture_ship", gov())
	assert_eq(big.tier, 2)
	assert_eq(big.enemy.type, "galleon")


func test_taking_the_named_ship_pays_and_builds_trust():
	s.career.marque = "england"
	var c := job("capture_ship", gov())
	Contracts.accept(c, s)
	var npc: Dictionary = world.shipping.find(c.npc)
	assert_false(npc.is_empty(), "the target sails the map")
	assert_eq(npc.enemy.name, c.ship)
	assert_eq(npc.dest, c.dest)
	Contracts.on_battle(s, npc.enemy, "enemy_struck", npc.pos)
	assert_eq(c.status, "done")
	var gold: float = s.gold
	Contracts.collect(c, s)
	assert_eq(s.gold, gold + c.reward)
	assert_eq(Contracts.trust(gov(), s), 10)
	assert_true(Contracts.active.is_empty())


func test_sinking_a_ship_you_were_to_capture_fails():
	s.career.marque = "england"
	var c := job("capture_ship", gov())
	Contracts.accept(c, s)
	var before: int = s.relations.england
	Contracts.on_battle(s, world.shipping.find(c.npc).enemy, "enemy_sunk", Vector2.ZERO)
	assert_true(Contracts.active.is_empty())
	assert_lt(Contracts.trust(gov(), s), 0)
	assert_lt(s.relations.england, before)


func test_raids_count_target_ships_near_the_port():
	s.career.marque = "england"
	var c := job("raid_shipping", gov())
	Contracts.accept(c, s)
	var spaniard := {"faction": "spain"}
	Contracts.on_battle(s, spaniard, "enemy_struck", Vector2(-99999, -99999))
	assert_eq(c.progress, 0, "too far from the raiding ground")
	Contracts.on_battle(s, {"faction": "dutch"}, "enemy_struck", Contracts._pos(c.port))
	assert_eq(c.progress, 0, "wrong nation")
	Contracts.on_battle(s, spaniard, "separated", Contracts._pos(c.port))
	assert_eq(c.progress, 0)
	for i in c.count:
		Contracts.on_battle(s, spaniard, "enemy_sunk", Contracts._pos(c.port))
	assert_eq(c.status, "done")


func test_deadlines_and_lost_targets_fail():
	s.career.marque = "england"
	var c := job("raid_shipping", gov())
	Contracts.accept(c, s)
	Clock.day = c.deadline + 1.0
	assert_string_contains(" ".join(Contracts.daily(s)), "time ran out")
	Clock.day = 0.0
	var hunt := job("hunt_pirate", gov())
	s.relations.england = 20
	Contracts.accept(hunt, s)
	assert_true(world.shipping.find(hunt.npc).has("home"), "a pirate target lurks where she was reported")
	world.shipping.remove(world.shipping.find(hunt.npc))
	Contracts.daily(s)
	assert_true(Contracts.active.is_empty())


func test_smuggling_costs_a_deposit_and_customs_can_be_tipped_off():
	var broker := Contracts.employer("st_eustatius", "broker")
	var c := job("smuggle", broker)
	assert_true(c.good in Ports.state[c.dest].laws.contraband)
	s.gold = 5000.0
	var gold: float = s.gold
	assert_string_contains(Contracts.problem(c, s, 0.0), "free hold")
	Contracts.accept(c, s)
	assert_eq(s.gold, gold - c.deposit)
	assert_eq(s.cargo[c.good], float(c.qty))
	var honest := Contracts.seizure_risk(c)
	c.trap = true
	assert_gt(Contracts.seizure_risk(c), honest)
	c.trap = false
	Ports.state[c.dest].laws.vigilance = 0.0
	Contracts.deliver(c, s)
	assert_eq(c.status, "done")
	Contracts.collect(c, s)
	assert_eq(s.gold, gold + c.reward, "the deposit comes back with the fee")


func test_a_lying_employer_pays_short_unless_you_lean_on_them():
	s.career.marque = "england"
	for demand in [false, true]:
		var c := job("raid_shipping", gov())
		c.lied = true
		Contracts.accept(c, s)
		c.status = "done"
		var gold: float = s.gold
		var trust_before := Contracts.trust(gov(), s)
		Contracts.collect(c, s, demand)
		var paid: float = s.gold - gold
		if not demand:
			assert_eq(paid, float(int(c.reward * Data.rules.contracts.lie_pay)))
		elif paid == float(c.reward):
			assert_gt(Contracts.trust(gov(), s), trust_before)
		else:
			assert_lt(Contracts.trust(gov(), s), trust_before, "a failed demand sours them")


func test_dispatches_are_lost_when_you_strike_or_sold_to_the_enemy():
	var c := job("dispatches", gov())
	Contracts.accept(c, s)
	Contracts.on_battle(s, {"faction": "spain"}, "player_struck", Vector2.ZERO)
	assert_true(Contracts.active.is_empty())
	var d := job("dispatches", gov())
	Contracts.accept(d, s)
	var gold: float = s.gold
	Contracts.betray(d, s, "havana")
	assert_gt(s.gold, gold)
	assert_eq(Contracts.trust(gov(), s), -100)


func test_contracts_survive_save_and_load():
	s.career.marque = "england"
	var c := job("capture_ship", gov())
	Contracts.accept(c, s)
	assert_eq(SaveGame.save_game(world, PATH), OK)
	Contracts.reset()
	assert_eq(SaveGame.load_game(world, PATH), OK)
	var back := Contracts.find(c.id)
	assert_eq(back.ship, c.ship)
	assert_eq(world.shipping.find(back.npc).enemy.contract, c.id)
	DirAccess.remove_absolute(PATH)


func test_an_escort_pays_when_she_makes_port_and_raiders_hunt_her():
	var c := job("escort_convoy", Contracts.employer("port_royal", "merchant"))
	assert_false(c.is_empty())
	Contracts.accept(c, s)
	var her: Dictionary = world.shipping.find(c.npc)
	assert_eq(her.escort, c.id)
	var raiders: Array = world.shipping.npcs.filter(func(n): return n.get("hunting", "") == c.npc)
	assert_eq(raiders.size(), c.count, "raiders are waiting along her course")
	world.shipping._arrive(her)
	assert_eq(c.status, "done")
	assert_true(world.shipping.find(c.npc).is_empty())


func test_a_lost_escort_fails():
	var c := job("escort_convoy", Contracts.employer("port_royal", "merchant"))
	Contracts.accept(c, s)
	world.shipping.remove(world.shipping.find(c.npc))  # the raiders had her
	Contracts.daily(s)
	assert_false(c in Contracts.active)


func test_a_blockade_counts_days_on_station_and_starves_the_town():
	s.career.marque = "england"
	var c := job("blockade_port", gov())
	Contracts.accept(c, s)
	world.ship.anchored_at = ""
	world.ship.position = Contracts._pos(c.port) + Vector2(20, 0)
	var hunger: float = PortLife.situation(c.port).hunger
	for i in c.count:
		Contracts.daily(s)
	assert_eq(c.status, "done")
	assert_lt(Economy.model.world_mult("imports:" + c.port), 1.0, "nothing goes in")


func test_taking_a_town_completes_the_job_only_the_way_they_wanted():
	var broker := Contracts.employer("nassau", "broker")
	s.relations.pirates = 50
	People.person(broker).relations[s.captain] = 20
	var c := job("sack_town", broker)
	Contracts.accept(c, s)
	for i in 80:
		s.crew.append(People.add(People.generate({})))
	Sieges.ransom(s, c.port)
	assert_false(c in Contracts.active, "ransom isn't what they paid for")
	var d := job("sack_town", broker)
	Contracts.accept(d, s)
	Sieges.sack(s, d.port)
	assert_eq(d.status, "done")


func test_a_kidnapped_grandee_must_be_handed_over():
	var broker := Contracts.employer("nassau", "broker")
	s.relations.pirates = 50
	var c := job("kidnap_noble", broker)
	Contracts.accept(c, s)
	var ship: Dictionary = world.shipping.find(c.npc)
	Contracts.on_battle(s, ship.enemy, "enemy_struck", ship.pos)
	assert_eq(c.status, "done")
	assert_true(s.hostages.any(func(h): return h.id == c.hostage))
	s.hostages.clear()  # ransomed them yourself instead
	Contracts.daily(s)
	assert_false(c in Contracts.active)
	assert_eq(People.person(broker).last_job.how, "failed", "and the broker remembers")


func test_how_the_last_job_ended_decides_the_next():
	s.career.marque = "england"
	var g := gov()
	assert_true(Contracts.make("a_second_chance", g, s).is_empty(), "nothing to make amends for")
	var c := job("dispatches", g)
	Contracts.accept(c, s)
	Contracts.abandon(c, s)
	assert_false(Contracts.make("a_second_chance", g, s).is_empty(), "now there is")
	var b := job("blockade_port", g)
	Contracts.accept(b, s)
	Contracts._complete(b, s)
	Contracts.collect(b, s)
	var next := job("storm_the_starved", g)
	assert_false(next.is_empty())
	assert_eq(next.port, b.port, "take the town you starved")
