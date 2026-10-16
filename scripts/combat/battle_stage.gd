class_name BattleStage
extends Node3D
## The battle as an HD-2D diorama (the Octopath look): pixel-art ships as flat sprites standing in a lit 3D sea,
## under a sky that follows the time of day, with glow, a tilted camera and a shallow depth of field.
## Cannon fire lights the ships up, fires burn with flickering light, and lanterns glow at dusk.
## Your ship sits front left, hers back right (Pokémon style); allies stand behind yours. The range band sets
## the gap. Ships are drawn from assets/ships_side/<type>/ (hull, sails, damaged and torn versions, layout.json).
## The battle's conditions show: fog rolls in (and lifts when it lifts), a dead calm flattens the sea, a squall
## brings rain, and a fort stands on the shore behind when its guns are in the fight.
## Built in code: Godot's 3D nodes are just objects, so a scene file would only hold the same settings.

const PIXEL := 0.016                         # world units per art pixel
const BAND_GAP := [12.0, 8.0, 4.5, 1.2]     # gap between hulls at each range band
const CAM_DIST := [27.0, 24.0, 21.0, 19.0]
const PUFF := preload("res://assets/fx/puff.png")

var ships: Array = []      # per side: {root, hull, sails, flag, len, layout, sinking, fire_light}
var allies: Array = []     # sprites for allied ships behind yours
var camera: Camera3D
var sun: DirectionalLight3D
var water_mat: ShaderMaterial
var _band := 0
var _shake := 0.0
var _night := 0.0          # 0 day .. 1 night: lanterns and fire glow matter more
var _t := 0.0
var _env: Environment
var _haze := 0.005         # the clear-weather haze the fog thins back to
var _fort: Sprite3D


func setup(battle: DiceCombat, flags: Array, looks: Array, wind_strength: float) -> void:
	_build_world(wind_strength, battle.conditions.map(func(c): return c.id))
	for i in 2:
		ships.append(_make_ship(battle.sides[i].type, flags[i], looks[i], i == 1))
	var k := 0
	for a in battle.sides[0].get("allies", []):
		if a.get("shore", false):  # shore guns aren't ships
			continue
		var sh := _make_ship(a.get("type", "sloop"), flags[0], a.get("look", {}), false)
		sh.root.scale = Vector3.ONE * 0.85
		sh.ally_name = a.name
		sh.slot = k
		allies.append(sh)
		k += 1
	_band = battle.band
	sync(battle, true)


# ---- the world --------------------------------------------------------------------------

