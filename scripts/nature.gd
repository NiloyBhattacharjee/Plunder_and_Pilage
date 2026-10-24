class_name Nature
## The captain's nature. A choice that one of the captain's traits cares about (data/voices.json traits x the
## choice's stances) is in it or against it, and the event dialog says so. Go against a trait often enough and
## it's gone; lean the same way often enough and you take one on. Tuning: rules.json "nature".


static func cfg() -> Dictionary:
	return Data.rules.nature


## The captain's traits this choice speaks to: {trait: 1 (in your nature) or -1 (against it)}.
static func stance(cap: Dictionary, voice: Dictionary) -> Dictionary:
	var out := {}
	for t in cap.traits:
		var w: Dictionary = Voices.table().traits.get(t, {})
		var v := 0
		for k in w:
			v += int(w[k]) * int(voice.get(k, 0))
		if absi(v) >= int(cfg().min):
			out[t] = signi(v)
	return out


## "[Merciful] " or "[Against: Bloodthirsty] ", in front of a choice.
static func tag(cap: Dictionary, voice: Dictionary) -> String:
	var st := stance(cap, voice)
	var out := ""
	for t in st:
		out += ("[%s] " if st[t] > 0 else "[Against: %s] ") % Data.table("traits")[t].name
	return out


## The captain chose. Going against a trait strains it until it breaks; leaning one way long enough becomes a
## trait. Returns the news.
static func chose(cap: Dictionary, voice: Dictionary) -> Array:
	var news := []
	var st := stance(cap, voice)
	cap.strain = cap.get("strain", {})
	for t in st:
		if st[t] > 0:
			cap.strain[t] = maxi(0, int(cap.strain.get(t, 0)) - 1)  # being yourself eases it
			continue
		cap.strain[t] = int(cap.strain.get(t, 0)) + 1
		var tn: String = Data.table("traits")[t].name.to_lower()
		if cap.strain[t] < int(cfg().strain):
			news.append("You went against your nature (%s, %d of %d)" % [tn, cap.strain[t], int(cfg().strain)])
			continue
		cap.traits.erase(t)
		cap.strain.erase(t)
		cap.history.append("Stopped being %s, %s." % [tn, Clock.date_string()])
		news.append("%s is no longer %s. You went against it once too often" % [cap.name, tn])
	cap.lean = cap.get("lean", {})
	for k in voice:
		if int(voice[k]) == 0:
			continue
		var key: String = k + ("+" if int(voice[k]) > 0 else "-")
		var t: String = cfg().drift_traits.get(key, "")
		if t == "" or t in cap.traits or People._conflicts(cap.traits, t):
			continue
		cap.lean[key] = int(cap.lean.get(key, 0)) + 1
		if cap.lean[key] >= int(cfg().drift):
			cap.lean.erase(key)
			cap.traits.append(t)
			var tn: String = Data.table("traits")[t].name.to_lower()
			cap.history.append("Became %s, %s." % [tn, Clock.date_string()])
			news.append("%s has become %s. It's who you are now" % [cap.name, tn])
	return news
