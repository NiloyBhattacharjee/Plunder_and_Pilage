extends Node
## Autoload "Clock": game time in days since the start date.
## Everything that moves listens to `ticked`; daily upkeep and weather listen to `day_passed`.

signal ticked(delta_days: float)
signal day_passed(day: int)

const SPEEDS := [0.0, 1.0, 2.0, 4.0]

var day := 0.0  # fractional days since start
var speed_index := 1
var _resume_index := 1
var _start_unix: int


func _ready() -> void:
	_start_unix = Time.get_unix_time_from_datetime_string(Data.rules.time.start_date)


func _process(delta: float) -> void:
	if speed_index > 0:
		advance(delta * SPEEDS[speed_index] / Data.rules.time.seconds_per_day)


func advance(days: float) -> void:
	var before := int(day)
	day += days
	ticked.emit(days)
	for d in range(before + 1, int(day) + 1):
		day_passed.emit(d)


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	if speed_index > 0:
		_resume_index = speed_index


func toggle_pause() -> void:
	set_speed(0 if speed_index > 0 else _resume_index)


func date() -> Dictionary:
	return Time.get_date_dict_from_unix_time(_start_unix + int(day) * 86400)


func date_string() -> String:
	var d := date()
	var months := ["January", "February", "March", "April", "May", "June", "July",
		"August", "September", "October", "November", "December"]
	return "%d %s %d" % [d.day, months[d.month - 1], d.year]


func save_state() -> Dictionary:
	return {"day": day}


func load_state(d: Dictionary) -> void:
	day = d.day
	set_speed(0)
