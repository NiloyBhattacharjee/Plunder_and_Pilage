extends CanvasLayer
## Top-left panel: date, time speed, wind, sailing readout and supplies. Bottom-left: recent messages.

const MAX_MESSAGES := 5

var ship: Node2D
var _messages: PackedStringArray = []

@onready var info: Label = %Info
@onready var compass = %Compass
@onready var log_label: Label = %Log


func _ready() -> void:
	for i in Clock.SPEEDS.size():
		%Speeds.get_child(i).pressed.connect(Clock.set_speed.bind(i))


func _process(_delta: float) -> void:
	if ship == null or ship.wind.is_empty():
		return
	var s: Dictionary = ship.state
	var w: Dictionary = ship.wind
	var lines := PackedStringArray()
	lines.append(Clock.date_string() + ("   [PAUSED]" if Clock.speed_index == 0 else "   x%d" % Clock.SPEEDS[Clock.speed_index]))
	var weather: String = Data.rules.storms[w.storm].name if w.storm != "" else ("Calm" if Weather.calm else "Fair")
	lines.append("Wind: from %s, %s" % [Geo.compass_name(w.dir), weather])
	if ship.anchored_at != "":
		lines.append("At anchor: " + Data.table("ports")[ship.anchored_at].name)
	elif not ship.route.is_empty():
		var tack := ", tacking" if ship.sail_info.tacking else ""
		lines.append("Sailing %s, %.1f kn (%s%s)" % [Geo.compass_name(ship.heading), ship.speed_knots,
			Sailing.point_of_sail(ship.sail_info.off_wind), tack])
	else:
		lines.append("Hove to")
	lines.append("")
	lines.append("Hull %d / %d    Crew %d" % [s.hull, ship.stats.hull, s.crew])
	lines.append("Food %d (%d days)    Water %d (%d days)" % [s.food, ship.days_of("food"), s.water, ship.days_of("water")])
	lines.append("Gold %d" % s.gold + ("    Wages owed %d" % s.wages_owed if s.wages_owed > 0 else ""))
	info.text = "\n".join(lines)
	compass.wind_dir = w.dir
	compass.heading = ship.heading
	compass.queue_redraw()


func show_message(text: String) -> void:
	_messages.append("%s: %s" % [Clock.date_string(), text])
	if _messages.size() > MAX_MESSAGES:
		_messages.remove_at(0)
	log_label.text = "\n".join(_messages)