func _build_world(wind_strength: float, conds: Array) -> void:
	var hour := fposmod(Clock.day, 1.0) * 24.0
	_night = clampf(absf(hour - 13.0) / 6.0 - 0.6, 0.0, 1.0)  # day from ~7 to ~19, dusk either side
	var storm := wind_strength > 1.25 or "squall" in conds or "hurricane" in conds or "norther" in conds
	var fog := "fog" in conds
	var day := Color("#7fb6e6")
	var dusk := Color("#f0a066")
	var top := Color("#2a4c86").lerp(Color("#0b1028"), _night)
	var horizon := day.lerp(dusk, clampf(_night * 2.0, 0.0, 1.0)).lerp(Color("#1a1f3a"), maxf(0.0, _night - 0.5) * 2.0)
	if storm:
		top = Color("#2a3038")
		horizon = Color("#5a6470")
	elif fog:
		top = top.lerp(Color("#b8c0c6"), 0.7)
		horizon = horizon.lerp(Color("#d8dcdc"), 0.75)

	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = top
	sm.sky_horizon_color = horizon
	sm.ground_horizon_color = horizon
	sm.ground_bottom_color = top.darkened(0.4)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = lerpf(1.0, 0.45, _night)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = lerpf(1.05, 0.8, _night)
	env.glow_enabled = true            # the soft bloom of HD-2D
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true             # distance haze toward the horizon
	env.fog_light_color = horizon.darkened(0.25)
	_haze = 0.005 if not storm else 0.02
	env.fog_density = 0.07 if fog else _haze
	_env = env
	env.fog_sky_affect = 0.0
	env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15 if not storm else 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("#fff1d6").lerp(Color("#ff9a5a"), clampf(_night * 1.5, 0.0, 1.0)).lerp(Color("#8aa0ff"), maxf(0.0, _night - 0.6) * 2.5)
	sun.light_energy = lerpf(1.4, 0.35, _night) * (0.5 if storm else 1.0)
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38.0 + _night * 25.0, -35.0, 0.0)  # low and raking at dusk
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 32.0
	var attr := CameraAttributesPractical.new()  # the tilt-shift blur: near and far out of focus
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 34.0
	attr.dof_blur_far_transition = 18.0
	attr.dof_blur_near_enabled = true
	attr.dof_blur_near_distance = 10.0
	attr.dof_blur_near_transition = 4.0
	attr.dof_blur_amount = 0.12
	camera.attributes = attr
	add_child(camera)
	camera.current = true

	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(260, 200)
	plane.subdivide_width = 160
	plane.subdivide_depth = 120
	sea.mesh = plane
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://assets/battle/water.gdshader")
	water_mat.set_shader_parameter("swell", 2.2 if storm else (0.2 if "calm" in conds else 1.0))
	if _night > 0.5:
		water_mat.set_shader_parameter("deep", Color("#06142a"))
		water_mat.set_shader_parameter("shallow", Color("#123a52"))
	sea.material_override = water_mat
	sea.position = Vector3(0, 0, -40)
	add_child(sea)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(Clock.day)
	_prop("res://assets/battle/island.png", Vector3(rng.randf_range(-40, 10), -0.2, -70), 0.2, false)
	if "fort" in conds:  # the port's walls on a headland behind the fight
		_prop("res://assets/battle/island.png", Vector3(0, -0.2, -30), 0.16, false)
		_fort = _prop("res://assets/map/town.png", Vector3(0, 1.1, -29.5), 0.28, false)
	if "shoals" in conds:  # breakers on the reefs
		for k in 3:
			_prop("res://assets/battle/rock.png", Vector3(rng.randf_range(-18, 18), -0.15, rng.randf_range(-24, -8)), 0.06, rng.randf() < 0.5)
	if rng.randf() < 0.6:
		_prop("res://assets/battle/island.png", Vector3(rng.randf_range(20, 50), -0.2, -85), 0.16, true)
	_prop("res://assets/battle/rock.png", Vector3(rng.randf_range(-14, 14), -0.1, -14), 0.08, rng.randf() < 0.5)
	for k in 5:
		var cl := _prop("res://assets/battle/cloud%d.png" % (k % 2 + 1), Vector3(rng.randf_range(-70, 70), rng.randf_range(14, 26), -95), 0.5, rng.randf() < 0.5)
		cl.shaded = false
		cl.modulate = Color.WHITE.lerp(horizon, 0.35 + _night * 0.4)
		cl.set_meta("drift", rng.randf_range(0.2, 0.7))
	if storm:
		_rain()


func _prop(path: String, pos: Vector3, px: float, flip: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = load(path)
	s.pixel_size = px
	s.position = pos
	s.flip_h = flip
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.offset = Vector2(0, s.texture.get_height() / 2.0)  # stand on the water
	add_child(s)
	return s


func _rain() -> void:
	var p := CPUParticles3D.new()
	p.amount = 900
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(30, 1, 15)
	p.position = Vector3(0, 16, -4)
	p.direction = Vector3(-0.3, -1, 0)
	p.spread = 3.0
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 24.0
	p.gravity = Vector3.ZERO
	var m := QuadMesh.new()
	m.size = Vector2(0.03, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.85, 0.95, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.material = mat
	p.mesh = m
	add_child(p)


# ---- ships ------------------------------------------------------------------------------------

func _make_ship(type_id: String, flag_id: String, look: Dictionary, facing_left: bool) -> Dictionary:
	var dir := "res://assets/ships_side/%s/" % type_id
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "layout.json"))
	var root := Node3D.new()
	add_child(root)
	var w: float = layout.size[0]
	var h: float = layout.size[1]
	var lift: float = (h / 2.0 - (h - layout.waterline)) * PIXEL  # the waterline sits on the sea
	var hull := _sprite(dir + "hull.png", facing_left)
	hull.position.y = lift
	hull.modulate = Color(Data.rules.ship_looks.paints.get(look.get("paint", "natural"), {}).get("color", "#ffffff"))
	root.add_child(hull)
	var sails := _sprite(dir + "sails.png", facing_left)
	sails.position = Vector3(0, lift, 0.01)
	sails.modulate = Color(Data.rules.ship_looks.sails.get(look.get("sails", "white"), {}).get("color", "#ffffff"))
	root.add_child(sails)
	var flag: Sprite3D = null
	if flag_id != "" and Data.table("flags").has(flag_id):
		flag = _sprite(Data.table("flags")[flag_id].path, not facing_left)
		flag.pixel_size = PIXEL * 0.45
		var fx: float = (layout.flag[0] - w / 2.0) * PIXEL * (-1.0 if facing_left else 1.0)
		var fy: float = (h / 2.0 - layout.flag[1]) * PIXEL + lift
		var fw: float = flag.texture.get_width() * flag.pixel_size
		flag.position = Vector3(fx + (fw / 2.0 if facing_left else -fw / 2.0), fy - flag.texture.get_height() * flag.pixel_size / 2.0, 0.02)
		root.add_child(flag)
	var lantern := OmniLight3D.new()  # a stern lantern, which matters at dusk
	lantern.light_color = Color("#ffc070")
	lantern.light_energy = 0.4 + _night * 2.5
	lantern.omni_range = 3.0
	lantern.position = Vector3((w * 0.42) * PIXEL * (1.0 if facing_left else -1.0), lift - (h / 2.0 - layout.waterline + 10) * PIXEL, 0.6)
	root.add_child(lantern)
	var fire := OmniLight3D.new()
	fire.light_color = Color("#ff7a2a")
	fire.omni_range = 5.0
	fire.light_energy = 0.0
	fire.position = Vector3(0, 1.0, 0.8)
	root.add_child(fire)
	return {"root": root, "hull": hull, "sails": sails, "flag": flag, "len": w * PIXEL, "dir": dir, "facing_left": facing_left, "paint": hull.modulate,
		"fire_light": fire, "sinking": false, "phase": randf() * TAU, "ally_name": "", "slot": 0, "key": ""}


