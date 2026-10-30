extends GutTest
## Living towns: plantation towns grow, war stops the settlers, blows take people and towns fill again, havens swell
## with pirates, and a town's trades follow its people.

var m: EconomyModel


func before_each():
	m = EconomyModel.new()
	m.setup(Data.table("goods"), Data.table("ports"), Data.table("economy").duplicate(true), 5)


func weeks(n: int, year := 1716) -> void:
	for i in n * 7:
		m.step(3, year)


func test_a_plantation_town_grows_and_makes_more():
	var made: float = m.params.bridgetown.sugar.make
	var before: int = m.ports.bridgetown.population
	weeks(104)
	assert_gt(m.ports.bridgetown.population, before * 1.03, "two years of new estates")
	assert_gt(m.params.bridgetown.sugar.make, made, "more hands in the cane")
	assert_gt(m.towns.growth("bridgetown"), m.towns.growth("trujillo"), "faster than a sleepy town")


func test_war_stops_the_settlers():
	var peace := m.towns.growth("bridgetown")
	m.traffic.wars = [["england", "france"]]
	assert_lt(m.towns.growth("bridgetown"), peace * 0.5)


func test_fever_takes_people_and_the_town_fills_again():
	var before: int = m.ports.havana.population
	var use: float = m.params.havana.food.use
	m.apply_effect("havana", {"type": "population", "mult": 0.8, "reason": "Yellow fever"})
	assert_almost_eq(float(m.ports.havana.population), before * 0.8, 2.0)
	assert_lt(m.params.havana.food.use, use, "fewer mouths")
	assert_eq(m.towns.losses.havana[-1].why, "Yellow fever")
	var low: int = m.ports.havana.population
	weeks(52)
	assert_gt(m.ports.havana.population, low * 1.04, "filling up again, faster than its usual growth")


func test_a_haven_swells_with_pirates_ashore():
	var co: Dictionary = m.brethren.companies[0]
	co.haven = "nassau"
	co.away = false
	m.towns.week()
	assert_gt(float(m.ports.nassau.population), m.towns.settled.nassau + co.men * 0.2)
	co.away = true  # gone north for the hurricane months
	m.towns.week()
	assert_almost_eq(float(m.ports.nassau.population), m.towns.settled.nassau, 1.0)


func test_towns_survive_save_and_load_and_a_new_game_starts_fresh():
	m.apply_effect("port_royal", {"type": "population", "mult": 0.5, "reason": "Earthquake"})
	var pop: int = m.ports.port_royal.population
	var saved := m.save_state().duplicate(true)
	var m2 := EconomyModel.new()
	m2.setup(Data.table("goods"), Data.table("ports"), Data.table("economy").duplicate(true), 6)
	assert_eq(int(m2.ports.port_royal.population), int(m2.ports.port_royal.orig_population), "a new model starts from the data")
	m2.load_state(saved)
	assert_eq(int(m2.ports.port_royal.population), pop)
	assert_eq(m2.towns.losses.port_royal.size(), 1)
