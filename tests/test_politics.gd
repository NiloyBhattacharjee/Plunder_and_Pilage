extends GutTest

var s: Dictionary
var ctx: Dictionary


func before_each():
	Clock.day = 0.0
	Politics.rng.seed = 2
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	ctx = {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "port_royal", "storm": false}


func after_each():
	Clock.day = 0.0
	Factions.reset()


func test_ports_are_run_by_people():
	var gov := Politics.official("port_royal", "governor")
	assert_eq(People.person(gov).name, Ports.port("port_royal").governor)
	assert_eq(Politics.official("port_royal", "governor"), gov, "the same person until replaced")
	assert_true("goal" in People.person(gov))
	assert_eq(Politics.official("nassau", "governor"), "", "no governor in a pirate haven")
	assert_ne(Politics.official("nassau", "broker"), "")
	assert_gt(Politics.offices("havana").size(), Politics.offices("basseterre").size(), "small colonies have fewer offices")


func test_interest_groups_set_the_laws():
	var p := Politics.power("havana")
	var total := 0.0
	for g in p:
		total += p[g]
	assert_almost_eq(total, 100.0, 0.01)
	var before: float = Ports.state.havana.laws.pirates
	Politics.shift("havana", "poor", 300.0)
	assert_eq(Politics.dominant("havana"), "poor")
	assert_gt(Ports.state.havana.laws.pirates, before, "the townsfolk welcome pirates")
	assert_gt(Ports.state.havana.laws.pirates, 0.4)
	s.career.pirate = true
	s.reputation.notoriety = 100
	assert_true(Career.port_access(s, "havana").open, "a pirates' town lets you in, wanted or not")
	Politics.shift("havana", "military", 2000.0)
	assert_false(Career.port_access(s, "havana").open)


func test_tariffs_change_prices():
	Ports.state.port_royal.laws.tariff = 0.0
	var before := Ports.price("port_royal", "sugar", true)
	Ports.state.port_royal.laws.tariff = 0.2
	var duty: float = Data.table("economy").duty.england
	assert_almost_eq(Ports.price("port_royal", "sugar", true), before * (1.2 + duty) / (1.0 + duty), 0.01, "the tariff is a duty on top")
	Ports.state.port_royal.laws.contraband = ["sugar"]
	assert_lt(Ports.price("port_royal", "sugar", true), before, "smugglers pay no duty")
	Ports.state.port_royal.laws.contraband = []


func test_favours_are_earned_spent_and_owed():
	var hm := Politics.official("port_royal", "harbour_master")
	assert_string_contains(Politics.favour_problem(hm, s, "blind_eye", false), "owes you")
	Politics.add_favours(hm, s, 1)
	var text := Politics.use_favour(hm, s, "blind_eye", ctx)
	assert_string_contains(text, "open to you")
	assert_eq(Politics.favours(hm, s), 0)
	s.career.pirate = true
	s.reputation.notoriety = 100
	assert_true(Career.port_access(s, "port_royal").open, "the harbour master looks the other way")
	var merchant := Politics.official("port_royal", "merchant")
	Politics.use_favour(merchant, s, "market_tip", ctx, true)
	assert_eq(Politics.favours(merchant, s), -1, "asked on credit: you owe them now")
	assert_has(Politics.creditors(s), merchant)


func test_a_new_captain_has_no_favours():
	var gov := Politics.official("port_royal", "governor")
	Politics.add_favours(gov, s, 3)
	Crew.captain_dies(s, "fell in battle")
	Crew.make_captain(s, s.crew[0], "command")
	assert_eq(Politics.favours(gov, s), 0, "the governor dealt with the old captain")


func test_secrets_blackmail_sell_and_expose():
	var gov := Politics.official("port_royal", "governor")
	Politics.gain_secret(s, "letters", gov)
	var sec: Dictionary = s.secrets[0]
	assert_string_contains(Politics.describe(sec), People.person(gov).name)
	Politics.blackmail(s, sec)
	assert_eq(Politics.favours(gov, s), 2)
	assert_lt(People.person(gov).relations[s.captain], -20, "blackmail makes an enemy")
	assert_has(Politics.enemies(s), gov)
	Politics.leverage_month(s)
	assert_eq(Politics.favours(gov, s), 3, "and pays every month")
	var gold: float = s.gold
	Politics.sell(s, sec)
	assert_gt(s.gold, gold)
	assert_true(s.secrets.is_empty())
	Politics.gain_secret(s, "bribes", Politics.official("port_royal", "commander"))
	var before: int = s.relations.england
	Politics.expose(s, s.secrets[0])
	assert_gt(s.relations.england, before)
	assert_ne(Politics.official("port_royal", "commander"), sec.about, "recalled and replaced")


func test_forgeries_backfire():
	var gov := Politics.official("port_royal", "governor")
	Politics.gain_secret(s, "letters", gov, true)
	var text := Politics.blackmail(s, s.secrets[0])
	assert_string_contains(text, "forgeries")
	assert_eq(Politics.favours(gov, s), 0)


func test_schedules_go_stale():
	Politics.gain_secret(s, "schedule", Politics.official("port_royal", "merchant"))
	Clock.day = 100.0
	Politics.prune_secrets(s)
	assert_true(s.secrets.is_empty())


func test_political_jobs_shift_power_and_pay_favours():
	Contracts.reset()
	var emp := Politics.official("port_royal", "priest")
	var c := Contracts.make("alms_voyage", emp, s)
	c.lied = false
	Contracts.accept(c, s)
	c.status = "done"
	var before: float = Politics.power("port_royal").church
	Contracts.collect(c, s)
	assert_gt(Politics.power("port_royal").church, before)
	assert_eq(Politics.favours(emp, s), 1)


func test_the_council_votes_and_can_be_won():
	var members := Politics.council_members()
	assert_eq(members.size(), 5)
	assert_eq(Politics.council_leader, members[0])
	s.council_member = true
	for id in members:
		People.person(id).relations[s.captain] = 90
	var r := Politics.council_vote(s, "defend", true, ctx)
	assert_true(r.passed, "friends vote your way")
	for id in members:
		People.person(id).relations[s.captain] = -90
	assert_false(Politics.council_vote(s, "defend", true, ctx).passed)
	for id in members:
		People.person(id).relations[s.captain] = 90
		People.person(id).relations[Politics.council_leader] = -50
	Politics.leadership_vote(s)
	assert_eq(Politics.council_leader, "player")


func test_officials_change_over_time():
	var gov := Politics.official("havana", "governor")
	Politics.replace("havana", "governor", "died of fever")
	var now := Politics.official("havana", "governor")
	assert_ne(now, gov)
	assert_true(People.chars.has(gov), "the old governor is still remembered")
	assert_eq(People.person(gov).port, "")
