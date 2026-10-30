extends Node2D
## Ships of the living world. Merchants are the economy's voyages (scripts/economy/traffic.gd), drawn when they
## pass near you: real cargo bound for a real market, so taking one starves that port and frightens that route. Navies patrol their coasts, pirates lurk on the
## trade routes (sometimes under false colours) and take merchants, hunters come for notorious pirates.
## Each NPC carries the same encounter data the battle scene uses. Only ships within sight are drawn.

signal contact(npc: Dictionary)
signal news(text: String)
signal alert(text: String)   # a hostile ship has started bearing down on you: worth pausing for

const SPRITE := preload("res://scenes/ship_sprite.tscn")

var npcs: Array = []   # {id, kind, enemy, pos, heading, route, origin, dest, flag, age, cooldown, hostile}
var next_id := 1
var terrain: TerrainGrid
var world: Node        # the world map: anchorages, the player's ship, busy()
var rng := RandomNumberGenerator.new()
var _routes := {}
var _sprites := {}
var _since_mirror := 1.0


func setup(t: TerrainGrid, w: Node) -> void:
	terrain = t
	world = w
	rng.randomize()
	Clock.ticked.connect(_tick)
	Clock.day_passed.connect(func(_d): daily())


static func cfg() -> Dictionary:
	return Data.rules.shipping


func nm(n: float) -> float:
	return n * Geo.px_per_nm()


# ---- movement --------------------------------------------------------------

func _tick(dd: float) -> void:
	if world == null:
		return
	var player: Node2D = world.ship
	_since_mirror += dd
	if _since_mirror >= 0.25:
		_since_mirror = 0.0
		_mirror(player.position)
	for n in npcs.duplicate():
		move(n, dd, player.position, player.state)
	_fights()
	_contacts(player)
	_update_sprites(player.position)


## One NPC's movement: follow its route, or chase/flee the player when it has reason to.
func move(n: Dictionary, dd: float, player_pos: Vector2, s: Dictionary) -> void:
	if n.has("fight"):  # hove to, broadside to broadside
		return
	var e: Dictionary = n.enemy
	var st := ShipStats.effective(e.type, e.upgrades)
	var dist: float = n.pos.distance_to(player_pos)
	var vis := Weather.visibility(player_pos)  # fog and the dark: you can slip past, or creep up unseen
	var sight := nm(cfg().sight_nm) * vis
	var target: Vector2
	var free_course := false  # off its route: deep keels won't follow into shallows
	if dist > sight:
		n.hostile = null  # out of sight: they'll judge you afresh next time
		n.search = false
	elif n.hostile == null and n.kind != "merchant":
		n.hostile = Career.npc_hostile(s, e, rng)
		# a friendly patrol may want a look in your hold: she comes to you, the rest hold their course
		n.search = not n.hostile and e.behaviour == "warship" and e.kind == "navy" and not n.get("treasure", false) and AtSea.wants_search(s, e.faction, rng)
	var was_chasing: bool = n.get("chasing", false)
	n.chasing = false
	var detour: bool = n.get("detour_until", 0.0) > Clock.day  # an island was in the way: following a path round it
	if detour and not n.route.is_empty():
		target = n.route[0]
	elif n.kind != "merchant" and (n.hostile == true or n.get("search", false)) and dist < nm(cfg().chase_nm) * vis and s.hull > 0:
		target = player_pos
		free_course = true
		n.chasing = true
		if not was_chasing and n.hostile != true:
			news.emit("The %s %s is closing on you, signalling you to heave to." % [Data.table("factions")[e.faction].adjective, e.name])
		elif not was_chasing:
			alert.emit("The %s is bearing down on you from the %s!" % [n.enemy.name, Geo.compass_name(Geo.bearing(n.pos - player_pos))])
	elif n.kind == "merchant" and dist < sight and wary(n, s):
		target = n.pos + (n.pos - player_pos).normalized() * 200.0
		free_course = true
	elif not n.route.is_empty():
		target = n.route[0]
	else:
		_new_goal(n)
		return
	var heading := Geo.bearing(target - n.pos)
	var wind := Weather.wind_at(n.pos)
	var knots: float = st.speed_knots * Sailing.best_course(st.polar, Geo.angle_between(heading, wind.dir)).factor * wind.strength * cfg().npc_speed_factor
	var next: Vector2 = n.pos.move_toward(target, Geo.knots_to_px_per_day(knots) * dd)
	var ground := terrain.at(next)
	var deep: bool = Data.rules.draught[st.draught].route_cost > 1.0
	if free_course and (ground == TerrainGrid.LAND or (deep and ground >= TerrainGrid.SHALLOW)):
		# can't go there: a sloop that runs into the shallows leaves a frigate behind, for a while.
		# If she's stuck, she finds a way round instead of sitting against the coast forever.
		n.stuck = n.get("stuck", 0.0) + dd
		if n.stuck > 0.3:
			n.stuck = 0.0
			n.detour_until = Clock.day + 1.0
			n.route = terrain.find_path(n.pos, terrain.nearest_sea(target))
		return
	n.stuck = 0.0
	# Following a found path, she trusts it: its corners may clip a coast cell at a narrow cove mouth.
	n.pos = next
	n.heading = heading
	if not free_course and not n.route.is_empty() and n.pos.distance_to(n.route[0]) < 1.0:
		n.route.remove_at(0)
		if n.route.is_empty():
			_arrive(n)


