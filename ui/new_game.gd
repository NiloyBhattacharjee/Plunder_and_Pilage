extends Control
## New-game screen: choose the captain's name, nationality and background, and name the ship.
## Background sets starting stats, skills, traits, money, ship, crew and how the nations regard you.
## The second page builds the captain: looks, points into stats and skills, an extra trait and an optional flaw.

@onready var name_edit: LineEdit = %CaptainName
@onready var nation_pick: OptionButton = %Nationality
@onready var bg_pick: OptionButton = %Background
@onready var ship_edit: LineEdit = %ShipName

var _build := {}
var _cap := {}         # a stand-in captain for the looks preview
var _page: PanelContainer
var _sheet: VBoxContainer


func _ready() -> void:
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
	%Continue.disabled = not FileAccess.file_exists(SaveGame.QUICKSAVE)
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
	%Description.text = "\n".join(lines)


func _start() -> void:
	var b := _build.duplicate(true)
	b.portrait = _cap.portrait
	_go({"name": name_edit.text.strip_edges(), "nationality": nation_pick.get_selected_metadata(),
		"background": bg_pick.get_selected_metadata(), "ship_name": ship_edit.text.strip_edges(), "build": b})


# ---- the captain: looks and build --------------------------------------------------

func _captain_page() -> void:
	$Panel.hide()
	_build = {"stats": {}, "skills": {}, "traits": [], "flaw": ""}
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
	var title := UIKit.label(v, "Captain %s" % _cap.name)
	title.theme_type_variation = &"Title"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var looks := LooksEditor.new()
	row.add_child(looks)
	looks.edit(_cap, "captain")
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
	for k in People.STATS + People.SKILLS:
		var pool := "stats" if k in People.STATS else "skills"
		var v := NewGame.build_value(bg, _build, k)
		UIKit.label(grid, People.SKILL_NAMES[k], "Base, plus %+d from your background." % (bg[pool].get(k, 0)))
		UIKit.button(grid, " - ", _spend.bind(pool, k, -1)).disabled = int(_build[pool].get(k, 0)) <= 0
		UIKit.label(grid, str(v)).custom_minimum_size.x = 30
		UIKit.button(grid, " + ", _spend.bind(pool, k, 1)).disabled = left[pool] <= 0 or v >= int(g.max_start)
	var traits := Data.table("traits")
	var taken: Array = bg.traits + _build.traits + ([_build.flaw] if _build.flaw != "" else [])
	UIKit.label(_sheet, "")
	UIKit.label(_sheet, "From your background: " + ", ".join(bg.traits.map(func(x): return traits[x].name)), "", Style.c("dim"))
	_trait_pick("An extra trait", traits.keys().filter(func(x): return traits[x].pools.has("crew") and not x in g.flaws and not x in bg.traits),
		_build.traits[0] if not _build.traits.is_empty() else "", taken, func(id): _build.traits = [] if id == "" else [id])
	_trait_pick("A flaw (+%d skill points)" % g.flaw_points, g.flaws.filter(func(x): return not x in bg.traits), _build.flaw, taken,
		func(id):
			_build.flaw = id
			_trim_skills())


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
