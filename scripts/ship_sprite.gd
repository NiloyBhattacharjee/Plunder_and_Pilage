extends Node2D
## A ship drawn from swappable layers: hull (clean or damaged), sails (furled, half, full, torn) and flag.
## Paths come from data: ships.json "art" folder and flags.json. Points up (north) at rotation 0.
## Replace the PNGs in assets/ships/<type>/ with real art and nothing here changes.

const SAIL_STATES := ["furled", "half", "full"]

var art := ""
var _key := ""


func setup(type_id: String, flag_id: String) -> void:
	art = Data.table("ships")[type_id].art
	$Hull.texture = load(art.path_join("hull.png"))
	$Sails.texture = load(art.path_join("sails_half.png"))
	set_flag(flag_id)
	_key = ""


## Flags are gameplay (nations, the black flag, false colours), so they're their own layer.
func set_flag(flag_id: String) -> void:
	$Flag.visible = flag_id != ""
	if flag_id != "":
		$Flag.texture = load(Data.table("flags")[flag_id].path)
		var length: float = $Hull.texture.get_height()
		$Flag.position = Vector2(0, length * 0.42)  # at the stern, streaming aft
		$Flag.rotation = PI / 2.0
		$Flag.offset = Vector2($Flag.texture.get_width() / 2.0, 0)


## Hull damaged below half strength; sails follow the sail setting (0-2) and tear when badly hit.
func set_state(hull_frac: float, sails_frac: float, sail_setting: int, struck := false) -> void:
	var sails: String = SAIL_STATES[clampi(sail_setting, 0, 2)]
	if sail_setting > 0 and sails_frac < 0.4:
		sails = "torn"
	var hull := "hull_damaged.png" if hull_frac < 0.5 else "hull.png"
	var key := hull + sails + str(struck)
	if key == _key:
		return
	_key = key
	$Hull.texture = load(art.path_join(hull))
	$Sails.texture = load(art.path_join("sails_%s.png" % sails))
	if struck:
		$Flag.visible = false  # striking the colours
