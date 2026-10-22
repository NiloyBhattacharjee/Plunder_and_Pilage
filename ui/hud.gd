extends CanvasLayer
## The top bar, Paradox style: the captain on the left, the ship's resources as icon chips across the middle
## (every one explains itself in its tooltip), the wind, the date and the game speed on the right.
## Below it a slim row of actions and map modes; recent messages at the bottom left.

const MAX_MESSAGES := 6
const ICONS := "res://assets/icons/hud/"
const BAR_HEIGHT := 64

signal enter_port_pressed
signal crew_pressed
signal save_pressed
signal load_pressed
signal map_mode_changed(good: String)  # "" = political, "@standing" = your standing, "@routes" = merchant traffic, "@life" = how the towns are, "@regard" = what they remember of you
signal flag_changed(flag: String)
signal ambition_pressed

var ship: Node2D
var _messages: PackedStringArray = []
var _chips := {}          # name -> {box, value: Label}
var _portrait: Control
var _cap_name: Label
var _cap_line: Label
var _date: Label
var _wind: Label
var _speeds: Array = []
var _enter_port: Button
var _status: Label
var _modes: OptionButton
var _colours: OptionButton
var _compass: Control
var _log: Label
var _portrait_for := ""
var _ambition: Button
var _mute: Button

const SETTINGS := "user://settings.cfg"  # kept apart from saves: it's your machine's, not the game's


