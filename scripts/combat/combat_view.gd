extends Node2D
## The battle scene: draws the sim, takes your orders, runs boarding, and reports the outcome.
## Controls: A/D (or arrows) steer, W/S sails, Q/E fire port/starboard, 1/2/3 ammo, B board, Space pause.

signal finished(result: Dictionary)

const SPEEDS := [0.0, 1.0, 2.0]

var sim := CombatSim.new()
var speed_index := 1
var effects: Array = []  # {kind, from, to, pos, text, age, color}
var enemy_data: Dictionary
var ending := false
var sprites: Array = []  # ShipSprite per sim ship
const PUFF := preload("res://assets/fx/puff.png")

@onready var camera: Camera2D = $Camera2D
@onready var dialog = $ChoiceDialog


func start(player_data: Dictionary, enemy: Dictionary, mode: String, wind_dir: float, wind_strength: float) -> void:
	enemy_data = enemy
	sim.rng.randomize()
	sim.setup(CombatSim.make_ship(player_data), CombatSim.make_ship(enemy), wind_dir, wind_strength, mode)
	var flags := [player_data.get("flag", "white"), Data.table("factions")[enemy.faction].flag]
	for i in 2:
		var sp: Node2D = load("res://scenes/ship_sprite.tscn").instantiate()
		add_child(sp)
		sp.setup(sim.ships[i].type, flags[i])
		sp.scale = Vector2.ONE * 0.6
		sprites.append(sp)
	_build_hud()
	camera.position = sim.ships[0].pos


func _process(delta: float) -> void:
	if not ending:
		_steer()
		sim.step(delta * SPEEDS[speed_index])
		for ev in sim.events:
			_effect(ev)
		sim.events.clear()
		if sim.result == "boarding":
			ending = true
			_boarding()
		elif sim.result != "":
			ending = true
			_end()
	for i in sprites.size():
		var s: Dictionary = sim.ships[i]
		sprites[i].position = s.pos
		sprites[i].rotation = deg_to_rad(s.heading)
		sprites[i].set_state(s.hull / s.stats.hull, s.sails / s.stats.sails, s.sail_setting, s.struck)
	for e in effects:
		e.age += delta
	effects = effects.filter(func(e): return e.age < 1.5)
	_fit_camera(delta)
	_update_hud()
	queue_redraw()


func _steer() -> void:
	var me: Dictionary = sim.ships[0]
	me.helm = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): me.helm -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): me.helm += 1.0


func _unhandled_input(event: InputEvent) -> void:
	if ending or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var me: Dictionary = sim.ships[0]
	match event.keycode:
		KEY_W, KEY_UP: me.sail_setting = mini(2, me.sail_setting + 1)
		KEY_S, KEY_DOWN: me.sail_setting = maxi(0, me.sail_setting - 1)
		KEY_Q: sim.fire(me, "port")
		KEY_E: sim.fire(me, "starboard")
		KEY_1: sim.set_ammo(me, "round")
		KEY_2: sim.set_ammo(me, "chain")
		KEY_3: sim.set_ammo(me, "grape")
		KEY_B: _try_board()
		KEY_SPACE: speed_index = 0 if speed_index > 0 else 1


func _try_board() -> void:
	if not sim.board(0):
		_note_text("Too far or too fast to board: get within %d and match her speed." % Data.rules.combat.board_distance)


func _effect(ev: Dictionary) -> void:
	match ev.kind:
		"broadside":
			var who := "Your" if ev.who == 0 else "Their"
			var color := Color(1.0, 0.85, 0.3) if ev.hits > 0 else Color(0.9, 0.9, 0.9)
			effects.append({"kind": "shot", "from": ev.from, "to": ev.to, "age": 0.0, "color": color})
			effects.append({"kind": "text", "pos": ev.to, "age": 0.0, "color": Style.c("ink"),
				"text": "%d hits" % ev.hits if ev.hits > 0 else "miss"})
			_log("%s broadside (%s, %d guns): %d hits." % [who, Data.rules.combat.ammo[ev.ammo].name.to_lower(), ev.guns, ev.hits])
			_gun_smoke(sim.ships[ev.who], ev.to, ev.guns)
			if ev.hits > 0:
				_burst(ev.to, Vector2.ZERO, Color("#7a5230"), mini(ev.hits * 2, 30), 180.0, Vector2(60, 140), 0.6, Vector2(0.15, 0.3))
			else:
				_burst(ev.to, Vector2.ZERO, Style.c("splash"), 14, 180.0, Vector2(30, 80), 0.5, Vector2(0.2, 0.45))
		"note":
			effects.append({"kind": "text", "pos": ev.pos + Vector2(0, -30), "age": 0.0, "color": Style.c("bad"), "text": ev.text})
			_log(("Enemy: " if ev.who == 1 else "You: ") + ev.text)