## Merchants run from anyone flying colours that threaten them.
func wary(n: Dictionary, s: Dictionary) -> bool:
	var shown := Career.flag_faction(s.get("flag", "white"))
	return shown == "pirates" or Factions.at_war(shown, n.enemy.faction)


## Only two kinds of meeting stop you: a ship you chose to run down (clicked), and one that came after you.
## Everyone else passes by on her own business.
func _contacts(player: Node2D) -> void:
	if world.busy() or player.anchored_at != "" or player.state.hull <= 0:
		return
	for n in npcs:
		var wanted: bool = n.id == world.chase_id or (n.get("chasing", false) and n.cooldown <= Clock.day)
		if wanted and n.pos.distance_to(player.position) < nm(cfg().contact_nm):
			n.cooldown = Clock.day + cfg().contact_cooldown_days
			contact.emit(n)
			return


func _arrive(n: Dictionary) -> void:
	if n.get("treasure", false):
		_say(n, "The treasure galleon %s has reached Havana safely." % n.enemy.name, true)
		remove(n)
		return
	if n.has("escort"):  # the merchant you were seeing safely to port
		var text := Contracts.escort_arrived(n.escort, world.ship.state)
		if text != "":
			news.emit("The %s has made %s safely. %s" % [n.enemy.name, Ports.port(n.dest).name, text])
		remove(n)
		return
	if n.has("expedition") or n.has("invasion"):  # off the town: she waits for the day of the assault
		_new_goal(n)
		return
	if n.kind == "merchant":
		if not n.has("voyage"):  # a contract's ship; a voyage's cargo reaches the market on the economy's schedule
			for g in n.enemy.cargo:
				Economy.add(n.dest, g, n.enemy.cargo[g])
		remove(n)
	else:
		_new_goal(n)


func _new_goal(n: Dictionary) -> void:
	var goal: Vector2
	if n.has("hunting"):  # raiders after a particular ship: they follow her
		var prey := find(n.hunting)
		if not prey.is_empty():
			_set_course(n, prey.pos)
			return
		n.erase("hunting")
	if n.has("captain_id") and Bonds.level(world.ship.state, n.captain_id) <= -3 and rng.randf() < 0.7:
		n.route = terrain.find_path(n.pos, world.ship.position)  # a blood feud: they come looking for you
		if not n.route.is_empty():
			return
	if n.has("home"):  # a contract target keeps to the waters she was reported in
		var r: float = nm(Data.rules.contracts.lurk_nm)
		goal = terrain.nearest_sea(world.anchorages[n.home] + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)))
		_set_course(n, goal)
		return
	var br: Brethren = Economy.model.brethren
	match n.kind:
		"navy":  # hunting where the pirates have been taking prizes, or showing the flag off her own ports
			var hot := _hot_ground(br)
			var own := _ports_of(n.enemy.faction)
			var ports: Array = br.cfg().grounds[hot].ports if hot != "" and n.enemy.kind == "navy" and rng.randf() < 0.6 else own
			ports = ports.filter(func(id): return world.anchorages.has(id))
			var a: Vector2 = world.anchorages[ports[rng.randi() % ports.size()]] if not ports.is_empty() else n.pos
			goal = terrain.nearest_sea(a + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90)))
		"hunter":
			goal = world.ship.position if rng.randf() < 0.6 else world.anchorages[Ports.state.keys()[rng.randi() % Ports.state.size()]]
		_ when n.has("company") and not br.find(n.company).is_empty():  # a company works its cruising ground
			var ports: Array = br.cfg().grounds[br.find(n.company).ground].ports.filter(func(id): return world.anchorages.has(id))
			var a: Vector2 = world.anchorages[ports[rng.randi() % ports.size()]]
			goal = terrain.nearest_sea(a + Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120)))
		_:  # pirates lurk somewhere along a trade route
			var ids: Array = Ports.state.keys()
			var a: Vector2 = world.anchorages[ids[rng.randi() % ids.size()]]
			var b: Vector2 = world.anchorages[ids[rng.randi() % ids.size()]]
			goal = terrain.nearest_sea(a.lerp(b, rng.randf_range(0.3, 0.7)))
	_set_course(n, goal)