func _ready() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = BAR_HEIGHT
	var sb := StyleBoxTexture.new()
	sb.texture = load(Data.table("palette").pixel_ui + "topbar.png")
	sb.texture_margin_bottom = 12
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)

	# the captain
	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(48, 48)
	row.add_child(_portrait)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -4)
	who.custom_minimum_size = Vector2(190, 0)
	row.add_child(who)
	_cap_name = _label(who, 19, "title")
	_cap_line = _label(who, 14, "italic", Style.c("ink_soft"))
	_cap_line.clip_text = true
	_cap_name.clip_text = true
	_divider(row)

	# the ship's resources
	for k in ["gold", "crew", "morale", "food", "water", "hold", "hull", "sails", "notoriety", "contracts", "unrest", "sick"]:
		_chip(row, k)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# wind, date and speed
	_divider(row)
	_compass = load("res://ui/compass.gd").new()
	_compass.custom_minimum_size = Vector2(46, 46)
	_compass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_compass.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_compass)
	_wind = _label(row, 15, "italic", Style.c("ink_soft"))
	_wind.custom_minimum_size = Vector2(84, 0)
	_divider(row)
	var hg := _icon(row, "date", 30)
	hg.tooltip_text = "Space pauses. 1, 2 and 3 set the speed."
	_date = _label(row, 19, "title")
	_date.custom_minimum_size = Vector2(124, 0)
	for i in Clock.SPEEDS.size():
		var b := _small_button(row, "II" if i == 0 else str(i), "Pause (Space)" if i == 0 else "Speed %d (key %d)" % [i, i])
		b.add_theme_constant_override("h_separation", 0)
		b.custom_minimum_size = Vector2(30, 30)
		b.pressed.connect(Clock.set_speed.bind(i))
		_speeds.append(b)

	# the action row under the bar
	var actions := HBoxContainer.new()
	actions.position = Vector2(10, BAR_HEIGHT + 4)
	actions.add_theme_constant_override("separation", 6)
	add_child(actions)
	_enter_port = _small_button(actions, "Enter port", "Go ashore.")
	_enter_port.pressed.connect(enter_port_pressed.emit)
	_small_button(actions, "Crew & ship (C)", "Your captain, ship, officers, crew and the people you know.").pressed.connect(crew_pressed.emit)
	_small_button(actions, "Save (F5)", "Quick-save.").pressed.connect(save_pressed.emit)
	_small_button(actions, "Load (F9)", "Quick-load.").pressed.connect(load_pressed.emit)
	_mute = _small_button(actions, "", "Music and sound on or off.")
	_mute.pressed.connect(toggle_mute)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	_set_mute(cfg.get_value("audio", "muted", false))
	_ambition = _small_button(actions, "Ambition", "What your captain is striving for. Achieve it for a title, and sometimes a lasting edge.")
	_ambition.pressed.connect(ambition_pressed.emit)
	_modes = OptionButton.new()
	_modes.tooltip_text = "Map mode. Trade modes show the last prices you know for a good at each port, and how old they are."
	_modes.add_theme_font_size_override("font_size", 15)
	_modes.add_item("Map: Political")
	_modes.set_item_metadata(0, "")
	_modes.add_item("Map: Your standing")
	_modes.set_item_metadata(1, "@standing")
	_modes.add_item("Map: Trade routes")
	_modes.set_item_metadata(2, "@routes")
	_modes.add_item("Map: Town life")
	_modes.set_item_metadata(3, "@life")
	_modes.add_item("Map: Towns' regard")
	_modes.set_item_metadata(4, "@regard")
	for good in Data.table("goods"):
		_modes.add_item("Map: " + Data.table("goods")[good].name)
		_modes.set_item_metadata(_modes.item_count - 1, good)
	_modes.item_selected.connect(func(i): map_mode_changed.emit(_modes.get_item_metadata(i)))
	actions.add_child(_modes)
	_colours = OptionButton.new()
	_colours.tooltip_text = "The flag you fly. False colours get you close to prey and past hostile forts, at a cost to your honour.\nThe black flag and the red flag (no quarter) terrify merchants into striking."
	_colours.add_theme_font_size_override("font_size", 15)
	for id in Data.table("flags"):
		_colours.add_item("Colours: " + Data.table("flags")[id].name)
		_colours.set_item_metadata(_colours.item_count - 1, id)
	_colours.item_selected.connect(func(i): flag_changed.emit(_colours.get_item_metadata(i)))
	actions.add_child(_colours)
	_status = _label(actions, 15, "italic", Style.c("ink"))
	_status.add_theme_color_override("font_outline_color", Style.c("parchment_light"))
	_status.add_theme_constant_override("outline_size", 5)

	# messages, bottom left
	_log = Label.new()
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.offset_left = 12
	_log.offset_top = -140
	_log.offset_right = 900
	_log.offset_bottom = -10
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_theme_color_override("font_color", Style.c("ink"))
	_log.add_theme_color_override("font_outline_color", Style.c("parchment_light"))
	_log.add_theme_constant_override("outline_size", 5)
	add_child(_log)


# ---- building blocks --------------------------------------------------------

func _label(parent: Node, size: int, font := "body", color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Style.font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color if color.a > 0.0 else Style.c("ink"))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(l)
	return l


