class_name Market
## Port market maths. A price comes only from local stock: producing a good keeps stock high (cheap),
## wanting it keeps stock low (dear). Player trades move stock, which then drifts back toward normal.
## Stock is measured in tons, so a unit of a light good (provisions) moves the market less.

const KIND_LABELS := {"produces": "produced here", "wants": "in demand here", "neutral": "traded here"}


static func cfg() -> Dictionary:
	return Data.rules.market


static func weight(good: String) -> float:
	return Data.table("goods")[good].get("weight", 1.0)


static func cargo_used(cargo: Dictionary) -> float:
	var total := 0.0
	for good in cargo:
		total += cargo[good] * weight(good)
	return total


static func kind(port: Dictionary, good: String) -> String:
	if good in port.produces: return "produces"
	if good in port.wants: return "wants"
	return "neutral"


## Stock this port drifts toward, after timed modifiers (shortages, gluts).
static func normal_stock(port: Dictionary, good: String, mods: Array) -> float:
	var n: float = cfg().normal_stock[kind(port, good)] * cfg().size_mult[port.size]
	for m in mods:
		if m.good == good:
			n *= m.mult
	return n


static func supply_factor(port: Dictionary, stock: float) -> float:
	var reference: float = cfg().normal_stock.neutral * cfg().size_mult[port.size]
	return clampf(pow(reference / maxf(stock, 0.5), cfg().elasticity), cfg().price_clamp[0], cfg().price_clamp[1])


static func unit_price(port: Dictionary, good: String, stock: float, buying: bool) -> float:
	var half: float = cfg().spread / 2.0
	var mid: float = Data.table("goods")[good].base_price * supply_factor(port, stock)
	return mid * (1.0 + half if buying else 1.0 - half)


## Total price of buying (or income from selling) qty units. Each unit moves stock, so big trades get worse prices.
static func quote(port: Dictionary, good: String, stock: float, qty: int, buying: bool) -> int:
	var w := weight(good)
	var total := 0.0
	for i in qty:
		total += unit_price(port, good, stock - i * w if buying else stock + i * w, buying)
	return int(round(total))


## Most units the market will sell before it runs dry.
static func max_buy(good: String, stock: float) -> int:
	return maxi(0, int((stock - 1.0) / weight(good)))


static func seizure_chance(laws: Dictionary, good: String, qty: int) -> float:
	if not good in laws.contraband:
		return 0.0
	var p: float = Data.rules.smuggling.seizure_per_10_units * laws.vigilance
	return 1.0 - pow(1.0 - p, qty / 10.0)


## One day of drift: stock moves part of the way back to normal, plus noise. Timed modifiers count down.
static func daily_update(port: Dictionary, pstate: Dictionary, rng: RandomNumberGenerator) -> void:
	for good in pstate.stock:
		var n := normal_stock(port, good, pstate.mods)
		var s: float = pstate.stock[good]
		s += (n - s) * cfg().reversion + rng.randfn(0.0, cfg().noise) * n
		pstate.stock[good] = maxf(1.0, s)
	for m in pstate.mods:
		m.days_left -= 1
	pstate.mods = pstate.mods.filter(func(m): return m.days_left > 0)


## Tooltip text explaining a price, Paradox style.
static func breakdown(port: Dictionary, good: String, pstate: Dictionary, laws: Dictionary) -> String:
	var stock: float = pstate.stock[good]
	var lines := PackedStringArray()
	lines.append("Base price: %s" % fmt(Data.table("goods")[good].base_price))
	lines.append("Normal stock: %d tons (%s, %s port)" % [normal_stock(port, good, []), KIND_LABELS[kind(port, good)], port.size])
	for m in pstate.mods:
		if m.good == good:
			lines.append("  %s: normal stock x%.1f (%d days left)" % [m.reason, m.mult, m.days_left])
	lines.append("Current stock: %d tons" % stock)
	lines.append("Supply: price x%.2f" % supply_factor(port, stock))
	lines.append("Merchant spread: %d%%" % int(cfg().spread * 100))
	if good in laws.contraband:
		lines.append("CONTRABAND here. Selling risks seizure and a fine.")
	return "\n".join(lines)


static func fmt(price: float) -> String:
	return "%.1f" % price if price < 10.0 else str(int(round(price)))
