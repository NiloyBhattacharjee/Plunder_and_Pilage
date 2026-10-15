extends GutTest

const Ship = preload("res://scripts/ship.gd")
var upkeep := {"food_per_crew": 0.1, "water_per_crew": 0.1, "wage_per_crew": 0.5}


func test_daily_upkeep_consumes_food_water_and_wages():
	var s := {"crew": 40, "food": 100.0, "water": 50.0, "gold": 100.0, "wages_owed": 0.0}
	Ship.apply_daily_upkeep(s, upkeep)
	assert_almost_eq(s.food, 96.0, 0.001)
	assert_almost_eq(s.water, 46.0, 0.001)
	assert_almost_eq(s.gold, 80.0, 0.001)


func test_supplies_never_go_negative():
	var s := {"crew": 40, "food": 1.0, "water": 0.0, "gold": 0.0, "wages_owed": 0.0}
	Ship.apply_daily_upkeep(s, upkeep)
	assert_eq(s.food, 0.0)
	assert_eq(s.water, 0.0)


func test_unpaid_wages_become_debt():
	var s := {"crew": 40, "food": 10.0, "water": 10.0, "gold": 5.0, "wages_owed": 0.0}
	Ship.apply_daily_upkeep(s, upkeep)
	assert_eq(s.gold, 0.0)
	assert_almost_eq(s.wages_owed, 15.0, 0.001)
