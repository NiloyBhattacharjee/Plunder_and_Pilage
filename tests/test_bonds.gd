extends GutTest

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 6
	Bonds.rng.seed = 6
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func after_each():
	Clock.day = 0.0
	Factions.reset()
	Bonds.reset()
	for f in Events.flags.keys().filter(func(k): return k.begins_with("fate_") or k.begins_with("gone_")):
		Events.flags.erase(f)


func bond(key: String, lvl: int) -> void:
	s.bonds[key] = {"type": "alliance" if lvl > 0 else "rivalry", "level": absi(lvl), "since": "", "strain": 0, "history": []}


func test_the_roster_sails_under_names():
	var r := Bonds.roster()
	assert_eq(r.size(), Data.table("bonds").captains.count)
	var c := People.person(r[0])
	assert_string_contains(c.name, '"')
	assert_true(Ports.state.has(c.haunt))
	assert_eq(c.faction, "pirates")
	assert_eq(Bonds.kind(r[0]), "captain")


func test_proposals_follow_the_breakdown():
	var cap: String = Bonds.roster()[0]
	People.person(cap).relations[s.captain] = -20
	var acc := Bonds.acceptance(s, cap)
	assert_false(acc.ok)
	assert_string_contains(Bonds.propose(s, cap), "declines")
	People.person(cap).relations[s.captain] = 30
	assert_true(Bonds.acceptance(s, cap).ok)
	Bonds.propose(s, cap)
	assert_eq(Bonds.level(s, cap), 1)
	assert_string_contains(Bonds.preview(s, cap), "Pact")


func test_their_enemies_become_yours():
	var r := Bonds.roster()
	Bonds.npc_set(r[0], r[1], -80)
	People.person(r[0]).relations[s.captain] = 50
	People.person(r[1]).relations[s.captain] = 0
	Bonds.propose(s, r[0])
	assert_lt(People.person(r[1]).relations[s.captain], 0)


func test_allies_hold_fire_and_rivals_dont():
	var cap: String = Bonds.roster()[0]
	var enemy := {"captain_id": cap, "faction": "pirates", "behaviour": "aggressive", "kind": "pirate"}
	s.relations.pirates = -50
	bond(cap, 1)
	assert_false(Career.npc_hostile(s, enemy, rng))
	bond(cap, -2)
	s.relations.pirates = 100
	assert_true(Career.npc_hostile(s, enemy, rng))


func test_neutral_captains_look_like_easy_prey():
	var pirate := {"faction": "pirates", "behaviour": "aggressive", "kind": "pirate"}
	s.relations.pirates = Data.rules.encounters.friendly_pirate_relation + 5
	assert_true(Career.npc_hostile(s, pirate, rng), "no friends anywhere")
	bond(Bonds.roster()[3], 1)
	assert_false(Career.npc_hostile(s, pirate, rng))


func test_breaking_costs_honour_and_makes_an_enemy():
	var cap: String = Bonds.roster()[0]
	bond(cap, 3)
	var honour: int = s.reputation.honour
	Bonds.break_bond(s, cap)
	assert_lt(s.reputation.honour, honour)
	assert_lt(Bonds.level(s, cap), 0, "a broken alliance becomes a rivalry")
	bond(cap, 4)
	var pirates: int = s.relations.pirates
	Bonds.break_bond(s, cap)
	assert_lt(s.relations.pirates, pirates - 20, "every pirate hears of a broken brotherhood")


func test_strain_drops_a_level():
	var cap: String = Bonds.roster()[0]
	bond(cap, 3)
	Bonds.strain(s, cap)
	assert_eq(Bonds.level(s, cap), 3)
	Bonds.strain(s, cap)
	assert_eq(Bonds.level(s, cap), 2)


func test_beating_a_rival_brings_fame_and_a_bounty():
	var cap: String = Bonds.roster()[0]
	bond(cap, -2)
	var gold: float = s.gold
	var fame: int = s.reputation.notoriety
	Bonds.on_battle(s, {"captain_id": cap}, "enemy_sunk", false)
	assert_gt(s.gold, gold, "a pirate's bounty")
	assert_gt(s.reputation.notoriety, fame)
	assert_false(People.person(cap).alive)
	assert_false(cap in Bonds.roster())


