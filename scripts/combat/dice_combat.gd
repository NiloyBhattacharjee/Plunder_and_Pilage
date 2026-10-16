class_name DiceCombat
extends RefCounted
## A sea fight as a tabletop battle. Two ships at a range band (Long, Medium, Close, Grappled), one of them
## holding the weather gauge. Each round every officer on each side takes one action: d20 + skill + situation
## against a DC or an opposed roll. sides[0] is the player, sides[1] the enemy.
## Actions are data (data/combat_actions.json); their effects are implemented here by id.

const PHASE := {  # support first, then manoeuvres, then guns, then the rest
	"steady": 0, "read_wind": 0, "shoals": 0, "hold": 0, "arm": 0, "keep_order": 0, "push": 0, "hold_rail": 0, "join_boarders": 0,
	"close": 1, "open": 1, "gauge": 1, "grapple": 1, "flee": 1, "cut_loose": 1,
	"round": 2, "chain": 2, "grape": 2, "chase": 2,
	"rally": 3, "intimidate": 3, "demand": 3, "duel": 3, "strike": 3, "plug": 3, "rigging": 3, "tend": 3,
}

var sides: Array = []
var band := 0
var gauge := 0
var round_no := 0
var wind_strength := 1.0
var rng := RandomNumberGenerator.new()
var entries: Array = []   # this round's log: {side, post, name, action, text, check?}
var result := ""          # "", enemy_struck, player_struck, enemy_sunk, player_sunk, separated
var orders: Array = [{}, {}]
var _mods: Array = []     # per side, this round: {all, boatswain, gunner, melee, guard, shoals}


static func cfg() -> Dictionary:
	return Data.rules.dice_combat


static func actions() -> Dictionary:
	return Data.table("combat_actions")


## data: {name, type, upgrades, hull, sails, crew, morale, roles, party: {post: {name, id, skills, stats}}, behaviour, kind, guns_lost}
static func make_side(data: Dictionary) -> Dictionary:
	var s := data.duplicate(true)
	s.stats = ShipStats.effective(data.type, data.get("upgrades", []))
	s.hull = float(s.hull)
	s.sails = float(s.sails)
	s.crew = float(s.crew)
	s.crew_start = s.crew
	s.hull_start = s.hull
	s.morale = float(s.morale)
	s.masts = int(s.stats.masts)
	s.guns_working = int(s.stats.guns) - int(data.get("guns_lost", 0))
	s.casualties = 0.0
	s.leak = 0
	s.fire = 0
	s.rudder = 0
	s.armed = false
	s.stance = "hold"
	s.struck = false
	s.captain_wounded = false
	s.officer_wounds = []
	s.xp = {}
	if not s.has("roles"):
		s.roles = Data.rules.crew_roles.presets.balanced.duplicate()
	return s


