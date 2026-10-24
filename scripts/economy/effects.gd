class_name EconomyEffects
## How story events and history change the market and the world: effects shaped {type, ...params}, the shape the
## Johnson events use (docs/economic_events.md lists every type and where it's used). An event choice can carry
## "effects": [...] beside its "outcomes"; a history entry in data/history.json can carry them too.
## World effects go to the economy model (EconomyModel.apply_effect, world conditions); the player's own
## (open markets, closed ports, fences, discounts) go into s.econ with an expiry day. An unknown type logs a
## warning and is skipped, so new content never breaks the game.

const MARKET := ["market_shock", "open_market", "port_closed_days", "port_damage", "trade_profit_multiplier",
	"unlock_trade_with", "unlock_fence", "fence_trust", "fence_dependence", "launder_prize", "prize_unsellable_here",
	"sell_items", "buy_provisions", "rep_with_smugglers", "treat_ships_from", "faction_port_hostility",
	"burn_ships_in_road", "bombard_port", "repair_discount", "free_supplies", "merchant_resistance_multiplier"]
const WORLD := ["war", "world_state", "pirate_spawn_rate_multiplier", "letter_of_marque", "revoke_letter_of_marque"]
const HISTORY := ["haven_closed", "fleet_blocked", "trade_slump", "fair_access", "port_laws", "flows", "stock", "spread", "sailings", "route_risk"]
const MONEY := ["gold", "gold_percent", "cargo_percent", "provisions"]
const SKIPPED := ["start_land_raid"]  # known, but not the market's business: logged and skipped

static var player: Dictionary = {}  # the player's state, for effects from history (set by the world map)


static func known(type: String) -> bool:
	return type in MARKET or type in WORLD or type in HISTORY or type in MONEY


## Applies a list of effects. ctx: {s (the player's state), port (where the player is), and any named ports the
## content uses, such as hunter_port}. Returns what happened, for the event's result text.
static func apply_all(effects: Array, ctx: Dictionary) -> Array:
	var out := []
	for e in effects:
		var text := apply(e, ctx)
		if text != "":
			out.append(text)
	return out