func _icon(parent: Node, name: String, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(ICONS + name + ".png") if ResourceLoader.exists(ICONS + name + ".png") else load("res://assets/icons/goods/%s.png" % name)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(r)
	return r


## An icon and a number, with its explanation as the tooltip.
func _chip(parent: Node, name: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.custom_minimum_size = Vector2(0, 44)
	parent.add_child(box)
	_icon(box, name, 30)
	var v := _label(box, 18, "body")
	v.custom_minimum_size = Vector2(28, 0)
	_chips[name] = {"box": box, "value": v}


func _divider(parent: Node) -> void:
	var d := ColorRect.new()
	d.color = Color(Style.c("ink"), 0.35)
	d.custom_minimum_size = Vector2(1, 40)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(d)


## Mutes the Master bus (map and battle music alike) and remembers it for next time.
func toggle_mute() -> void:
	_set_mute(not AudioServer.is_bus_mute(0))
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "muted", AudioServer.is_bus_mute(0))
	cfg.save(SETTINGS)


func _set_mute(on: bool) -> void:
	AudioServer.set_bus_mute(0, on)
	_mute.text = "Sound off (M)" if on else "Sound on (M)"


func _small_button(parent: Node, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b


func _show_chip(name: String, text: String, tip: String, color := Color(0, 0, 0, 0), show := true) -> void:
	var c: Dictionary = _chips[name]
	c.box.visible = show
	c.value.text = text
	c.value.add_theme_color_override("font_color", color if color.a > 0.0 else Style.c("ink"))
	c.box.tooltip_text = tip


# ---- every frame ------------------------------------------------------------

func _process(_delta: float) -> void:
	if ship == null or ship.wind.is_empty():
		return
	var s: Dictionary = ship.state
	var st: Dictionary = ship.stats
	var w: Dictionary = ship.wind
	var cap := ShipStats.captain(s)

	if _portrait_for != s.captain:  # a new captain: a new face in the corner
		_portrait_for = s.captain
		for ch in _portrait.get_children():
			ch.queue_free()
		_portrait.add_child(Portrait.make(cap, "captain", 48))
	_portrait.tooltip_text = People.describe(cap)
	_cap_name.text = "Capt. " + cap.name
	Ambitions.ensure(s)
	_cap_name.tooltip_text = People.describe(cap) + ("\n\nKnown as: " + ", ".join(cap.titles.map(func(id): return Ambitions.table()[id].title)) if not cap.titles.is_empty() else "")
	var ctx := {"s": s, "stats": st, "port": ship.anchored_at, "storm": false}
	if cap.ambition.is_empty():
		_ambition.text = "Choose an ambition!"
		_ambition.modulate = Color(1, 1, 1, 0.75 + 0.25 * sin(Time.get_ticks_msec() / 300.0))  # a gentle pulse until you do
	else:
		_ambition.text = "Ambition: " + Ambitions.summary(s, ctx)
		_ambition.modulate = Color.WHITE
	_cap_line.text = "%s %s.  %s" % [Data.table("ships")[s.type].name, s.name, Career.status_text(s)]

	var u: Dictionary = Data.rules.upkeep
	var officers: int = s.officers.size()
	_show_chip("gold", "%d" % s.gold, "Gold %d\nDaily cost %s: wages %s, ship upkeep %d.%s" % [s.gold, Market.fmt(ShipStats.daily_cost(s, st)),
		Market.fmt((s.crew.size() - officers) * u.wage_per_crew + officers * u.wage_per_crew * u.officer_wage_mult), st.upkeep,
		"\nWages owed: %d. The crew notice." % s.wages_owed if s.wages_owed > 0 else ""],
		Style.c("bad") if s.wages_owed > 0 else Color(0, 0, 0, 0))
	var need := ShipStats.crew_needed(s, st)
	var able := Crew.able(s)
	_show_chip("crew", "%d" % ShipStats.headcount(s), "Crew %d (needs %d to sail well, berths for %d).\n%d able to work.%s" % [ShipStats.headcount(s), need, st.crew_max, able,
		"\nShort-handed: the ship sails slower." if able < need else ""], Style.c("bad") if able < need else Color(0, 0, 0, 0))
	var mood := Crew.morale(s, st)
	_show_chip("morale", "%d" % mood.value, mood.text, Style.c("bad") if mood.value < 30 else (Style.c("good") if mood.value >= 60 else Color(0, 0, 0, 0)))
	for supply in ["food", "water"]:
		var days: float = ship.days_of(supply)
		_show_chip(supply, "%dd" % mini(int(days), 999), "%s %d, %d days for %d mouths." % [supply.capitalize(), s.cargo.get(supply, 0), days, ShipStats.headcount(s)],
			Style.c("bad") if days < 7 else Color(0, 0, 0, 0))
	_show_chip("hold", "%d/%d" % [Market.cargo_used(s.cargo), ship.capacity()], "Hold %d of %d tons." % [Market.cargo_used(s.cargo), ship.capacity()]
		+ ("\nPrizes in company: " + ", ".join(s.prizes.map(func(p): return p.name)) if not s.prizes.is_empty() else ""))
	var hull_pct := int(s.hull / st.hull * 100)
	_show_chip("hull", "%d%%" % hull_pct, "Hull %d of %d. Fouling %d%%: careen at a shipyard to clean her." % [s.hull, st.hull, int(s.fouling * 100)],
		Style.c("bad") if hull_pct < 50 else Color(0, 0, 0, 0))
	var sail_pct := int(s.sails / st.sails * 100)
	_show_chip("sails", "%d%%" % sail_pct, "Sails %d of %d." % [s.sails, st.sails] + ("\n" + ship.speed_text if not ship.route.is_empty() else ""),
		Style.c("bad") if sail_pct < 50 else Color(0, 0, 0, 0))
	var rep: Dictionary = s.reputation
	_show_chip("notoriety", "%d" % rep.notoriety, "Notoriety %d: how widely your name is known.\nHonour %+d, fear %+d.\n%s\n%s" % [rep.notoriety, rep.honour, rep.fear, Career.status_text(s), Career.bounty_text(s)],
		Style.c("bad") if Career.wanted(s) else Color(0, 0, 0, 0))
	_show_chip("contracts", "%d" % Contracts.active.size(), "Contracts:\n" + ("\n".join(Contracts.active.map(func(c): return Contracts.summary(c))) if not Contracts.active.is_empty() else "None."),
		Color(0, 0, 0, 0), not Contracts.active.is_empty())
	_show_chip("unrest", Crew.stage_name(s), "Unrest among the crew: %s.\nSee the crew screen." % Crew.stage_name(s).to_lower(), Style.c("bad"), s.unrest.stage > 0)
	var sick := Crew.sick_count(s)
	_show_chip("sick", "%d" % sick, "%d sick. They eat, but can't work." % sick, Style.c("bad"), sick > 0)

	var weather: String = Data.rules.storms[w.storm].name if w.storm != "" else ("Calm" if Weather.calm else "Fair")
	_wind.text = "%s wind\n%s" % [Geo.compass_name(w.dir), weather]
	_wind.tooltip_text = "Wind from the %s, %s.%s" % [Geo.compass_name(w.dir), weather.to_lower(), "\n" + ship.speed_text if not ship.route.is_empty() else ""]
	_compass.wind_dir = w.dir
	_compass.heading = ship.heading
	_compass.tooltip_text = _wind.tooltip_text
	_compass.queue_redraw()
	_date.text = Clock.date_string()
	for i in _speeds.size():
		_speeds[i].disabled = Clock.speed_index == i

	_enter_port.visible = ship.anchored_at != ""
	var base: String = ship.get_parent().at_base if ship.get_parent() and "at_base" in ship.get_parent() else ""
	if base != "" and ship.route.is_empty():
		_status.text = "At anchor in %s%s" % [Bases.cove(base).name, " (your base)" if Bases.bases.has(base) else ""]
	elif ship.anchored_at != "":
		_status.text = "At anchor in " + Data.table("ports")[ship.anchored_at].name
	elif not ship.route.is_empty():
		_status.text = "Sailing %s, %.1f knots, %s%s" % [Geo.compass_name(ship.heading), ship.speed_knots,
			Sailing.point_of_sail(ship.sail_info.off_wind), ", tacking" if ship.sail_info.tacking else ""]
	else:
		_status.text = "Hove to"
	if _colours.get_selected_metadata() != s.get("flag", "white"):
		for i in _colours.item_count:
			if _colours.get_item_metadata(i) == s.get("flag", "white"):
				_colours.select(i)


func show_message(text: String) -> void:
	_messages.append("%s: %s" % [Clock.date_string(), text])
	if _messages.size() > MAX_MESSAGES:
		_messages.remove_at(0)
	if _log:
		_log.text = "\n".join(_messages)