func _sprite(path: String, flip: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = load(path)
	s.pixel_size = PIXEL
	s.flip_h = flip
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD  # crisp edges, and it casts shadows on the sea
	s.shaded = true
	s.double_sided = true
	return s


## Moves the ships to the range band and shows damage. `snap` jumps instead of gliding.
func sync(battle: DiceCombat, snap := false) -> void:
	_band = battle.band
	if _env:  # fog that lifts mid-fight thins away
		var want := 0.07 if battle.has_condition("fog") else _haze
		_env.fog_density = lerpf(_env.fog_density, want, 0.02)
	for i in 2:
		var sh: Dictionary = ships[i]
		var s: Dictionary = battle.sides[i]
		var key := "%s%s" % [s.hull < s.stats.hull * 0.5, s.sails < s.stats.sails * 0.4]
		if key != sh.key:
			sh.key = key
			sh.hull.texture = load(sh.dir + ("hull_damaged.png" if s.hull < s.stats.hull * 0.5 else "hull.png"))
			sh.sails.texture = load(sh.dir + ("sails_torn.png" if s.sails < s.stats.sails * 0.4 else "sails.png"))
		if sh.flag:
			sh.flag.visible = not s.struck
		sh.fire_target = 1.6 + _night if s.fire > 0 else 0.0
	if snap:
		for i in 2:
			ships[i].root.position = _home(i)
		for a in allies:
			a.root.position = _ally_home(a)


func _home(i: int) -> Vector3:
	var gap: float = BAND_GAP[_band]
	if i == 0:
		return Vector3(-gap / 2.0 - ships[0].len / 2.0, 0.0, 1.5)
	return Vector3(gap / 2.0 + ships[1].len / 2.0, 0.0, -1.5)


func _ally_home(a: Dictionary) -> Vector3:
	return _home(0) + Vector3(-3.0 - a.slot * 4.0, 0.0, -4.5 - a.slot * 2.5)


func _process(delta: float) -> void:
	if ships.is_empty():
		return
	_t += delta
	var all: Array = ships + allies
	for k in all.size():
		var sh: Dictionary = all[k]
		if sh.sinking:
			continue
		var home: Vector3 = _home(k) if k < 2 else _ally_home(sh)
		var p: Vector3 = sh.root.position.lerp(home, minf(1.0, delta * 1.5))
		p.y = sin(_t * 1.3 + sh.phase) * 0.08  # bob on the swell
		sh.root.position = p
		sh.root.rotation.z = sin(_t * 0.9 + sh.phase) * 0.025  # and roll
		var fl: OmniLight3D = sh.fire_light
		var target: float = sh.get("fire_target", 0.0)
		fl.light_energy = lerpf(fl.light_energy, target * (0.7 + randf() * 0.6), minf(1.0, delta * 10.0))
	var gap_mid := (_home(0).x + _home(1).x) / 2.0
	var dist: float = CAM_DIST[_band]
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake
	_shake = maxf(0.0, _shake - delta * 1.5)
	camera.position = camera.position.lerp(Vector3(gap_mid, 5.5, dist), minf(1.0, delta * 2.0)) + shake
	camera.look_at(Vector3(gap_mid, 0.6, -1.0) + shake * 0.5)
	for c in get_children():
		if c is Sprite3D and c.has_meta("drift"):
			c.position.x = wrapf(c.position.x + delta * c.get_meta("drift"), -80, 80)


func shake(amount := 0.35) -> void:
	_shake = maxf(_shake, amount)


## A broadside from side i (or from an ally, by name): flashes that light the hull, smoke, and splinters or a splash.
func broadside(i: int, hit: bool, ally := "") -> void:
	var from: Dictionary = ships[i]
	for a in allies:
		if ally != "" and a.ally_name == ally:
			from = a
	var target: Dictionary = ships[1 - i] if ally == "" else ships[1]
	var dir := -1.0 if ally == "" and i == 1 else 1.0  # toward the other ship
	var origin: Vector3 = from.root.position + Vector3(dir * 0.4, 0.45, 0.6)
	var flash := OmniLight3D.new()
	flash.light_color = Color("#ffd27a")
	flash.light_energy = 9.0
	flash.omni_range = 7.0
	flash.position = origin
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	for k in 6:
		var x: float = from.root.position.x + (k - 2.5) * from.len / 7.0
		_puff(Vector3(x, 0.5, from.root.position.z + 0.5), Vector3(dir, 0.25, 0.2), Color(0.85, 0.82, 0.78, 0.8), 6, 1.6, 0.35)
		_puff(Vector3(x, 0.5, from.root.position.z + 0.5), Vector3(dir, 0.1, 0), Color(1.0, 0.85, 0.4, 1.0), 2, 0.18, 0.2)
	var at: Vector3 = target.root.position + Vector3(0, 0.6, 0.6)
	if hit:
		_puff(at, Vector3(0, 1, 0.3), Color(0.55, 0.36, 0.2, 1.0), 18, 0.7, 0.12)
		target.hull.modulate = Color(1.8, 0.9, 0.8)  # a flash of the hit
		create_tween().tween_property(target.hull, "modulate", target.paint, 0.25)
		shake(0.15)
	else:
		_puff(at + Vector3(-dir * 1.5, -0.4, 0.8), Vector3.UP, Color(0.92, 0.96, 1.0, 0.9), 16, 0.8, 0.25)


## The fort's guns: a flash on the walls, then splinters or a splash by the ship it fires on.
func fort_fire(target_i: int, hit: bool) -> void:
	if _fort == null:
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color("#ffd27a")
	flash.light_energy = 12.0
	flash.omni_range = 9.0
	flash.position = _fort.position + Vector3(0, 1.0, 1.0)
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.tween_callback(flash.queue_free)
	_puff(_fort.position + Vector3(0, 1.2, 0.5), Vector3(1, 0.4, 0.3), Color(0.85, 0.82, 0.78, 0.8), 14, 2.0, 0.6)
	var target: Dictionary = ships[target_i]
	var at: Vector3 = target.root.position + Vector3(0, 0.6, 0.6)
	if hit:
		_puff(at, Vector3(0, 1, 0.3), Color(0.55, 0.36, 0.2, 1.0), 18, 0.7, 0.12)
		shake(0.2)
	else:
		_puff(at + Vector3(-1.5, -0.4, 0.8), Vector3.UP, Color(0.92, 0.96, 1.0, 0.9), 16, 0.8, 0.25)


func _puff(pos: Vector3, dir: Vector3, color: Color, amount: int, life: float, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.position = pos
	p.direction = dir
	p.spread = 30.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 0.6, 0) if color.r > 0.7 and color.b > 0.7 else Vector3(0, -4.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	var m := QuadMesh.new()
	m.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = PUFF
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if color.g > 0.8 and color.b < 0.5 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.material = mat
	p.mesh = m
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


## Side i goes down: a last splash, then she settles by the stern and slips under.
func sink(i: int) -> Tween:
	var sh: Dictionary = ships[i]
	sh.sinking = true
	_puff(sh.root.position + Vector3(0, 0.3, 0.6), Vector3.UP, Color(0.92, 0.96, 1.0, 0.9), 40, 1.2, 0.3)
	var tw := create_tween().set_parallel()
	tw.tween_property(sh.root, "position:y", -6.0, 3.0).set_ease(Tween.EASE_IN)
	tw.tween_property(sh.root, "rotation:z", 0.35 * (1.0 if i == 0 else -1.0), 3.0)
	return tw
