extends GutTest
## The weekly record behind the Charts tab.

var s: Dictionary


func before_each():
	Clock.day = 0.0
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func after_each():
	Clock.day = 0.0


func test_a_week_is_recorded_and_read_back():
	Clock.day = 7.0
	Stats.week(s, ShipStats.effective(s.type, s.upgrades), [{"kind": "pirate"}, {"kind": "hunter"}])
	assert_eq(s.stats.size(), 1)
	assert_eq(Stats.line(s, "gold"), [float(s.gold)])
	assert_eq(Stats.line(s, "relations.england"), [float(s.relations.england)])
	assert_eq([s.stats[0].pirates, s.stats[0].navy], [1, 1])


func test_wars_merge_into_bands_and_history_falls_in_its_week():
	var utrecht := Time.get_unix_time_from_datetime_string("1713-04-11")
	var day := int((utrecht - Time.get_unix_time_from_datetime_string(Data.rules.time.start_date)) / 86400)
	var war := [["france", "spain"]]
	s.stats = [{"day": day - 14, "wars": war}, {"day": day - 7, "wars": war}, {"day": day, "wars": []}, {"day": day + 7, "wars": war}]
	var bands := Stats.war_bands(s)
	assert_eq(bands.size(), 2, "a gap splits the war into two bands")
	assert_eq([bands[0].from, bands[0].to], [0, 1])
	assert_true(Stats.history_marks(s).any(func(m): return m.at == 2 and "Utrecht" in m.text), "Utrecht lands in its week")
