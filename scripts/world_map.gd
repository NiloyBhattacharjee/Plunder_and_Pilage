class_name WorldMap
extends Node2D
## World map scene: builds the chart from data, routes the ship on click, and runs the camera.
## Controls: left-click sea or a port to sail there. Right/middle-drag pans, wheel zooms, F follows the ship.
## Space pauses, 1/2/3 set time speed. F5 quick-saves, F9 quick-loads.

const PORT_CLICK_RADIUS := 14.0  # screen pixels
const ZOOM_MAX := 4.0

var terrain: TerrainGrid
var port_positions := {}  # where the port marker is drawn
var anchorages := {}      # nearest navigable point to each port
var follow_ship := true
var combat: Node = null
var rng := RandomNumberGenerator.new()
var current_npc := {}     # the NPC ship you're dealing with, if any
var chase_id := ""        # the NPC ship you're chasing
var _chase_timer := 0.0
var _in_event := false
var _attacked := false
@onready var port_layer: Node2D = $PortLayer
var _overlays: Array = []  # the label layer, hidden with the world
var _daylight: CanvasModulate
var _lights: Array = []    # towns' and your lantern's light at night
var at_base := ""         # the cove you're anchored at, if any (a cove isn't a port: you count as at sea)
var cove_anchors := {}    # cove id -> navigable anchorage
var _raid_base := ""      # the base you're fighting for   # you opened fire in the last battle (it matters to named captains)   # an event's "time" outcome runs days; don't start another inside it

## Set by the new-game screen before switching here: {name, nationality, background, ship_name} or {"load": true}.
static var start_config := {}

@onready var ship: Node2D = $Ship
@onready var camera: Camera2D = $Camera2D
@onready var hud = $HUD
@onready var port_screen = $PortScreen
@onready var crew_screen = $CrewScreen
@onready var prize_screen = $PrizeScreen
@onready var dialog = $ChoiceDialog
@onready var shipping = $Shipping


func _ready() -> void:
	_pixel_layers()
	rng.randomize()
	terrain = TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	for id in Data.table("ports"):
		var p: Dictionary = Data.table("ports")[id]
		port_positions[id] = Geo.latlon_to_px(p.lat, p.lon)
		anchorages[id] = terrain.nearest_sea(port_positions[id])
	port_layer.port_positions = port_positions
	for id in Data.table("coves"):
		if not id.begins_with("_"):
			cove_anchors[id] = terrain.nearest_sea(Bases.cove_pos(id))

	camera.limit_right = int(Data.map.size[0])
	camera.limit_bottom = int(Data.map.size[1])

	ship.terrain = terrain
	ship.stats_changed.connect(func():
		var d: Dictionary = Data.rules.draught[ship.stats.draught]
		terrain.set_shallow_cost(d.route_cost, d.reef_route_cost))
	# Loading still builds a default game first; the save then overwrites it (and it's a safe fallback if loading fails).
	var cfg: Dictionary = start_config if start_config.has("background") else Data.rules.start
	var game := NewGame.build(cfg)
	var start_port: String = game.start_port
	ship.setup(game.state)
	ship.position = anchorages[start_port]
	ship.anchored_at = start_port
	ship.arrived.connect(_on_arrived)
	ship.message.connect(hud.show_message)
	ship.foundered.connect(_on_foundered)
	hud.ship = ship
	hud.enter_port_pressed.connect(func(): port_screen.open(ship.anchored_at, ship))
	hud.save_pressed.connect(_save)
	hud.load_pressed.connect(_load)
	hud.map_mode_changed.connect(func(good):
		port_layer.ship_state = ship.state
		port_layer.trade_good = good)
	port_screen.message.connect(hud.show_message)
	port_screen.closed.connect(port_layer.queue_redraw)
	Clock.day_passed.connect(func(_d): if port_layer.trade_good != "": port_layer.queue_redraw())
	hud.crew_pressed.connect(_open_crew)
	crew_screen.message.connect(hud.show_message)
	shipping.setup(terrain, self)
	Contracts.shipping = shipping
	Politics.news.connect(hud.show_message)
	Bonds.news.connect(hud.show_message)
	Bases.news.connect(hud.show_message)
	$BaseScreen.message.connect(hud.show_message)
	$BaseScreen.closed.connect(port_layer.queue_redraw)
	Contracts.changed.connect(port_layer.queue_redraw)
	shipping.contact.connect(_on_contact)
	shipping.news.connect(hud.show_message)
	shipping.alert.connect(func(text):
		hud.show_message(text + " (Paused. Space to resume.)")
		Clock.set_speed(0))
	Factions.changed.connect(func(text):
		hud.show_message(text)
		var lost := Career.check_peace(ship.state)
		if lost != "":
			hud.show_message(lost))
	Clock.day_passed.connect(func(_d): _daily())
	hud.flag_changed.connect(func(f):
		ship.state.flag = f
		ship.refresh_stats())
	hud.show_message("Captain %s and the %s lie at anchor in %s. Click the sea or a port to set a course. C opens the crew and ship." % [
		ShipStats.captain(ship.state).name, ship.state.name, Data.table("ports")[start_port].name])
	if start_config.get("load", false):
		_load.call_deferred()
	else:
		port_screen.open.call_deferred(start_port, ship)


