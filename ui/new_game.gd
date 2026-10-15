extends Control
## New-game screen: choose the captain's name, nationality and background, and name the ship.
## Background sets starting stats, skills, traits, money, ship, crew and how the nations regard you.

@onready var name_edit: LineEdit = %CaptainName
@onready var nation_pick: OptionButton = %Nationality
@onready var bg_pick: OptionButton = %Background
@onready var ship_edit: LineEdit = %ShipName


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
	%Start.pressed.connect(_start)
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
	_go({"name": name_edit.text.strip_edges(), "nationality": nation_pick.get_selected_metadata(),
		"background": bg_pick.get_selected_metadata(), "ship_name": ship_edit.text.strip_edges()})


func _go(cfg: Dictionary) -> void:
	WorldMap.start_config = cfg
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")