## A path to the goal. If there's none (she's somewhere the pathfinder can't start from, deep in a cove),
## she's eased out to the nearest open sea and tries again later, rather than sailing straight at the land.
func _set_course(n: Dictionary, goal: Vector2) -> void:
	n.route = terrain.find_path(n.pos, goal)
	if n.route.is_empty():
		n.pos = terrain.nearest_sea(n.pos)
		n.route = terrain.find_path(n.pos, goal)


# ---- the daily round: spawning, ageing, ships meeting ships ----------------

func daily() -> void:
	for n in npcs.duplicate():
		n.age += 1
		if n.age > cfg().max_age_days and not n.has("contract") and not n.has("captain_id") and not n.has("company") and not n.get("treasure", false) and not n.has("expedition") and not n.has("escort") and not n.has("invasion"):  # contract targets and named captains stay
			remove(n)
		elif n.has("captain_id") and not n.has("fight") and _stale_captain(n):
			remove(n)  # dead, ashore, or in a new ship or service: they'll put to sea again as they are now
		elif n.has("expedition") and Bases.bases.get(n.expedition, {}).get("raid", {}).get("npc", "") != n.id:
			remove(n)  # the expedition is over, one way or the other
		elif n.has("invasion") and Factions.invasion_at(n.invasion).get("npc", "") != n.id:
			remove(n)  # the attack is over
	_companies()
	var b: Brethren = Economy.model.brethren
	for f in Career.nations():  # as many men-of-war as the nation has on station against the pirates, up to a few
		var want := mini(int(cfg().navy_per_faction), roundi(b.navy.get(f, 1.0)))
		if not _ports_of(f).is_empty() and npcs.filter(func(n): return n.kind == "navy" and n.enemy.faction == f and n.enemy.kind == "navy").size() < want:
			spawn("navy", f)
	var s: Dictionary = world.ship.state
	var price := Career.bounty_total(s)
	var per: float = Data.rules.career.bounty.per_hunter
	if (Career.hunted(s) or Career.wanted(s)) and count("hunter") < cfg().hunters_max + int(price / per) and rng.randf() < cfg().hunter_spawn_chance * (1.0 + price / per):
		var worst := Career.bounty_by(s)
		if worst == "":
			worst = Career.nations().reduce(func(a, b): return a if s.relations[a] < s.relations[b] else b)
		var h := spawn("hunter", worst, "", Career.hunter_ship(s))
		_say(h, "Word in the taverns: a %s pirate hunter, the %s (%s), has sailed to collect the %d gold on your head." % [
			Data.table("factions")[worst].adjective, h.enemy.name, Data.table("ships")[h.enemy.type].name.to_lower(), s.get("bounty", {}).get(worst, 0.0)], true)
	if npcs.filter(func(n): return n.enemy.kind == "smuggler").size() < cfg().smugglers:
		_spawn_trader("smuggler")
	if npcs.filter(func(n): return n.enemy.kind == "coaster").size() < cfg().coasters:
		_spawn_trader("coaster")
	if not _ports_of("spain").is_empty() and npcs.filter(func(n): return n.enemy.kind == "guarda_costa").size() < cfg().guarda_costas:
		spawn("navy", "spain", "guarda_costa")
	_expeditions()
	_invasions()
	_meetings()


