class_name AtSea
## Meetings at sea that aren't (yet) fights: hailing a ship to swap news and trade over the rail, a navy patrol
## that wants to search your hold, and other ships' battles you come upon (take a side, wait for the winner, or
## keep clear). The rules and their numbers are here (data/rules.json at_sea); the dialogs are in world_map.gd.


static func cfg() -> Dictionary:
	return Data.rules.at_sea


# ---- hailing ------------------------------------------------------------------

## Why she won't heave to and talk, or "" if she will.
static func hail_problem(s: Dictionary, e: Dictionary) -> String:
	var shown := Career.flag_faction(s.get("flag", "white"))
	match e.behaviour:
		"merchant":
			if shown == "pirates" or Factions.at_war(shown, e.faction):
				return "She's crowding on sail: your colours frighten her."
			if Career.wanted(s):
				return "Her master knows your face from the posters. She won't stop."
		"aggressive":
			if s.relations.get("pirates", 0) < int(cfg().gam_relation):
				return "The Brethren don't trust you enough to heave to."
	return ""


## What she knows: a merchant shares her papers (prices where she sailed from, as they stood); anyone else, a
## word of news from the nearest port.
static func news(npc: Dictionary, near_port: String) -> String:
	if npc.has("voyage"):
		var v := Economy.voyage(npc.voyage)
		if not v.is_empty():
			var n := Ports.learn_news(v.news, "hail")
			if n > 0:
				return "Her master shares the prices %s had heard of when she sailed: %d port%s." % [Ports.port(v.origin).name, n, "" if n == 1 else "s"]
	return Ports.rumour(near_port, int(Clock.day))


## Her cargo, offered over the rail: {good, qty, price (each), stolen} or {}. A merchant asks a little under what
## it fetches where she's bound (you save her the rest of the voyage); a pirate sells plunder cheap.
static func offer(npc: Dictionary, near_port: String) -> Dictionary:
	var e: Dictionary = npc.enemy
	var pirate: bool = e.behaviour == "aggressive"
	var where: String = npc.get("dest", "") if not pirate and Ports.state.has(npc.get("dest", "")) else near_port
	for g in e.cargo:
		if int(e.cargo[g]) >= 1 and Data.table("goods").has(g) and Data.table("goods")[g].get("economy", true):
			var mult: float = cfg().plunder_price if pirate else cfg().rail_price
			return {"good": g, "qty": int(e.cargo[g]), "price": maxf(1.0, Economy.price(where, g, false) * mult), "stolen": pirate}
	return {}


## Buys up to qty of an offer. Her cargo (and her voyage, if she's a merchant bound for a market) goes down by it.
static func buy(s: Dictionary, npc: Dictionary, o: Dictionary, qty: int, capacity: float) -> String:
	var g: String = o.good
	qty = mini(qty, int(o.qty))
	qty = mini(qty, int((capacity - Market.cargo_used(s.cargo)) / Market.weight(g) + 0.0001))
	qty = mini(qty, int(s.gold / o.price))
	if qty <= 0:
		return "No room in the hold, or not enough gold."
	var cost := int(round(qty * o.price))
	s.gold -= cost
	s.cargo[g] = s.cargo.get(g, 0) + qty
	s.cargo_cost[g] = s.cargo_cost.get(g, 0.0) + cost
	if o.stolen:
		s.stolen = s.get("stolen", {})
		s.stolen[g] = s.stolen.get(g, 0.0) + qty
	npc.enemy.cargo[g] = int(npc.enemy.cargo[g]) - qty
	if npc.enemy.cargo[g] <= 0:
		npc.enemy.cargo.erase(g)
	if npc.has("voyage"):
		var v := Economy.voyage(npc.voyage)
		if not v.is_empty():
			v.qty = maxf(0.0, float(v.qty) - qty)
	Ports.log_trade(s, "", g, qty, -cost, 0.0)
	o.qty = int(o.qty) - qty
	return "Bought %d %s over the rail for %d.%s" % [qty, Data.table("goods")[g].name.to_lower(), cost, " (Plunder: careful who sees it.)" if o.stolen else ""]


## A pirate's gam: word of a fat merchant on the move near here. Returns the tip, or "".
static func prize_tip(pos: Vector2, rng: RandomNumberGenerator) -> String:
	var best := {}
	var best_value := 0.0
	for v in Economy.voyages():
		var o: Dictionary = Data.table("ports").get(v.origin, {})
		var d: Dictionary = Data.table("ports").get(v.dest, {})
		if o.is_empty() or d.is_empty() or not Data.table("goods").has(v.good):
			continue
		var near := minf(pos.distance_to(Geo.latlon_to_px(o.lat, o.lon)), pos.distance_to(Geo.latlon_to_px(d.lat, d.lon)))
		if near > float(cfg().tip_nm) * Geo.px_per_nm():
			continue
		var value: float = float(v.qty) * Data.table("goods")[v.good].base_price * rng.randf_range(0.8, 1.2)
		if value > best_value:
			best = v
			best_value = value
	if best.is_empty():
		return ""
	var days := int(Clock.day) - Economy.to_game_day(int(best.depart))
	return "A %s merchantman sailed from %s for %s %s with %d %s aboard. Worth looking for along that route." % [
		Data.table("factions")[best.faction].adjective, Data.table("ports")[best.origin].name, Data.table("ports")[best.dest].name,
		"today" if days <= 0 else "%d day%s ago" % [days, "" if days == 1 else "s"], int(best.qty), Data.table("goods")[best.good].name.to_lower()]


