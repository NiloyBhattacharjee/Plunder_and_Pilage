extends GutTest
## Rivals who grow, the price on your head, and the other ships at sea (smugglers, coasters, guarda costas).

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 3
	Bonds.rng.seed = 3
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func after_each():
	Clock.day = 0.0


func test_a_captain_who_takes_prizes_moves_up_to_a_bigger_ship():
	var id: String = Bonds.roster()[0]
	var c := People.person(id)
	c.fame = 0
	c.ship_type = "sloop"
	var gunnery: int = c.skills.gunnery + c.skills.seamanship + c.skills.swordplay + c.stats.authority + c.stats.intimidation
	var news := ""
	for i in 20:
		news += Bonds.grow(id, 6)
	assert_eq(c.ship_type, "frigate")
	assert_string_contains(news, "has taken a")
	assert_gt(c.skills.gunnery + c.skills.seamanship + c.skills.swordplay + c.stats.authority + c.stats.intimidation, gunnery, "and better at the trade")


func test_the_dead_are_replaced():
	var r := Bonds.roster()
	People.person(r[0]).alive = false
	Data.table("bonds").growth.new_captain_chance = 1.0
	Bonds.monthly(s)
	Data.table("bonds").growth.new_captain_chance = 0.3
	assert_eq(Bonds.roster().filter(func(id): return not People.person(id).has("real")).size(), int(Data.table("bonds").captains.count))


func test_beating_you_makes_their_name():
	var id: String = Bonds.roster()[0]
	var fame: int = People.person(id).fame
	Bonds.on_battle(s, {"captain_id": id}, "player_struck", false)
	assert_gt(People.person(id).fame, fame)


func test_piracy_puts_a_price_on_your_head():
	assert_eq(Career.bounty_total(s), 0.0)
	Career.on_attack(s, Encounters.generate("spain", rng, "merchant"))
	assert_gt(Career.bounty_total(s), 0.0)
	assert_eq(Career.bounty_by(s), "spain")
	Sieges.sack(s, "maracaibo")
	assert_true(Career.hunted(s))
	var hunter := Encounters.generate("spain", rng, "hunter")
	s.reputation.notoriety = 0  # not wanted for notoriety: hunted for the money
	assert_true(Career.npc_hostile(s, hunter, rng), "Spanish hunters come for the Spanish price")
	Career.add_bounty(s, "spain", 5000)
	assert_ne(Career.hunter_ship(s), "brigantine", "a big price brings a big ship")
	assert_true(Events.flags.has("sacked_maracaibo"), "events remember the sack")


func test_a_pardon_clears_that_nations_price_and_it_fades():
	Career.add_bounty(s, "spain", 1000)
	Career.add_bounty(s, "france", 500)
	s.career.pirate = true
	Career.pardon(s, "spain", true)
	assert_false(s.bounty.has("spain"))
	for i in 100:
		Career.bounty_daily(s)
	assert_lt(s.bounty.france, 500.0)


func test_a_guarda_costa_searches_foreign_ships():
	var g := Encounters.generate("england", rng, "guarda_costa")
	assert_eq(g.faction, "spain", "guarda costas are always Spanish")
	s.flag = "england"
	s.cargo = {"cloth": 10.0}
	assert_true(Career.npc_hostile(s, g, rng), "forbidden cloth aboard: a prize")
