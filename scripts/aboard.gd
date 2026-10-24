class_name Aboard
## Life below decks (data/aboard.json): small moments between the hands, picked by who they are (a fiddler, a
## drunk, a navy man drilling the guns, two friends, two who can't stand each other), each with a small real
## effect: morale, what they think of each other, a skill passed on. And what's on each hand's mind today, for
## the roster. The moments are kept in s.aboard.log, newest first.


static func table() -> Dictionary:
	return Data.table("aboard")


## Maybe one moment today. Returns the news.
static func day(s: Dictionary, port: String, rng: RandomNumberGenerator) -> Array:
	var r: Dictionary = table()._rules
	if s.crew.size() < 2 or rng.randf() >= float(r.chance):
		return []
	var st: Dictionary = s.get("aboard", {"log": [], "last": {}})
	s.aboard = st
	var ids: Array = table().moments.keys()
	ids.shuffle()
	for id in ids:
		if Clock.day - float(st.last.get(id, -9999.0)) < float(r.cooldown):
			continue
		var m: Dictionary = table().moments[id]
		var cast := _cast(s, m, port, rng)
		if cast.is_empty():
			continue
		st.last[id] = Clock.day
		var text := _apply(s, m, cast, port)
		st.log.push_front({"day": int(Clock.day), "text": text})
		if st.log.size() > int(r.log):
			st.log.pop_back()
		return [text]
	return []


## Who it happens to: {a, b?}, or {} if nobody aboard fits.
static func _cast(s: Dictionary, m: Dictionary, port: String, rng: RandomNumberGenerator) -> Dictionary:
	var where: String = m.get("where", "")
	if (where == "sea" and port != "") or (where == "port" and port == "") or (m.get("rum", false) and s.cargo.get("rum", 0.0) <= 0.0):
		return {}
	var hands: Array = Crew.people(s).filter(func(c): return _fits(c, m.a))
	if hands.is_empty():
		return {}
	var a: Dictionary = hands[rng.randi() % hands.size()]
	if not m.has("b"):
		return {"a": a}
	var others: Array = Crew.people(s).filter(func(c): return c.id != a.id and _other(s, a, c, m.b))
	if others.is_empty():
		return {}
	return {"a": a, "b": others[rng.randi() % others.size()]}


static func _fits(c: Dictionary, want: Dictionary) -> bool:
	if c.get("sick", "") != "":
		return false
	if want.has("tags") and not Crew.tags(c).any(func(t): return t in want.tags):
		return false
	if want.has("traits") and not People.known_traits(c).any(func(t): return t in want.traits):
		return false
	for sk in want.get("skill", {}):
		if People.value(c, sk) < int(want.skill[sk]):
			return false
	return true


static func _other(s: Dictionary, a: Dictionary, c: Dictionary, kind: String) -> bool:
	match kind:
		"friend": return c.id in Crew.friends_of(s, a.id)
		"feud": return Crew.feuds(s).any(func(p): return a.id in p and c.id in p)
		"green": return c.age < 25 or "green" in c.traits
		"sick": return c.get("sick", "") != ""
	return c.get("sick", "") == ""


static func _apply(s: Dictionary, m: Dictionary, cast: Dictionary, port: String) -> String:
	var a: Dictionary = cast.a
	var b: Dictionary = cast.get("b", {})
	if m.has("mood"):
		Crew.add_mod(s, "aboard", m.name, float(m.mood[0]), float(m.mood[1]))
	if m.has("bond") and not b.is_empty():
		for pair in [[a, b], [b, a]]:
			pair[0].relations[pair[1].id] = clampi(pair[0].relations.get(pair[1].id, 0) + int(m.bond), -100, 100)
	if m.has("teach") and not b.is_empty():
		People.gain_xp(b, m.teach, float(table()._rules.teach_xp))
	if m.has("opinion"):
		Crew.feel(s, a, int(m.opinion), m.name)
	var text: String = m.text.replace("{a}", a.name).replace("{b}", b.get("name", "")).replace("{ship}", s.name)
	return text.replace("{port}", Ports.port(port).name if port != "" else "port")


## What's on a hand's mind today, in a few words, most pressing first.
static func mind(c: Dictionary, s: Dictionary) -> String:
	if c.get("sick", "") != "":
		return "Down with %s" % Data.rules.crew.disease[c.sick].name.to_lower()
	if s.unrest.stage > 0 and c.id in s.unrest.support:
		return "Listening to the plotters" if c.id != s.unrest.leader else "Stirring up the crew"
	var feud := Crew.feuds(s).filter(func(p): return c.id in p)
	if not feud.is_empty():
		return "Can't stand %s" % People.person(feud[0][0] if feud[0][1] == c.id else feud[0][1]).name
	if Wants.open(c):
		return Wants.want_text(c)
	var mem := Crew.memories(c, s)
	if not mem.is_empty() and Clock.day - float(mem[0].day) < 14.0:
		return ("Still sore: " if mem[0].n < 0 else "Pleased: ") + mem[0].why.to_lower()
	var friends := Crew.friends_of(s, c.id)
	if not friends.is_empty():
		return "Thick as thieves with %s" % People.person(friends[0]).name
	for t in People.known_traits(c):
		if table().idle.has(t):
			return table().idle[t]
	return "Content enough"


## What a hand holds for and against you, for a tooltip.
static func reasons(c: Dictionary, s: Dictionary) -> String:
	var mem := Crew.memories(c, s)
	if mem.is_empty():
		return "Nothing in particular, for or against you."
	return "\n".join(mem.map(func(m): return "%+d  %s (%s)" % [m.n, m.why, Clock.date_string_of(m.day)]))
