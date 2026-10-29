extends Control
## New-game screen: choose when the game opens (data/bookmarks.json), the captain's name, nationality and
## background, and name the ship.
## Background sets starting stats, skills, traits, money, ship, crew and how the nations regard you.
## The second page builds the captain: looks, points into stats and skills, a focus and an optional flaw. Then the game
## opens on the night you took the ship (data/events/night.json), which decides the rest.

@onready var name_edit: LineEdit = %CaptainName
@onready var nation_pick: OptionButton = %Nationality
@onready var bg_pick: OptionButton = %Background
@onready var ship_edit: LineEdit = %ShipName

var _build := {}
var _focus := ""       # data/focus.json
var _cap := {}         # a stand-in captain for the looks preview
var _looks: LooksEditor
var _nick: OptionButton
var _title: Label
var _page: PanelContainer
var _sheet: VBoxContainer
var _ironman := CheckBox.new()
var _era := OptionButton.new()
var _hints := CheckBox.new()


func _ready() -> void:
	for id in Data.table("bookmarks"):
		if id.begins_with("_"):
			continue
		var bm: Dictionary = Data.table("bookmarks")[id]
		_era.add_item(bm.name + ("  (recommended)" if bm.get("recommended", false) else ""))
		_era.set_item_metadata(_era.item_count - 1, id)
		if bm.get("recommended", false):
			_era.select(_era.item_count - 1)
	_era.item_selected.connect(func(_i): _describe())
	var era_label := Label.new()
	era_label.text = "Start"
	var form: GridContainer = nation_pick.get_parent()
	var row := [era_label, _era, Control.new()]
	for i in row.size():  # the first row of the form
		form.add_child(row[i])
		form.move_child(row[i], i)
	for id in Data.table("nations"):
		nation_pick.add_item(Data.table("nations")[id].name)
		nation_pick.set_item_metadata(nation_pick.item_count - 1, id)
	for id in Data.table("backgrounds"):
		bg_pick.add_item(Data.table("backgrounds")[id].name)
		bg_pick.set_item_metadata(bg_pick.item_count - 1, id)
	nation_pick.item_selected.connect(func(_i): _random_name(); _describe())
	bg_pick.item_selected.connect(func(_i): _describe())
	%RandomName.pressed.connect(_random_name)
	%Start.text = "Next: your captain"
	%Start.pressed.connect(_captain_page)
	%Continue.pressed.connect(func(): _go({"load": true}))
	%Continue.disabled = SaveGame.latest() == ""
	_hints.text = "First-voyage hints"
	_hints.button_pressed = true
	_hints.tooltip_text = "A short word the first time you meet each part of the game."
	_ironman.text = "Ironman"
	_ironman.tooltip_text = "One save, written for you in every port. No reloading, and when the story ends, the save goes with it."
	for box in [_hints, _ironman]:  # beside the start button
		%Start.get_parent().add_child(box)
		%Start.get_parent().move_child(box, %Start.get_index())
	_random_name()
	ship_edit.text = Data.rules.ship_names[randi() % Data.rules.ship_names.size()]
	_describe()


func _random_name() -> void:
	name_edit.text = People.generate({"nationality": nation_pick.get_selected_metadata()}).name


func _describe() -> void:
	var bg: Dictionary = Data.table("backgrounds")[bg_pick.get_selected_metadata()]
	var nation: Dictionary = Data.table("nations")[nation_pick.get_selected_metadata()]
	var lines := PackedStringArray([bg.description, ""])
	var bonus := PackedStringArray()
	for k in bg.stats:
		bonus.append("%s %+d" % [People.SKILL_NAMES[k], bg.stats[k]])
	for k in bg.skills:
		bonus.append("%s %+d" % [People.SKILL_NAMES[k], bg.skills[k]])
	lines.append("Bonuses: " + ", ".join(bonus))
	lines.append("Traits: " + ", ".join(bg.traits.map(func(t): return Data.table("traits")[t].name)))
	lines.append("Starts with a %s, %d crew and %d gold." % [Data.table("ships")[bg.ship].name, bg.crew, bg.gold])
	var rel := PackedStringArray()
	for key in bg.relations:
		var f: String = nation.faction if key == "own" else key
		if f != "":
			rel.append("%s %+d" % [Data.table("factions")[f].name, bg.relations[key]])
	if not rel.is_empty():
		lines.append("Standing: " + ", ".join(rel))
	var port: String = bg.get("start_port", nation.start_port)
	lines.append("Starting port: " + Data.table("ports")[port].name)
	var bm: Dictionary = Data.table("bookmarks")[_era.get_selected_metadata()]
	var era := PackedStringArray([bm.text])
	for line in bm.now:
		era.append("  •  " + line)
	era.append("Suits: " + bm.suits)
	%Description.text = "\n".join(era) + "\n\n" + "\n".join(lines)
	$Panel/VBox/Subtitle.text = "The Caribbean, " + bm.date.left(4)


