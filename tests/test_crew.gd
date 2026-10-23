extends GutTest

var s: Dictionary
var stats: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 4
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	stats = ShipStats.effective(s.type, s.upgrades)
	s.cargo.rum = 10.0


func after_each():
	Clock.day = 0.0


func part(m: Dictionary, label: String) -> float:
	for p in m.parts:
		if p[0].begins_with(label):
			return p[1]
	return 0.0


func test_morale_explains_itself():
	var m := Crew.morale(s, stats)
	var total := 0.0
	for p in m.parts:
		total += p[1]
	assert_almost_eq(m.value, clampf(total, 0, 100), 0.01)
	assert_gt(part(m, "Rum ration"), 0.0)
	s.cargo.erase("rum")
	assert_lt(part(Crew.morale(s, stats), "No rum"), 0.0)
	s.wages_owed = 100.0
	assert_lt(part(Crew.morale(s, stats), "Wages"), 0.0, "unpaid wages hurt")
	Crew.add_mod(s, "battle", "Victory", 10, 30)
	assert_eq(part(Crew.morale(s, stats), "Victory"), 10.0)
	Clock.day = 31.0
	Crew.daily(s, stats, "port_royal", rng)
	assert_eq(part(Crew.morale(s, stats), "Victory"), 0.0, "timed modifiers expire")


func test_rum_is_drunk_daily():
	Crew.daily(s, stats, "", rng)
	assert_lt(s.cargo.rum, 10.0)


func test_plunder_pays_the_crew_their_share():
	s.gold = 0.0
	s.articles.crew_share = 0.4
	s.gold += 1000.0
	var text := Crew.plunder(s, 1000.0)
	assert_eq(s.gold, 600.0)
	assert_string_contains(text, "400")
	assert_gt(part(Crew.morale(s, stats), "Shares paid"), 0.0)
	assert_eq(s.last_plunder, Clock.day)


func test_no_prey_no_pay():
	s.articles.pay = "shares"
	s.last_plunder = 0.0
	Clock.day = 60.0
	assert_lt(part(Crew.morale(s, stats), "No prey"), 0.0, "a long cruise without plunder")


func test_pirates_vote_on_their_articles():
	s.career.pirate = true
	for id in s.crew:
		People.person(id).relations[s.captain] = -60
	var before: float = s.articles.crew_share
	var text := Crew.set_articles(s, stats, "wages", 0.0, rng)
	assert_string_contains(text, "vote it down")
	assert_eq(s.articles.crew_share, before)
	for id in s.crew:
		People.person(id).relations[s.captain] = 60
	Crew.set_articles(s, stats, "wages", 0.5, rng)
	assert_eq(s.articles.crew_share, 0.5, "a bigger share passes easily")


func test_long_voyages_bring_scurvy_and_port_cures_it():
	Data.rules.crew.disease.scurvy.chance = 1.0
	s.days_at_sea = 100
	Crew.disease_day(s, "", rng)
	assert_gt(Crew.sick_count(s), 0)
	assert_lt(Crew.able(s), ShipStats.headcount(s), "the sick can't work")
	Data.rules.crew.disease.scurvy.chance = 0.004
	Data.rules.crew.disease.scurvy.death = 0.0
	for i in 40:
		Crew.disease_day(s, "port_royal", rng)
	assert_eq(Crew.sick_count(s), 0, "rest ashore")
	Data.rules.crew.disease.scurvy.death = 0.004


func test_friends_mourn_and_feuds_are_found():
	var a: String = s.crew[0]
	var b: String = s.crew[1]
	People.person(b).relations[a] = 50
	assert_has(Crew.friends_of(s, a), b)
	Crew.mourn(s, a)
	assert_lt(part(Crew.morale(s, stats), "Mourning"), 0.0)
	People.person(a).relations[b] = -50
	People.person(b).relations[a] = -50
	assert_eq(Crew.feuds(s).size(), 1)


func test_unrest_builds_from_a_ringleader_and_misery():
	var leader := People.person(s.crew[0])
	leader.traits = ["schemer"]
	leader.stats.charisma = 16
	leader.relations[s.captain] = -50
	for id in s.crew:
		People.person(id).relations[s.captain] = -40
	leader.relations[s.captain] = -50
	s.wages_owed = 500.0
	s.cargo.erase("rum")
	Data.rules.crew.leader_chance = 1.0
	for i in 30:
		Clock.day = float(i)
		Crew.unrest_day(s, stats, rng)
	Data.rules.crew.leader_chance = 0.1
	assert_lte(s.unrest.stage, 4, "one stage a week: the warning signs come in order")
	assert_eq(s.unrest.leader, leader.id)
	assert_gt(s.unrest.support.size(), 3)
	assert_gt(s.unrest.stage, 1)
	Crew.calm(s, 999)
	assert_eq(s.unrest.support, [leader.id], "talking them round leaves the leader alone")


func test_loyal_hands_never_join():
	var leader := People.person(s.crew[0])
	s.unrest = {"leader": leader.id, "support": [leader.id], "stage": 1, "known": false}
	var loyal := People.person(s.crew[1])
	loyal.traits = ["loyal"]
	loyal.relations[s.captain] = 0
	s.wages_owed = 500.0
	for i in 40:
		Crew.unrest_day(s, stats, rng)
	assert_false(loyal.id in s.unrest.support)


