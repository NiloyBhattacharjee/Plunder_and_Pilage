class_name Voices
## Your people speak up at decisions (data/voices.json). Before you choose, the officers and hands you know argue
## for or against a choice in their own words, from who they are. Take their advice and they warm to you; overrule
## them and they remember.
## A voice: {id, index (the option), choice (its text), for (true: for it, false: against it), line}.


static func table() -> Dictionary:
	return Data.table("voices")


## A choice's stances from its outcomes: "kill {thief}", "fear +3", "gold -300" -> {cruel: 2, greedy: -1}.
static func infer(outcomes: Array) -> Dictionary:
	var out := {}
	for o in outcomes:
		var a: PackedStringArray = str(o).split(" ")
		var rule: Dictionary = table().infer.get(a[0], {})
		var n := 1.0
		if a.size() > 1 and a[0] in ["fear", "honour", "gold"]:
			n = signf(float(a[1].trim_suffix("%")))
		for k in rule:
			out[k] = out.get(k, 0) + int(rule[k] * n)
	return out


## How much this person likes a choice with these stances, and which stance moves them most.
static func _score(c: Dictionary, stances: Dictionary) -> Array:
	var total := 0
	var top := ""
	var top_v := 0
	for t in c.traits:
		var w: Dictionary = table().traits.get(t, {})
		for k in w:
			var v := int(w[k]) * int(stances.get(k, 0))
			total += v
			if absi(v) > absi(top_v):
				top_v = v
				top = k
	return [total, top]


## Who speaks up, and for what. options: [{text, disabled?, voice: {stance: n}}]; skip: people the decision is about.
static func weigh(s: Dictionary, options: Array, skip := [], rng: RandomNumberGenerator = null) -> Array:
	var r: Dictionary = table()._rules
	var out := []
	if options.filter(func(o): return not o.get("disabled", false)).size() < 2:
		return out  # nothing to argue about
	for id in Wants.people(s):
		if id in skip:
			continue
		var c := People.person(id)
		var best := {}
		for i in options.size():
			if options[i].get("disabled", false) or options[i].get("voice", {}).is_empty():
				continue
			var sc := _score(c, options[i].voice)
			if absi(sc[0]) >= int(r.min) and (best.is_empty() or absi(sc[0]) > absi(best.score)):
				var key: String = sc[1] + ("+" if int(options[i].voice[sc[1]]) > 0 else "-")
				var lines: Array = table().lines[key]["for" if sc[0] > 0 else "against"]
				best = {"id": id, "index": i, "for": sc[0] > 0, "score": sc[0], "choice": options[i].text,
					"line": lines[(rng.randi() if rng != null else absi(hash(id + str(Clock.day)))) % lines.size()]}
		if not best.is_empty():
			out.append(best)
	out.sort_custom(func(a, b): return absi(a.score) > absi(b.score))
	return out.slice(0, int(r.max))


static func _who(s: Dictionary, id: String) -> String:
	var c := People.person(id)
	for post in s.officers:
		if s.officers[post] == id:
			return "%s, your %s," % [c.name, Data.rules.officer_roles[post].name.to_lower()]
	return c.name


## The dialog with its voices: the arguments under the text, and who's for and against in each option's tooltip.
## Returns {text, options, voices}.
static func dress(s: Dictionary, text: String, options: Array, skip := [], rng: RandomNumberGenerator = null) -> Dictionary:
	var voices := weigh(s, options, skip, rng)
	if voices.is_empty():
		return {"text": text, "options": options, "voices": voices}
	var said := PackedStringArray()
	for v in voices:
		said.append("%s is %s \"%s\": \"%s\"" % [_who(s, v.id), "for" if v["for"] else "against", v.choice, v.line])
	var opts := options.duplicate(true)
	for i in opts.size():
		var who := PackedStringArray()
		for v in voices.filter(func(x): return x.index == i):
			who.append("%s is %s it" % [People.person(v.id).name, "for" if v["for"] else "against"])
		if not who.is_empty():
			opts[i].tooltip = (opts[i].get("tooltip", "") + "\n" if opts[i].get("tooltip", "") != "" else "") + ". ".join(who) + ". They'll remember what you choose."
	return {"text": text + "\n\n" + "\n".join(said), "options": opts, "voices": voices}


## You chose. Those you heeded warm to you; those you overruled remember. Returns the news.
static func heard(s: Dictionary, voices: Array, pick: int) -> Array:
	var r: Dictionary = table()._rules
	var out := []
	for v in voices:
		if not People.chars.has(v.id) or not v.id in s.crew:
			continue
		var c := People.person(v.id)
		var heeded: bool = (pick == v.index) == v["for"]
		var d := int(r.heeded if heeded else r.overruled)
		c.relations[s.captain] = clampi(c.relations.get(s.captain, 0) + d, -100, 100)
		if heeded:
			out.append("%s: you listened (opinion %+d)" % [c.name, d])
		else:
			c.history.append("Spoke %s \"%s\" and was overruled, %s." % ["for" if v["for"] else "against", v.choice, Clock.date_string()])
			out.append("%s won't forget you overruled them (opinion %+d)" % [c.name, d])
	return out