static func apply(e: Dictionary, ctx: Dictionary) -> String:
	var type: String = e.get("type", "")
	if not known(type):
		push_warning("Economy: effect '%s' isn't handled here; skipped." % type)
		return ""
	var s: Dictionary = ctx.get("s", player)
	var here: String = ctx.get("port", "")
	var port := _port(e.get("port", "current"), ctx)
	var days := int(e.get("days", 30))
	var until := Clock.day + days
	var m: EconomyModel = Economy.model
	match type:
		# ---- the market itself ----
		"market_shock", "port_damage", "flows", "stock", "spread", "sailings", "route_risk", "haven_closed":
			if port == "":
				return _skip(type, "no port")
			var eff := e.duplicate(true)
			if eff.has("text"):
				eff.reason = "Still recovering" if type == "port_damage" else eff.text
			m.apply_effect(port, eff)
			if e.has("text"):
				Economy.add_news(e.text, port)
			return {"market_shock": "Prices in %s will climb" if float(e.get("price_multiplier", 1.0)) > 1.0 else "Prices in %s will fall",
				"port_damage": "%s is badly damaged", "haven_closed": "%s is no haven for pirates any more"}.get(type, "The market in %s shifts") % Ports.port(port).name
		"bombard_port":
			if port == "":
				return _skip(type, "no port")
			var sev: float = float(e.get("severity", 1.0))
			m.apply_effect(port, {"type": "port_damage", "severity": 0.3 * sev, "reason": "Rebuilding after the bombardment"})
			var f: String = Ports.port(port).faction
			s.relations[f] = s.relations.get(f, 0) - int(15 * sev)
			s.reputation.notoriety += int(5 * sev)
			s.reputation.fear += int(2 * sev)
			return "%s burns under your guns" % Ports.port(port).name
		"burn_ships_in_road":
			var n := 0
			for v in m.traffic.voyages.duplicate():
				if n < int(e.get("count", 1)) and (v.origin == here or v.dest == here):
					m.traffic.lose(v, "player", m.day)
					n += 1
			if here != "":
				var f: String = Ports.port(here).faction
				s.relations[f] = s.relations.get(f, 0) - 5 * n
			return "%d ship%s burned in the roads" % [n, "" if n == 1 else "s"]
		"open_market":  # a market opens for you here: a smugglers' night, a fair; it pays a bonus on what it wants
			_econ(s).open_market[here] = {"kind": e.get("kind", "smuggling"), "bonus": float(e.get("price_bonus", 20)) / 100.0, "until": Clock.day + int(e.get("days", 7))}
			return "A %s market opens to you%s" % [e.get("kind", "smuggling"), " in " + Ports.port(here).name if here != "" else ""]
		"port_closed_days":
			if port == "":
				return _skip(type, "no port")
			_econ(s).closed_ports[port] = Clock.day + int(e.get("days", 30))
			return "%s is closed to you for %d days" % [Ports.port(port).name, int(e.get("days", 30))]
		"free_supplies":
			if port == "":
				return _skip(type, "no port")
			_econ(s).free_supplies[port] = until
			return "Provisions and water are yours for the asking in %s" % Ports.port(port).name
		"repair_discount":
			_econ(s).repair_discount = {"percent": float(e.get("percent", 25)), "until": until}
			return "Repairs cost %d%% less for %d days" % [int(e.get("percent", 25)), days]
		"trade_profit_multiplier":
			_econ(s).trade_mult = {"value": float(e.get("value", 1.0)), "until": until}
			return "Your trading fetches %d%% %s for a while" % [absi(int(round((float(e.get("value", 1.0)) - 1.0) * 100))), "more" if float(e.get("value", 1.0)) >= 1.0 else "less"]
		"merchant_resistance_multiplier":
			_econ(s).merchant_resist = {"value": float(e.get("value", 1.0)), "until": until}
			return "Merchants will fight %s for a while" % ("harder" if float(e.get("value", 1.0)) > 1.0 else "less")
		"buy_provisions":  # buy days of food from whoever you've hailed, at their price
			var mouths := ShipStats.headcount(s)
			var qty := int(ceil(mouths * Data.rules.upkeep.food_per_crew * float(e.get("days", 14))))
			var unit: float = Data.table("goods").food.base_price * float(e.get("price_multiplier", 1.0))
			qty = mini(qty, int(s.gold / maxf(unit, 0.01)))
			s.gold -= qty * unit
			s.cargo.food = s.cargo.get("food", 0.0) + qty
			return "Bought %d provisions for %d" % [qty, int(qty * unit)]
		"sell_items":  # sell what you hold of these goods, at a fraction of their worth
			var got := 0
			for item in e.get("items", []):
				var g := Market.canonical(item)
				if not Data.table("goods").has(g):
					continue
				var have: float = s.cargo.get(g, 0.0)
				if have > 0.0:
					got += int(have * Data.table("goods")[g].base_price * float(e.get("price_multiplier", 1.0)))
					Ports.remove_cargo(s, g, have)
			s.gold += got
			return "Sold for %d" % got if got > 0 else ""
		"launder_prize":  # papers that make a prize lawful
			for p in s.get("prizes", []):
				p.laundered = true
			return "Your prize's papers are in order now"
		"prize_unsellable_here":
			if here != "":
				_econ(s).prize_banned[here] = true
			return "No one here will buy your prize"
		"unlock_fence":
			if here != "":
				_econ(s).fences[here] = true
			return "You have a fence in %s now" % Ports.port(here).name if here != "" else ""
		"fence_trust", "fence_dependence":
			var where := here if here != "" and Ports.is_fence(here, s) else _nearest_fence(here)
			if where == "":
				return ""
			if type == "fence_trust":
				s.fence_trust = s.get("fence_trust", {})
				s.fence_trust[where] = maxf(0.0, s.fence_trust.get(where, 0.0) + float(e.get("amount", 0)) * Data.rules.fence.trust_per_point)
				return "The fence in %s %s you more" % [Ports.port(where).name, "trusts" if float(e.get("amount", 0)) > 0 else "distrusts"]
			_econ(s).fence_dependence[where] = _econ(s).fence_dependence.get(where, 0.0) + float(e.get("amount", 0))
			return "You're more at the mercy of the fence in %s" % Ports.port(where).name
		"rep_with_smugglers":
			_econ(s).smugglers = clampf(_econ(s).smugglers + float(e.get("amount", 0)), -100.0, 100.0)
			return "The smugglers think %s of you" % ("better" if float(e.get("amount", 0)) > 0 else "less")
		"unlock_trade_with":
			_econ(s).trade_with.append(e.get("npc", ""))
			return "They'll trade with you now"
		"treat_ships_from", "faction_port_hostility":
			if port == "":
				return _skip(type, "no port")
			var f: String = Ports.port(port).faction
			if type == "faction_port_hostility":
				s.relations[f] = s.relations.get(f, 0) - int(e.get("amount", 20))
				return "%s turns against you" % Ports.port(port).name
			_econ(s).hostile[f] = Clock.day + int(e.get("days", 180))
			return "Ships out of %s will attack you on sight" % Ports.port(port).name
		# ---- the world ----
		"war":
			var between: Array = e.get("between", [])
			if between.size() == 2:
				Factions.declare(between[0], between[1], e.get("until", ""))
				return "War between %s and %s" % [Data.table("factions")[between[0]].name, Data.table("factions")[between[1]].name]
		"world_state":
			m.set_world("state:" + e.key, e.get("value", true), int(e.get("days", -1)))
			if e.get("value", true):
				Events.flags[e.key] = Clock.day + int(e.days) if e.has("days") else -1.0
			else:
				Events.flags.erase(e.key)
			return ""
		"pirate_spawn_rate_multiplier":
			m.set_world("pirates", float(e.get("value", 1.0)), int(e.get("days", 365)))
			return "More pirates on the seas" if float(e.get("value", 1.0)) > 1.0 else "Fewer pirates on the seas"
		"letter_of_marque":
			return Career.grant_marque(s, e.get("faction", "england")) if not s.is_empty() else ""
		"revoke_letter_of_marque":
			return Career.revoke(s, "the commission is withdrawn") if not s.is_empty() and s.career.marque != "" else ""
		# ---- history's own ----
		"fleet_blocked":
			m.set_world("fleet_blocked:" + e.fleet, true, days)
			return "%s won't sail while the blockade holds" % Economy.cfg().fleets[e.fleet].name.capitalize()
		"trade_slump":
			m.set_world("sailings:" + e.faction, float(e.get("sailings", 0.6)), days)
			m.set_world("imports:" + e.faction, float(e.get("imports", 0.7)), days)
			return "Trade with %s's colonies slumps" % Data.table("factions")[e.faction].name
		"fair_access":
			m.set_world("fair_access:" + e.faction, true, int(e.get("days", -1)))
			return "%s ships may trade at the Spanish fairs" % Data.table("factions")[e.faction].adjective.capitalize()
		"port_laws":
			if port == "":
				return _skip(type, "no port")
			var laws: Dictionary = Ports.state[port].laws
			for k in e.get("laws", {}):
				laws[k] = e.laws[k]
			if e.has("fence"):
				Ports.state[port].fence_closed = not e.fence
			return ""
		# ---- money and cargo ----
		"gold":
			s.gold = maxf(0.0, s.gold + float(e.get("amount", 0)))
			return "%+d gold" % int(e.get("amount", 0))
		"gold_percent":
			var delta: float = s.gold * float(e.get("percent", 0)) / 100.0
			s.gold = maxf(0.0, s.gold + delta)
			return "%+d gold" % int(delta)
		"cargo_percent":
			var pct: float = float(e.get("percent", 0)) / 100.0
			for g in s.cargo.keys():
				if g != "food" and g != "water":
					var change: float = floor(s.cargo[g] * pct)
					if change < 0:
						Ports.remove_cargo(s, g, -change)
					else:
						s.cargo[g] += change
			return "%+d%% of your cargo" % int(pct * 100)
		"provisions":
			var food: float = ShipStats.headcount(s) * Data.rules.upkeep.food_per_crew * float(e.get("days", e.get("amount", 0)))
			s.cargo.food = maxf(0.0, s.cargo.get("food", 0.0) + food)
			return "%+d days of provisions" % int(e.get("days", e.get("amount", 0)))
	return ""