func _note_text(text: String) -> void:
	_log(text)


# ---- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var view := Rect2(camera.position - get_viewport_rect().size / camera.zoom, get_viewport_rect().size / camera.zoom * 2.0)
	draw_rect(view, Style.c("sea"))
	var step := 100.0
	var x := floorf(view.position.x / step) * step
	while x < view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), Style.c("ink_faint"), 1.0)
		x += step
	var y := floorf(view.position.y / step) * step
	while y < view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), Style.c("ink_faint"), 1.0)
		y += step

	var me: Dictionary = sim.ships[0]
	var them: Dictionary = sim.ships[1]
	_draw_arcs(me, Color(0.2, 0.5, 0.3), them)
	_draw_arcs(them, Color(0.7, 0.2, 0.2), me)
	_draw_ship(me, Color("#6b3d1a"))
	_draw_ship(them, Color(Data.table("factions")[enemy_data.faction].color))
	for e in effects:
		var a: float = 1.0 - e.age / 1.5
		if e.kind == "shot":
			draw_line(e.from, e.to, Color(e.color, a), 2.0)
		else:
			draw_string(ThemeDB.fallback_font, e.pos - Vector2(50, e.age * 30), e.text, HORIZONTAL_ALIGNMENT_CENTER, 100, 16, Color(e.color, a))


func _draw_arcs(s: Dictionary, color: Color, target: Dictionary) -> void:
	var arc: float = Data.rules.combat.broadside_arc
	var r := CombatSim.gun_range(s)
	for side in ["port", "starboard"]:
		var centre: float = s.heading + 90.0 * CombatSim.SIDE_SIGN[side]
		var pts := PackedVector2Array([s.pos])
		for i in 9:
			pts.append(s.pos + Geo.from_bearing(centre - arc + arc * 2.0 * i / 8.0) * r)
		var ready: bool = s.reload[side] <= 0.0
		var bears: bool = CombatSim.bearing_side(s, target.pos) == side and s.pos.distance_to(target.pos) <= r
		var alpha := 0.22 if ready and bears else (0.1 if ready else 0.04)
		draw_colored_polygon(pts, Color(color, alpha))


## Cannon smoke rolling off the firing side, with muzzle flashes along the hull.
func _gun_smoke(s: Dictionary, aim: Vector2, guns: int) -> void:
	var dir: Vector2 = (aim - s.pos).normalized()
	var fwd := Geo.from_bearing(s.heading)
	var length: float = sprites[sim.ships.find(s)].get_node("Hull").texture.get_height() * 0.6 * 0.8
	for i in mini(guns, 6):
		var p: Vector2 = s.pos + fwd * lerpf(-length / 2.0, length / 2.0, (i + 0.5) / mini(guns, 6)) + dir * 8.0
		_burst(p, dir, Color(Style.c("smoke"), 0.55), 5, 30.0, Vector2(15, 35), 1.6, Vector2(0.6, 1.4))
		_burst(p, dir, Style.c("flash"), 3, 20.0, Vector2(60, 110), 0.15, Vector2(0.2, 0.4))


