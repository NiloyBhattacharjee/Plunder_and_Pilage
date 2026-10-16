extends Node
## Autoload "Economy": runs the EconomyModel on the game clock and answers the game's questions about prices.
## Everything that moves stock goes through here (the player's trades, merchants arriving, shocks), so the
## model stays the one source of truth. Laws (duties, contraband) live with the ports (Ports.state[id].laws).

var model := EconomyModel.new()
var _warm := {}  # starting month -> warmed-up {stock, history}


func _ready() -> void:
	reset()
	Clock.day_passed.connect(_on_day)


func cfg() -> Dictionary:
	return Data.table("economy")


## A fresh economy, warmed up so it opens at its own balance. seed < 0 picks one at random.
func reset(seed := -1) -> void:
	model.setup(Data.table("goods"), Data.table("ports"), cfg(), seed if seed >= 0 else randi())
	var month: int = Clock.date_of(int(Clock.day)).month
	if not _warm.has(month):  # the warm-up has no randomness, so it's worked out once per starting month
		model.warm_up(int(cfg().warm_up_days), month)
		_warm[month] = {"stock": model.stock.duplicate(true), "history": model.history.duplicate(true)}
	model.stock = _warm[month].stock.duplicate(true)
	model.history = _warm[month].history.duplicate(true)


func _on_day(d: int) -> void:
	model.step(Clock.date_of(d).month)
	if d % 7 == 0:
		model.sample_week()


## Duty on a legal trade in this good here: the nation's customs plus the port's own tariff. Smugglers pay none.
func duty(id: String, good: String) -> float:
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


func save_state() -> Dictionary:
	return model.save_state()


func load_state(d: Dictionary) -> void:
	model.load_state(d)