## The captain's name with a nickname in it, if one's chosen: Jack "Calico" Rackham.
func _full_name() -> String:
	var name := name_edit.text.strip_edges()
	var nick: String = _nick.get_selected_metadata() if _nick and _nick.selected > 0 else ""
	if nick == "" or name.find(" ") < 0:
		return name
	return '%s "%s" %s' % [name.get_slice(" ", 0), nick, name.substr(name.find(" ") + 1)]


func _start() -> void:
	var b := _build.duplicate(true)
	b.portrait = _cap.portrait
	_go({"name": _full_name(), "nationality": nation_pick.get_selected_metadata(),
		"background": bg_pick.get_selected_metadata(), "ship_name": ship_edit.text.strip_edges(), "build": b, "focus": _focus, "night": true, "bookmark": _era.get_selected_metadata(),
		"ironman": _ironman.button_pressed, "tutorial": _hints.button_pressed})


# ---- the captain: looks and build --------------------------------------------------

func _captain_page() -> void:
	$Panel.hide()
	_build = {"stats": {}, "skills": {}, "traits": [], "flaw": ""}
	_focus = ""
	_cap = People.generate({"nationality": nation_pick.get_selected_metadata()})
	_cap.name = name_edit.text
	_cap.background = bg_pick.get_selected_metadata()
	_cap.age = 28
	_cap.traits = []
	_cap.portrait = {"seed": randi(), "pick": {}}
	_page = PanelContainer.new()
	_page.set_anchors_preset(Control.PRESET_CENTER)
	_page.offset_left = -720
	_page.offset_right = 720
	_page.offset_top = -420
	_page.offset_bottom = 420
	add_child(_page)
	var v := VBoxContainer.new()
	_page.add_child(v)
	var head := UIKit.row(v)
	_title = UIKit.label(head, "Captain %s" % _cap.name)
	_title.theme_type_variation = &"Title"
	UIKit.label(head, "     Known as:  ")
	_nick = OptionButton.new()
	_nick.add_item("(no nickname)")
	_nick.set_item_metadata(0, "")
	for e in Data.table("bonds").captains.epithets + Data.table("bonds").get("player_epithets", []):
		_nick.add_item('"%s"' % e)
		_nick.set_item_metadata(_nick.item_count - 1, e)
	_nick.item_selected.connect(func(_i): _title.text = "Captain " + _full_name())
	head.add_child(_nick)
	UIKit.button(head, "  Roll a whole pirate  ", _roll_pirate, "A random face, a random pirate type, a nickname, a focus, and points spent for you. Change anything after.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	_looks = LooksEditor.new()
	_looks.preview_size = 256
	row.add_child(_looks)
	_looks.edit(_cap, "captain")
	_sheet = VBoxContainer.new()
	row.add_child(_sheet)
	_build_sheet()
	var buttons := UIKit.row(v)
	UIKit.button(buttons, "  Back  ", func():
		_page.queue_free()
		$Panel.show())
	UIKit.button(buttons, "  Set sail  ", _start)


func _build_sheet() -> void:
	UIKit.clear(_sheet)
	var bg: Dictionary = Data.table("backgrounds")[bg_pick.get_selected_metadata()]
	var g: Dictionary = Data.rules.growth.build
	var left := NewGame.build_points(_build)
	UIKit.label(_sheet, "Leadership: %d points left    Skills: %d points left" % [left.stats, left.skills],
		"Spend every point: nothing carries over. Background bonuses are already in. Nothing can start above %d." % g.max_start, Style.c("header"))
	var grid := UIKit.grid(_sheet, 4)
	for k in People.STATS + g.captain_skills:
		var pool := "stats" if k in People.STATS else "skills"
		var v := NewGame.build_value(bg, _build, k)
		var tip := "%s\n\nBase, plus %+d from your background." % [People.effect_text(k, v), bg[pool].get(k, 0)]
		UIKit.label(grid, People.SKILL_NAMES[k], tip)
		UIKit.button(grid, " - ", _spend.bind(pool, k, -1)).disabled = int(_build[pool].get(k, 0)) <= 0
		UIKit.label(grid, str(v), tip).custom_minimum_size.x = 30
		UIKit.button(grid, " + ", _spend.bind(pool, k, 1)).disabled = left[pool] <= 0 or v >= int(g.max_start)
	var officer: Array = People.SKILLS.filter(func(k): return not k in g.captain_skills)
	UIKit.label(_sheet, "Your officers' work: " + ", ".join(officer.map(func(k): return "%s %d" % [People.SKILL_NAMES[k], NewGame.build_value(bg, _build, k)])),
		"Hire a navigator, master gunner, carpenter and surgeon for these. Until you do, you cover the empty posts at half skill.\n\n"
		+ "\n\n".join(officer.map(func(k): return "%s: %s" % [People.SKILL_NAMES[k], Data.rules.people.skill_effects[k]])), Style.c("dim"))
	var traits := Data.table("traits")
	var taken: Array = bg.traits + _build.traits + ([_build.flaw] if _build.flaw != "" else [])
	UIKit.label(_sheet, "")
	UIKit.label(_sheet, "From your background: " + ", ".join(bg.traits.map(func(x): return traits[x].name)),
		"What kind of captain you are, you'll find out the night you take the ship.", Style.c("dim"))
	_focus_pick()
	_trait_pick("A flaw (+%d skill points)" % g.flaw_points, g.flaws.filter(func(x): return not x in bg.traits), _build.flaw, taken,
		func(id):
			_build.flaw = id
			_trim_skills())


## What the captain has given their life to: every day in it teaches, and in time brings its perks.
func _focus_pick() -> void:
	var row := UIKit.row(_sheet)
	UIKit.label(row, "Focus:  ", "Change it any time from the captain's sheet. Each focus teaches its perks over the months, in order.")
	var pick := OptionButton.new()
	pick.add_item("(choose later)")
	pick.set_item_metadata(0, "")
	for id in Data.table("focus"):
		if id.begins_with("_"):
			continue
		var f: Dictionary = Data.table("focus")[id]
		pick.add_item(f.name)
		pick.set_item_metadata(pick.item_count - 1, id)
		pick.set_item_tooltip(pick.item_count - 1, "%s\n\n%s" % [f.description, "\n".join(f.perks.map(func(p): return "%s: %s" % [Data.table("perks")[p].name, Data.table("perks")[p].description]))])
		if id == _focus:
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(i):
		_focus = pick.get_item_metadata(i)
		_build_sheet())
	row.add_child(pick)
	if _focus != "":
		var f: Dictionary = Data.table("focus")[_focus]
		UIKit.label(_sheet, "In time: " + ", then ".join(f.perks.map(func(p): return Data.table("perks")[p].name)), f.description, Style.c("dim"))


