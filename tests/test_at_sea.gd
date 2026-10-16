extends GutTest
## Meetings at sea: hailing, trading over the rail, a patrol's search, other ships' fights.

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	Ports.reset()
	rng.seed = 3
	s = NewGame.build({"nationality": "english", "background": "merchant_son"}).state


func merchant_npc() -> Dictionary:
	var v: Dictionary = Economy.voyages()[0]
	var e := Encounters.generate(v.faction, rng, "merchant")
	e.cargo = {v.good: int(v.qty)}
	return {"id": "n1", "enemy": e, "voyage": v.id, "origin": v.origin, "dest": v.dest}


func test_who_will_talk():
	var m := merchant_npc()
	assert_eq(AtSea.hail_problem(s, m.enemy), "")
	s.flag = "black"
	assert_ne(AtSea.hail_problem(s, m.enemy), "", "a merchant runs from the black flag")


func test_buying_over_the_rail_takes_from_her_voyage():
	var m := merchant_npc()
	var v := Economy.voyage(m.voyage)
	var before: float = v.qty
	s.gold = 100000
	var o := AtSea.offer(m, "port_royal")
	assert_false(o.is_empty())
	assert_lt(o.price, Economy.price(m.dest, o.good, false), "under what it fetches where she's bound")
	var had: int = int(s.cargo.get(o.good, 0))
	var n: int = mini(5, int(o.qty))
	AtSea.buy(s, m, o, 5, 1000000.0)
	assert_eq(int(s.cargo[o.good]), had + n)
	assert_eq(v.qty, before - n, "fewer reach market")


func test_pirate_plunder_is_cheap_and_stolen():
	var e := Encounters.generate("pirates", rng, "pirate")
	e.cargo = {"sugar": 30}
	var o := AtSea.offer({"enemy": e}, "port_royal")
	assert_true(o.stolen)
	assert_almost_eq(o.price, Economy.price("port_royal", "sugar", false) * AtSea.cfg().plunder_price, 0.01)
	s.gold = 10000
	AtSea.buy(s, {"enemy": e}, o, 10, 1000.0)
	assert_eq(s.stolen.sugar, 10.0)


func test_a_patrol_finds_what_it_should():
	assert_true(AtSea.suspect(s, "england").is_empty(), "nothing to hide yet")
	s.cargo.sugar = 20  # enumerated by the English
	s.flag = Data.table("factions").dutch.flag
	assert_true(AtSea.suspect(s, "england").has("sugar"), "English sugar under Dutch colours")
	s.flag = Data.table("factions").england.flag
	assert_false(AtSea.suspect(s, "england").has("sugar"), "...is fine under English colours")
	s.cargo.silver = 5
	s.stolen = {"silver": 5.0}
	assert_true(AtSea.suspect(s, "england").has("silver"), "plunder is recognised")


func test_a_search_seizes_and_fines():
	s.flag = Data.table("factions").england.flag
	s.cargo.silver = 5
	s.stolen = {"silver": 5.0}
	s.gold = 1000
	var notoriety: float = s.reputation.notoriety
	var text := ""
	for k in 20:  # until they find it
		text = AtSea.search(s, "england", rng)
		if not s.cargo.has("silver"):
			break
	assert_false(s.cargo.has("silver"))
	assert_lt(s.gold, 1000.0)
	assert_gt(s.reputation.notoriety, notoriety)
	assert_string_contains(text, "Fined")


func test_fights_wear_ships_down():
	var e := Encounters.generate("pirates", rng, "pirate")
	var before := AtSea.strength(e)
	AtSea.hurt(e, 0.4)
	assert_lt(AtSea.strength(e), before)
	var ally := AtSea.as_ally({"id": "n9", "enemy": e})
	assert_gt(ally.guns, 0)
	assert_eq(ally.npc, "n9")


func test_pirates_know_of_prizes():
	var tip := AtSea.prize_tip(Geo.latlon_to_px(Ports.port("port_royal").lat, Ports.port("port_royal").lon), rng)
	assert_string_contains(tip, "merchantman")


func test_searched_once_left_alone_a_while():
	AtSea.search(s, "england", rng)
	for k in 30:
		assert_false(AtSea.wants_search(s, "england", rng), "not again so soon")
	Clock.day += AtSea.cfg().search_again_days + 1
	var asked := false
	for k in 50:
		asked = asked or AtSea.wants_search(s, "england", rng)
	assert_true(asked)
