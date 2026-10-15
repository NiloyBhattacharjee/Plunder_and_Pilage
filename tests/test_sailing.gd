extends GutTest

var polar: Array = Data.table("ships").sloop.polar


func test_polar_interpolates_between_points():
	assert_almost_eq(Sailing.polar_factor(polar, 100), 1.0, 0.001)
	assert_almost_eq(Sailing.polar_factor(polar, 42.5), 0.6, 0.001)  # halfway between 35->0.45 and 50->0.75


func test_dead_upwind_ship_tacks_and_still_makes_progress():
	var c := Sailing.best_course(polar, 0)
	assert_true(c.tacking)
	assert_between(c.factor, 0.3, 0.6)  # zig-zagging, roughly half speed made good
	assert_between(c.sail_angle, 35.0, 70.0)


func test_beam_reach_sails_straight_at_full_speed():
	var c := Sailing.best_course(polar, 90)
	assert_false(c.tacking)
	assert_gt(c.factor, Sailing.best_course(polar, 0).factor)


func test_angle_between_wraps_around_north():
	assert_almost_eq(Geo.angle_between(350, 10), 20.0, 0.001)
	assert_almost_eq(Geo.angle_between(90, 270), 180.0, 0.001)


func test_bearing_matches_screen_directions():
	assert_almost_eq(Geo.bearing(Vector2(0, -1)), 0.0, 0.001)   # up = north
	assert_almost_eq(Geo.bearing(Vector2(1, 0)), 90.0, 0.001)   # right = east
	assert_almost_eq(Geo.from_bearing(180).y, 1.0, 0.001)       # south = down