## A smuggler runs a Spanish port's forbidden goods in from a foreign island; a coaster carries a port's own goods
## to a neighbour. Both sail like merchants, and what they carry lands in the market they're bound for.
func _spawn_trader(kind: String) -> void:
	var origin := ""
	var dest := ""
	var cargo := {}
	if kind == "smuggler":
		var markets: Array = Ports.state.keys().filter(func(id): return not Ports.state[id].laws.contraband.is_empty() and world.anchorages.has(id))
		var homes: Array = Ports.state.keys().filter(func(id): return Ports.port(id).faction in ["dutch", "england"] and world.anchorages.has(id))
		if markets.is_empty() or homes.is_empty():
			return
		dest = markets[rng.randi() % markets.size()]
		homes = homes.filter(func(id): return Ports.port(id).faction != Ports.port(dest).faction)
		if homes.is_empty():
			return
		origin = homes[rng.randi() % homes.size()]
		var goods: Array = Ports.state[dest].laws.contraband
		cargo[goods[rng.randi() % goods.size()]] = 1
	else:
		var ports: Array = Ports.state.keys().filter(func(id): return Ports.port(id).faction != "pirates" and world.anchorages.has(id))
		if ports.size() < 2:
			return
		origin = ports[rng.randi() % ports.size()]
		var here: Vector2 = world.anchorages[origin]
		ports = ports.filter(func(id): return id != origin and not Factions.at_war(Ports.port(id).faction, Ports.port(origin).faction))
		if ports.is_empty():
			return
		ports.sort_custom(func(a, b): return world.anchorages[a].distance_to(here) < world.anchorages[b].distance_to(here))
		for p in ports:  # the nearest neighbour she can actually sail to
			if not _route(origin, p).is_empty():
				dest = p
				break
		if dest == "":
			return
		var makes: Array = Economy.produces(origin)
		if not makes.is_empty():
			cargo[makes[rng.randi() % makes.size()]] = 1
	if _route(origin, dest).is_empty():
		return
	var f: String = Ports.port(origin).faction
	var e := Encounters.generate(f, rng, kind)
	var room: float = ShipStats.effective(e.type, e.upgrades).cargo * rng.randf_range(0.4, 0.9)
	e.cargo = {}
	for g in cargo:
		e.cargo[g] = maxi(1, int(room / Market.weight(g)))
	var n := _add("merchant", e, world.anchorages[origin], Data.table("factions")[f].flag)
	n.origin = origin
	n.dest = dest
	n.route = _route(origin, dest)


## Expeditions to retake your towns sail from their nation's nearest port some days before they're due:
## catch one at sea and beat it, and that attempt is over.
func _expeditions() -> void:
	var lead: float = Data.rules.sieges.hold.expedition.lead_days
	for id in Bases.bases:
		var b: Dictionary = Bases.bases[id]
		var r: Dictionary = b.raid
		if not b.has("town") or r.get("kind", "") != "expedition" or r.has("npc") or r.day - Clock.day > lead or not world.anchorages.has(id):
			continue
		var ships: Array = Data.rules.sieges.hold.expedition.ships
		var n := _sail_against(b.town.from, id, ships[mini(int(b.town.get("failed", 0)), ships.size() - 1)], "the expedition to retake %s" % b.name)
		r.npc = ""
		if n.is_empty():
			continue  # nowhere to sail from: it comes anyway, unseen
		n.expedition = id
		r.npc = n.id


## Wartime squadrons sent to take a town (Factions.invasions): they sail lead_days before the attack is due.
func _invasions() -> void:
	var inv: Dictionary = Data.rules.diplomacy.invasion
	for x in Factions.invasions:
		if x.spawned or x.due - Clock.day > inv.lead_days or not world.anchorages.has(x.port):
			continue
		x.spawned = true
		var n := _sail_against(x.by, x.port, inv.ships[Ports.port(x.port).size], "the %s squadron sent against %s" % [
			Data.table("factions")[x.by].adjective, Ports.port(x.port).name])
		if n.is_empty():
			x.unseen = true  # nowhere to sail from: the attack comes anyway, unseen
			continue
		n.invasion = x.port
		x.npc = n.id


## A warship of nation f sailing from its nearest port to attack town `to`, announced in the taverns. {} if
## no port of theirs has a route there.
func _sail_against(f: String, to: String, type: String, label: String) -> Dictionary:
	var homes: Array = (_ports_of(f) if f != "pirates" else Ports.state.keys().filter(func(p): return Ports.port(p).get("fence", false)))
	homes = homes.filter(func(p): return p != to and not Bases.bases.has(p) and world.anchorages.has(p) and not _route(p, to).is_empty())
	if homes.is_empty():
		return {}
	var here: Vector2 = world.anchorages[to]
	homes.sort_custom(func(a, c): return world.anchorages[a].distance_to(here) < world.anchorages[c].distance_to(here))
	var kind := "pirate" if f == "pirates" else "navy"
	var e := Encounters.generate(f, rng, kind, type)
	e.label = label
	var n := _add(kind, e, world.anchorages[homes[0]], Data.table("factions")[f].flag)
	n.origin = homes[0]
	n.dest = to
	n.route = _route(homes[0], to)
	n.home = to  # once there, she waits off the town for the day of the attack
	_say(n, "Word from %s: the %s, %s, has sailed. Catch her at sea and the attack is off." % [Ports.port(homes[0]).name, e.name, label], true)
	return n


