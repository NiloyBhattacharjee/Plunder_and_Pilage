extends GutTest

const Ship = preload("res://scripts/ship.gd")
var upkeep := {"food_per_crew": 0.1, "water_per_crew": 0.1, "wage_per_crew": 0.5}


func _state(food: float, water: float, gold: float) -> Dictionary:
	return {"crew": 40, "gold": gold, "wages_owed": 0.0, "cargo": {"food": food, "water": water}, "cargo_cost": {}}


func test_daily_upkeep_consumes_food_water_and_wages():
	var s := _state(100.0, 50.0, 100.0)
	Ship.apply_daily_upkeep(s, upkeep)
	assert_almost_eq(s.cargo.food, 96.0, 0.001)
	assert_almost_eq(s.cargo.water, 46.0, 0.001)
	assert_almost_eq(s.gold, 80.0, 0.001)


func test_supplies_run_out_and_leave_the_hold():
	var s := _state(1.0, 0.0, 0.0)
	Ship.apply_daily_upkeep(s, upkeep)
	assert_false(s.cargo.has("food"))
	assert_false(s.cargo.has("water"))


func test_unpaid_wages_become_debt():
	var s := _state(10.0, 10.0, 5.0)
	Ship.apply_daily_upkeep(s, upkeep)
	assert_eq(s.gold, 0.0)
	assert_almost_eq(s.wages_owed, 15.0, 0.001)
