extends GutTest

var clock


func before_each():
	clock = preload("res://scripts/clock.gd").new()
	add_child_autofree(clock)
	clock.set_process(false)  # drive time manually


func test_starts_on_start_date():
	assert_eq(clock.date_string(), "1 January 1680")


func test_leap_year_1680():
	clock.advance(59)
	assert_eq(clock.date_string(), "29 February 1680")


func test_day_passed_fires_once_per_whole_day_even_on_big_steps():
	watch_signals(clock)
	clock.advance(0.5)
	assert_signal_emit_count(clock, "day_passed", 0)
	clock.advance(2.7)
	assert_signal_emit_count(clock, "day_passed", 3)


func test_pause_toggle_resumes_previous_speed():
	clock.set_speed(3)
	clock.toggle_pause()
	assert_eq(clock.speed_index, 0)
	clock.toggle_pause()
	assert_eq(clock.speed_index, 3)