## Pirates fall on merchants and navies run down pirates. Where you can see, it's a fight that lasts a while,
## and you can come up and take a side; out of sight it's over before you'd know.
func _meetings() -> void:
	var player_pos: Vector2 = world.ship.position
	var sight := nm(cfg().sight_nm) * 1.5 * Weather.visibility(player_pos)
	for p in npcs.filter(func(n): return n.kind == "pirate" and not n.has("fight")):
		for m in npcs.filter(func(n): return n.kind == "merchant" and not n.has("contract") and not n.has("captain_id") and not n.has("fight")):
			if p.pos.distance_to(m.pos) < nm(cfg().contact_nm) * 2.0 and p.pos.distance_to(player_pos) < sight:
				_start_fight(p, m)
				break
			if p.pos.distance_to(m.pos) < nm(cfg().contact_nm) * 2.0:
				for g in m.enemy.cargo:
					p.enemy.cargo[g] = p.enemy.cargo.get(g, 0) + m.enemy.cargo[g]
				_say(m, "Pirates took the %s merchantman %s; her cargo never reached %s." % [
					Data.table("factions")[m.enemy.faction].adjective, m.enemy.name, Ports.port(m.dest).name])
				_fame(p, 2)
				if m.has("voyage"):
					Economy.lose_voyage(m.voyage, "pirates", p.get("company", ""))
				remove(m)
	for v in npcs.filter(func(n): return (n.kind == "navy" or n.kind == "hunter") and not n.has("fight") and not n.get("treasure", false)):
		for p in npcs.filter(func(n): return n.kind == "pirate" and not n.has("contract") and not n.has("captain_id") and not n.has("fight")):
			if v.pos.distance_to(p.pos) < nm(cfg().contact_nm) * 2.0 and v.pos.distance_to(player_pos) < sight:
				_start_fight(v, p)
				break
			if v.pos.distance_to(p.pos) < nm(cfg().contact_nm) * 2.0:
				_say(p, "The %s navy chased the pirate %s off her cruising ground." % [Data.table("factions")[v.enemy.faction].adjective, p.enemy.name])
				remove(p)  # out of your sight the Brethren model decides who's caught (its catch_rate): counting it here too wiped them out


func _start_fight(a: Dictionary, v: Dictionary) -> void:
	var until := Clock.day + float(Data.rules.at_sea.npc_battle_days)
	a.fight = {"with": v.id, "until": until, "attacker": true}
	v.fight = {"with": a.id, "until": until, "attacker": false}
	a.cooldown = 0.0
	v.cooldown = 0.0
	var where := Geo.compass_name(Geo.bearing(a.pos - world.ship.position))
	alert.emit("Gunfire to the %s! The %s %s has fallen on the %s %s. (Click one of them to take a hand.)" % [where, a.enemy.label, a.enemy.name, v.enemy.label, v.enemy.name])


## Fights whose time is up end on their own.
func _fights() -> void:
	for n in npcs.duplicate():
		if n.has("fight") and n.fight.attacker and Clock.day >= n.fight.until and not world.busy():
			resolve_fight(n)


## How a fight between two NPC ships ends: the stronger usually wins (the one who chose the fight has an edge),
## and nobody comes out of it unhurt. A ship taken or sunk leaves wreckage. Returns the winner.
func resolve_fight(a: Dictionary) -> Dictionary:
	var v := find(a.fight.with)
	a.erase("fight")
	if v.is_empty():
		return a
	v.erase("fight")
	var pa := AtSea.strength(a.enemy) * float(Data.rules.at_sea.attacker_edge)
	var a_wins := rng.randf() < pa / (pa + AtSea.strength(v.enemy))
	var w: Dictionary = a if a_wins else v
	var l: Dictionary = v if a_wins else a
	AtSea.hurt(w.enemy, rng.randf_range(0.15, 0.4))
	w.cooldown = 0.0  # come up on the winner now, and she's in no state to run far
	_fame(w, int(Data.table("bonds").growth.fight_won))
	var pos: Vector2 = (a.pos + v.pos) / 2.0
	if a_wins and l.kind == "merchant":
		for g in l.enemy.cargo:
			w.enemy.cargo[g] = w.enemy.cargo.get(g, 0) + l.enemy.cargo[g]
		_say(l, "The pirate %s took the merchantman %s; her cargo will never reach %s." % [w.enemy.name, l.enemy.name, Ports.port(l.dest).name if Ports.state.has(l.dest) else "port"], true)
		if l.has("voyage"):
			Economy.lose_voyage(l.voyage, "pirates", w.get("company", ""))
		remove(l)
	elif l.kind == "pirate":
		_say(l, "The %s ran down the pirate %s. She went down fighting." % [w.enemy.name, l.enemy.name], true)
		if l.has("company"):
			Economy.model.brethren.lose(l.company, "navy")
		remove(l)
	else:
		AtSea.hurt(l.enemy, rng.randf_range(0.3, 0.5))
		_say(l, "The %s beat off the %s, and both ships limp away." % [w.enemy.name, l.enemy.name], true)
		return w
	if world.get("finds") != null:
		var inst := Events.instance_of("battle_wreckage", world._event_ctx())
		if not inst.is_empty():
			world.finds.spawn(inst, pos, 0.0)
	return w


