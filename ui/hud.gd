extends CanvasLayer
## Top-left panel: date, time speed, wind, sailing readout and supplies. Bottom-left: recent messages.

const MAX_MESSAGES := 6

signal enter_port_pressed
signal crew_pressed
signal save_pressed
signal load_pressed
signal map_mode_changed(good: String)  # "" = political

var ship: Node2D
var _messages: PackedStringArray = []

@onready var info: Label = %Info
@onready var compass = %Compass
@onready var log_label: Label = %Log


func _ready() -> void:
	for i in Clock.SPEEDS.size():
		%Speeds.get_child(i).pressed.connect(Clock.set_speed.bind(i))
	%EnterPort.pressed.connect(enter_port_pressed.emit)
	%Crew.pressed.connect(crew_pressed.emit)
	info.mouse_filter = Control.MOUSE_FILTER_PASS  # so the speed breakdown tooltip shows
	%Save.pressed.connect(save_pressed.emit)
	%Load.pressed.connect(load_pressed.emit)
	var modes: OptionButton = %MapMode
	modes.add_item("Map: Political")
	modes.set_item_metadata(0, "")
	for good in Data.table("goods"):
		modes.add_item("Map: Trade - " + Data.table("goods")[good].name)
		modes.set_item_metadata(modes.item_count - 1, good)
	modes.item_selected.connect(func(i): map_mode_changed.emit(modes.get_item_metadata(i)))


func _process(_delta: float) -> void:
	if ship == null or ship.wind.is_empty():
		return
	var s: Dictionary = ship.state
	var w: Dictionary = ship.wind
	%EnterPort.visible = ship.anchored_at != ""
	var lines := PackedStringArray()
	lines.append(Clock.date_string() + ("   [PAUSED]" if Clock.speed_index == 0 else "   x%d" % Clock.SPEEDS[Clock.speed_index]))
	lines.append("Captain %s, %s %s" % [ShipStats.captain(s).name, Data.table("ships")[s.type].name, s.name])
	var weather: String = Data.rules.storms[w.storm].name if w.storm != "" else ("Calm" if Weather.calm else "Fair")
	lines.append("Wind: from %s, %s" % [Geo.compass_name(w.dir), weather])
	info.tooltip_text = ship.speed_text if not ship.route.is_empty() else ""
	if ship.anchored_at != "":
		lines.append("At anchor: " + Data.table("ports")[ship.anchored_at].name)
	elif not ship.route.is_empty():
		var tack := ", tacking" if ship.sail_info.tacking else ""
		lines.append("Sailing %s, %.1f kn (%s%s)" % [Geo.compass_name(ship.heading), ship.speed_knots,
			Sailing.point_of_sail(ship.sail_info.off_wind), tack])
	else:
		lines.append("Hove to")
	lines.append("")
	lines.append("Hull %d / %d   Sails %d / %d   Fouling %d%%" % [s.hull, ship.stats.hull, s.sails, ship.stats.sails, int(s.fouling * 100)])
	lines.append("Crew %d (needs %d, berths %d)" % [ShipStats.headcount(s), ShipStats.crew_needed(s, ship.stats), ship.stats.crew_max])
	lines.append("Food %d (%d days)    Water %d (%d days)" % [s.cargo.get("food", 0), ship.days_of("food"), s.cargo.get("water", 0), ship.days_of("water")])
	lines.append("Hold %d / %d tons" % [Market.cargo_used(s.cargo), ship.capacity()] + ("   Prizes: " + ", ".join(s.prizes.map(func(p): return p.name)) if not s.prizes.is_empty() else ""))
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
