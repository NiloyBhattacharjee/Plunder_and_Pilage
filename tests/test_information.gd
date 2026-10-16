extends GutTest
## What the player knows: news on the quay, captured papers, news at sailing speed, rumours and estimates.

var s: Dictionary


func before_each():
	Clock.day = 0.0
	s = NewGame.build({"nationality": "english", "background": "merchant_son"}).state
	Economy.news = []


func after_each():
	Clock.day = 0.0


func test_the_quay_knows_what_its_ships_brought():
	assert_true(Ports.known.is_empty())
	var n := Ports.learn_board("port_royal")
	assert_gt(n, 0, "ships in harbour bring news")
	for id in Ports.known:
		for good in Ports.known[id]:
			var k: Dictionary = Ports.known[id][good]
			assert_eq(k.source, "news")
			assert_true(k.day <= int(Clock.day), "news is never from the future")


func test_captured_papers_carry_prices():
	var v: Dictionary = Economy.voyages()[0]
	var n := Ports.learn_news(v.news, "papers")
	assert_gt(n, 0)
	assert_true(Ports.known.has(v.origin), "at least her home port's prices as she sailed")
	assert_eq(Ports.known[v.origin].values()[0].source, "papers")


func test_news_travels_at_sailing_speed():
	Economy.add_news("The galeones have reached Cartagena.", "cartagena")
	assert_true(Economy.news_reaching("port_royal").is_empty(), "not yet: it's days away")
	assert_eq(Economy.news_reaching("cartagena").size(), 1, "but it's known at once where it happened")
	Economy.add_news("The galeones have reached Cartagena.", "cartagena")
	Clock.day = Economy.model.traffic.days("cartagena", "port_royal") + 1.0
	assert_eq(Economy.news_reaching("port_royal").size(), 1)


func test_estimates_from_old_news_and_better_traders():
	Ports.record_prices("havana", 0)
	assert_eq(Ports.estimate("havana", "cloth", s).err, 0.0, "fresh news needs no guessing")
	Clock.day = 60.0
	var dull := Ports.estimate("havana", "cloth", s)
	assert_gt(dull.err, 0.0)
	People.person(s.captain).skills.trade = 20
	var sharp := Ports.estimate("havana", "cloth", s)
	assert_lt(sharp.err, dull.err, "a better trader guesses closer")
	assert_eq(sharp.age, 60)


func test_rumours_carry_old_news():
	for i in 20:
		Ports.rumour("port_royal", int(Clock.day))
	var sources := []
	for id in Ports.known:
		for good in Ports.known[id]:
			sources.append(Ports.known[id][good].source)
			assert_true(Ports.known[id][good].day <= int(Clock.day))
	assert_has(sources, "rumour")


func test_best_sale_uses_the_estimate():
	Ports.record_prices("havana", 0)
	Clock.day = 40.0
	var best := Ports.best_known_sale("cloth", "port_royal", s)
	assert_eq(best.port, "havana")
	assert_false(best.est.is_empty())
	assert_almost_eq(best.sell, best.est.sell, 0.001)
