extends GutTest

var s: Dictionary


func before_each():
	Clock.day = 0.0
	Bases.rng.seed = 3
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	s.gold = 5000.0
	for i in 20:
		s.crew.append(People.add(People.generate({})))


func after_each():
	Clock.day = 0.0


func base() -> Dictionary:
	Bases.discovered.append("roatan")
	Bases.claim(s, "roatan")
	return Bases.bases.roatan


func test_coves_are_found_by_sailing_close():
	var nav: String = s.crew[0]
	s.officers.navigator = nav
	People.person(nav).skills.navigation = 20
	var found := ""
	for i in 20:
		found = Bases.look_for_coves(s, Bases.cove_pos("isle_of_pines"))
		if found != "":
			break
	assert_string_contains(found, "Isle of Pines")
	assert_has(Bases.discovered, "isle_of_pines")
	assert_eq(Bases.look_for_coves(s, Vector2(-9999, -9999)), "", "nothing out in the empty sea")


func test_claiming_costs_gold_and_men():
	var crew: int = s.crew.size()
	var b := base()
	assert_eq(s.gold, 5000.0 - Data.rules.bases.claim_cost)
	assert_eq(b.garrison, Data.rules.bases.claim_garrison)
	assert_eq(s.crew.size(), crew - Data.rules.bases.claim_garrison)
	for i in 4:
		Bases.bases["x%d" % i] = {}
	assert_string_contains(Bases.claim_problem(s, "saona"), "more than")


func test_buildings_take_time_and_need_each_other():
	var b := base()
	assert_string_contains(Bases.build_problem(s, "roatan", "warehouse"), "dock")
	Bases.build(s, "roatan", "dock")
	assert_string_contains(Bases.build_problem(s, "roatan", "watchtower"), "Already building")
	for i in Data.table("buildings").dock.days + 1:
		Bases.daily(s, "")
	assert_true(Bases.has(b, "dock"))
	assert_string_contains(Bases.build_problem(s, "roatan", "plantation"), "Nothing grows", "Roatán has no soil for it")


func test_plantations_grow_and_distilleries_make_rum():
	Bases.discovered.append("vieques")
	Bases.claim(s, "vieques")
	var b: Dictionary = Bases.bases.vieques
	b.buildings = ["dock", "plantation", "distillery"]
	b.storage.food = 50.0
	b.storage.water = 50.0
	b.gold = 500.0
	for i in 10:
		Bases.daily(s, "")
	assert_eq(b.storage.get("tobacco", 0.0), 0.0, "five men keep the base; nobody works the fields")
	b.garrison = 5 + Bases.hands_needed(b)
	b.storage.molasses = 3.0
	for i in 10:
		Bases.daily(s, "")
	assert_gt(b.storage.get("rum", 0.0), 0.0)
	assert_gt(b.storage.get("tobacco", 0.0), 0.0)
	assert_eq(b.storage.molasses, 0.0, "molasses brought in goes to the stills first")


func test_an_unpaid_hungry_garrison_turns():
	var b := base()
	b.gold = 0.0
	b.storage.food = 0.0
	var before: float = b.loyalty
	for i in 10:
		Bases.daily(s, "")
	assert_lt(b.loyalty, before)


func test_storage_keeps_stolen_marks_and_is_safe():
	var b := base()
	s.cargo.silver = 10.0
	s.stolen = {"silver": 10.0}
	Bases.move_goods(s, "roatan", "silver", 10, 100)
	assert_eq(b.storage.silver, 10.0)
	assert_eq(b.stolen.silver, 10.0)
	Encounters.surrender_losses(s)
	assert_eq(b.storage.silver, 10.0, "what's ashore stays ashore")
	b.buildings = ["dock", "warehouse", "smugglers_market"]
	var gold: float = s.gold
	Bases.sell(s, "roatan", "silver", 10)
	assert_gt(s.gold, gold)


func test_raids_against_strong_and_weak_bases():
	var b := base()
	b.garrison = 200
	b.buildings = ["dock", "battery", "fort", "watchtower"]
	b.raid = {"day": 0.0, "kind": "pirate", "faction": "pirates", "captain": "", "label": "pirates", "warned": true}
	assert_string_contains(Bases.resolve_raid(s, "roatan", 0), "beaten off")
	b.garrison = 1
	b.buildings = ["dock"]
	b.raid = {"day": 0.0, "kind": "navy", "faction": "spain", "captain": "", "label": "a Spanish squadron", "warned": false}
	assert_string_contains(Bases.resolve_raid(s, "roatan", 0), "fallen")
	assert_false(Bases.bases.has("roatan"))


func test_a_raid_on_your_anchorage_is_a_battle():
	var b := base()
	b.raid = {"day": 0.0, "kind": "pirate", "faction": "pirates", "captain": "", "label": "pirates", "warned": false}
	assert_eq(Bases.daily(s, "roatan").battle, "roatan")


func test_watchtowers_warn_ahead():
	var b := base()
	b.buildings = ["watchtower"]
	b.visibility = 100.0
	var warned := false
	for i in 60:
		Clock.day = float(i)
		if not b.raid.is_empty():
			warned = b.raid.warned and b.raid.day > Clock.day
			break
		Bases.daily(s, "")
	assert_true(warned)


func test_the_stockade_collects_ransoms():
	var b := base()
	b.buildings = ["dock", "stockade"]
	var h := People.add(People.generate({}))
	s.hostages = [{"id": h, "faction": "spain", "ransom": 200}]
	Bases.leave_hostage(s, "roatan", 0)
	Clock.day = 30.0
	Bases.daily(s, "")
	assert_eq(b.gold, 300.0, "ransom times one and a half")
	assert_true(b.hostages.is_empty())
