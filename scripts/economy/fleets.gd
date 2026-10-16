class_name Fleets
extends RefCounted
## The great convoys that set the rhythm of the year (data/economy.json "fleets"). The Spanish treasure fleets come
## out once a year: before they arrive, European goods are scarce and dear in Spanish ports; when they do, a fair
## floods the market, and when they sail home they carry off the silver and much of the colonial produce. After
## 1700 they're irregular: some years they don't come at all. The English and French sugar convoys gather in summer,
## buying sugar and rum for home before they sail. Each fleet's "brings" is so many days of each port's use;
## "takes" is the share of the stock it buys up when it sails; "fair_use" raises use while it's in port.

var m: EconomyModel
var state := {}          # fleet id -> {status: waiting/due/fair, due, until, year}
var events: Array = []   # [{kind: arrived/sailed/skipped, fleet, day, ports, treasure}] for the game to report


func _init(model: EconomyModel) -> void:
	m = model
	for id in table():
		state[id] = {"status": "waiting", "due": -1, "until": -1, "year": 0}


func table() -> Dictionary:
	var out := {}
	for id in m.cfg.get("fleets", {}):
		if not id.begins_with("_"):
			out[id] = m.cfg.fleets[id]
	return out


func step(day: int, month: int, year: int) -> void:
	for id in table():
		var f: Dictionary = m.cfg.fleets[id]
		var st: Dictionary = state[id]
		if st.status == "waiting" and month == int(f.month) and st.year != year:
			st.year = year
			if year >= int(f.get("irregular_from", 99999)) and m.rng.randf() < f.get("skip_chance", 0.0):
				events.append({"kind": "skipped", "fleet": id, "day": day, "ports": f.ports})
				continue
			st.status = "due"
			st.due = day + m.rng.randi_range(int(f.delay_days[0]), int(f.delay_days[1]))
		if st.status == "due" and day >= st.due:
			for p in f.ports:
				for g in f.get("brings", {}):
					m.add(p, g, m.params[p][g].use * float(f.brings[g]))
			st.status = "fair"
			st.until = day + int(f.fair_days)
			events.append({"kind": "arrived", "fleet": id, "day": day, "ports": f.ports})
		elif st.status == "fair" and day >= st.until:
			var treasure := 0.0
			for p in f.ports:
				for g in f.get("takes", {}):
					var qty: float = m.stock[p][g] * float(f.takes[g])
					m.add(p, g, -qty)
					if m.goods[g].demand == "treasure":
						treasure += qty * m.goods[g].base_price
			st.status = "waiting"
			events.append({"kind": "sailed", "fleet": id, "day": day, "ports": f.ports, "treasure": treasure})


## Use multiplier while a fleet is in: crowds at a fair, a convoy buying cargo for home.
func use_mult(port: String, good: String) -> float:
	var mult := 1.0
	for id in table():
		var f: Dictionary = m.cfg.fleets[id]
		if state[id].status == "fair" and port in f.ports:
			mult *= float(f.get("fair_use", {}).get(good, 1.0))
	return mult


## The fleet that serves this port, and where it stands: {id, status, days} (days until due or until it sails), or {}.
func for_port(port: String) -> Dictionary:
	for id in table():
		if port in m.cfg.fleets[id].ports:
			var st: Dictionary = state[id]
			var days := -1
			if st.status == "due":
				days = st.due - m.day
			elif st.status == "fair":
				days = st.until - m.day
			return {"id": id, "status": st.status, "days": days}
	return {}


func take_events() -> Array:
	var out := events
	events = []
	return out


func save_state() -> Dictionary:
	return {"state": state}


func load_state(d: Dictionary) -> void:
	for id in d.state:
		if state.has(id):
			state[id] = d.state[id]
			for k in ["due", "until", "year"]:
				state[id][k] = int(state[id][k])
