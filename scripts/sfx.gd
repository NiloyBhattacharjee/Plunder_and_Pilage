extends Node
## Sound effects by name. Each name lists file-name prefixes under assets/audio/effects; every file that starts
## with one is a variation, and play() picks one at random (and nudges the pitch) so a repeated sound doesn't grate.
## An autoload that runs while the game is paused, so the Esc menu's buttons click too.
## Every button in the game clicks: buttons are caught as they enter the tree.

const DIR := "res://assets/audio/effects/"
const PP := "pirate_pack_vol_1/Pirate Pack Vol 1/"
const SOUNDS := {
	"cannon": [PP + "Misc Sfx/sfx_cannon_fire_", "cannon/cannon_fire."],
	"shot_hits": ["cannon/cannon_hit_ship_short", "cannon/cannon_hit_wall_no_splash", "cannon/cannon_hit."],
	"shot_misses": ["cannon/cannon_miss", "water surface explosion/WaterSurfaceExplosion0", PP + "Misc Sfx/sfx_splash_"],
	"gun_bursts": ["ExplosionMetal."],
	"break": ["ExplosionMetalGverb"],
	"musket": ["GunShot.", PP + "Misc Sfx/sfx_pistol_"],
	"blades": ["80-CC0-RPG-SFX/blade_", PP + "Misc Sfx/sfx_sword_swing_"],
	"draw_sword": [PP + "Misc Sfx/sfx_sword_unsheathe", PP + "Misc Sfx/sfx_sword_equip"],
	"rigging": [PP + "Misc Sfx/sfx_rope_pull_"],
	"ships_meet": ["Ship/ship_ram_ship_shortened"],
	"hammer": ["80-CC0-RPG-SFX/wood_"],
	"sinks": ["Ship/ship_destroyed_short"],
	"dice": ["accessory/sfx/die-one-roll-", "accessory/sfx/dice-two-roll-"],
	"coins": [PP + "Misc Sfx/sfx_coin_clink_", "accessory/sfx/coins-shake-", "80-CC0-RPG-SFX/item_coins_"],
	"plunder": [PP + "Misc Sfx/sfx_coin_spill_", "gold sack/gold_sack"],
	"anchor": ["80-CC0-RPG-SFX/chain_"],
	"wave": ["waves/wave_"],
	"click": ["80-CC0-RPG-SFX/wood_"],
	"deck": [PP + "Ambiences (Loops)/amb_deck_creaks"],
	"storm": [PP + "Ambiences (Loops)/amb_sea_storm."],
}

var _files := {}  # name -> every matching file path


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in SOUNDS:
		_files[id] = files(id)
		if _files[id].is_empty():
			push_warning("Sfx: no files for " + id)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_click):  # a button can leave and re-enter the tree
		n.pressed.connect(_click)


func _click() -> void:
	play("click", -14.0)


## The files a sound draws on, from its prefixes. Only audio Godot can import (not .flac).
static func files(id: String) -> Array:
	var out := []
	for prefix: String in SOUNDS[id]:
		var dir := DIR + prefix.get_base_dir()
		for f in ResourceLoader.list_directory(dir):
			if f.begins_with(prefix.get_file()) and f.get_extension() in ["ogg", "wav", "mp3"]:
				out.append(dir.path_join(f))
	return out


func play(id: String, volume_db := 0.0) -> void:
	if _files.get(id, []).is_empty():
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(_files[id].pick_random())
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.93, 1.07)
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


## A sound played after a moment, like a shot landing after the flash.
func play_after(seconds: float, id: String, volume_db := 0.0) -> void:
	get_tree().create_timer(seconds).timeout.connect(play.bind(id, volume_db))


## A looping ambience for `owner` (the world map, the battle): freed with it. Change its sound with set_loop().
func loop(owner: Node, id: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = volume_db
	p.finished.connect(p.play)
	owner.add_child(p)
	set_loop(p, id)
	return p


func set_loop(p: AudioStreamPlayer, id: String) -> void:
	if _files.get(id, []).is_empty() or (p.stream and p.stream.resource_path == _files[id][0]):
		return
	p.stream = load(_files[id][0])
	p.play()