## A one-shot puff of particles (Godot's CPUParticles2D) that cleans itself up.
func _burst(pos: Vector2, dir: Vector2, color: Color, amount: int, spread: float, speed: Vector2, life: float, size: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = PUFF
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.direction = dir if dir != Vector2.ZERO else Vector2.RIGHT
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


## Name labels above each ship (the ships themselves are ShipSprite nodes).
func _draw_ship(s: Dictionary, _color: Color) -> void:
	var length: float = sprites[sim.ships.find(s)].get_node("Hull").texture.get_height() * 0.6
	var label := "%s%s" % [s.name, " (struck)" if s.struck else ""]
	draw_string(Style.font("italic"), s.pos + Vector2(-90, -length * 0.6 - 8), label, HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Style.c("ink"))


func _fit_camera(delta: float) -> void:
	var a: Vector2 = sim.ships[0].pos
	var b: Vector2 = sim.ships[1].pos
	camera.position = camera.position.lerp((a + b) / 2.0, minf(1.0, delta * 3.0))
	var vp := get_viewport_rect().size
	var span := maxf(absf(a.x - b.x) / vp.x, absf(a.y - b.y) / (vp.y * 0.55)) * 1.5  # the HUD covers ~45% of the height
	var z := clampf(1.0 / maxf(span, 0.001), 0.35, 1.4)
	camera.zoom = camera.zoom.lerp(Vector2(z, z), minf(1.0, delta * 2.0))


# ---- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var c: Dictionary = Data.rules.combat
	var row := %Controls
	for ammo in ["round", "chain", "grape"]:
		var b := UIKit.button(row, c.ammo[ammo].name, func(): sim.set_ammo(sim.ships[0], ammo),
			"%s\nSwitching shot means reloading both broadsides." % c.ammo[ammo].description)
		b.name = "ammo_" + ammo
	for i in 3:
		UIKit.button(row, c.sail_settings[i].name, func(): sim.ships[0].sail_setting = i,
			["No way on: you'll drift and barely turn.", "Fighting canvas: slower, guns fully crewed.",
			"All sail: fastest, but hands aloft slow your reloading (x%.1f)." % c.sail_settings[2].reload][i])
	for preset in c_roles():
		var p: Dictionary = Data.rules.crew_roles.presets[preset]
		UIKit.button(row, p.name, func(): sim.set_roles(sim.ships[0], preset),
			"%s\nSailors %d%%, gunners %d%%, marines %d%%. Re-stationing men restarts your reloading." % [
			p.description, p.sailors * 100, p.gunners * 100, p.marines * 100])
	var row2 := %Controls2
	UIKit.button(row2, "Fire port (Q)", func(): sim.fire(sim.ships[0], "port"))
	UIKit.button(row2, "Fire starboard (E)", func(): sim.fire(sim.ships[0], "starboard"))
	UIKit.button(row2, "Board (B)", _try_board, "Close alongside and match her speed first.")
	UIKit.button(row2, "Strike your colours", func(): sim.strike(0), "Surrender. They'll strip your hold and take half your gold.")
	UIKit.button(row2, "Pause", func(): speed_index = 0)
	UIKit.button(row2, "1x", func(): speed_index = 1)
	UIKit.button(row2, "2x", func(): speed_index = 2)


static func c_roles() -> Array:
	return Data.rules.crew_roles.presets.keys()


func _update_hud() -> void:
	var me: Dictionary = sim.ships[0]
	var them: Dictionary = sim.ships[1]
	%Mine.text = _status(me, true)
	%Theirs.text = _status(them, false)
	%Info.text = "Distance %d (escape at %d)   Wind from %s   %s" % [sim.distance(), Data.rules.combat.escape_distance,
		Geo.compass_name(sim.wind_dir), "PAUSED" if speed_index == 0 else "x%d" % SPEEDS[speed_index]]
	%Compass.wind_dir = sim.wind_dir
	%Compass.heading = me.heading
	%Compass.queue_redraw()


func _status(s: Dictionary, mine: bool) -> String:
	var crew := "%d" % s.crew if mine else "about %d" % (int(s.crew / 5.0) * 5)
	var lines := PackedStringArray([
		"%s (%s)" % [s.name, Data.table("ships")[s.type].name],
		"Hull %d / %d   Sails %d / %d   Masts %d / %d" % [s.hull, s.stats.hull, s.sails, s.stats.sails, s.masts, s.stats.masts],
		"Crew %s   Guns %d   Morale %d" % [crew, s.guns_working, s.morale],
		"Speed %.1f kn   %s   %s" % [s.speed / Data.rules.combat.px_per_knot, Data.rules.combat.sail_settings[s.sail_setting].name,
			Data.rules.combat.ammo[s.ammo].name],
	])
	if mine:
		lines.append("Port %s   Starboard %s   Range %d   Sailors %d  Gunners %d  Marines %d" % [_reload_text(s, "port"),
			_reload_text(s, "starboard"), CombatSim.gun_range(s), CombatSim.sailors(s), CombatSim.gunners(s), s.crew * s.roles.marines])
		if s.leak > 0.0:
			lines.append("LEAKING %.1f hull/s" % s.leak)
	return "\n".join(lines)


func _reload_text(s: Dictionary, side: String) -> String:
	return "READY" if s.reload[side] <= 0.0 else "%.0fs" % s.reload[side]


func _log(text: String) -> void:
	var lines: PackedStringArray = %Log.text.split("\n", false)
	lines.append(text)
	%Log.text = "\n".join(lines.slice(maxi(0, lines.size() - 3)))


# ---- Boarding and the end --------------------------------------------------

func _boarding() -> void:
	var me: Dictionary = sim.ships[0]
	var them: Dictionary = sim.ships[1]
	var rng := sim.rng
	var mine := {"crew": me.crew, "swordplay": me.swordplay, "captain_swordplay": me.captain_swordplay, "morale": me.morale,
		"swivels": me.stats.swivels, "marines": me.roles.marines}
	var theirs := {"crew": them.crew, "swordplay": them.swordplay, "captain_swordplay": them.captain_swordplay, "morale": them.morale,
		"swivels": them.stats.swivels, "marines": them.roles.marines}
	var report := Boarding.opening_volley(mine, theirs, rng)
	report.push_front("%s! Grapnels fly and the ships crash together." % ("You board them" if sim.boarded_by == 0 else "They board you"))
	var result := ""
	var choices: Dictionary = Data.rules.boarding.choices
	while result == "":
		var options := []
		for id in ["push", "hold", "captain"]:
			options.append({"text": choices[id].name, "tooltip": choices[id].description})
		options.append({"text": "Cut the grapples and fall back", "tooltip": "Back to the guns, if you can get clear."})
		var text := "\n".join(report) + "\n\nYour men: %d (morale %d, swordplay %.1f)\nTheirs: about %d (morale %d)" % [
			mine.crew, mine.morale, mine.swordplay, int(theirs.crew / 5.0) * 5, theirs.morale]
		var pick: int = await dialog.ask("Boarding", text, options)
		if pick == 3:
			result = "cut"
			break
		var r := Boarding.fight_round(mine, theirs, ["push", "hold", "captain"][pick], Boarding.enemy_choice(theirs, mine), rng)
		report = r.lines
		result = r.result
	for pair in [[me, mine], [them, theirs]]:
		pair[0].casualties += pair[0].crew - pair[1].crew
		pair[0].crew = pair[1].crew
		pair[0].morale = pair[1].morale
	me.captain_wounded = mine.get("captain_wounded", false)
	match result:
		"won": sim.strike(1)
		"lost": sim.strike(0)
		"cut":  # shove off and fight on
			sim.result = ""
			sim.boarded_by = -1
			them.pos += (them.pos - me.pos).normalized() * 120.0
			ending = false
			return
	_end()


func _end() -> void:
	var titles := {"enemy_struck": "She strikes her colours!", "player_struck": "You strike your colours",
		"enemy_sunk": "She goes down", "player_sunk": "Your ship is lost", "separated": "The ships part"}
	var texts := {
		"enemy_struck": "The %s is yours. Time to decide what to do with her." % enemy_data.name,
		"player_struck": "The fight is lost. The enemy boards to take what they want.",
		"enemy_sunk": "The %s slips beneath the waves, cargo and all." % enemy_data.name,
		"player_sunk": "The sea takes your ship.",
		"separated": "The distance between you grows until the %s is just a sail on the horizon." % enemy_data.name,
	}
	var me: Dictionary = sim.ships[0]
	if sim.result.ends_with("sunk"):  # let her go down before the report
		var who := 1 if sim.result == "enemy_sunk" else 0
		_burst(sim.ships[who].pos, Vector2.ZERO, Style.c("splash"), 40, 180.0, Vector2(20, 90), 1.2, Vector2(0.3, 0.7))
		var tw := create_tween().set_parallel()
		tw.tween_property(sprites[who], "modulate:a", 0.0, 1.8)
		tw.tween_property(sprites[who], "scale", sprites[who].scale * 0.7, 1.8)
		await tw.finished
	var text: String = texts[sim.result] + "\n\nYour casualties: %d.  Hull %d, sails %d." % [me.casualties, me.hull, me.sails]
	if me.get("captain_wounded", false):
		text += "\nYour captain was wounded in the fighting."
	await dialog.ask(titles[sim.result], text, [{"text": "Continue"}])
	finished.emit({"outcome": sim.result, "player": me, "enemy": sim.ships[1], "enemy_data": enemy_data})