## A named captain's name grows with every ship they take.
func _fame(n: Dictionary, amount: int) -> void:
	if n.has("captain_id"):
		var text := Bonds.grow(n.captain_id, amount)
		if text != "":
			news.emit(text)


func _say(n: Dictionary, text: String, always := false) -> void:
	if always or world.ship.position.distance_to(n.pos) < nm(cfg().sight_nm) * 2.0:
		news.emit(text)


## A treasure galleon, sailing from the fair to join the fleet at Havana with the year's silver aboard.
func spawn_treasure(port: String, value: float) -> Dictionary:
	if not world.anchorages.has(port) or not world.anchorages.has("havana") or port == "havana":
		return {}
	var e := Encounters.generate("spain", rng, "navy", "galleon")
	e.name = ["Nuestra Senora de Atocha", "Nuestra Senora de la Concepcion", "Santa Margarita", "San Jose", "Nuestra Senora de Guadalupe"][rng.randi() % 5]
	e.label = "the treasure galleon"
	e.cargo = {"silver": maxi(10, int(value * 0.7 / 200.0)), "gold": maxi(2, int(value * 0.3 / 600.0))}
	e.morale = 85.0
	var n := _add("navy", e, world.anchorages[port], Data.table("factions").spain.flag)
	n.treasure = true
	n.origin = port
	n.dest = "havana"
	n.route = _route(port, "havana")
	return n


## A merchant voyage from the economy (Economy.voyages()), drawn as a ship where she is along her route right now.
## Her cargo is the voyage's. She's the same voyage: take her and the cargo never reaches port.
func spawn_voyage(v: Dictionary, pos: Vector2, rest: PackedVector2Array) -> Dictionary:
	var f: String = v.faction
	var e := Encounters.generate(f, rng, "merchant")
	e.cargo = {v.good: v.qty}
	var n := _add("merchant", e, pos, Data.table("factions")[f].flag)
	n.voyage = v.id
	n.origin = v.origin
	n.dest = v.dest
	n.route = rest
	return n


## Ships at sea near you (or a watchtower) are drawn from the voyages; ones far out of sight are let go
## (the voyage sails on, unseen). Checked a few times a day.
func _mirror(player_pos: Vector2) -> void:
	var near := nm(cfg().sight_nm) * 1.5
	var eyes: Array = [player_pos] + Bases.watch_points()
	var drawn := {}
	for n in npcs.duplicate():
		if not n.has("voyage"):
			continue
		if eyes.all(func(p): return n.pos.distance_to(p) > near * 2.0):
			remove(n)
		else:
			drawn[n.voyage] = true
	for v in Economy.voyages():
		if drawn.has(v.id) or not world.anchorages.has(v.origin) or not world.anchorages.has(v.dest):
			continue
		var path := _route(v.origin, v.dest)
		if path.is_empty():
			continue
		var at := _along(world.anchorages[v.origin], path, Economy.progress(v))
		if eyes.any(func(p): return at[0].distance_to(p) < near):
			spawn_voyage(v, at[0], at[1])


## The point a fraction f of the way along a route, and the rest of the route from there: [Vector2, PackedVector2Array].
static func _along(start: Vector2, path: PackedVector2Array, f: float) -> Array:
	var total := 0.0
	var prev := start
	for p in path:
		total += prev.distance_to(p)
		prev = p
	var left := total * f
	prev = start
	for i in path.size():
		var seg := prev.distance_to(path[i])
		if left <= seg:
			return [prev.move_toward(path[i], left), path.slice(i)]
		left -= seg
		prev = path[i]
	return [prev, PackedVector2Array()]


## Every pirate company working the islands is a ship on the map (scripts/economy/brethren.gd): her captain, her
## name and her men are the company's. One that has gone north, been taken or come in for a pardon sails off once
## she's out of sight.
func _companies() -> void:
	var b: Brethren = Economy.model.brethren
	var here := {}
	for n in npcs.duplicate():
		if not n.has("company"):
			continue
		var co := b.find(n.company)
		if co.is_empty() or co.away:
			if not _sprites.has(n.id) and not n.has("fight"):
				remove(n)
			continue
		here[co.id] = true
		n.enemy.crew = mini(co.men, int(ShipStats.effective(n.enemy.type, n.enemy.upgrades).crew_max))
	for co in b.companies:
		if not co.away and not here.has(co.id):
			_spawn_company(co)


