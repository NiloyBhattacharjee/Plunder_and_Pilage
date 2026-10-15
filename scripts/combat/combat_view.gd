extends Node2D
## The battle screen, tabletop style. Choose an action for each officer, roll, and read the dice in the log.
## The ships are drawn side by side, broadside to broadside, as far apart as the range band;
## whoever holds the weather gauge sits upwind (left). Space or Enter rolls.

signal finished(result: Dictionary)

const PUFF := preload("res://assets/fx/puff.png")
const BAND_GAP := [620.0, 420.0, 230.0, 90.0]

var battle := DiceCombat.new()
var enemy_data: Dictionary
var sprites: Array = []
var pickers := {}          # post -> OptionButton
var busy := false

@onready var camera: Camera2D = $Camera2D
@onready var dialog = $ChoiceDialog


func start(player_data: Dictionary, enemy: Dictionary, mode: String, _wind_dir: float, wind_strength: float) -> void:
	enemy_data = enemy
	battle.rng.randomize()
	var foe := enemy.duplicate(true)
	foe.party = DiceCombat.npc_party(enemy, battle.rng)
	battle.setup(DiceCombat.make_side(player_data), DiceCombat.make_side(foe), mode, wind_strength)
	var flags := [player_data.get("flag", "white"), Data.table("factions")[enemy.faction].flag]
	for i in 2:
		var sp: Node2D = load("res://scenes/ship_sprite.tscn").instantiate()
		add_child(sp)
		sp.setup(battle.sides[i].type, flags[i])
		sp.scale = Vector2.ONE * 0.8
		sprites.append(sp)
	camera.position = Vector2(0, 40)
	%Roll.pressed.connect(_roll)
	_log("[i]The %s %s. Your officers await your orders.[/i]" % [enemy.label, enemy.name])
	_refresh()


func _process(_delta: float) -> void:
	_place_ships()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER] and not busy and not dialog.visible:
		_roll()


# ---- orders ---------------------------------------------------------------

func _refresh() -> void:
	%Mine.text = _status(battle.sides[0], true)
	%Theirs.text = _status(battle.sides[1], false)
	var bands: Array = DiceCombat.cfg().bands
	var track := PackedStringArray()
	for b in bands.size():
		track.append("[ %s ]" % bands[b].to_upper() if b == battle.band else bands[b])
	%Info.text = "  —  ".join(track) + "        %s the weather gauge." % ("You hold" if battle.gauge == 0 else "They hold")
	_build_party()


func _build_party() -> void:
	var box: GridContainer = %Party
	var keep := {}
	for post in pickers:  # remember choices between rounds
		if is_instance_valid(pickers[post]) and pickers[post].selected >= 0:
			keep[post] = pickers[post].get_selected_metadata()
	UIKit.clear(box)
	pickers = {}
	var me: Dictionary = battle.sides[0]
	var posts: Array = ["captain"] + DiceCombat.cfg().order.filter(func(p): return p != "captain")
	for post in posts:
		var m: Dictionary = me.party.get(post, {})
		if m.is_empty():
			UIKit.icon(box, "", 36)
			UIKit.label(box, "%s: (vacant)" % _post_name(post), "Nobody holds this post, so it takes no action. Appoint officers in the crew screen.", Style.c("dim"))
			UIKit.label(box, "")
			UIKit.label(box, "")
			continue
		if m.id != "" and People.chars.has(m.id):
			box.add_child(Portrait.make(People.person(m.id), "captain" if post == "captain" else "officer", 36))
		else:
			UIKit.icon(box, "", 36)
		var skill: String = DiceCombat.cfg().post_skills[post]
		UIKit.label(box, "%s: %s%s" % [_post_name(post), m.name, " (wounded)" if m.get("wounded", false) else ""],
			"%s %d (%+d)" % [People.SKILL_NAMES.get(skill, skill), DiceCombat.value(m, skill), Dice.mod(DiceCombat.value(m, skill))])
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(330, 0)
		var can := battle.available(0, post)
		pick.add_item("(no action)")
		pick.set_item_metadata(0, "")
		for id in can:
			var chance := battle.odds(0, post, id)
			pick.add_item("%s  (%d%%)" % [can[id].name, int(round(chance * 100))])
			pick.set_item_metadata(pick.item_count - 1, id)
			pick.set_item_tooltip(pick.item_count - 1, can[id].description)
			if keep.get(post, "") == id:
				pick.select(pick.item_count - 1)
		if pick.selected <= 0 and pick.item_count > 1 and not keep.has(post):
			pick.select(_default_pick(post, pick))
		box.add_child(pick)
		pickers[post] = pick
		var desc := UIKit.label(box, "")
		pick.item_selected.connect(func(i): desc.text = _hint(post, pick.get_item_metadata(i)))
		desc.text = _hint(post, pick.get_selected_metadata())


