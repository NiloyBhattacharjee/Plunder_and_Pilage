class_name Market
## Small helpers about goods and cargo. Prices and stock live in the Economy (scripts/economy/).


static func weight(good: String) -> float:
	return Data.table("goods")[good].get("weight", 1.0)


static func cargo_used(cargo: Dictionary) -> float:
	var total := 0.0
	for good in cargo:
		total += cargo[good] * weight(good)
	return total


## A good's id, following the aliases in data/economy.json (provisions -> food, gems -> gold...).
static func canonical(good: String) -> String:
	return Data.table("economy").aliases.get(good, good)


static func seizure_chance(laws: Dictionary, good: String, qty: int) -> float:
	if not good in laws.contraband:
		return 0.0
	var p: float = Data.rules.smuggling.seizure_per_10_units * laws.vigilance
	return 1.0 - pow(1.0 - p, qty / 10.0)


static func fmt(price: float) -> String:
	return "%.1f" % price if price < 10.0 else str(int(round(price)))