func _spawn_company(co: Dictionary) -> Dictionary:
	var e := Encounters.generate("pirates", rng, "pirate", co.ship)
	e.name = co.name
	e.captain.name = co.captain
	e.crew = mini(co.men, int(ShipStats.effective(e.type, e.upgrades).crew_max))
	var flag: String = Data.table("factions").pirates.flag
	if rng.randf() < Data.rules.flags.npc_false_flag_chance:
		var nat: Array = Career.nations()
		flag = Data.table("factions")[nat[rng.randi() % nat.size()]].flag  # honest-looking colours
	var ports: Array = ([co.haven] if co.haven != "" else []) + Economy.model.brethren.cfg().grounds.get(co.ground, {}).get("ports", [])  # older saves: companies without a ground
	ports = ports.filter(func(id): return world.anchorages.has(id))
	var n := _add("pirate", e, terrain.nearest_sea(world.anchorages[ports[0]]), flag)
	n.company = co.id
	_new_goal(n)
	return n


## The cruising ground where the most prizes have been taken lately, or "" if none.
func _hot_ground(b: Brethren) -> String:
	var best := ""
	for g in b.heat:
		if b.heat[g] > 0.5 and (best == "" or b.heat[g] > b.heat[best]):
			best = g
	return best


## kind: how she sails (merchant, navy, pirate, hunter); ekind: what she is, if not that (a guarda costa sails as a navy).
func spawn(kind: String, f: String, ekind := "", type := "") -> Dictionary:
	var e := Encounters.generate(f, rng, ekind if ekind != "" else kind, type)
	var flag: String = Data.table("factions")[f].flag
	if kind == "pirate" and rng.randf() < Data.rules.flags.npc_false_flag_chance:
		var nat: Array = Career.nations()
		flag = Data.table("factions")[nat[rng.randi() % nat.size()]].flag  # honest-looking colours
	var homes := _ports_of(f) if f != "pirates" else Ports.state.keys().filter(func(id): return Ports.port(id).get("fence", false))
	var n := _add(kind, e, world.anchorages[homes[rng.randi() % homes.size()]], flag)
	_new_goal(n)
	return n


## A named captain from the roster (Bonds), in their own ship, haunting their home waters.
func spawn_captain(id: String) -> Dictionary:
	var c := People.person(id)
	var kind := "pirate" if c.faction == "pirates" else "hunter"
	var e := Encounters.generate(c.faction, rng, kind, c.ship_type)
	e.name = c.ship
	e.captain = c.duplicate(true)
	e.captain_id = id
	e.label = "the %s, %s's ship" % [c.ship, c.name]
	var flag: String = Data.table("factions")[c.faction].flag
	var n := _add(kind, e, world.anchorages[c.haunt], flag)
	n.captain_id = id
	n.home = c.haunt
	_new_goal(n)
	return n


func _stale_captain(n: Dictionary) -> bool:
	if not Bonds.exists(n.captain_id):
		return true
	var c := People.person(n.captain_id)
	return n.enemy.name != c.ship or n.kind != ("pirate" if c.faction == "pirates" else "hunter")


## A merchant you're hired to escort, and the raiders who'll be after her: they wait along her course.
func spawn_escort(e: Dictionary, origin: String, dest: String, contract_id: String, raiders: int) -> Dictionary:
	var n := _add("merchant", e, world.anchorages[origin], Data.table("factions")[e.faction].flag)
	n.escort = contract_id
	n.origin = origin
	n.dest = dest
	n.route = _route(origin, dest)
	for i in raiders:
		var r := spawn("pirate", "pirates")
		var at: Array = _along(world.anchorages[origin], n.route, rng.randf_range(0.35, 0.7))
		r.pos = terrain.nearest_sea(at[0] + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60)))
		r.hunting = n.id
		r.route = PackedVector2Array()
	return n


## A named ship for a contract. Merchants sail origin to dest; the others lurk near origin.
func spawn_target(kind: String, e: Dictionary, origin: String, dest: String) -> Dictionary:
	var n := _add(kind, e, world.anchorages[origin], Data.table("factions")[e.faction].flag)
	n.contract = e.contract
	if dest != "":
		n.origin = origin
		n.dest = dest
		n.route = _route(origin, dest)
	else:
		n.home = origin
		_new_goal(n)
	return n


func _add(kind: String, e: Dictionary, pos: Vector2, flag: String) -> Dictionary:
	var n := {"id": "n%d" % next_id, "kind": kind, "enemy": e, "pos": pos, "heading": 0.0, "route": PackedVector2Array(),
		"origin": "", "dest": "", "flag": flag, "age": 0, "cooldown": 0.0, "hostile": null}
	next_id += 1
	npcs.append(n)
	return n