func _default_pick(post: String, pick: OptionButton) -> int:
	var prefer := {"captain": "steady", "boatswain": "close", "master_gunner": "round", "navigator": "read_wind",
		"quartermaster": "arm", "carpenter": "plug", "surgeon": "tend"}
	for i in pick.item_count:
		if pick.get_item_metadata(i) == prefer.get(post, ""):
			return i
	return 1


func _hint(post: String, id: String) -> String:
	if id == "":
		return ""
	var a: Dictionary = DiceCombat.actions()[post][id]
	if a.has("ammo"):
		return "DC %d" % battle.gun_dc(0)
	if a.has("vs"):
		return "vs their %s" % _post_name(a.vs).to_lower()
	return "DC %d" % battle._dc_for(0, id, a) if a.get("dc", 0) > 0 or id in ["close", "open", "demand"] else ""


static func _post_name(post: String) -> String:
	return "Captain" if post == "captain" else Data.rules.officer_roles[post].name


func _status(s: Dictionary, mine: bool) -> String:
	var crew := "%d" % s.crew if mine else "about %d" % (int(s.crew / 5.0) * 5)
	var lines := PackedStringArray([
		"%s (%s)" % [s.name, Data.table("ships")[s.type].name],
		"Hull %d / %d   Sails %d / %d   Masts %d / %d" % [s.hull, s.stats.hull, s.sails, s.stats.sails, s.masts, s.stats.masts],
		"Crew %s   Guns %d   Morale %d" % [crew, s.guns_working, s.morale],
	])
	var trouble := PackedStringArray()
	if s.leak > 0: trouble.append("LEAKING")
	if s.fire > 0: trouble.append("ON FIRE")
	if s.rudder > 0: trouble.append("rudder damaged")
	if s.armed: trouble.append("boarders armed")
	if not trouble.is_empty():
		lines.append(", ".join(trouble))
	return "\n".join(lines)


# ---- a round ----------------------------------------------------------------

func _roll() -> void:
	if busy or battle.result != "":
		return
	busy = true
	%Roll.disabled = true
	var orders := {}
	for post in pickers:
		var id: String = pickers[post].get_selected_metadata()
		if id != "":
			orders[post] = id
	var entries := battle.play_round(orders)
	for e in entries:
		_show_entry(e)
		await get_tree().create_timer(0.35).timeout
	_refresh()
	busy = false
	%Roll.disabled = false
	if battle.result != "":
		_end()


func _show_entry(e: Dictionary) -> void:
	var who := "" if e.side < 0 else ("[color=#2b4a7a]You[/color] - " if e.side == 0 else "[color=#7a2e1c]Them[/color] - ")
	var text: String = who + e.text
	if not e.check.is_empty():
		text += "\n      " + Dice.describe(e.check)
		%DiceFace.text = str(e.check.roll)
		%DiceFace.add_theme_color_override("font_color", Style.c("good") if e.check.success else Style.c("bad"))
	_log(text)
	if e.post == "master_gunner" and e.side >= 0 and not e.check.is_empty():
		_gun_smoke(e.side, e.check.success)


func _log(text: String) -> void:
	%Log.append_text(text + "\n")


# ---- drawing ---------------------------------------------------------------