func _trait_pick(label: String, ids: Array, now: String, taken: Array, on_pick: Callable) -> void:
	var row := UIKit.row(_sheet)
	UIKit.label(row, label + ":  ")
	var pick := OptionButton.new()
	pick.add_item("(none)")
	pick.set_item_metadata(0, "")
	for id in ids:
		var td: Dictionary = Data.table("traits")[id]
		if id != now and People._conflicts(taken, id):
			continue
		pick.add_item(td.name)
		pick.set_item_metadata(pick.item_count - 1, id)
		var fx := PackedStringArray()
		for k in td.get("effects", {}):
			fx.append("%s %+d" % [People.SKILL_NAMES[k], td.effects[k]])
		pick.set_item_tooltip(pick.item_count - 1, td.description + ("
" + ", ".join(fx) if not fx.is_empty() else ""))
		if id == now:
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(i):
		on_pick.call(pick.get_item_metadata(i))
		_build_sheet())
	row.add_child(pick)


## Everything at once: a face, a pirate type, a nickname, and the points spent where they suit the background.
func _roll_pirate() -> void:
	_cap.portrait = {"seed": randi(), "pick": {}}
	var presets: Array = Data.table("portraits").presets.keys().filter(func(k): return not k.begins_with("_"))
	_looks.apply_preset(presets[randi() % presets.size()])
	_nick.select(randi() % _nick.item_count)
	_title.text = "Captain " + _full_name()
	_build = {"stats": {}, "skills": {}, "traits": [], "flaw": ""}
	var foci: Array = Data.table("focus").keys().filter(func(k): return not k.begins_with("_"))
	_focus = foci[randi() % foci.size()]
	var g: Dictionary = Data.rules.growth.build
	var bg: Dictionary = Data.table("backgrounds")[bg_pick.get_selected_metadata()]
	for pool in ["stats", "skills"]:
		var keys: Array = People.STATS if pool == "stats" else g.captain_skills
		var guard := 200
		while NewGame.build_points(_build)[pool] > 0 and guard > 0:
			guard -= 1
			var k: String = keys[randi() % keys.size()]
			if NewGame.build_value(bg, _build, k) < int(g.max_start):
				_build[pool][k] = int(_build[pool].get(k, 0)) + 1
	_build_sheet()


func _spend(pool: String, k: String, d: int) -> void:
	_build[pool][k] = int(_build[pool].get(k, 0)) + d
	_build_sheet()


## Dropping a flaw takes its points back: unspend skills until the books balance.
func _trim_skills() -> void:
	while NewGame.build_points(_build).skills < 0:
		var k: String = _build.skills.keys().filter(func(x): return _build.skills[x] > 0)[0]
		_build.skills[k] -= 1


func _go(cfg: Dictionary) -> void:
	WorldMap.start_config = cfg
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")