func test_a_mutiny_ends_one_way_or_another():
	for seed in 10:
		before_each()
		rng.seed = seed
		var plotters: Array = s.crew.slice(0, int(s.crew.size() * 0.7))
		s.unrest = {"leader": plotters[0], "support": plotters.duplicate(), "stage": 5, "known": true}
		var r := Crew.mutiny(s, rng)
		assert_has(["crushed", "deposed", "killed", "split"], r.outcome)
		if r.outcome in ["deposed", "killed"]:
			assert_true(s.has("succession"))
			assert_eq(s.succession.favour, plotters[0])
		if r.outcome == "crushed":
			Crew.punish(s, r.rebels, "maroon")
			assert_false(plotters[1] in s.crew)
			assert_eq(s.unrest.stage, 0)


func test_succession_hands_over_the_ship():
	var heir: String = s.crew[2]
	s.heir = heir
	s.reputation.fear = 20
	s.relations.england = 50
	var old: String = s.captain
	Crew.captain_dies(s, "fell in battle")
	var cands := Crew.candidates(s, rng)
	assert_true(cands.any(func(c): return c.id == heir), "your heir is always a candidate")
	var total := 0.0
	for c in cands:
		total += c.support
	assert_almost_eq(total, 1.0, 0.01)
	Crew.make_captain(s, heir, "elected")
	assert_eq(s.captain, heir)
	assert_false(heir in s.crew)
	assert_false(People.chars.has(old))
	assert_eq(s.captains.size(), 1)
	assert_eq(s.captains[0].fate, "fell in battle")
	assert_eq(s.relations.england, 30, "standing carries over only partly")
	assert_eq(s.reputation.fear, 10)
	assert_false(s.has("succession"))


func test_chain_of_command_unless_the_crew_refuse():
	var qm: String = s.crew[3]
	s.officers = {"quartermaster": qm}
	s.heir = ""
	var cands := [{"id": qm, "support": 0.5}, {"id": s.crew[4], "support": 0.5}]
	assert_eq(Crew.chosen(s, cands), {"id": qm, "how": "command"})
	cands = [{"id": s.crew[4], "support": 0.9}, {"id": qm, "support": 0.1}]
	assert_eq(Crew.chosen(s, cands).how, "elected", "the crew won't follow them: they vote instead")
	s.career.pirate = true
	assert_eq(Crew.chosen(s, [{"id": s.crew[4], "support": 0.6}, {"id": qm, "support": 0.4}]).id, s.crew[4], "pirates always vote")


func test_events_can_end_a_captaincy():
	var ctx := {"s": s, "stats": stats, "port": "", "storm": false}
	var inst := {"id": "unrest_black_spot", "vars": {"leader": s.crew[0]}}
	s.unrest = {"leader": s.crew[0], "support": [s.crew[0]], "stage": 4, "known": true}
	var res := Events.resolve(inst, 3, ctx)
	assert_true(s.has("succession"), "standing down")
	s.erase("succession")
	res = Events.resolve(inst, 0, ctx)
	assert_true(res.mutiny, "drawing your sword starts the mutiny")


func test_hard_times_turn_the_crew_against_you_down_to_a_floor():
	Crew.ensure(s)
	var p := People.person(s.crew[0])
	p.relations[s.captain] = 0
	var hard := {"value": 10.0, "parts": [["No rum", -5.0]]}
	for d in 6:
		Crew.mood_day(s, hard)
	assert_eq(Crew.opinion(p, s), 0, "a bad week is forgiven")
	assert_eq(Crew.mood_day(s, hard).size(), 1, "the seventh day: they start to blame you, and you're told")
	assert_lt(Crew.opinion(p, s), 0)
	for d in 200:
		Crew.mood_day(s, hard)
	assert_eq(Crew.opinion(p, s), int(Crew.cfg().grudge.floor), "hardship alone stops at the floor")
	p.relations[s.captain] = -50
	for d in 30:
		Crew.mood_day(s, hard)
	assert_eq(Crew.opinion(p, s), -50, "nor deepens a grudge your deeds earned")
	Crew.mood_day(s, {"value": 50.0, "parts": []})
	assert_eq(s.hard_days, 0, "an ordinary day breaks the run")
	p.relations[s.captain] = 0
	for d in 200:
		Crew.mood_day(s, {"value": 90.0, "parts": []})
	assert_eq(Crew.opinion(p, s), int(Crew.cfg().grudge.good_cap), "good times win them only so far")


func test_striking_and_a_bloodbath_are_laid_at_your_door():
	var p := People.person(s.crew[0])
	p.relations[s.captain] = 0
	assert_ne(Crew.after_battle(s, "player_struck", {"casualties": 30.0, "crew_start": 60.0}), "")
	assert_eq(Crew.opinion(p, s), int(Crew.cfg().grudge.struck) + int(Crew.cfg().grudge.losses))
	p.relations[s.captain] = 0
	assert_eq(Crew.after_battle(s, "enemy_struck", {"casualties": 1.0, "crew_start": 60.0}), "")
	assert_eq(Crew.opinion(p, s), int(Crew.cfg().grudge.prize), "a prize cheaply taken warms them")