func _place_ships() -> void:
	if sprites.is_empty():
		return
	var gap: float = BAND_GAP[battle.band]
	sprites[battle.gauge].position = sprites[battle.gauge].position.lerp(Vector2(-gap / 2.0, 0), 0.08)
	sprites[1 - battle.gauge].position = sprites[1 - battle.gauge].position.lerp(Vector2(gap / 2.0, 0), 0.08)
	for i in 2:
		var s: Dictionary = battle.sides[i]
		sprites[i].set_state(s.hull / s.stats.hull, s.sails / s.stats.sails, 1, s.struck)


func _draw() -> void:
	var view := Rect2(camera.position - get_viewport_rect().size, get_viewport_rect().size * 2.0)
	draw_rect(view, Style.c("sea"))
	for x in range(-1200, 1300, 100):
		draw_line(Vector2(x, -800), Vector2(x, 800), Style.c("ink_faint"), 1.0)
	var font := Style.font("italic")
	var ink := Color(Style.c("ink"), 0.6)
	draw_string(font, Vector2(-80, -150), "wind", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	draw_line(Vector2(-90, -138), Vector2(10, -138), ink, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(20, -138), Vector2(5, -145), Vector2(5, -131)]), ink)
	for i in sprites.size():
		var s: Dictionary = battle.sides[i]
		draw_string(font, sprites[i].position + Vector2(-100, -100), s.name + (" (struck)" if s.struck else ""),
			HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Style.c("ink"))


func _gun_smoke(i: int, hit: bool) -> void:
	var from: Vector2 = sprites[i].position
	var to: Vector2 = sprites[1 - i].position
	var dir := (to - from).normalized()
	for k in 5:
		var p := from + Vector2(0, -40 + k * 20) + dir * 20.0
		_burst(p, dir, Color(Style.c("smoke"), 0.55), 5, 30.0, Vector2(20, 45), 1.6, Vector2(0.6, 1.4))
		_burst(p, dir, Style.c("flash"), 3, 20.0, Vector2(60, 110), 0.15, Vector2(0.2, 0.4))
	if hit:
		_burst(to, -dir, Color("#7a5230"), 20, 120.0, Vector2(60, 140), 0.6, Vector2(0.15, 0.3))
	else:
		_burst(to - dir * 60.0, Vector2.UP, Style.c("splash"), 16, 180.0, Vector2(30, 80), 0.6, Vector2(0.2, 0.45))


func _burst(pos: Vector2, dir: Vector2, color: Color, amount: int, spread: float, speed: Vector2, life: float, size: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = PUFF
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.damping_min = speed.x * 0.5
	p.damping_max = speed.y * 0.5
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


# ---- the end -----------------------------------------------------------------

func _end() -> void:
	var titles := {"enemy_struck": "She strikes her colours!", "player_struck": "You strike your colours",
		"enemy_sunk": "She goes down", "player_sunk": "Your ship is lost", "separated": "The ships part"}
	var texts := {
		"enemy_struck": "The %s is yours. Time to decide what to do with her." % enemy_data.name,
		"player_struck": "The fight is lost. The enemy boards to take what they want.",
		"enemy_sunk": "The %s slips beneath the waves, cargo and all." % enemy_data.name,
		"player_sunk": "The sea takes your ship.",
		"separated": "The distance grows until the %s is just a sail on the horizon." % enemy_data.name,
	}
	var me: Dictionary = battle.sides[0]
	if battle.result.ends_with("sunk"):
		var who := 1 if battle.result == "enemy_sunk" else 0
		_burst(sprites[who].position, Vector2.UP, Style.c("splash"), 40, 180.0, Vector2(20, 90), 1.2, Vector2(0.3, 0.7))
		var tw := create_tween().set_parallel()
		tw.tween_property(sprites[who], "modulate:a", 0.0, 1.8)
		tw.tween_property(sprites[who], "scale", sprites[who].scale * 0.7, 1.8)
		await tw.finished
	var text: String = texts[battle.result] + "\n\nRounds fought: %d.  Your casualties: %d.  Hull %d, sails %d." % [battle.round_no, me.casualties, me.hull, me.sails]
	if me.captain_wounded:
		text += "\nYour captain was wounded."
	await dialog.ask(titles[battle.result], text, [{"text": "Continue"}])
	finished.emit({"outcome": battle.result, "player": me, "enemy": battle.sides[1], "enemy_data": enemy_data})