## Hands on a pirate ship who'd rather sail with you: how many, from her crew and your free berths.
static func volunteers(s: Dictionary, e: Dictionary, crew_max: int, rng: RandomNumberGenerator) -> int:
	var r: Array = cfg().volunteers
	return mini(rng.randi_range(int(r[0]), int(r[1])), mini(crew_max - ShipStats.headcount(s), int(e.crew) - 5))


static func take_volunteers(s: Dictionary, e: Dictionary, n: int) -> String:
	for i in n:
		var c := People.generate({"mix": Data.rules.people.recruit_mix.pirates})
		c.history.append("Left the %s to join the %s, %s." % [e.name, s.name, Clock.date_string()])
		s.crew.append(People.add(c))
	e.crew = int(e.crew) - n
	return "%d of her hands come across to join you." % n


# ---- a patrol's search ---------------------------------------------------------

## What a patrol of nation f would take from your hold: {good: qty}. Goods its laws keep for its own ships
## (unless you fly its colours), goods it forbids, and plunder its officers can recognise.
static func suspect(s: Dictionary, f: String) -> Dictionary:
	var out := {}
	var shown := Career.flag_faction(s.get("flag", "white"))
	for id in Ports.state:
		if Ports.port(id).faction != f:
			continue
		var laws: Dictionary = Ports.state[id].laws
		for g in laws.get("enumerated", []) + laws.get("contraband", []):
			if shown != f and s.cargo.get(g, 0) >= 1:
				out[g] = int(s.cargo[g])
	for g in s.get("stolen", {}):
		if s.stolen[g] >= 1.0 and s.cargo.get(g, 0) >= 1:
			out[g] = maxi(int(out.get(g, 0)), int(minf(s.stolen[g], s.cargo[g])))
	return out


static func suspect_value(s: Dictionary, f: String) -> float:
	var total := 0.0
	var sus := suspect(s, f)
	for g in sus:
		total += sus[g] * float(Data.table("goods")[g].base_price)
	return total


## Will a friendly patrol want to look in your hold? More likely the worse your name; not again so soon after
## their navy last searched you.
static func wants_search(s: Dictionary, f: String, rng: RandomNumberGenerator) -> bool:
	if s.get("searched", {}).get(f, -INF) + float(cfg().search_again_days) > Clock.day:
		return false
	return rng.randf() < clampf(float(cfg().inspect_chance) + s.reputation.notoriety * float(cfg().inspect_per_notoriety), 0.0, 0.9)


static func bribe_cost(s: Dictionary, f: String) -> int:
	return int(cfg().bribe_base + suspect_value(s, f) * float(cfg().bribe_share))


## The boarding officer goes through the hold. Returns what happened.
static func search(s: Dictionary, f: String, rng: RandomNumberGenerator) -> String:
	s.searched = s.get("searched", {})
	s.searched[f] = Clock.day
	var sus := suspect(s, f)
	if sus.is_empty():
		s.relations[f] = s.relations.get(f, 0) + int(cfg().clean_relation)
		return "They turn the hold over and find nothing amiss. The lieutenant apologises for the delay. (Standing with %s %+d)" % [Career.fname(f), int(cfg().clean_relation)]
	if rng.randf() > float(cfg().search_find):
		return "They poke about the hold and miss what's under the ballast. You breathe again."
	var value := suspect_value(s, f)
	var plunder := false
	for g in sus:
		plunder = plunder or s.get("stolen", {}).has(g)
		Ports.remove_cargo(s, g, sus[g], sus[g])
	var fine := int(value * float(Data.rules.smuggling.fine_mult))
	s.gold = maxf(0.0, s.gold - fine)
	s.relations[f] = s.relations.get(f, 0) - int(Data.rules.smuggling.seizure_relation)
	var text := "They find it: %s, seized. Fined %d. (Standing with %s -%d)" % [", ".join(sus.keys().map(func(g): return Data.table("goods")[g].name.to_lower())),
		fine, Career.fname(f), int(Data.rules.smuggling.seizure_relation)]
	if plunder:
		s.reputation.notoriety += float(cfg().plunder_notoriety)
		text += "\nSome of it was taken from honest ships, and they know whose. Notoriety +%d." % int(cfg().plunder_notoriety)
	return text


# ---- other ships' battles --------------------------------------------------------

## How much fight a ship has in her: crew and guns, steadied by morale.
static func strength(e: Dictionary) -> float:
	var st := ShipStats.effective(e.type, e.upgrades)
	return (float(e.crew) + st.guns * 4.0) * (0.5 + float(e.morale) / 100.0) * maxf(0.2, float(e.hull) / float(st.hull))


## Battle damage: a share of her hull, some of her crew, and her nerve.
static func hurt(e: Dictionary, frac: float) -> void:
	e.hull = maxf(1.0, float(e.hull) * (1.0 - frac))
	e.crew = maxi(4, int(float(e.crew) * (1.0 - frac * 0.5)))
	e.morale = maxf(10.0, float(e.morale) - frac * 30.0)


## What a ship fighting beside you brings to the battle (an ally in DiceCombat).
static func as_ally(npc: Dictionary) -> Dictionary:
	var e: Dictionary = npc.enemy
	var st := ShipStats.effective(e.type, e.upgrades)
	return {"name": e.name, "type": e.type, "guns": st.guns, "gun_weight": st.gun_weight, "gunnery": int(e.get("gunnery", 8)), "id": "", "npc": npc.id}