func _process(delta: float) -> void:
	if follow_ship:
		camera.position = ship.position
	if chase_id != "" and Clock.speed_index > 0:  # keep re-aiming at the ship you're chasing
		_chase_timer -= delta
		if _chase_timer <= 0.0:
			_chase_timer = 0.5
			var n: Dictionary = shipping.find(chase_id)
			if n.is_empty():
				chase_id = ""
			else:
				var path := terrain.find_path(ship.position, n.pos)
				if not path.is_empty():
					ship.set_route(path)


func _daily() -> void:
	var s: Dictionary = ship.state
	s.reputation.notoriety = maxf(0.0, s.reputation.notoriety - Data.rules.career.notoriety_decay_per_day)
	for m in Contracts.daily(s):
		hud.show_message(m)
	Politics.prune_secrets(s)
	Bonds.ensure_on_map(shipping)
	for m in Fleet.daily(s, rng):
		hud.show_message(m)
	if ship.anchored_at == "" and not ship.route.is_empty():
		var found := Bases.look_for_coves(s, ship.position)
		if found != "":
			hud.show_message(found)
			port_layer.queue_redraw()
	var base_day := Bases.daily(s, at_base)
	for m in base_day.messages:
		hud.show_message(m)
	if base_day.messages.size() > 0:
		port_layer.queue_redraw()
	if base_day.battle != "" and not busy():
		defend_base(base_day.battle)
		return
	if Clock.date().day == 1:
		Politics.leverage_month(s)
		for m in Bonds.monthly(s):
			hud.show_message(m)
	if s.has("succession") and not busy():
		run_succession()
		return
	if not busy() and s.hull > 0:
		var inst_any := Events.pick("any", _event_ctx()) if ship.anchored_at != "" else {}
		if not inst_any.is_empty():
			run_event(inst_any)
			return
	if ship.anchored_at == "" and not busy() and s.hull > 0:
		var inst := Events.pick("sea", _event_ctx())
		if not inst.is_empty():
			run_event(inst)