## Officers for an NPC ship, by kind: their main skill from the encounter's skill range.
static func npc_party(enemy: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var e: Dictionary = Data.table("encounters")[enemy.kind]
	var posts: Array = cfg().enemy_posts.get(enemy.kind, cfg().enemy_posts.merchant)
	var party := {}
	for post in posts:
		var c: Dictionary = enemy.captain if post == "captain" else People.generate({"mix": Data.rules.people.recruit_mix[enemy.faction]})
		var m := {"name": c.name, "id": "", "skills": {}, "stats": {}}
		for k in People.SKILLS:
			m.skills[k] = People.value(c, k)
		for k in People.STATS:
			m.stats[k] = People.value(c, k)
		var main: String = cfg().post_skills[post]
		var level := rng.randi_range(e.skill[0], e.skill[1]) + 2
		if main in People.SKILLS:
			m.skills[main] = maxi(m.skills[main], level)
		else:
			m.stats[main] = maxi(m.stats[main], level)
		party[post] = m
	return party


func setup(player: Dictionary, enemy: Dictionary, mode: String, wstrength: float) -> void:
	sides = [player, enemy]
	band = int(cfg().start_band.get(mode, 1))
	gauge = 0 if rng.randf() < cfg().start_gauge.get(mode, 0.5) else 1
	wind_strength = wstrength
	round_no = 0
	_mods = [_fresh_mods(), _fresh_mods()]


static func value(m: Dictionary, key: String) -> int:
	return m.skills[key] if m.skills.has(key) else m.stats.get(key, 0)


func other(i: int) -> int:
	return 1 - i


## Actions this post can take right now: {id: action data}.
func available(i: int, post: String) -> Dictionary:
	var out := {}
	if not sides[i].party.has(post):
		return out
	var list: Dictionary = actions().get(post, {})
	for id in list:
		var a: Dictionary = list[id]
		if id.begins_with("_") or not float(band) in a.bands:  # JSON numbers are floats; 1 in [1.0] is false
			continue
		if a.get("needs", "") == "chase_guns" and sides[i].stats.chase_guns <= 0:
			continue
		if a.get("needs", "") == "shallower" and not _shallower(i):
			continue
		if a.has("ammo") and _manned_guns(sides[i]) <= 0:
			continue
		if a.has("ammo") and id != "chase" and cfg().ammo[a.ammo].range_mod[band] <= -99:
			continue
		if id == "strike" and i == 1:
			continue
		out[id] = a
	return out


# ---- modifiers ---------------------------------------------------------------

func _base(i: int, post: String, skill: String) -> Array:
	var m: Dictionary = sides[i].party[post]
	var parts := [["%s %s" % [m.name.get_slice(" ", 0), People.SKILL_NAMES.get(skill, skill)], Dice.mod(value(m, skill))]]
	if m.get("wounded", false):
		parts.append(["Wounded", -3])
	if post != "captain" and _mods[i].all != 0:
		parts.append(["Captain holds steady", _mods[i].all])
	if sides[i].morale < cfg().low_morale:
		parts.append(["Low morale", cfg().low_morale_penalty])
	return parts


func _seamanship_parts(i: int) -> Array:
	var s: Dictionary = sides[i]
	var o: Dictionary = sides[other(i)]
	var parts := _base(i, "boatswain", "seamanship") if s.party.has("boatswain") else [["No boatswain", -2]]
	var speed := clampf((_speed(s) - _speed(o)) * cfg().speed_mod_per_knot, -cfg().speed_mod_max, cfg().speed_mod_max)
	if int(speed) != 0:
		parts.append(["Speed", int(speed)])
	var turn := int((s.stats.turning - o.stats.turning) * cfg().turning_mod_per_point)
	if turn != 0:
		parts.append(["Handling", turn])
	if gauge == i:
		parts.append(["Weather gauge", cfg().gauge_bonus])
	if s.rudder > 0:
		parts.append(["Damaged rudder", -2 * s.rudder])
	if s.sails < s.stats.sails * 0.5:
		parts.append(["Torn sails", -2])
	var need: float = s.stats.crew_min * Data.rules.crew_roles.sailor_need_fraction
	if s.crew * s.roles.sailors < need:
		parts.append(["Too few hands aloft", -2])
	if _mods[i].boatswain != 0:
		parts.append(["Help", _mods[i].boatswain])
	return parts


func _gunnery_parts(i: int, ammo: String) -> Array:
	var s: Dictionary = sides[i]
	var parts := _base(i, "master_gunner", "gunnery")
	if gauge == i:
		parts.append(["Weather gauge", cfg().gauge_bonus])
	var rm: int = cfg().ammo[ammo].range_mod[band]
	if rm != 0:
		parts.append(["%s at this range" % ammo.capitalize(), rm])
	var need: float = s.guns_working / 2.0 * Data.rules.combat.crew_per_gun
	var gunners: float = s.crew * s.roles.gunners
	if gunners < need * 0.5:
		parts.append(["Very short of gunners", cfg().very_shorthanded_gunners])
	elif gunners < need:
		parts.append(["Short of gunners", cfg().shorthanded_gunners])
	if wind_strength > 1.25:
		parts.append(["Heavy seas", -cfg().storm_penalty])
	if _mods[i].gunner != 0:
		parts.append(["A steady deck", _mods[i].gunner])
	return parts


func gun_dc(i: int) -> int:
	var t: Dictionary = sides[other(i)]
	var dc: int = cfg().hit_dc[band]
	if t.stats.hull <= cfg().small_hull:
		dc += cfg().small_dc
	elif t.stats.hull >= cfg().large_hull:
		dc += cfg().large_dc
	return dc


## Odds for the action menu: chance of success with the current situation (opposed rolls assume their likely skill).
func odds(i: int, post: String, id: String) -> float:
	var a: Dictionary = actions()[post][id]
	if a.has("ammo"):
		return Dice.chance(Dice.sum_parts(_gunnery_parts(i, a.ammo)), gun_dc(i))
	if a.get("dc", -1) == 0:
		return 1.0
	var parts: Array = _seamanship_parts(i) if post == "boatswain" else _base(i, post, a.skill)
	if a.has("vs"):
		var o := other(i)
		var opp: Array = _seamanship_parts(o) if a.vs == "boatswain" else (_base(o, a.vs, a.vs_skill) if sides[o].party.has(a.vs) else [])
		return Dice.contest_chance(Dice.sum_parts(parts), Dice.sum_parts(opp))
	return Dice.chance(Dice.sum_parts(parts), _dc_for(i, id, a))


func _dc_for(i: int, id: String, a: Dictionary) -> int:
	if id == "demand":
		var t: Dictionary = sides[other(i)]
		var dc: float = 10.0 + t.morale * cfg().demand_dc_per_morale + t.hull / t.hull_start * 5.0
		if i == 0:
			dc -= sides[0].get("fear", 0) * cfg().demand_fear_per_point
		return int(dc)
	if id == "close" or id == "open":
		return cfg().uncontested_dc
	return int(a.get("dc", 10))


# ---- a round -----------------------------------------------------------------

## Plays one round with the player's orders ({post: action id}). The enemy chooses its own.
func play_round(player_orders: Dictionary) -> Array:
	entries = []
	round_no += 1
	_mods = [_fresh_mods(), _fresh_mods()]
	orders = [player_orders, ai_orders(1)]
	var init := Dice.contest(rng, "Initiative", _seamanship_parts(0), _seamanship_parts(1))
	var first := 0 if init.success else 1
	_note(-1, "", "Round %d: %s %s the initiative." % [round_no, "you" if first == 0 else "they", "win" if first == 0 else "take"], init)
	for i in [first, other(first)]:
		var posts: Array = orders[i].keys()
		posts.sort_custom(func(a, b): return PHASE.get(orders[i][a], 3) < PHASE.get(orders[i][b], 3))
		for post in posts:
			if result != "":
				break
			_act(i, post, orders[i][post])
	if band < 3:  # allied ships in company add their broadsides (not into a grappled melee)
		for a in sides[0].get("allies", []):
			if result == "":
				_ally_fires(a)
	if result == "" and band == 3:
		_melee()
	for i in 2:
		_burn(i)
	_morale_checks()
	_check_end()
	return entries


func _fresh_mods() -> Dictionary:
	return {"all": 0, "boatswain": 0, "gunner": 0, "melee": 0, "guard": false, "shoals": false}


func _act(i: int, post: String, id: String) -> void:
	if not available(i, post).has(id):
		return
	var a: Dictionary = actions()[post][id]
	var s: Dictionary = sides[i]
	var o := other(i)
	var t: Dictionary = sides[o]
	var c := {}
	var who: String = s.party[post].name
	match id:
		"strike":
			_note(i, post, "%s orders the colours struck." % who)
			_strike(i)
		"steady", "read_wind", "hold", "arm", "keep_order", "join_boarders", "shoals":
			c = _roll(i, post, a)
			if c.success:
				match id:
					"steady": _mods[i].all = 1
					"read_wind": _mods[i].boatswain += 3
					"hold": _mods[i].gunner += 2
					"arm": s.armed = true
					"keep_order":
						s.morale += cfg().keep_order
						_mods[i].guard = true
					"join_boarders": _mods[i].melee += 2
					"shoals": _mods[i].shoals = true
			_note(i, post, "%s: %s." % [who, a.name], c)
		"push", "hold_rail":
			s.stance = a.stance
			_note(i, post, "%s: %s." % [who, a.name])
		"close", "open":
			var opposed := _opposes(o, id)
			if id == "close" and _mods[o].shoals:
				_note(i, post, "%s tries to close, but the shoals keep her off." % who)
				return
			c = _contest_seamanship(i, a.name) if opposed else _roll(i, post, a)
			if c.success:
				band = clampi(band + (1 if id == "close" else -1), 0, 2)
			_note(i, post, "%s: %s. %s" % [who, a.name, ("Now at " + cfg().bands[band].to_lower() + ".") if c.success else "No headway."], c)
		"gauge":
			c = _contest_seamanship(i, a.name)
			if c.success:
				gauge = i
			_note(i, post, "%s: %s. %s" % [who, a.name, "%s hold the weather gauge." % ("You" if gauge == 0 else "They")], c)
		"grapple":
			if _mods[o].shoals:
				_note(i, post, "%s can't get alongside in the shoals." % who)
				return
			c = _contest_seamanship(i, a.name)
			if c.success:
				band = 3
			_note(i, post, "%s: %s. %s" % [who, a.name, "Grapnels bite: the ships are locked together!" if c.success else "She slips away."], c)
		"flee":
			var parts := _seamanship_parts(i)
			if _mods[i].shoals:
				parts.append(["Shoals", 4])
			c = Dice.contest(rng, a.name, parts, _seamanship_parts(o))
			_xp(i, post, "seamanship", c.success)
			if c.success:
				result = "separated"
			_note(i, post, "%s: %s. %s" % [who, a.name, "Clean away!" if c.success else "She hangs on."], c)
		"cut_loose":
			c = _roll(i, post, a)
			if c.success:
				band = 2
			_note(i, post, "%s: %s. %s" % [who, a.name, "Free, at close range." if c.success else "The lines hold."], c)
		"round", "chain", "grape", "chase":
			_broadside(i, post, id, a)
		"rally":
			c = _roll(i, post, a)
			if c.success:
				s.morale += Dice.roll(rng, 1, cfg().rally[1]) + Dice.mod(value(s.party[post], "charisma"))
			_note(i, post, "%s: %s. Morale %d." % [who, a.name, s.morale], c)
		"intimidate":
			c = _contest(i, post, a)
			if c.success:
				_hit_morale(o, c.margin * cfg().intimidate_per_margin + Dice.roll(rng, 1, 6))
			_note(i, post, "%s: %s. %s" % [who, a.name, "Their nerve cracks (morale %d)." % t.morale if c.success else "They jeer back."], c)
		"demand":
			c = Dice.check(rng, a.name, _base(i, post, a.skill), _dc_for(i, id, a))
			_xp(i, post, a.skill, c.success)
			_note(i, post, "%s: %s. %s" % [who, a.name, "They strike their colours!" if c.success else "They answer with a broadside."], c)
			if c.success:
				_strike(o)
		"duel":
			c = _contest(i, post, a)
			if c.success:
				_hit_morale(o, cfg().duel_win_morale)
				t.party.captain.wounded = true
				t.captain_wounded = true
				if c.crit:
					_hit_morale(o, 30)
			else:
				_hit_morale(i, cfg().duel_lose_morale)
				s.party.captain.wounded = true
				s.captain_wounded = true
			_note(i, post, "%s: %s. %s" % [who, a.name, ("Their captain falls!" if c.success else "%s is wounded and driven back." % who)], c)
		"plug":
			c = _roll(i, post, a)
			if c.success:
				s.leak = 0
				s.fire = 0
				s.hull = minf(s.stats.hull, s.hull + Dice.roll(rng, 1, cfg().plug_hull[1]) + Dice.mod(value(s.party[post], "carpentry")))
			_note(i, post, "%s: %s. Hull %d." % [who, a.name, s.hull], c)
		"rigging":
			c = _roll(i, post, a)
			if c.success:
				s.sails = minf(s.stats.sails, s.sails + Dice.roll(rng, cfg().rigging_sails[0], cfg().rigging_sails[1]) + Dice.mod(value(s.party[post], "carpentry")))
			_note(i, post, "%s: %s. Sails %d." % [who, a.name, s.sails], c)
		"tend":
			c = _roll(i, post, a)
			if c.success:
				var n := clampf(Dice.roll(rng, 1, cfg().tend[1]) + Dice.mod(value(s.party[post], "medicine")), 0.0, s.casualties)
				s.crew += n
				s.casualties -= n
				s.morale += 2
				_note(i, post, "%s: %s. %d men back at their stations." % [who, a.name, n], c)
			else:
				_note(i, post, "%s: %s." % [who, a.name], c)


func _opposes(o: int, id: String) -> bool:
	var theirs: String = orders[o].get("boatswain", "")
	if id == "close":
		return theirs in ["open", "flee"]
	return theirs in ["close", "grapple"]


func _roll(i: int, post: String, a: Dictionary) -> Dictionary:
	var parts: Array = _seamanship_parts(i) if post == "boatswain" else _base(i, post, a.skill)
	var c := Dice.check(rng, a.name, parts, int(a.get("dc", cfg().uncontested_dc)) if a.get("dc", 0) > 0 else cfg().uncontested_dc)
	_xp(i, post, a.skill, c.success)
	return c


func _contest(i: int, post: String, a: Dictionary) -> Dictionary:
	var o := other(i)
	var opp: Array = _base(o, a.vs, a.vs_skill) if sides[o].party.has(a.vs) else [["Nobody to answer", -2]]
	var c := Dice.contest(rng, a.name, _base(i, post, a.skill), opp)
	_xp(i, post, a.skill, c.success)
	return c


func _contest_seamanship(i: int, label: String) -> Dictionary:
	var c := Dice.contest(rng, label, _seamanship_parts(i), _seamanship_parts(other(i)))
	_xp(i, "boatswain", "seamanship", c.success)
	return c


# ---- guns --------------------------------------------------------------------

func _broadside(i: int, post: String, id: String, a: Dictionary) -> void:
	var s: Dictionary = sides[i]
	var o := other(i)
	var t: Dictionary = sides[o]
	var ammo: String = a.ammo
	var c := Dice.check(rng, a.name, _gunnery_parts(i, ammo), gun_dc(i))
	_xp(i, post, "gunnery", c.success)
	var who: String = s.party[post].name
	if c.fumble:
		s.guns_working = maxi(0, s.guns_working - 1)
		var hurt := Dice.roll(rng, 1, 4)
		s.crew = maxf(0.0, s.crew - hurt)
		s.casualties += hurt
		_note(i, post, "%s: %s. A gun bursts in its carriage! (%d men hurt)" % [who, a.name, hurt], c)
		return
	if not c.success:
		_note(i, post, "%s: %s. The shot falls short." % [who, a.name], c)
		return
	var n: int = cfg().chase_dice if id == "chase" else maxi(1, ceili(_manned_guns(s) / float(cfg().guns_per_die)))
	var die := _damage_die(s.stats.gun_weight)
	var dmg := Dice.roll(rng, n, die) + maxi(0, c.margin) / 2
	if c.crit:
		dmg *= 2
	var fx: Dictionary = cfg().ammo[ammo]
	var crew_before: float = t.crew
	var hull_before: float = t.hull
	t.hull -= dmg * fx.hull
	t.sails = maxf(0.0, t.sails - dmg * fx.sails)
	var killed := minf(t.crew, dmg * fx.crew)
	t.crew -= killed
	t.casualties += killed
	_hit_morale(o, (crew_before - t.crew) / maxf(t.crew_start, 1.0) * 100.0 * cfg().morale_per_crew_pct
		+ (hull_before - t.hull) / t.hull_start * 100.0 * cfg().morale_per_hull_pct + dmg * fx.morale)
	var text := "%s: %s. %dd%d%s = %d damage: hull %d, sails %d, %d men down." % [who, a.name, n, die,
		" + margin" if c.margin >= 2 else "", dmg, dmg * fx.hull, dmg * fx.sails, killed]
	if c.crit:
		text += " " + _crit(o, ammo)
	_note(i, post, text, c)


## An allied ship fires into the enemy, rolled like any broadside.
func _ally_fires(a: Dictionary) -> void:
	var t: Dictionary = sides[1]
	var c := Dice.check(rng, "%s's broadside" % a.name, [["Their gunnery", Dice.mod(a.gunnery)]], gun_dc(0))
	if not c.success:
		_note(-1, "", "Your ally the %s fires and misses." % a.name, c)
		return
	var n := maxi(1, ceili(a.guns / 2.0 / cfg().guns_per_die))
	var dmg := Dice.roll(rng, n, _damage_die(a.gun_weight))
	var killed := minf(t.crew, dmg * cfg().ammo.round.crew)
	var hull_before: float = t.hull
	t.hull -= dmg
	t.crew -= killed
	t.casualties += killed
	_hit_morale(1, killed / maxf(t.crew_start, 1.0) * 100.0 * cfg().morale_per_crew_pct + (hull_before - t.hull) / t.hull_start * 100.0 * cfg().morale_per_hull_pct)
	_note(-1, "", "Your ally the %s rakes her: %d damage, %d men down." % [a.name, dmg, killed], c)


static func _damage_die(gun_weight: float) -> int:
	for pair in cfg().damage_dice:
		if gun_weight <= pair[0]:
			return int(pair[1])
	return 12


static func _manned_guns(s: Dictionary) -> int:
	return mini(int(s.guns_working / 2.0), int(s.crew * s.roles.gunners / Data.rules.combat.crew_per_gun))


func _crit(o: int, ammo: String) -> String:
	var t: Dictionary = sides[o]
	var table: Array = cfg().crits
	var pick: Dictionary = table[rng.randi() % table.size()]
	if ammo == "chain" and rng.randf() < 0.5:
		pick = table.filter(func(x): return x.id == "mast")[0]
	elif ammo == "grape" and rng.randf() < 0.5:
		pick = table.filter(func(x): return x.id == "officer")[0]
	match pick.id:
		"leak": t.leak += 1
		"rudder": t.rudder += 1
		"mast":
			if t.masts > 0:
				t.masts -= 1
				t.sails *= float(t.masts) / (t.masts + 1)
		"gun": t.guns_working = maxi(0, t.guns_working - 2)
		"fire": t.fire += 1
		"officer":
			var posts: Array = t.party.keys().filter(func(p): return p != "captain" and not t.party[p].get("wounded", false))
			if not posts.is_empty():
				var p: String = posts[rng.randi() % posts.size()]
				t.party[p].wounded = true
				if t.party[p].id != "":
					t.officer_wounds.append(t.party[p].id)
				return pick.text + " (%s is wounded)" % t.party[p].name
		"powder":
			var k := minf(t.crew, Dice.roll(rng, 1, 10))
			t.crew -= k
			t.casualties += k
		"colours": _hit_morale(o, 10)
	return pick.text


func _burn(i: int) -> void:
	var s: Dictionary = sides[i]
	if s.leak > 0 or s.fire > 0:
		var dmg: float = s.leak * cfg().leak_per_round + s.fire * cfg().fire_per_round
		s.hull -= dmg
		s.sails = maxf(0.0, s.sails - s.fire * 3)
		_note(i, "", "%s takes %d damage from %s." % ["Your ship" if i == 0 else "Their ship", dmg,
			"leaks and fire" if s.leak > 0 and s.fire > 0 else ("leaks" if s.leak > 0 else "fire")])


# ---- boarding: both sides fight every round while grappled -------------------

func _melee_parts(i: int) -> Array:
	var s: Dictionary = sides[i]
	var o: Dictionary = sides[other(i)]
	var parts := [["Swordplay", Dice.mod(s.get("swordplay", 8))]]
	var marines := int(round(s.roles.marines * cfg().melee_marine_bonus))
	if marines != 0:
		parts.append(["Marines", marines])
	var nums := int(clampf(round(log(maxf(s.crew, 1.0) / maxf(o.crew, 1.0)) / log(2.0) * 3.0), -6, 6))
	if nums != 0:
		parts.append(["Numbers", nums])
	var morale := int((s.morale - 50.0) / 10.0)
	if morale != 0:
		parts.append(["Morale", morale])
	if s.armed:
		parts.append(["Armed boarders", 2])
	if int(s.stats.swivels / 3) > 0:
		parts.append(["Swivel guns", int(s.stats.swivels / 3)])
	if _mods[i].melee != 0:
		parts.append(["Gun crews join in", _mods[i].melee])
	if s.stance == "push":
		parts.append(["Pushing forward", 2])
	elif s.stance == "hold":
		parts.append(["Holding the rail", -2])
	return parts


func _melee() -> void:
	var c := Dice.contest(rng, "Boarding melee", _melee_parts(0), _melee_parts(1))
	var w := 0 if c.success else 1
	var l := other(w)
	var winner: Dictionary = sides[w]
	var loser: Dictionary = sides[l]
	var scale_w := maxf(1.0, winner.crew / cfg().melee_scale_per)
	var scale_l := maxf(1.0, loser.crew / cfg().melee_scale_per)
	var push_w: float = cfg().push_mult if winner.stance == "push" else (cfg().hold_mult if winner.stance == "hold" else 1.0)
	var guard_l: float = cfg().hold_mult if loser.stance == "hold" else (cfg().push_mult if loser.stance == "push" else 1.0)
	var lost_l := minf(loser.crew, (absi(c.margin) + Dice.roll(rng, 1, 6)) * scale_w * push_w * guard_l)
	var lost_w := minf(winner.crew, Dice.roll(rng, 1, 4) * scale_l * push_w)
	for pair in [[l, lost_l], [w, lost_w]]:
		var side: Dictionary = sides[pair[0]]
		var before: float = side.crew
		side.crew -= pair[1]
		side.casualties += pair[1]
		_hit_morale(pair[0], (before - side.crew) / maxf(side.crew_start, 1.0) * 100.0 * cfg().morale_per_crew_pct)
	_note(-1, "", "Hand to hand: %s gain the upper hand. You lose %d men, they lose %d." % [
		"your boarders" if w == 0 else "their men", lost_w if w == 0 else lost_l, lost_l if w == 0 else lost_w], c)


# ---- morale and the end --------------------------------------------------------

func _hit_morale(i: int, amount: float) -> void:
	if _mods.size() > i and _mods[i].guard:
		amount *= 0.5
	sides[i].morale -= amount


func _morale_checks() -> void:
	for i in 2:
		var s: Dictionary = sides[i]
		s.morale = clampf(s.morale, 0.0, 100.0)  # rallies and losses within a round can overshoot
		if result != "" or s.morale >= cfg().morale_check_below:
			continue
		var dc := int(cfg().morale_check_dc + (cfg().morale_check_below - s.morale) / 3.0)
		var parts: Array = [["Captain's authority", Dice.mod(value(s.party.captain, "authority"))]]
		var c := Dice.check(rng, "Morale", parts, dc)
		if c.success:
			_note(i, "", "%s crew waver, but hold." % ("Your" if i == 0 else "Their"), c)
		elif i == 1 or s.morale <= 15:
			_note(i, "", "%s crew break and strike the colours!" % ("Your" if i == 0 else "Their"), c)
			_strike(i)
		else:
			_note(i, "", "Your crew are close to breaking.", c)


func _strike(i: int) -> void:
	sides[i].struck = true
	result = "player_struck" if i == 0 else "enemy_struck"


func _check_end() -> void:
	if result != "":
		return
	if sides[1].hull <= 0:
		result = "enemy_sunk"
	elif sides[0].hull <= 0:
		result = "player_sunk"
	elif sides[1].crew < 3:
		_strike(1)
	elif sides[0].crew < 3:
		_strike(0)


# ---- the enemy's choices -------------------------------------------------------

func ai_orders(i: int) -> Dictionary:
	var s: Dictionary = sides[i]
	var t: Dictionary = sides[other(i)]
	var out := {}
	var b: String = s.get("behaviour", "warship")
	var stronger: bool = s.crew > t.crew * (1.3 if b == "aggressive" else 1.8)
	for post in s.party:
		var can := available(i, post)
		var pick := ""
		match post:
			"boatswain":
				if b == "merchant" or (s.hull < s.hull_start * 0.35):
					pick = "flee" if can.has("flee") else ("open" if can.has("open") else "cut_loose")
				elif band == 3:
					pick = "" if stronger else "cut_loose"
				elif stronger and can.has("grapple"):
					pick = "grapple"
				elif stronger or band == 0:
					pick = "close"
				elif gauge != i and can.has("gauge"):
					pick = "gauge"
				else:
					pick = "hold" if can.has("hold") else "open"
			"master_gunner":
				if b == "aggressive" and band >= 2 and can.has("grape"):
					pick = "grape"
				elif b == "aggressive" and t.sails > t.stats.sails * 0.4 and can.has("chain"):
					pick = "chain"
				elif can.has("round"):
					pick = "round"
				elif can.has("chase"):
					pick = "chase"
			"captain":
				if band == 3 and stronger and can.has("duel"):
					pick = "duel"
				elif t.morale < 40 and b != "merchant":
					pick = "demand"
				elif s.morale < 50:
					pick = "rally"
				elif can.has("intimidate") and b != "merchant":
					pick = "intimidate"
				else:
					pick = "steady"
			"quartermaster":
				pick = ("push" if stronger else "hold_rail") if band == 3 else ("arm" if not s.armed else "keep_order")
			"navigator":
				pick = "read_wind" if can.has("read_wind") else ""
			"carpenter":
				pick = "plug" if s.leak > 0 or s.fire > 0 or s.hull < s.hull_start * 0.7 else ("rigging" if can.has("rigging") else "plug")
			"surgeon":
				pick = "tend"
		if pick != "" and can.has(pick):
			out[post] = pick
	return out


func _shallower(i: int) -> bool:
	var d: Dictionary = Data.rules.draught
	return d[sides[i].stats.draught].route_cost < d[sides[other(i)].stats.draught].route_cost


static func _speed(s: Dictionary) -> float:
	# speed on a broad reach, the usual point of sailing in a chase, after damage
	var sails_frac := clampf(s.sails / float(s.stats.sails), 0.0, 1.0)
	return s.stats.speed_knots * Sailing.polar_factor(s.stats.polar, 120.0) * lerpf(0.3, 1.0, sails_frac) * float(s.masts) / s.stats.masts


func _xp(i: int, post: String, skill: String, success: bool) -> void:
	if i != 0 or not sides[0].party.has(post):
		return
	var id: String = sides[0].party[post].id
	if id == "" or not skill in People.SKILLS:
		return
	if not sides[0].xp.has(id):
		sides[0].xp[id] = {}
	sides[0].xp[id][skill] = sides[0].xp[id].get(skill, 0.0) + cfg().xp_per_roll + (cfg().xp_per_success if success else 0.0)


func _note(side: int, post: String, text: String, c := {}) -> void:
	entries.append({"side": side, "post": post, "text": text, "check": c})
