extends GutTest

var weather


func before_each():
	weather = preload("res://scripts/weather.gd").new()
	weather.rng.seed = 42
	weather.wind_dir = Data.rules.weather.trade_wind_from


func after_each():
	weather.free()


func _hurricanes() -> int:
	return weather.storms.filter(func(s): return s.kind == "hurricane").size()


func test_no_hurricanes_outside_season():
	for month in [1, 2, 3, 4, 5, 12]:
		for i in 200:
			weather.new_day(month)
	assert_eq(_hurricanes(), 0)


func test_hurricanes_happen_in_season():
	var seen := 0
	for i in 200:
		weather.new_day(9)
		seen = maxi(seen, _hurricanes())
	assert_gt(seen, 0)


func test_wind_stays_near_trade_wind_on_average():
	var sum := Vector2.ZERO
	for i in 365:
		weather.new_day(3)
		sum += Geo.from_bearing(weather.wind_dir)
	assert_lt(Geo.angle_between(Geo.bearing(sum), Data.rules.weather.trade_wind_from), 20.0)


func test_storm_wind_circles_anticlockwise():
	weather.storms = [{"kind": "squall", "pos": Vector2(500, 500), "vel": Vector2.ZERO, "radius": 100.0, "days_left": 3}]
	var east_of_eye: Dictionary = weather.wind_at(Vector2(550, 500))
	assert_eq(east_of_eye.storm, "squall")
	assert_almost_eq(east_of_eye.dir, 180.0, 0.01)  # wind from the south, blowing north
	assert_eq(weather.wind_at(Vector2(700, 500)).storm, "")


func test_storms_expire():
	weather.spawn_storm("squall")
	for i in 10:
		weather.new_day(1)
	assert_true(weather.storms.all(func(s): return s.days_left > 0))
	assert_lt(weather.storms.size(), 3)