func _unhandled_input(event: InputEvent) -> void:
	if busy():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _set_course(get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP: _zoom(1.15)
			MOUSE_BUTTON_WHEEL_DOWN: _zoom(1.0 / 1.15)
	elif event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		follow_ship = false
		camera.position -= event.relative / camera.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: Clock.toggle_pause()
			KEY_1: Clock.set_speed(1)
			KEY_2: Clock.set_speed(2)
			KEY_3: Clock.set_speed(3)
			KEY_F: follow_ship = true
			KEY_C: _open_crew()
			KEY_F5: _save()
			KEY_F9: _load()


func _set_course(target: Vector2) -> void:
	if ship.state.hull <= 0:
		return
	chase_id = ""
	at_base = ""
	var npc: Dictionary = shipping.npc_at(target, 14.0 / camera.zoom.x)
	if not npc.is_empty():
		chase_id = npc.id
		hud.show_message("Giving chase to the %s." % npc.enemy.name)
		_chase_timer = 0.0
		return
	var cove := _cove_near(target)
	if cove != "":
		if cove == at_base:
			_at_cove(cove)
			return
		var cpath := terrain.find_path(ship.position, cove_anchors[cove])
		if not cpath.is_empty():
			ship.set_route(cpath, "cove:" + cove)
			hud.show_message("Setting course for %s." % Bases.cove(cove).name)
		return
	var port_id := _port_near(target)
	if port_id != "" and port_id == ship.anchored_at:
		port_screen.open(port_id, ship)
		return
	if port_id != "":
		target = anchorages[port_id]
	elif terrain.at(target) == TerrainGrid.LAND:
		hud.show_message("That's dry land, Captain.")
		return
	var path := terrain.find_path(ship.position, target)
	if path.is_empty():
		hud.show_message("No sea route to there.")
		return
	ship.set_route(path, port_id)
	if port_id != "":
		hud.show_message("Setting course for %s." % Data.table("ports")[port_id].name)


func _cove_near(pos: Vector2) -> String:
	var radius := PORT_CLICK_RADIUS / camera.zoom.x
	for id in Bases.discovered:
		if pos.distance_to(Bases.cove_pos(id)) < radius or pos.distance_to(cove_anchors[id]) < radius:
			return id
	return ""


## Arriving at a cove: claim it, or step ashore at your own base.
func _at_cove(id: String) -> void:
	ship.anchored_at = ""
	at_base = id
	if Bases.bases.has(id):
		Bases.visit(id)
		var leave := Bases.shore_leave(ship.state, id)
		if leave != "":
			hud.show_message(leave)
		$BaseScreen.open(id, ship)
		return
	UIKit.pause_clock()
	var why := Bases.claim_problem(ship.state, id)
	var pick: int = await dialog.ask(Bases.cove(id).name, "%s\n\nMake it your base? It costs %d gold to set up, and %d hands stay behind as a garrison. A base needs men, food and money, and the more you use it the easier it is to find." % [
		Bases.cove(id).description, Data.rules.bases.claim_cost, Data.rules.bases.claim_garrison],
		[{"text": "Make it ours", "disabled": why != "", "tooltip": why if why != "" else "Shelter %d. %s%s" % [Bases.cove(id).shelter,
			"Good soil for a plantation. " if Bases.cove(id).soil else "", "A spring: the garrison needs no water brought in." if Bases.cove(id).water else "No fresh water: bring it."]},
		{"text": "Not now"}])
	if pick == 0:
		hud.show_message(Bases.claim(ship.state, id))
		port_layer.queue_redraw()
		$BaseScreen.open(id, ship)
		return
	UIKit.resume_clock()


## A raid on a base you're anchored at: fight it at sea, with the shore guns beside you.
func defend_base(id: String) -> void:
	var b: Dictionary = Bases.bases[id]
	var r: Dictionary = b.raid
	var enemy := Encounters.generate(r.faction, rng, r.kind)
	if r.captain != "" and People.chars.has(r.captain):
		var c := People.person(r.captain)
		enemy.name = c.ship
		enemy.captain = c.duplicate(true)
		enemy.captain_id = r.captain
	_raid_base = id
	hud.show_message("%s is attacking %s!" % [r.label.capitalize(), b.name])
	start_combat(enemy, "defend")


func _port_near(pos: Vector2) -> String:
	var radius := PORT_CLICK_RADIUS / camera.zoom.x
	for id in port_positions:
		if pos.distance_to(port_positions[id]) < radius or pos.distance_to(anchorages[id]) < radius:
			return id
	return ""


func _zoom(factor: float) -> void:
	# Never zoom out past the point where the map stops filling the window.
	var fit := get_viewport_rect().size / Vector2(Data.map.size[0], Data.map.size[1])
	var z := clampf(camera.zoom.x * factor, maxf(fit.x, fit.y), ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	port_layer.zoom = z


func _on_arrived(id: String) -> void:
	if id.begins_with("cove:"):
		_at_cove(id.substr(5))
		return
	var access := Career.port_access(ship.state, id)
	if access.open:
		hud.show_message("Anchored at %s." % Data.table("ports")[id].name)
		var inst := Events.pick("port", _event_ctx())
		if not inst.is_empty():
			await run_event(inst)
		if ship.anchored_at == id and combat == null:
			port_screen.open(id, ship)
		return
	UIKit.pause_clock()
	var s: Dictionary = ship.state
	var p: Dictionary = Ports.port(id)
	var fools := Career.flag_fools_port(s, id)
	var pick: int = await dialog.ask("The harbour is closed to you", "%s\nThe fort at %s runs out its guns." % [access.reason, p.name], [
		{"text": "Turn away", "tooltip": "Find another port."},
		{"text": "Slip in under false colours (%d%% risk)" % int(access.detect * 100), "disabled": not fools,
			"tooltip": "Fly the colours of a nation at peace with %s and hope nobody looks too closely.\nCaught: the fort opens fire and your standing drops." % Data.table("factions")[p.faction].name
				if fools else "Hoist the flag of a nation at peace with %s first (Colours, top left)." % Data.table("factions")[p.faction].name},
		{"text": "Bribe the harbour master (%d gold)" % access.bribe, "disabled": s.gold < access.bribe,
			"tooltip": "Usually works. Sometimes he takes the money and calls the guard anyway."},
	])
	var pa: Dictionary = Data.rules.port_access
	var entered := false
	match pick:
		1:
			if rng.randf() < access.detect:
				var dmg := rng.randi_range(pa.fort_damage[0], pa.fort_damage[1])
				s.hull = maxf(1.0, s.hull - dmg)
				s.relations[p.faction] -= int(pa.caught_relation)
				hud.show_message("Recognised! The fort at %s opens fire as you claw back out to sea. Hull -%d." % [p.name, dmg])
			else:
				entered = true
				hud.show_message("Nobody looks twice at your colours. You're in %s." % p.name)
		2:
			s.gold -= access.bribe
			if rng.randf() < pa.bribe_success:
				entered = true
				hud.show_message("The harbour master pockets the gold and looks the other way.")
			else:
				hud.show_message("He takes your gold and sends for the guard. You leave in a hurry.")
	if entered:
		port_screen.open(id, ship, true)
	else:
		ship.anchored_at = ""
		ship.position = terrain.nearest_sea(ship.position + (ship.position - port_positions[id]).normalized() * 30.0)
		UIKit.resume_clock()


func _event_ctx() -> Dictionary:
	return {"s": ship.state, "stats": ship.stats, "port": ship.anchored_at, "storm": ship.wind.get("storm", "") != "", "base": at_base}


## Shows an event, applies the choice, and shows what came of it. A choice can start a fight.
func run_event(inst: Dictionary) -> void:
	UIKit.pause_clock()
	_in_event = true
	var ctx := _event_ctx()
	var v := Events.view(inst, ctx)
	var pick: int = await dialog.ask(v.title, v.text, v.options)
	var res := Events.resolve(inst, pick, ctx)
	ship.refresh_stats()
	var body: String = res.text
	if not res.effects.is_empty():
		body += ("

" if body != "" else "") + "
".join(res.effects)
	if body != "":
		await dialog.ask(v.title, body, [{"text": "Continue"}])
	hud.show_message("%s: %s" % [v.title, ", ".join(res.effects.filter(func(e): return not e.begins_with("d20")))] if not res.effects.is_empty() else v.title)
	if res.mutiny:
		await run_mutiny()
	_in_event = false
	if ship.state.has("succession"):
		await run_succession()
		return
	if not res.fight.is_empty():
		start_combat(Encounters.generate(res.fight.faction, rng, res.fight.kind), res.fight.mode)
		return
	UIKit.resume_clock()


## Blades out on the main deck. Win, and decide what happens to the mutineers.
func run_mutiny() -> void:
	var s: Dictionary = ship.state
	var r := Crew.mutiny(s, rng)
	var roll := Dice.describe(r.check).replace("[b]", "").replace("[/b]", "").replace("[/color]", "").replace("[color=#2e6b3a]", "").replace("[color=#a3261b]", "")
	if r.outcome != "crushed":
		await dialog.ask("Mutiny", r.text + "

" + roll, [{"text": "Continue"}])
		hud.show_message(r.text)
		return
	var pick: int = await dialog.ask("The mutiny is crushed", r.text + "

" + roll, [
		{"text": "Hang the ringleader", "tooltip": "Fear +3. The other mutineers will hate you a little more."},
		{"text": "Maroon them all", "tooltip": "Every mutineer is put off the ship. Fear +2. You lose %d hands." % r.rebels.size()},
		{"text": "Forgive them", "tooltip": "Honour +2. They think better of you; some think you weak."},
	])
	hud.show_message(Crew.punish(s, r.rebels, ["hang", "maroon", "forgive"][pick]))


## The captain is gone. The crew choose, by vote or by chain of command, unless someone takes the ship by force.
func run_succession() -> void:
	var s: Dictionary = ship.state
	UIKit.pause_clock()
	_in_event = true
	var old := ShipStats.captain(s)
	var cause: String = s.succession.cause
	if s.crew.is_empty():
		s.captains.append({"name": old.name, "until": Clock.date_string(), "fate": cause})
		var line := "
".join(s.captains.map(func(c): return "%s (until %s, %s)" % [c.name, c.until, c.fate]))
		await dialog.ask("The end of the %s" % s.name, "Captain %s %s, and there is no one left to take the helm.

The captains of the %s:
%s" % [
			old.name, cause, s.name, line], [{"text": "Start a new game"}])
		get_tree().change_scene_to_file("res://ui/new_game.tscn")
		return
	var cands := Crew.candidates(s, rng)
	var winner := Crew.chosen(s, cands)
	var lines := PackedStringArray()
	for c in cands:
		var p := People.person(c.id)
		lines.append("%s%s: %d%% of the crew" % [p.name, " (%s)" % c.why if c.why != "" else "", int(c.support * 100)])
	var how_text: String = "By the articles, the crew vote." if Crew.culture(s) == "election" else "By the chain of command, the next in line takes over, unless the crew won't follow them."
	var options := [{"text": "%s takes command (%s)" % [People.person(winner.id).name, "elected" if winner.how == "elected" else "chain of command"],
		"tooltip": People.describe(People.person(winner.id))}]
	var force: Array = Crew.strongmen(s).filter(func(id): return id != winner.id).slice(0, 2)
	for id in force:
		options.append({"text": "%s seizes the ship by force" % People.person(id).name,
			"tooltip": People.describe(People.person(id)) + "

Nobody will argue with them, but the crew start out resentful (morale %d)." % Data.rules.crew.by_force})
	var pick: int = await dialog.ask("Captain %s %s" % [old.name, cause], "%s

%s

You will play on as the new captain." % [how_text, "
".join(lines)], options)
	var id: String = winner.id if pick == 0 else force[pick - 1]
	for m in Crew.make_captain(s, id, winner.how if pick == 0 else "force"):
		hud.show_message(m)
	ship.refresh_stats()
	Contracts.changed.emit()
	_in_event = false
	UIKit.resume_clock()


func _save() -> void:
	var err := SaveGame.save_game(self)
	hud.show_message("Game saved." if err == OK else "Save failed: %s" % error_string(err))


func _load() -> void:
	for screen in [port_screen, crew_screen]:
		if screen.visible:
			screen.close()
	var err := SaveGame.load_game(self)
	port_layer.queue_redraw()
	match err:
		OK: hud.show_message("Game loaded (paused).")
		ERR_INVALID_DATA: hud.show_message("That save is from an older version of the game and can't be loaded. Started a new game instead.")
		_: hud.show_message("Load failed: %s" % error_string(err))


## True while a screen, dialog or battle has the player's attention.
func busy() -> bool:
	return combat != null or _in_event or $BaseScreen.visible or port_screen.visible or crew_screen.visible or prize_screen.visible or dialog.visible


# ---- Encounters and battle -------------------------------------------------

# ---- Encounters and battle -------------------------------------------------

## An NPC ship has come within hail.
func _on_contact(npc: Dictionary) -> void:
	encounter(npc.enemy, npc)


func encounter(enemy: Dictionary, npc := {}) -> void:
	UIKit.pause_clock()
	current_npc = npc
	var s: Dictionary = ship.state
	var seen := Encounters.sighting(enemy, rng)
	var flag_note := ""
	if not npc.is_empty() and npc.flag != Data.table("factions")[enemy.faction].flag:
		flag_note = "\nShe was flying %s colours, but up close she's no %s." % [
			Data.table("factions")[Career.flag_faction(npc.flag)].adjective if Career.flag_faction(npc.flag) != "" else "plain",
			Data.table("factions")[Career.flag_faction(npc.flag)].adjective if Career.flag_faction(npc.flag) != "" else "honest ship"]
	if enemy.has("captain_id"):  # a named captain: who they are to you matters
		var lvl := Bonds.level(s, enemy.captain_id)
		flag_note += "\nIt's %s.%s" % [People.person(enemy.captain_id).name, "" if lvl == 0 else " %s: %s." % [
			"Your ally" if lvl > 0 else "Your rival", Bonds.level_name(enemy.captain_id, lvl)]]
	var job := Contracts.find(enemy.get("contract", ""))
	if not job.is_empty():
		flag_note += "
This is the %s you were hired to find." % enemy.name
		if job.trap:
			flag_note += " But she's no %s: her gunports are open and her decks are packed with men. You were sold out." % job.kind
	var hostile: bool = npc.get("hostile") if npc.get("hostile") != null else Career.npc_hostile(s, enemy, rng)
	if enemy.behaviour == "merchant":
		hostile = false
	if hostile:
		var pick: int = await dialog.ask("Enemy sail!", "A %s is bearing down on you.\n%s%s" % [enemy.label, seen, flag_note], [
			{"text": "Clear for action", "tooltip": "Turn and fight."},
			{"text": "Crowd on sail and run", "tooltip": "Start the fight at long range with the weather gauge likely hers. Win a run for it and you're free.\nA fast, handy ship runs better; a shallower keel can lead her onto the shoals."},
			{"text": "Strike your colours", "tooltip": "Surrender without a fight. They'll strip your hold and take half your gold."},
		])
		match pick:
			0: start_combat(enemy, "defend")
			1: start_combat(enemy, "flee")
			2:
				hud.show_message("You strike without a fight. " + Encounters.surrender_losses(s))
				current_npc = {}
				UIKit.resume_clock()
	else:
		var verdict := Career.judge_attack(s, enemy.faction)
		var hit: int = Data.table("encounters")[enemy.kind].relation_hit
		var tip := "%s\nStanding with %s -%d." % [verdict.why, Data.table("factions")[enemy.faction].name, hit]
		if not verdict.legal:
			tip += " Every other nation -%d. Notoriety +%d. You'll be a pirate." % [Data.rules.career.piracy_all_nations,
				Data.rules.career.notoriety_piracy + Data.table("encounters")[enemy.kind].notoriety]
		elif s.career.marque != "" and enemy.faction != "pirates":
			tip += " Your service counts toward promotion; the Crown takes %d%% of the prize." % int(Career.crown_cut(s) * 100)
		if Career.false_colours(s):
			tip += "\nYou're under false colours: she won't run until it's too late (honour %d)." % Data.rules.flags.false_colours_honour
		if enemy.has("captain_id") and Bonds.level(s, enemy.captain_id) > 0:
			tip += "\n%s is your ally: attacking breaks your %s, and everyone hears of it." % [People.person(enemy.captain_id).name,
				Bonds.level_name(enemy.captain_id, Bonds.level(s, enemy.captain_id)).to_lower()]
		var pick: int = await dialog.ask("Sail ho!", "A %s.\n%s%s" % [enemy.label, seen, flag_note], [
			{"text": "Attack her" + ("" if verdict.legal else " (piracy)"), "tooltip": tip},
			{"text": "Let her pass", "tooltip": "Hold your course."},
		])
		if pick == 0:
			for m in Career.on_attack(s, enemy):
				hud.show_message(m)
			start_combat(enemy, "attack")
		else:
			current_npc = {}
			UIKit.resume_clock()


## The port names and markers sit on a layer of their own (following the camera), so the night doesn't dim them.
## The map's own shaders snap to a grid of art pixels in world space, so there's no screen-wide pixel filter
## to blur things when you zoom out. Day and night tint the world (a CanvasModulate), and lights come on at dusk.
func _pixel_layers() -> void:
	var labels := CanvasLayer.new()
	labels.layer = 2
	labels.follow_viewport_enabled = true
	add_child(labels)
	_overlays = [labels]
	port_layer.reparent.call_deferred(labels)
	hud.layer = 5
	ship.z_index = 2  # above the clouds
	_daylight = CanvasModulate.new()
	add_child(_daylight)
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = 128
	glow.height = 128
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = g
	_lights = []
	for id in Data.table("ports"):
		var l := PointLight2D.new()
		l.texture = glow
		l.color = Color("#ffc46b")
		l.texture_scale = 1.2
		l.position = Geo.latlon_to_px(Data.table("ports")[id].lat, Data.table("ports")[id].lon)
		add_child(l)
		_lights.append(l)
	var lantern := PointLight2D.new()
	lantern.texture = glow
	lantern.color = Color("#ffb85a")
	lantern.texture_scale = 0.6
	lantern.energy = 0.0
	lantern.set_meta("dim", 0.45)  # a lantern, not a lighthouse
	ship.add_child(lantern)
	_lights.append(lantern)
	Clock.ticked.connect(func(_dd): _update_daylight())
	_update_daylight()


## The light of the hour: bright noon, gold at dusk and dawn, blue night with lit towns; storms darken it.
func _update_daylight() -> void:
	var hour := fposmod(Clock.day, 1.0) * 24.0
	var night := clampf((absf(hour - 12.5) - 4.0) / 4.0, 0.0, 1.0)  # 0 from 8.30 to 16.30, gold toward 18, night by 20.30
	var c := Color.WHITE.lerp(Color("#ffcf9a"), clampf(night * 2.0, 0.0, 1.0)).lerp(Color("#5a6cb0"), clampf(night * 2.0 - 1.0, 0.0, 1.0))
	if ship.wind.get("storm", "") != "":
		c = c.darkened(0.3)
	_daylight.color = c
	for l in _lights:
		l.energy = clampf(night * 1.6 - 0.3, 0.0, 1.2) * l.get_meta("dim", 1.0)


func _open_crew() -> void:
	crew_screen.docked = ship.anchored_at != "" or at_base != ""
	crew_screen.open(ship)


func start_combat(enemy: Dictionary, mode: String) -> void:
	UIKit.pause_clock()
	var s: Dictionary = ship.state
	var flag: String = s.get("flag", "white")
	if Data.rules.flags.has(flag):  # the black flag and the red flag strike fear before a shot is fired
		var fx: Dictionary = Data.rules.flags[flag]
		enemy.morale += fx.enemy_morale
		s.reputation.fear += int(fx.fear)
		s.reputation.honour += int(fx.honour)
		hud.show_message("You run up the %s. Her crew blanch." % Data.table("flags")[flag].name.to_lower())
	var dread := ShipStats.look_effect(s, "enemy_morale")  # black sails, a snarling figurehead
	if dread != 0.0:
		enemy.morale += dread
	if mode == "attack" and not Data.rules.flags.has(flag) and Career.false_colours(s):
		if ShipStats.look_effect(s, "no_false_colours") > 0.0:
			hud.show_message("Nobody believes false colours over black sails.")
		else:
			s.reputation.honour += int(Data.rules.flags.false_colours_honour)
			mode = "ambush"
	combat = load("res://scenes/combat.tscn").instantiate()
	_show_world(false)
	get_tree().root.add_child(combat)
	var w := Weather.wind_at(ship.position)
	var side := Encounters.player_side(s)
	side.intel = Encounters.intel_on(s, enemy)
	side.allies = Fleet.allies(s) + Bonds.battle_allies(s, ship.position, shipping).filter(func(a): return a.id == "" or a.id != enemy.get("captain_id", ""))
	if _raid_base != "" and Bases.bases.has(_raid_base):  # the shore guns join in
		for bid in ["battery", "fort"]:
			if Bases.has(Bases.bases[_raid_base], bid):
				side.allies.append({"name": Bases.building(bid).name.to_lower() + " at " + Bases.bases[_raid_base].name, "guns": Bases.building(bid).guns * 2,
					"gun_weight": 12, "gunnery": 10, "id": "", "shore": true})
	_attacked = mode in ["attack", "ambush"]
	if not side.allies.is_empty():
		hud.show_message("Your allies close in to fight beside you: " + ", ".join(side.allies.map(func(a): return "the " + a.name)) + ".")
	combat.start(side, enemy, mode, w.dir, w.strength)
	combat.finished.connect(_on_combat_finished)


func _show_world(on: bool) -> void:
	visible = on
	hud.visible = on
	for layer in _overlays:
		layer.visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _on_combat_finished(result: Dictionary) -> void:
	combat.queue_free()
	combat = null
	_show_world(true)
	camera.make_current()
	var s: Dictionary = ship.state
	for m in Encounters.apply_battle(s, result.player, rng):
		hud.show_message(m)
	for m in Fleet.after_battle(s, result.player.get("allies", [])):
		hud.show_message(m)
	var e: Dictionary = result.enemy_data
	Encounters.remember(s, e, result.enemy.known)
	for m in Contracts.on_battle(s, e, result.outcome, ship.position):
		hud.show_message(m)
	for m in Bonds.on_battle(s, e, result.outcome, _attacked):
		hud.show_message(m)
	if _raid_base != "" and Bases.bases.has(_raid_base):
		var won: bool = result.outcome in ["enemy_struck", "enemy_sunk"]
		hud.show_message(Bases.resolve_raid(s, _raid_base, 4 if won else -3))
		port_layer.queue_redraw()
	_raid_base = ""
	if result.outcome in ["enemy_struck", "enemy_sunk"] and not current_npc.is_empty():
		if current_npc.has("voyage"):  # her cargo never reaches port, and the route remembers
			Economy.lose_voyage(current_npc.voyage, "player")
		shipping.remove(current_npc)
	current_npc = {}
	match result.outcome:
		"enemy_struck", "enemy_sunk":
			Crew.add_mod(s, "battle", "Victory over the %s" % e.name, Data.rules.crew.victory, Data.rules.crew.victory_days)
		"player_struck":
			Crew.add_mod(s, "battle", "We struck our colours", Data.rules.crew.defeat, Data.rules.crew.defeat_days)
	match result.outcome:
		"enemy_struck":
			ShipStats.captain(s).history.append("Took the %s %s, %s." % [Data.table("factions")[e.faction].name, e.name, Clock.date_string()])
			prize_screen.open(ship, result)
			for m in await prize_screen.done:
				hud.show_message(m)
			var allies: Array = result.player.get("allies", [])
			if not allies.is_empty() and e.gold > 0:  # those who fought beside you take their cut
				var cut: float = floorf(e.gold * Data.table("bonds").split * allies.size())
				s.gold = maxf(0.0, s.gold - cut)
				hud.show_message("Your allies take their share of the strongbox: %d gold." % cut)
		"enemy_sunk":
			hud.show_message("The %s sank with all her cargo." % e.name)
		"separated":
			hud.show_message("You and the %s go your separate ways." % e.name)
		"player_struck":
			hud.show_message("You struck your colours. " + Encounters.surrender_losses(s))
		"player_sunk":
			s.hull = 0.0
			ship.route.clear()
			_on_foundered()
			return
	ship.refresh_stats()
	if s.has("succession"):
		await run_succession()
		return
	UIKit.resume_clock()


func _on_foundered() -> void:
	Clock.set_speed(0)
	hud.show_message("The ship has foundered. All hands lost. (Restart to try again.)")