## A port named by an effect: an id, "current" (where the player is), or a name the content gives in ctx.
static func _port(spec: String, ctx: Dictionary) -> String:
	if Ports.state.has(spec):
		return spec
	if spec == "current" or spec == "":
		return ctx.get("port", "")
	var named: String = ctx.get(spec, "")
	return named if Ports.state.has(named) else ""


static func _nearest_fence(here: String) -> String:
	for id in Ports.state:
		if Ports.port(id).get("fence", false):
			return id
	return ""


## The player's market standing from effects, with expiry days: {open_market, closed_ports, free_supplies, ...}.
static func _econ(s: Dictionary) -> Dictionary:
	if not s.has("econ"):
		s.econ = {"open_market": {}, "closed_ports": {}, "free_supplies": {}, "repair_discount": {}, "trade_mult": {},
			"merchant_resist": {}, "prize_banned": {}, "fences": {}, "fence_dependence": {}, "smugglers": 0.0,
			"trade_with": [], "hostile": {}}
	return s.econ


static func econ(s: Dictionary) -> Dictionary:
	return _econ(s)


## A timed effect's value if it's still in force: {value or percent...} dicts with "until", or a plain expiry day.
static func active(s: Dictionary, key: String, sub := "") -> Variant:
	var e: Dictionary = _econ(s)
	var v = e.get(key)
	if sub != "":
		v = v.get(sub) if v is Dictionary else null
	if v is Dictionary and v.is_empty():
		return null
	if v is Dictionary and v.has("until"):
		return v if Clock.day <= float(v.until) else null
	if v is float or v is int:
		return v if Clock.day <= float(v) else null
	return v


static func _skip(type: String, why: String) -> String:
	push_warning("Economy: effect '%s' skipped (%s)." % [type, why])
	return ""
