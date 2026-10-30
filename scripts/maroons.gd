extends Node
## Autoload "Maroons": people who escaped slavery and hold the hills of Jamaica and Hispaniola. They don't wait
## for the player: escapes swell them, they raid the estates below (the planters' crops fall: a market effect), and
## the governor sends the militia into the hills, which mostly comes back with nothing. You meet them at a landing
## on an empty coast (a cove in data/coves.json with a "maroons" key, learnt from people, never stumbled on): trade
## them powder, tools and cloth for provisions and hides, bring them people who asked for the hills, ally with them
## (the bond "f:maroons"), raid the estates beside them, or sell their paths to the governor.
## Rules for all of it: docs/representation.md. Tuning: rules.json "maroons".
##   bands[landing] = {strength 0-100, armed (powder and tools they've had from you, fading), heat (the governor's
##                     anger at their raids), burned (day their town was found and burned, -1), betrayed, stock (hides
##                     to trade, refilled monthly), raided (day you last raided with them)}

var bands := {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	reset()
	Clock.day_passed.connect(func(_d):
		if Clock.date().day == 1:
			for n in monthly():
				Economy.add_news(n.text, n.port))


static func cfg() -> Dictionary:
	return Data.rules.maroons


static func landings() -> Array:
	return Data.table("coves").keys().filter(func(id): return not id.begins_with("_") and Data.table("coves")[id].has("maroons"))


static func is_landing(id: String) -> bool:
	return Data.table("coves").has(id) and Data.table("coves")[id].has("maroons")


static func info(id: String) -> Dictionary:
	return Data.table("coves")[id].maroons


## The nations whose colonies lie below the Maroons' hills.
static func colonies() -> Array:
	var out := []
	for id in landings():
		var f: String = Ports.port(info(id).near).faction
		if not f in out:
			out.append(f)
	return out


func reset() -> void:
	bands = {}
	for id in landings():
		bands[id] = {"strength": float(info(id).strength), "armed": 0.0, "heat": 0.0, "burned": -1, "betrayed": false,
			"stock": float(cfg().stock), "raided": -9999}


## Their town was found and burned lately: they've gone deeper into the hills and won't come down to trade.
func burned(id: String) -> bool:
	return bands[id].burned >= 0 and Clock.day - bands[id].burned < int(cfg().burned_days)


## How strong they are, in words.
func strength_word(id: String) -> String:
	var v: float = bands[id].strength
	return "a few families in hiding" if v < 20.0 else ("a strong band" if v < 50.0 else ("a whole people in arms" if v >= 75.0 else "many towns in the hills"))


## The Maroons an event is about: the landing you're at, or one you know of whose colony is the port you're in.
func near(ctx: Dictionary) -> String:
	var at: String = ctx.get("base", "")
	if is_landing(at):
		return at
	for id in landings():
		if id in Bases.discovered and info(id).near == ctx.get("port", ""):
			return id
	return ""


## The landing nearest a port, for people who tell you where the Maroons trade (with no port, one you don't know).
func nearest(port: String) -> String:
	if port == "":
		var left := landings().filter(func(id): return not id in Bases.discovered)
		return left[0] if not left.is_empty() else ""
	var best := ""
	for id in landings():
		if best == "" or Bases.cove_pos(id).distance_to(Bases.cove_pos(port)) < Bases.cove_pos(best).distance_to(Bases.cove_pos(port)):
			best = id
	return best


func reveal(id: String) -> String:
	if id == "" or id in Bases.discovered:
		return ""
	Bases.discovered.append(id)
	return "You learn where %s come down to trade: %s" % [info(id).band, Bases.cove(id).name]


# ---- the world ------------------------------------------------------------------------

## A month in the hills. Returns news [{text, port}].
func monthly() -> Array:
	var c := cfg()
	var out := []
	for id in bands:
		var b: Dictionary = bands[id]
		var i: Dictionary = info(id)
		var port: String = i.near
		b.stock = float(c.stock)
		b.armed *= float(c.armed_fade)
		b.heat *= float(c.heat_fade)
		if not burned(id):
			b.strength = minf(100.0, b.strength + float(c.grow))  # people keep escaping to them
		if b.strength >= float(c.raid_from) and not burned(id) and rng.randf() < float(c.raid_chance) * b.strength / 100.0 * (1.0 + b.armed / float(c.armed_full)):
			for g in Economy.produces(port):
				Economy.shock(port, {"good": g, "make": float(c.raid_make), "days": int(c.raid_days), "reason": "Maroon raids on the estates"})
			b.heat += 1.0
			out.append({"text": "%s have come down from %s and burned estates outside %s. The planters are calling for the militia." % [
				i.band.capitalize(), i.hills, Ports.port(port).name], "port": port})
		if b.betrayed or rng.randf() < float(c.militia_chance) * b.heat:
			out.append(_militia(id))
	return out


## The governor sends the militia into the hills. Without a guide it mostly finds empty huts; with one it burns
## their town. Powder you sold them makes the soldiers pay for every mile.
func _militia(id: String) -> Dictionary:
	var c := cfg()
	var b: Dictionary = bands[id]
	var i: Dictionary = info(id)
	var guided: bool = b.betrayed
	var defence := minf(1.0, b.armed / float(c.armed_full))
	var loss: float = rng.randf_range(c.militia_loss[0], c.militia_loss[1]) * (float(c.guided_mult) if guided else 1.0) * (1.0 - 0.5 * defence)
	b.strength = maxf(5.0, b.strength - loss)
	b.heat = 0.0
	b.betrayed = false
	var port: String = i.near
	if guided:
		b.burned = Clock.day
		return {"text": "The militia of %s marched into %s with a guide who knew the paths, and burned the Maroons' town. %s have scattered deeper into the hills." % [
			Ports.port(port).name, i.hills, i.band.capitalize()], "port": port}
	return {"text": "The militia of %s spent a month in %s and came back %s." % [Ports.port(port).name, i.hills,
		"with a dozen of their own dead and nothing else" if defence > 0.3 else "with little but blistered feet"], "port": port}


# ---- you and them ------------------------------------------------------------------------

## Will they deal with you at all? "" if they will, or why not.
func trade_problem(s: Dictionary, id: String) -> String:
	if burned(id):
		return "Their town was burned. Nobody comes down to the landing."
	if s.relations.get("maroons", 0) < int(cfg().trade_min) and Bonds.level(s, "f:maroons") < 1:
		return "They don't trust you enough to come down to the landing."
	return ""


## What a lot of each good they want is worth to them, and what they give: [{good, qty, hides, food, value}].
func offers(s: Dictionary, id: String) -> Array:
	var out := []
	var rate: float = float(cfg().barter) + (float(cfg().pact_bonus) if Bonds.level(s, "f:maroons") >= 2 else 0.0)
	for g in cfg().wants:
		var qty := mini(int(s.cargo.get(g, 0)), int(cfg().lot))
		if qty <= 0:
			continue
		var value: float = qty * float(Data.table("goods")[g].base_price) * rate
		var hides := mini(int(bands[id].stock), int(value * float(cfg().hides_share) / Data.table("goods").hides.base_price))
		var food := int((value - hides * Data.table("goods").hides.base_price) / Data.table("goods").food.base_price)
		out.append({"good": g, "qty": qty, "hides": hides, "food": food, "value": value})
	return out


## One lot traded. Arms make them stronger, and the colony may hear who sold them.
func trade(s: Dictionary, id: String, o: Dictionary) -> String:
	var c := cfg()
	s.cargo[o.good] = s.cargo.get(o.good, 0) - o.qty
	s.cargo.hides = s.cargo.get("hides", 0) + o.hides
	s.cargo.food = s.cargo.get("food", 0) + o.food
	bands[id].stock -= o.hides
	s.relations.maroons = s.relations.get("maroons", 0) + int(c.trade_relation)
	var text := "%d %s for %d hides and %d of provisions: smoked hog, yams and plantains." % [o.qty, Data.table("goods")[o.good].name.to_lower(), o.hides, o.food]
	if o.good in c.arms:
		bands[id].armed += o.qty
		var f: String = Ports.port(info(id).near).faction
		if rng.randf() < float(c.heard):
			s.relations[f] = s.relations.get(f, 0) - int(c.heard_relation)
			text += " Word reaches %s that you're arming the Maroons (standing with %s -%d)." % [Ports.port(info(id).near).name, Career.fname(f), c.heard_relation]
	return text


## People who asked to be taken to the hills go up with the Maroons' guides.
func land_freed(s: Dictionary, id: String) -> String:
	Events.flags.erase("freed_aboard")
	bands[id].strength = minf(100.0, bands[id].strength + float(cfg().freed_strength))
	s.relations.maroons = s.relations.get("maroons", 0) + int(cfg().freed_relation)
	return "The people you carried go up the river path with the Maroons' guides, and don't look back. Up in the hills, they'll remember whose ship it was."


func raid_problem(s: Dictionary, id: String) -> String:
	if Bonds.level(s, "f:maroons") < 3:
		return "Only allies go down to the estates with them."
	if Clock.day - bands[id].raided < int(cfg().raid_every):
		return "They raided with you lately. The estates are on guard."
	return trade_problem(s, id)


## Down to the estates beside them, by night: plunder for you, the crops burned, and people on the estates who
## choose to come away with them. The colony knows whose ship was in the bay.
func raid(s: Dictionary, id: String) -> String:
	var c := cfg()
	var b: Dictionary = bands[id]
	var port: String = info(id).near
	var f: String = Ports.port(port).faction
	b.raided = Clock.day
	b.heat += 1.0
	b.strength = minf(100.0, b.strength + float(c.raid_strength))
	var gold := rng.randi_range(int(c.raid_gold[0]), int(c.raid_gold[1]))
	s.gold += gold
	var sugar := int(c.raid_sugar)
	s.cargo.sugar = s.cargo.get("sugar", 0) + sugar
	s.stolen.sugar = s.stolen.get("sugar", 0) + sugar
	for g in Economy.produces(port):
		Economy.shock(port, {"good": g, "make": float(c.raid_make), "days": int(c.raid_days), "reason": "Maroon raids on the estates"})
	s.relations[f] = s.relations.get(f, 0) - int(c.raid_relation)
	Career.add_bounty(s, f, float(c.raid_bounty))
	return "You go down to the estates outside %s with %s by night: %d gold from the great house, %d sugar from the boiling house, the cane burning behind you. Some of the people on the estates come away into the hills. Standing with %s -%d, and %s puts a price on your head." % [
		Ports.port(port).name, info(id).band, gold, sugar, Career.fname(f), c.raid_relation, Career.fname(f)]


## You sold their paths to the governor. The militia goes in with a guide; the Maroons, and your own people, know.
func betray(s: Dictionary, id: String) -> String:
	bands[id].betrayed = true
	var out := PackedStringArray()
	if Bonds.level(s, "f:maroons") > 0:
		out.append(Bonds.break_bond(s, "f:maroons", "you sold them to the governor"))
	s.relations.maroons = -100
	var hurt := 0
	for cid in s.crew:  # crew of African descent take it hardest: it could have been their people
		var p := People.person(cid)
		var mine: bool = p.get("nationality", "") == "afro_caribbean"
		Crew.feel(s, p, -int(cfg().betray_opinion[0 if mine else 1]), "Sold the Maroons to the governor")
		hurt += 1 if mine else 0
	out.append("The crew heard where the militia's guide came from.%s" % (" %d of them won't forget it." % hurt if hurt > 0 else ""))
	return " ".join(out)


## Sworn to you, with their hills above this town and their town not burned: they fight beside you. The band, or "".
func sworn_near(s: Dictionary, port: String) -> String:
	if Bonds.level(s, "f:maroons") < 4:
		return ""
	for id in landings():
		if info(id).near == port and not burned(id):
			return info(id).band
	return ""


func save_state() -> Dictionary:
	return {"bands": bands}


func load_state(d: Dictionary) -> void:
	reset()
	for id in d.get("bands", {}):
		if bands.has(id):
			bands[id].merge(d.bands[id], true)
			for k in ["burned", "raided"]:
				bands[id][k] = int(bands[id][k])
