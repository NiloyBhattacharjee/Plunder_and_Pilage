extends Node
## Autoload "Economy": runs the EconomyModel on the game clock and answers the game's questions about prices.
## Everything that moves stock goes through here (the player's trades, merchants arriving, shocks), so the
## model stays the one source of truth. Laws (duties, contraband) live with the ports (Ports.state[id].laws).

signal fleet_event(ev: Dictionary)  # a fleet arrived, sailed, or didn't come this year

var model := EconomyModel.new()
var _warm := {}  # starting month -> the warmed-up model's state
var news: Array = []  # [{text, port, day}]: things that happened, travelling toward the player at sailing speed


func _ready() -> void:
	reset()
	Clock.day_passed.connect(_on_day)


func cfg() -> Dictionary:
	return Data.table("economy")


## A fresh economy, warmed up so it opens at its own balance. seed < 0 picks one at random.
func reset(seed := -1) -> void:
	model.setup(Data.table("goods"), Data.table("ports"), cfg(), seed if seed >= 0 else randi())
	var date := Clock.date_of(int(Clock.day))
	var month: int = date.month
	if not _warm.has(month):  # warming up takes a moment, so it's done once per starting month and reused
		model.warm_up(int(cfg().warm_up_days), month, date.year)
		_warm[month] = model.save_state().duplicate(true)
	model.load_state(_warm[month].duplicate(true))


func _on_day(d: int) -> void:
	model.traffic.wars = _wars()
	model.brethren.pardons = Factions.pardons.duplicate()
	var date := Clock.date_of(d)
	model.step(date.month, date.year)
	for ev in model.brethren.take_events():
		add_news(ev.text, ev.port)
	for ev in model.fleets.take_events():
		fleet_event.emit(ev)
	for ev in model.shocks.take_events():
		add_news(ev.news, ev.port)
	if d % 7 == 0:
		model.sample_week()


## Duty on a legal trade in this good here: the nation's customs plus the port's own tariff. Smugglers pay none,
## and nor do you in a town you hold.
func duty(id: String, good: String) -> float:
	if Bases.is_town(id):
		return 0.0
	var laws: Dictionary = Ports.state[id].laws
	if good in laws.contraband:
		return 0.0
	return maxf(0.0, cfg().duty.get(Ports.port(id).faction, 0.0) + laws.get("tariff", 0.0))


func price(id: String, good: String, buying: bool, spread_mult := 1.0) -> float:
	return model.price(id, good, buying, spread_mult, duty(id, good))


func quote(id: String, good: String, qty: int, buying: bool, spread_mult := 1.0) -> int:
	return model.quote(id, good, qty, buying, spread_mult, duty(id, good))


func mult(id: String, good: String) -> float:
	return model.mult(id, good)


func stock(id: String, good: String) -> float:
	return model.stock[id].get(good, 100000.0)


func add(id: String, good: String, qty: float) -> void:
	model.add(id, good, qty)


func max_buy(id: String, good: String) -> int:
	return model.max_buy(id, good)


func level(id: String, good: String) -> String:
	return model.level(id, good) if model.is_traded(good) else "normal"


func reason(id: String, good: String) -> String:
	return model.reason(id, good, Clock.date().month)


func breakdown(id: String, good: String, spread_mult := 1.0) -> String:
	var text := model.breakdown(id, good, Clock.date().month, spread_mult, duty(id, good))
	if good in Ports.state[id].laws.contraband:
		text += "\nCONTRABAND here: no duty, but selling risks seizure and a fine."
	return text


func history(id: String, good: String) -> Array:
	return model.history.get(id, {}).get(good, [])


func produces(id: String) -> Array:
	return model.produces(id)


func wants(id: String) -> Array:
	return model.wants(id)


## A timed shock on one good in one port (see EconomyModel.add_mod).
func shock(id: String, s: Dictionary) -> void:
	model.add_mod(id, s)


func mods(id: String) -> Array:
	return model.mods[id]


## Which nations are at war, for the merchants to steer clear of.
func _wars() -> Array:
	var out := []
	var nations: Array = Career.nations()
	for i in nations.size():
		for j in range(i + 1, nations.size()):
			if Factions.at_war(nations[i], nations[j]):
				out.append([nations[i], nations[j]])
	return out


## The fleet that serves this port in a sentence, or "": what every quayside knows.
func fleet_text(id: String) -> String:
	var f := model.fleets.for_port(id)
	if f.is_empty():
		return ""
	var name: String = cfg().fleets[f.id].name
	match f.status:
		"fair":
			return "%s is in port: %d more days before it sails for home." % [name.capitalize(), f.days]
		"due":
			return "%s is expected in about %d days." % [name.capitalize(), maxi(1, f.days)]
	return "%s is due again in %s." % [name.capitalize(), ["January", "February", "March", "April", "May", "June", "July",
		"August", "September", "October", "November", "December"][int(cfg().fleets[f.id].month) - 1]]


func price_at(id: String, good: String, mult: float, buying: bool, spread_mult := 1.0) -> float:
	return model.price_at_mult(id, good, mult, buying, spread_mult, duty(id, good))


## A day in the model's count as a game day (the model ran a warm-up before the game began).
func to_game_day(model_day: int) -> int:
	return int(Clock.day) - (model.day - model_day)


func voyage(id: String) -> Dictionary:
	for v in model.traffic.voyages:
		if v.id == id:
			return v
	return {}


## Something happened at a port; the player hears of it when a ship could have brought word.
func add_news(text: String, port: String) -> void:
	news.append({"text": text, "port": port, "day": int(Clock.day)})


## The news that has reached `near` (the port nearest the player) by today, removed from the queue.
func news_reaching(near: String) -> Array:
	var out := []
	for n in news.duplicate():
		var delay := 0.0 if n.port == near or near == "" else model.traffic.days(n.port, near)
		if Clock.day >= n.day + delay:
			news.erase(n)
			out.append(n)
	return out


func voyages() -> Array:
	return model.traffic.voyages


## A voyage ends without arriving: taken by the player or by pirates, or sunk.
func lose_voyage(id: String, cause: String, company := "") -> void:
	model.traffic.lose_id(id, cause, model.day, company)


## How far along her voyage a ship is, 0 at the origin and 1 at the destination.
func progress(v: Dictionary) -> float:
	return clampf(float(model.day - v.depart) / maxf(1.0, v.arrive - v.depart), 0.0, 1.0)


func save_state() -> Dictionary:
	var d := model.save_state()
	d.news = news
	return d


func load_state(d: Dictionary) -> void:
	model.load_state(d)
	news = d.get("news", [])