func _route(a: String, b: String) -> PackedVector2Array:
	var key := a + ">" + b
	if not _routes.has(key):
		_routes[key] = terrain.find_path(world.anchorages[a], world.anchorages[b])
	return _routes[key].duplicate()


func remove(n: Dictionary) -> void:
	npcs.erase(n)
	if _sprites.has(n.id):
		_sprites[n.id].queue_free()
		_sprites.erase(n.id)


func count(kind: String) -> int:
	return npcs.filter(func(n): return n.kind == kind).size()


func npc_at(pos: Vector2, radius: float) -> Dictionary:
	for n in npcs:
		if n.pos.distance_to(pos) < radius and _sprites.has(n.id):
			return n
	return {}


func find(id: String) -> Dictionary:
	for n in npcs:
		if n.id == id:
			return n
	return {}


func _ports_of(f: String) -> Array:
	return Ports.state.keys().filter(func(id): return Ports.port(id).faction == f)


# ---- drawing: sprites for ships within sight -------------------------------

func _update_sprites(player_pos: Vector2) -> void:
	var sight := nm(cfg().sight_nm) * Weather.visibility(player_pos)
	for n in npcs:
		var visible: bool = n.pos.distance_to(player_pos) < sight or Bases.watch_points().any(func(w): return n.pos.distance_to(w) < sight)  # watchtowers see too
		if visible and not _sprites.has(n.id):
			var shown := Career.flag_faction(n.flag)
			var adj: String = Data.table("factions")[shown].adjective if shown != "" and shown != "pirates" else ""
			news.emit("Sail ho: %s %s to the %s." % ["a pirate" if shown == "pirates" else (("an " if adj.left(1).to_lower() in "aeiou" else "a ") + adj if adj != "" else "an unmarked"),
				Data.table("ships")[n.enemy.type].name.to_lower(), Geo.compass_name(Geo.bearing(n.pos - player_pos))])
			var sp: Node2D = SPRITE.instantiate()
			add_child(sp)
			sp.setup(n.enemy.type, n.flag)
			sp.scale = Vector2.ONE * 0.74
			_sprites[n.id] = sp
		elif not visible and _sprites.has(n.id):
			_sprites[n.id].queue_free()
			_sprites.erase(n.id)
		if visible:
			var sp: Node2D = _sprites[n.id]
			sp.position = n.pos
			sp.rotation = lerp_angle(sp.rotation, deg_to_rad(n.heading), 0.12)  # she comes about, she doesn't snap
			sp.set_state(1.0, 1.0, 2)
	queue_redraw()


func _draw() -> void:
	var font := Style.font("pixel")
	for n in npcs:
		if _sprites.has(n.id):
			var back := -Geo.from_bearing(n.heading)
			for k in range(1, 6):  # her wake
				draw_rect(Rect2(n.pos + back * (6.0 + k * 3.0) - Vector2(1, 1), Vector2(2, 2)), Color(0.95, 0.98, 1.0, 0.6 - k * 0.1))
			draw_set_transform(n.pos, 0.0, Geo.UPRIGHT)
			draw_string_outline(font, Vector2(-60, -18), n.enemy.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, 4, Color(0.04, 0.08, 0.16, 0.7))
			draw_string(font, Vector2(-60, -18), n.enemy.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(0.95, 0.95, 0.9))
			draw_set_transform(Vector2.ZERO)
			if n.has("fight") and n.fight.attacker:
				_gunfire(n)


## Two ships in a fight on the chart: flashes along their sides and drifting powder smoke.
func _gunfire(a: Dictionary) -> void:
	var v := find(a.fight.with)
	if v.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	for k in 6:
		var ph := fposmod(t * 0.7 + k / 6.0, 1.0)
		var from: Vector2 = a.pos if k % 2 == 0 else v.pos
		var to: Vector2 = v.pos if k % 2 == 0 else a.pos
		var at := from.lerp(to, 0.15 + (k % 3) * 0.05)
		draw_circle(at + Vector2(ph * 6.0, -ph * 8.0), 2.0 + ph * 5.0, Color(0.85, 0.83, 0.8, 0.55 * (1.0 - ph)))
		if ph < 0.12:
			draw_circle(from.lerp(to, 0.12), 2.5, Color(1.0, 0.8, 0.35, 0.9))


# ---- saving ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {"npcs": npcs, "next_id": next_id}


func load_state(d: Dictionary) -> void:
	for id in _sprites:
		_sprites[id].queue_free()
	_sprites = {}
	npcs = d.npcs
	next_id = d.next_id