func test_attacking_an_ally_is_betrayal():
	var cap: String = Bonds.roster()[1]
	bond(cap, 2)
	Bonds.on_battle(s, {"captain_id": cap}, "separated", true)
	assert_lt(Bonds.level(s, cap), 0)


func test_nations_as_allies():
	s.relations.england = 30
	assert_true(Bonds.acceptance(s, "f:england").ok)
	assert_false(Bonds.acceptance(s, "f:spain").ok)
	Bonds.propose(s, "f:england")
	Bonds.propose(s, "f:england")
	assert_eq(Bonds.level(s, "f:england"), 2)
	assert_lt(Bonds.price_mult(s, "port_royal"), 1.0, "a pact means better prices")
	bond("f:england", 4)
	s.career.pirate = true
	s.reputation.notoriety = 100
	assert_true(Career.port_access(s, "port_royal").open, "patronage keeps the port open")
	assert_eq(Career.pardon_cost(s, "england"), 0)


func test_allies_fight_beside_you():
	var p := Encounters.player_side(s)
	p.allies = [{"name": "Ranger", "guns": 12, "gun_weight": 6, "gunnery": 20, "id": ""}]
	var e := Encounters.generate("spain", rng, "merchant")
	e.party = DiceCombat.npc_party(e, rng)
	var b := DiceCombat.new()
	b.rng.seed = 2
	b.setup(DiceCombat.make_side(p), DiceCombat.make_side(e), "attack", 1.0)
	var seen := false
	for i in 4:
		if b.result != "":
			break
		b.play_round({})
		seen = seen or b.entries.any(func(x): return x.text.contains("Ranger"))
	assert_true(seen)


func test_officers_leave_for_ships_of_their_own():
	var off: String = s.crew[0]
	var text := Bonds.former_officer(s, off, 2)
	assert_false(off in s.crew)
	assert_has(Bonds.roster(), off)
	assert_eq(Bonds.level(s, off), 2)
	assert_string_contains(text, "friend")


func test_a_new_captain_may_lose_allies():
	var cap: String = Bonds.roster()[0]
	bond(cap, 3)
	People.person(cap).relations[s.captain] = 45
	Crew.captain_dies(s, "fell in battle")
	Crew.make_captain(s, s.crew[0], "command")
	assert_lt(Bonds.level(s, cap), 3, "they don't know the new captain")


func test_pirate_friends_cost_you_with_the_nations():
	bond(Bonds.roster()[0], 2)
	var before: int = s.relations.spain
	Bonds.monthly(s)
	assert_lt(s.relations.spain, before)


func _day_of(date: String) -> float:
	return (Time.get_unix_time_from_datetime_string(date) - Time.get_unix_time_from_datetime_string(Data.rules.time.start_date)) / 86400.0


func test_real_captains_keep_to_the_histories():
	Bonds.reset()
	Bonds.history_day(s)
	assert_true(Bonds.real.has("de_graaf"), "Lorencillo is there at the start")
	assert_false(Bonds.real.has("blackbeard"))
	Clock.day = _day_of("1717-12-01")
	Bonds.history_day(s)
	var bb := People.person(Bonds.real.blackbeard)
	assert_eq(bb.ship, "Queen Anne's Revenge")
	assert_true(bb.id in Bonds.roster())
	Clock.day = _day_of("1718-11-23")
	Bonds.history_day(s)
	assert_false(bb.alive)
	assert_true(Events.flags.has("fate_blackbeard"))
	assert_false(Bonds.real.grammont in Bonds.roster(), "lost at sea in 1686")
	assert_eq(People.person(Bonds.real.hornigold).faction, "england", "took the pardon")


func test_crossing_their_wake_takes_them_off_the_script():
	Bonds.reset()
	Clock.day = _day_of("1718-01-01")
	Bonds.history_day(s)
	bond(Bonds.real.blackbeard, -1)
	Clock.day = _day_of("1718-11-23")
	var msgs := Bonds.history_day(s)
	var bb := People.person(Bonds.real.blackbeard)
	assert_true(bb.alive)
	assert_true(bb.off_script)
	assert_eq(bb.ship, "Queen Anne's Revenge", "no later steps once off the script")
	assert_false(Events.flags.has("fate_blackbeard"))
	assert_true(msgs.any(func(m): return "another end" in m))
